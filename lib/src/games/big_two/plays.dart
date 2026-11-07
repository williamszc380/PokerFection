/// Plays (combinations), how they compare, and how to list every play a
/// hand can make.
///
/// Hands are stored as 13 rank masks: byte `r` holds one bit per suit
/// strength (bit 0 = the lowest suit under the rules) for rank `r`. A card's
/// engine code is `rank * 4 + suit strength`, so a higher code is a higher
/// single. This keeps move generation to small loops over ranks, and uses
/// no 64-bit integers, so it runs the same in JavaScript.
library;

import 'dart:typed_data';

import 'cards.dart';
import 'rules.dart';

/// The kinds of play. Pagat: "singles", "pairs", "triples" and five-card
/// hands, which from low to high are "straight", "flush", "full house",
/// "four of a kind" (with "any fifth card": "four equal cards by
/// themselves are not a playable combination") and "straight flush".
enum PlayKind {
  /// Not playing this turn.
  pass(0, 0),

  /// One card.
  single(1, 0),

  /// Two cards of one rank.
  pair(2, 0),

  /// Three cards of one rank.
  triple(3, 0),

  /// Five consecutive ranks, not all one suit.
  straight(5, 1),

  /// Five cards of one suit, not in sequence.
  flush(5, 2),

  /// A triple and a pair.
  fullHouse(5, 3),

  /// Four cards of one rank plus any fifth card.
  fourOfAKind(5, 4),

  /// Five consecutive ranks of one suit.
  straightFlush(5, 5);

  const PlayKind(this.size, this.fiveCardOrder);

  /// Number of cards in a play of this kind.
  final int size;

  /// Order among five-card hands, 1 (straight) to 5 (straight flush); 0 for
  /// the rest.
  final int fiveCardOrder;
}

/// Five-card keys put the kind above everything else, so one number orders
/// all five-card hands.
const _kindStep = 4194304; // 2^22, above the largest inner key (13^5 * 4).

/// One play: its kind, its cards (as engine codes, lowest first) and a key
/// that orders plays of the same size.
///
/// Plays are compared through [BigTwoRules.beats]; the key alone is only
/// meaningful between plays of the same size.
class Play {
  Play._(this.kind, this.codes, this.key, this._rules);

  /// Not playing this turn.
  static final pass = Play._(PlayKind.pass, const <int>[], -1, null);

  /// What sort of play this is.
  final PlayKind kind;

  /// Engine codes of the cards, lowest first. See [BigTwoRules.codeOf].
  final List<int> codes;

  /// Orders plays of the same size: higher beats lower. For five-card hands
  /// it includes the kind.
  final int key;

  final BigTwoRules? _rules;

  /// Number of cards played (0 for a pass).
  int get size => codes.length;

  /// True for a pass.
  bool get isPass => kind == PlayKind.pass;

  /// Four of a kind and straight flushes, which beat anything when the
  /// rules turn on [BigTwoRules.bombs].
  bool get isBomb => kind == PlayKind.fourOfAKind || kind == PlayKind.straightFlush;

  /// The cards, lowest first.
  List<Card> get cards => [for (final c in codes) _rules!.cardOf(c)];

  /// The highest card's engine code (its rank is `>> 2`).
  int get topCode => codes.isEmpty ? -1 : codes.last;

  /// How many 2s are in the play.
  int get twos {
    var n = 0;
    for (final c in codes) {
      if (c >> 2 == Ranks.two) n++;
    }
    return n;
  }

  /// True if the play contains the card with engine [code].
  bool containsCode(int code) {
    for (final c in codes) {
      if (c == code) return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) {
    if (other is! Play || other.kind != kind || other.codes.length != codes.length) return false;
    for (var i = 0; i < codes.length; i++) {
      if (other.codes[i] != codes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(codes));

  @override
  String toString() => isPass ? 'pass' : '${kind.name} ${cards.map((c) => c.label).join(' ')}';
}

/// Comparisons, classification and move generation, built on the rules'
/// lookup tables.
extension BigTwoPlays on BigTwoRules {
  /// Whether [play] may be played on [current] (null when leading). Passes
  /// are not handled here.
  ///
  /// Pagat: "you must either pass (play no cards) or beat the previous play
  /// by playing a higher combination of the same number of cards." With
  /// [BigTwoRules.bombs], a bomb also beats any single, pair or triple. With
  /// [BigTwoRules.fiveCardSameType], a five-card reply must match the kind
  /// led, unless it is a bomb that outranks it.
  bool beats(Play play, Play? current) {
    if (current == null || current.isPass) return !play.isPass;
    if (play.isPass) return false;
    if (play.size == current.size) {
      if (play.size == 5 && fiveCardSameType && play.kind != current.kind) {
        return bombs && play.isBomb && play.key > current.key;
      }
      return play.key > current.key;
    }
    return bombs && play.isBomb && current.size < 5;
  }

  /// The play these cards make, or null if they are not a legal
  /// combination. Use it to read a play the player picked on screen.
  Play? classify(List<Card> cards) => classifyCodes([for (final c in cards) codeOf(c)]);

  /// [classify] for engine codes. The codes must be distinct.
  Play? classifyCodes(List<int> input) {
    final codes = List<int>.of(input)..sort();
    final n = codes.length;
    if (n == 0) return null;
    if (codes.toSet().length != n) return null;
    final r0 = codes.first >> 2;
    final allSameRank = codes.every((c) => c >> 2 == r0);
    switch (n) {
      case 1:
        return Play._(PlayKind.single, codes, codes[0], this);
      case 2:
        return allSameRank ? Play._(PlayKind.pair, codes, codes[1], this) : null;
      case 3:
        return allSameRank ? Play._(PlayKind.triple, codes, codes[2], this) : null;
      case 5:
        return _classifyFive(codes);
      default:
        return null;
    }
  }

  Play? _classifyFive(List<int> codes) {
    final counts = List<int>.filled(13, 0);
    var rankBits = 0;
    final s0 = codes[0] & 3;
    var sameSuit = true;
    for (final c in codes) {
      counts[c >> 2]++;
      rankBits |= 1 << (c >> 2);
      if (c & 3 != s0) sameSuit = false;
    }
    final groups = [for (final k in counts) if (k > 0) k]..sort();
    if (groups.length == 2 && groups[1] == 4) {
      final quad = counts.indexOf(4);
      return Play._(PlayKind.fourOfAKind, codes, PlayKind.fourOfAKind.fiveCardOrder * _kindStep + quad, this);
    }
    if (groups.length == 2 && groups[1] == 3) {
      final trip = counts.indexOf(3);
      return Play._(PlayKind.fullHouse, codes, PlayKind.fullHouse.fiveCardOrder * _kindStep + trip, this);
    }
    if (groups.length != 5) return null;
    final pos = straightPosition(rankBits);
    if (pos >= 0) {
      final tieRank = straightTieRank(pos);
      final tie = codes.firstWhere((c) => c >> 2 == tieRank);
      if (sameSuit) {
        return Play._(PlayKind.straightFlush, codes, PlayKind.straightFlush.fiveCardOrder * _kindStep + pos * 4 + s0,
            this);
      }
      return Play._(PlayKind.straight, codes, PlayKind.straight.fiveCardOrder * _kindStep + pos * 4 + (tie & 3), this);
    }
    if (sameSuit) return Play._(PlayKind.flush, codes, _flushKey(codes, s0), this);
    return null;
  }

  int _flushKey(List<int> sortedCodes, int suit) {
    final top = sortedCodes[4] >> 2;
    final inner = switch (flushOrder) {
      FlushOrder.suitFirst => suit * 16 + top,
      FlushOrder.rankFirst => top * 4 + suit,
      FlushOrder.allRanks => (((((sortedCodes[4] >> 2) * 13 + (sortedCodes[3] >> 2)) * 13 + (sortedCodes[2] >> 2)) *
                          13 +
                      (sortedCodes[1] >> 2)) *
                  13 +
              (sortedCodes[0] >> 2)) *
          4 +
          suit,
    };
    return PlayKind.flush.fiveCardOrder * _kindStep + inner;
  }

  /// Every play the hand in `masks[offset .. offset + 13)` can make that
  /// beats [current] (every lead when [current] is null), largest plays
  /// limited to [maxSize] cards. Passes are not included.
  ///
  /// The order is fixed (by size, then kind, then key) so results are
  /// reproducible.
  List<Play> playsFrom(Uint8List masks, int offset, Play? current, {int maxSize = 5}) {
    final out = <Play>[];
    if (current == null || current.isPass) {
      if (maxSize >= 1) _singles(masks, offset, -1, out);
      if (maxSize >= 2) _groups(masks, offset, 2, -1, out);
      if (maxSize >= 3) _groups(masks, offset, 3, -1, out);
      if (maxSize >= 5) _fives(masks, offset, null, out);
      return out;
    }
    switch (current.size) {
      case 1:
        if (maxSize >= 1) _singles(masks, offset, current.key, out);
      case 2:
        if (maxSize >= 2) _groups(masks, offset, 2, current.key, out);
      case 3:
        if (maxSize >= 3) _groups(masks, offset, 3, current.key, out);
    }
    if (maxSize >= 5 && (current.size == 5 || bombs)) _fives(masks, offset, current, out);
    return out;
  }

  void _singles(Uint8List m, int off, int above, List<Play> out) {
    for (var code = above + 1; code < 52; code++) {
      if (m[off + (code >> 2)] & (1 << (code & 3)) != 0) {
        out.add(Play._(PlayKind.single, [code], code, this));
      }
    }
  }

  void _groups(Uint8List m, int off, int size, int above, List<Play> out) {
    final kind = size == 2 ? PlayKind.pair : PlayKind.triple;
    for (var r = above < 0 ? 0 : above >> 2; r < 13; r++) {
      final mask = m[off + r];
      if (popCount4[mask] < size) continue;
      for (final sub in subsetsOfSize[size][mask]) {
        final codes = [for (final s in suitsIn[sub]) r * 4 + s];
        final key = codes.last;
        if (key > above) out.add(Play._(kind, codes, key, this));
      }
    }
  }

  void _fives(Uint8List m, int off, Play? current, List<Play> out) {
    var total = 0;
    for (var r = 0; r < 13; r++) {
      total += popCount4[m[off + r]];
    }
    if (total < 5) return;
    final start = out.length;
    _straights(m, off, out);
    _flushes(m, off, out);
    _fullHouses(m, off, out);
    _quads(m, off, out);
    if (current != null) {
      var w = start;
      for (var i = start; i < out.length; i++) {
        if (beats(out[i], current)) out[w++] = out[i];
      }
      out.length = w;
    }
  }

  void _straights(Uint8List m, int off, List<Play> out) {
    final n = straights.order.length;
    final picks = List<int>.filled(5, 0);
    for (var pos = 0; pos < n; pos++) {
      final startRank = straightStart(pos);
      var ok = true;
      for (var k = 0; k < 5; k++) {
        if (m[off + (startRank + k) % 13] == 0) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      final tieRank = straightTieRank(pos);
      void rec(int k) {
        if (k == 5) {
          final codes = <int>[];
          var sameSuit = true;
          var tieSuit = 0;
          for (var i = 0; i < 5; i++) {
            final r = (startRank + i) % 13;
            codes.add(r * 4 + picks[i]);
            if (picks[i] != picks[0]) sameSuit = false;
            if (r == tieRank) tieSuit = picks[i];
          }
          codes.sort();
          if (sameSuit) {
            out.add(Play._(PlayKind.straightFlush, codes,
                PlayKind.straightFlush.fiveCardOrder * _kindStep + pos * 4 + picks[0], this));
          } else {
            out.add(Play._(PlayKind.straight, codes, PlayKind.straight.fiveCardOrder * _kindStep + pos * 4 + tieSuit,
                this));
          }
          return;
        }
        final mask = m[off + (startRank + k) % 13];
        for (final s in suitsIn[mask]) {
          picks[k] = s;
          rec(k + 1);
        }
      }

      rec(0);
    }
  }

  void _flushes(Uint8List m, int off, List<Play> out) {
    final ranks = List<int>.filled(13, 0);
    for (var s = 0; s < 4; s++) {
      var n = 0;
      for (var r = 0; r < 13; r++) {
        if (m[off + r] & (1 << s) != 0) ranks[n++] = r;
      }
      if (n < 5) continue;
      for (var a = 0; a < n - 4; a++) {
        for (var b = a + 1; b < n - 3; b++) {
          for (var c = b + 1; c < n - 2; c++) {
            for (var d = c + 1; d < n - 1; d++) {
              for (var e = d + 1; e < n; e++) {
                final bits = (1 << ranks[a]) | (1 << ranks[b]) | (1 << ranks[c]) | (1 << ranks[d]) | (1 << ranks[e]);
                if (straightPosition(bits) >= 0) continue; // a straight flush, listed with the straights
                final codes = [ranks[a] * 4 + s, ranks[b] * 4 + s, ranks[c] * 4 + s, ranks[d] * 4 + s, ranks[e] * 4 + s];
                out.add(Play._(PlayKind.flush, codes, _flushKey(codes, s), this));
              }
            }
          }
        }
      }
    }
  }

  void _fullHouses(Uint8List m, int off, List<Play> out) {
    for (var t = 0; t < 13; t++) {
      final tm = m[off + t];
      if (popCount4[tm] < 3) continue;
      for (final tsub in subsetsOfSize[3][tm]) {
        for (var p = 0; p < 13; p++) {
          if (p == t) continue;
          final pm = m[off + p];
          if (popCount4[pm] < 2) continue;
          for (final psub in subsetsOfSize[2][pm]) {
            final codes = [
              for (final s in suitsIn[tsub]) t * 4 + s,
              for (final s in suitsIn[psub]) p * 4 + s,
            ]..sort();
            out.add(Play._(PlayKind.fullHouse, codes, PlayKind.fullHouse.fiveCardOrder * _kindStep + t, this));
          }
        }
      }
    }
  }

  void _quads(Uint8List m, int off, List<Play> out) {
    for (var q = 0; q < 13; q++) {
      if (m[off + q] != 15) continue;
      for (var k = 0; k < 52; k++) {
        if (k >> 2 == q || m[off + (k >> 2)] & (1 << (k & 3)) == 0) continue;
        final codes = [q * 4, q * 4 + 1, q * 4 + 2, q * 4 + 3, k]..sort();
        out.add(Play._(PlayKind.fourOfAKind, codes, PlayKind.fourOfAKind.fiveCardOrder * _kindStep + q, this));
      }
    }
  }
}

/// Number of bits set in a 4-bit suit mask.
const popCount4 = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4];

/// The suit strengths in a 4-bit mask, lowest first.
final List<List<int>> suitsIn = List.unmodifiable([
  for (var m = 0; m < 16; m++) List<int>.unmodifiable([for (var s = 0; s < 4; s++) if (m & (1 << s) != 0) s]),
]);

/// `subsetsOfSize[k][mask]`: the sub-masks of `mask` with exactly k bits.
final List<List<List<int>>> subsetsOfSize = List.unmodifiable([
  for (var k = 0; k <= 4; k++)
    List<List<int>>.unmodifiable([
      for (var m = 0; m < 16; m++)
        List<int>.unmodifiable([for (var sub = 1; sub < 16; sub++) if (sub & m == sub && popCount4[sub] == k) sub]),
    ]),
]);

/// Builds 13 rank masks from engine codes.
Uint8List masksOf(Iterable<int> codes) {
  final m = Uint8List(13);
  for (final c in codes) {
    m[c >> 2] |= 1 << (c & 3);
  }
  return m;
}

/// Engine codes held in `masks[offset .. offset + 13)`, lowest first.
List<int> codesIn(Uint8List masks, [int offset = 0]) => [
      for (var r = 0; r < 13; r++)
        for (final s in suitsIn[masks[offset + r]]) r * 4 + s,
    ];
