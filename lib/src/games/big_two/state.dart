/// The game itself: the deal, whose turn it is, legal moves, applying a
/// move, the end of the deal and its score, and what each seat may see.
library;

import 'dart:typed_data';

import 'cards.dart';
import 'plays.dart';
import 'random.dart';
import 'rules.dart';

/// One turn in the history: who acted and what they played (or passed).
class BigTwoTurn {
  /// A turn by [seat].
  const BigTwoTurn(this.seat, this.play, {this.forcedHighest = false});

  /// Who acted.
  final int seat;

  /// What they played; [Play.pass] for a pass.
  final Play play;

  /// True when the last-card rule made this single the player's highest
  /// card, which tells everyone they hold nothing higher.
  final bool forcedHighest;

  @override
  String toString() => 'seat $seat: $play';
}

/// A card everyone at the table has seen that is still in a hand, and
/// whose hand it is: [code] is its engine code, [seat] its holder.
typedef VisibleCard = ({int code, int seat});

/// The cards everyone at the table has seen that are still in a hand
/// (see [BigTwoState.visibleCards]), from the public facts of a deal:
/// - the starting card, from the deal until it is played. Its holder leads
///   with it (Pagat: "The player who holds the three of diamonds begins"),
///   so the whole table knows where it is, rank and suit; with two players
///   the lowest card dealt is found by naming low cards upward until
///   someone holds one. Under a chosen leader nobody shows it.
/// - a three-player deal's face-up 52nd card, which its taker adds to
///   their hand in front of everyone (Pagat).
///
/// The two are one entry when the face-up card is itself the starting card.
List<VisibleCard> _visibleCards({
  required bool leaderChosen,
  required int startCode,
  required int startSeat,
  required int extraCode,
  required int extraSeat,
  required bool Function(int code) isPlayed,
}) {
  final start = !leaderChosen && startSeat >= 0 && startCode >= 0 && !isPlayed(startCode);
  return [
    if (start) (code: startCode, seat: startSeat),
    if (extraCode >= 0 && extraSeat >= 0 && !(start && extraCode == startCode) && !isPlayed(extraCode))
      (code: extraCode, seat: extraSeat),
  ];
}

/// The cards everyone knows a seat holds without having seen them, from
/// where a three-player deal's face-up 52nd card went. Pagat: "The holder
/// of the three of diamonds adds this extra card to their hand", and if it
/// is the 3♦ itself "the holder of the three of clubs must take it". Either
/// way its taker holds the lowest card of the 51 in the hands: the 3♣ when
/// the 52nd card is the 3♦, the 3♦ otherwise (which is usually shown
/// anyway, as the starting card, but not under a chosen leader).
///
/// Nobody turns these over, so the app draws no eye on them; but a guess
/// that deals one elsewhere deals a deal that can't have happened, so the
/// samplers and the proof keep them with their holder
/// ([BigTwoState.knownCards]).
List<VisibleCard> _impliedCards({
  required int players,
  required int extraCode,
  required int extraSeat,
  required List<VisibleCard> visible,
  required bool Function(int code) isPlayed,
}) {
  if (players != 3 || extraCode < 0 || extraSeat < 0) return const [];
  final low = extraCode == 0 ? 1 : 0;
  if (isPlayed(low) || visible.any((v) => v.code == low)) return const [];
  return [(code: low, seat: extraSeat)];
}

/// How a finished deal came out.
class BigTwoResult {
  /// The result for a finished deal.
  const BigTwoResult({
    required this.winner,
    required this.cardsLeft,
    required this.penalties,
    required this.scores,
    this.dragon = false,
  });

  /// The seat that went out first (or was dealt a dragon).
  final int winner;

  /// Cards still held by each seat (0 for the winner).
  final List<int> cardsLeft;

  /// Penalty points each seat pays under penalty scoring (0 for the winner
  /// and under Pusoy Dos scoring).
  final List<int> penalties;

  /// Points won (+) or lost (-) by each seat this deal. Under penalty
  /// scoring the winner collects every penalty, so the scores add up to 0.
  /// Under Pusoy Dos scoring only the winner scores.
  final List<int> scores;

  /// True when the deal was won by a dealt dragon, before any play.
  final bool dragon;
}

/// The full state of one deal, with every hand. Bots and the coach never
/// look at it directly: they get a [BigTwoView] from [viewFor].
///
/// The state is mutable for speed (the coach plays out thousands of deals a
/// second); call [copy] to branch it.
class BigTwoState {
  BigTwoState._(this.rules)
      : players = rules.players,
        _hands = Uint8List(rules.players * 13),
        _counts = Int16List(rules.players),
        _dealt = Int16List(rules.players),
        _played = Uint8List(13),
        _bounds = Int8List(rules.players)..fillRange(0, rules.players, 52);

  /// Shuffles and deals with [seed], so the same seed gives the same deal on
  /// every platform. [leader] makes that seat lead anything (for tables
  /// where the last winner starts); otherwise the holder of the lowest card
  /// dealt leads, as Pagat describes.
  factory BigTwoState.deal(BigTwoRules rules, {required int seed, int? leader, bool keepHistory = true}) {
    final rng = GameRandom(seed);
    final deck = List<int>.generate(52, (i) => i);
    rng.shuffle(deck);
    final hands = [
      for (var s = 0; s < rules.players; s++) deck.sublist(s * rules.cardsEach, (s + 1) * rules.cardsEach),
    ];
    return BigTwoState._start(rules, hands, rules.players == 3 ? deck[51] : -1, leader, keepHistory);
  }

  /// A deal with chosen hands, for tests and replays. With three players
  /// pass the face-up 52nd card as [extra].
  factory BigTwoState.fromHands(BigTwoRules rules, List<List<Card>> hands,
      {Card? extra, int? leader, bool keepHistory = true}) {
    if (hands.length != rules.players) throw ArgumentError('Need ${rules.players} hands');
    final codes = [for (final h in hands) [for (final c in h) rules.codeOf(c)]];
    final all = [for (final h in codes) ...h, if (extra != null) rules.codeOf(extra)];
    if (all.toSet().length != all.length) throw ArgumentError('A card was dealt twice');
    return BigTwoState._start(rules, codes, extra == null ? -1 : rules.codeOf(extra), leader, keepHistory);
  }

  /// [BigTwoState.fromHands] for engine codes, used to replay a deal
  /// from a guess at the starting hands.
  factory BigTwoState.fromCodes(BigTwoRules rules, List<List<int>> hands,
          {int extra = -1, int? leader, bool keepHistory = false}) =>
      BigTwoState._start(rules, hands, extra, leader, keepHistory);

  factory BigTwoState._start(BigTwoRules rules, List<List<int>> hands, int extra, int? leader, bool keepHistory) {
    final s = BigTwoState._(rules);
    if (keepHistory) s._history = <BigTwoTurn>[];
    var lowest = 52, lowSeat = 0;
    for (var seat = 0; seat < s.players; seat++) {
      for (final c in hands[seat]) {
        s._hands[seat * 13 + (c >> 2)] |= 1 << (c & 3);
        if (c < lowest) {
          lowest = c;
          lowSeat = seat;
        }
      }
      s._counts[seat] = hands[seat].length;
    }
    if (extra >= 0) {
      // Pagat, three players: "the last card is placed face up in the centre
      // of the table". The holder of the 3♦ adds it, or the 3♣ holder if it
      // is the 3♦ itself; both mean the holder of the lowest card in hand.
      s._hands[lowSeat * 13 + (extra >> 2)] |= 1 << (extra & 3);
      s._counts[lowSeat]++;
      s.extraCode = extra;
      s.extraSeat = lowSeat;
      if (extra < lowest) lowest = extra;
    }
    for (var seat = 0; seat < s.players; seat++) {
      s._dealt[seat] = s._counts[seat];
    }
    s.startCode = lowest;
    s.startSeat = lowSeat;
    if (leader != null) {
      s.toMove = leader;
      s.firstPlay = false;
      s.leaderChosen = true;
    } else {
      s.toMove = lowSeat;
      s.firstPlay = true;
    }
    // Pagat: "a player who is dealt a dragon, which is one card of each
    // rank ... immediately wins". That is a 13-card hand: with 17 or 21
    // cards most hands hold every rank, so bigger deals have no dragon.
    if (rules.dragonWins && rules.cardsEach == 13) {
      for (var k = 0; k < s.players; k++) {
        final seat = (s.toMove + k) % s.players;
        if (s._dealt[seat] == 13 && s._isDragon(seat)) {
          s.winner = seat;
          s.dragonWin = true;
          break;
        }
      }
    }
    return s;
  }

  /// A full state for one guess at the hidden cards: the public facts of
  /// [view] plus [hands] (engine codes for every seat; the viewer's own
  /// hand is taken from the view). Used by the coach and the bots to play
  /// out possible deals.
  factory BigTwoState.fromView(BigTwoView view, List<List<int>>? hands) {
    final s = BigTwoState._(view.rules);
    for (var seat = 0; seat < s.players; seat++) {
      final cards = seat == view.seat ? view.handCodes : (hands == null ? const <int>[] : hands[seat]);
      for (final c in cards) {
        s._hands[seat * 13 + (c >> 2)] |= 1 << (c & 3);
      }
      s._counts[seat] = view.counts[seat];
      s._dealt[seat] = view.dealt[seat];
      s._bounds[seat] = view.bounds[seat];
    }
    for (var r = 0; r < 13; r++) {
      s._played[r] = view.playedMasks[r];
    }
    s.toMove = view.toMove;
    s.current = view.current;
    s.lastPlayer = view.lastPlayer;
    s.passesInRow = view.passesInRow;
    s.lockedMask = view.lockedMask;
    s.firstPlay = view.firstPlay;
    s.leaderChosen = view.leaderChosen;
    s.startCode = view.startCode;
    s.startSeat = view.startSeat;
    s.winner = view.winner;
    s.extraCode = view.extraCode;
    s.extraSeat = view.extraSeat;
    return s;
  }

  /// The rules of this deal.
  final BigTwoRules rules;

  /// Number of seats.
  final int players;

  final Uint8List _hands;
  final Int16List _counts;
  final Int16List _dealt;
  final Uint8List _played;
  final Int8List _bounds;
  List<BigTwoTurn>? _history;

  /// The seat whose turn it is.
  int toMove = 0;

  /// The play to beat, or null when [toMove] leads.
  Play? current;

  /// Who made [current] (-1 before the first play).
  int lastPlayer = -1;

  /// Passes since [current] was played. When every other seat has passed,
  /// [lastPlayer] leads: Pagat, "all but one of the players pass in
  /// succession".
  int passesInRow = 0;

  /// Seats locked out of this trick by [BigTwoRules.passLockout] (bit per
  /// seat).
  int lockedMask = 0;

  /// True until the first play of the deal, which must contain the starting
  /// card when [BigTwoRules.mustPlayStartCard] is on.
  bool firstPlay = true;

  /// Engine code of the starting card: the lowest card dealt (the 3♦ in
  /// the standard four-player game). In a state built from a view it is
  /// the view's [BigTwoView.startCode] (-1 when nobody is told it).
  int startCode = 0;

  /// The seat that was dealt [startCode]. In a state built from a view it
  /// is the view's [BigTwoView.startSeat] (-1 under a chosen leader).
  int startSeat = -1;

  /// True when the deal began with a chosen leader ("the winner of the
  /// last deal starts") rather than with the holder of the starting card.
  /// The table rule is public, so views carry it too.
  bool leaderChosen = false;

  /// The seat that won, or -1 while the deal goes on.
  int winner = -1;

  /// True if the deal was won by a dealt dragon.
  bool dragonWin = false;

  /// The play that emptied the winner's hand (Pusoy Dos scoring counts its
  /// 2s).
  Play? winningPlay;

  /// The face-up card of a three-player deal (-1 if none), and who took it.
  int extraCode = -1, extraSeat = -1;

  /// Whether the deal is over.
  bool get isOver => winner >= 0;

  /// Whether a card has been played.
  bool isPlayed(int code) => _played[code >> 2] & (1 << (code & 3)) != 0;

  /// The cards everyone has seen that are still in a hand: the starting
  /// card until it is played (unless a chosen seat led), and a
  /// three-player deal's face-up card. Bots, the coach and the samplers
  /// treat each as known and fixed to its holder; the app shows it face up
  /// in that seat. Every seat's view has the same list
  /// ([BigTwoView.visibleCards]).
  List<VisibleCard> get visibleCards => _visibleCards(
    leaderChosen: leaderChosen,
    startCode: startCode,
    startSeat: startSeat,
    extraCode: extraCode,
    extraSeat: extraSeat,
    isPlayed: isPlayed,
  );

  /// Every card the whole table can place in a hand: [visibleCards] plus
  /// the card a three-player deal's taker of the 52nd card must hold
  /// (see [_impliedCards]), which nobody shows. Guesses and the proof keep
  /// each with its holder.
  List<VisibleCard> get knownCards {
    final visible = visibleCards;
    return [
      ...visible,
      ..._impliedCards(
          players: players, extraCode: extraCode, extraSeat: extraSeat, visible: visible, isPlayed: isPlayed),
    ];
  }

  /// Raw hand masks, 13 bytes per seat, for the engine's own search code.
  Uint8List get handMasks => _hands;

  /// Cards played so far, as 13 rank masks.
  Uint8List get playedMasks => _played;

  /// Cards still held by [seat].
  int countOf(int seat) => _counts[seat];

  /// Cards dealt to [seat].
  int dealtTo(int seat) => _dealt[seat];

  /// Exclusive upper bound on the codes [seat] can still hold (52 when
  /// nothing is known), learned from the last-card rule.
  int boundOf(int seat) => _bounds[seat];

  /// Every turn so far (empty if the state was made without history).
  List<BigTwoTurn> get history => List.unmodifiable(_history ?? const <BigTwoTurn>[]);

  /// [seat]'s cards, lowest first.
  List<Card> handOf(int seat) => [for (final c in handCodesOf(seat)) rules.cardOf(c)];

  /// [seat]'s cards as engine codes, lowest first.
  List<int> handCodesOf(int seat) => codesIn(_hands, seat * 13);

  /// The seat after [seat] in turn order.
  int nextSeat(int seat) => seat + 1 == players ? 0 : seat + 1;

  bool _isDragon(int seat) {
    for (var r = 0; r < 13; r++) {
      if (_hands[seat * 13 + r] == 0) return false;
    }
    return true;
  }

  /// An independent copy (without history, which searches don't need).
  BigTwoState copy() {
    final s = BigTwoState._(rules);
    s._hands.setAll(0, _hands);
    s._counts.setAll(0, _counts);
    s._dealt.setAll(0, _dealt);
    s._played.setAll(0, _played);
    s._bounds.setAll(0, _bounds);
    s.toMove = toMove;
    s.current = current;
    s.lastPlayer = lastPlayer;
    s.passesInRow = passesInRow;
    s.lockedMask = lockedMask;
    s.firstPlay = firstPlay;
    s.leaderChosen = leaderChosen;
    s.startCode = startCode;
    s.startSeat = startSeat;
    s.winner = winner;
    s.dragonWin = dragonWin;
    s.winningPlay = winningPlay;
    s.extraCode = extraCode;
    s.extraSeat = extraSeat;
    return s;
  }

  /// Every legal move for [toMove], passes included. Empty once the deal is
  /// over.
  List<Play> legalMoves() {
    if (winner >= 0) return const [];
    final seat = toMove;
    if (rules.passLockout && lockedMask & (1 << seat) != 0) return [Play.pass];
    var plays = rules.playsFrom(_hands, seat * 13, current);
    if (firstPlay && rules.mustPlayStartCard) {
      // Pagat: the holder of the 3♦ "must play this card, either by itself
      // or as part of a legal combination".
      plays = [for (final p in plays) if (p.containsCode(startCode)) p];
    }
    if (rules.lastCardRule && _counts[nextSeat(seat)] == 1) {
      final highest = _highestCode(seat);
      plays = [for (final p in plays) if (p.size != 1 || p.codes[0] == highest) p];
    }
    if (rules.noTopSingleFinish && _counts[seat] == 1) {
      // Pagat (Hong Kong): "The deal cannot be won by playing a single ♠2
      // as your last card." The ♠2 is the highest card, code 51.
      plays = [for (final p in plays) if (p.codes[0] != 51) p];
      // Pagat doesn't say what a player left with only that card does on
      // lead. Leading is otherwise compulsory, so they pass the lead on.
      if (current == null && plays.isEmpty) return [Play.pass];
    }
    if (current != null) plays.add(Play.pass);
    return plays;
  }

  int _highestCode(int seat) {
    for (var r = 12; r >= 0; r--) {
      final m = _hands[seat * 13 + r];
      if (m != 0) return r * 4 + (m >= 8 ? 3 : m >= 4 ? 2 : m >= 2 ? 1 : 0);
    }
    return -1;
  }

  /// Whether [move] is legal for [toMove] now.
  bool isLegal(Play move) => legalMoves().contains(move);

  /// Plays [move] for [toMove]. Throws if it isn't legal.
  void apply(Play move) {
    if (!isLegal(move)) throw StateError('Illegal move for seat $toMove: $move');
    applyTrusted(move);
  }

  /// [apply] without the legality check, for search code that only plays
  /// moves taken from [legalMoves].
  void applyTrusted(Play move) {
    final seat = toMove;
    if (move.isPass) {
      _history?.add(BigTwoTurn(seat, move));
      if (current == null) {
        // A pass on lead (see BigTwoRules.noTopSingleFinish): the next seat
        // leads instead, and nobody is locked out.
        toMove = nextSeat(seat);
        return;
      }
      passesInRow++;
      if (rules.passLockout) lockedMask |= 1 << seat;
      if (passesInRow >= players - 1) {
        // Everyone else passed: the last player to play leads anything.
        current = null;
        toMove = lastPlayer;
        passesInRow = 0;
        lockedMask = 0;
      } else {
        toMove = nextSeat(seat);
      }
      return;
    }
    final forced = rules.lastCardRule && move.size == 1 && _counts[nextSeat(seat)] == 1;
    _history?.add(BigTwoTurn(seat, move, forcedHighest: forced));
    for (final c in move.codes) {
      _hands[seat * 13 + (c >> 2)] &= ~(1 << (c & 3));
      _played[c >> 2] |= 1 << (c & 3);
    }
    _counts[seat] -= move.size;
    if (forced && move.codes[0] < _bounds[seat]) _bounds[seat] = move.codes[0];
    current = move;
    lastPlayer = seat;
    passesInRow = 0;
    firstPlay = false;
    if (_counts[seat] == 0) {
      winner = seat;
      winningPlay = move;
      return;
    }
    toMove = nextSeat(seat);
  }

  /// The score of the finished deal. Throws while it is still going on.
  BigTwoResult get result {
    if (winner < 0) throw StateError('The deal is not over');
    return scoreDeal(this);
  }

  /// What [seat] may know: their own hand and everything played in public.
  BigTwoView viewFor(int seat) => BigTwoView._fromState(this, seat);
}

/// Scores a finished deal. Pagat's penalty scoring is for 13-card deals; with
/// 17 or 21 cards a player who never played pays triple and 10 or more
/// cards pay double, the same thresholds.
BigTwoResult scoreDeal(BigTwoState s) {
  final rules = s.rules;
  final n = s.players;
  final left = [for (var i = 0; i < n; i++) s.countOf(i)];
  final penalties = List<int>.filled(n, 0);
  final scores = List<int>.filled(n, 0);
  if (rules.scoring == BigTwoScoring.pusoyDos) {
    // Pagat: "if you win and your last play includes a deuce you score 2
    // points; if it contains two deuces you score 4 points" and so on.
    scores[s.winner] = 1 << (s.winningPlay?.twos ?? 0);
  } else {
    var total = 0;
    for (var i = 0; i < n; i++) {
      if (i == s.winner) continue;
      penalties[i] = penaltyFor(rules, s.handMasks, i, left[i], s.dealtTo(i));
      total += penalties[i];
      scores[i] = -penalties[i];
    }
    scores[s.winner] = total;
  }
  return BigTwoResult(winner: s.winner, cardsLeft: left, penalties: penalties, scores: scores, dragon: s.dragonWin);
}

/// One loser's penalty. Pagat: "One point per card in your hand if you have
/// 9 cards or fewer, two points per card if you have 10, 11 or 12 cards, and
/// three points per card (i.e. 39 points) if you have all 13 of your cards
/// left", plus the optional doublings from Wikipedia.
int penaltyFor(BigTwoRules rules, Uint8List masks, int seat, int left, int dealt) {
  var p = left * (left == dealt ? 3 : (left >= 10 ? 2 : 1));
  if (rules.doubleTwosLeft) {
    p <<= popCount4[masks[seat * 13 + Ranks.two]];
  }
  if (rules.doubleBombLeft && _holdsBomb(rules, masks, seat)) p *= 2;
  return p;
}

bool _holdsBomb(BigTwoRules rules, Uint8List masks, int seat) {
  for (var r = 0; r < 13; r++) {
    if (masks[seat * 13 + r] == 15) return true;
  }
  for (final p in rules.playsFrom(masks, seat * 13, null)) {
    if (p.kind == PlayKind.straightFlush) return true;
  }
  return false;
}

/// What one seat may know: their own hand plus everything public (cards
/// played, how many cards each seat holds, the play to beat, the history).
///
/// Bots and the coach work only from a view, so they can never peek.
class BigTwoView {
  BigTwoView._fromState(BigTwoState s, this.seat)
      : rules = s.rules,
        handCodes = List.unmodifiable(s.handCodesOf(seat)),
        counts = List.unmodifiable([for (var i = 0; i < s.players; i++) s.countOf(i)]),
        dealt = List.unmodifiable([for (var i = 0; i < s.players; i++) s.dealtTo(i)]),
        bounds = List.unmodifiable([for (var i = 0; i < s.players; i++) s.boundOf(i)]),
        playedMasks = Uint8List.fromList(s.playedMasks),
        toMove = s.toMove,
        current = s.current,
        lastPlayer = s.lastPlayer,
        passesInRow = s.passesInRow,
        lockedMask = s.lockedMask,
        firstPlay = s.firstPlay,
        leaderChosen = s.leaderChosen,
        startCode = publicStartOf(s),
        startSeat = s.leaderChosen ? -1 : s.startSeat,
        winner = s.winner,
        extraCode = s.extraCode,
        extraSeat = s.extraSeat,
        history = s.history;

  BigTwoView._raw({
    required this.rules,
    required this.seat,
    required this.handCodes,
    required this.counts,
    required this.dealt,
    required this.bounds,
    required this.playedMasks,
    required this.toMove,
    required this.current,
    required this.lastPlayer,
    required this.passesInRow,
    required this.lockedMask,
    required this.firstPlay,
    required this.leaderChosen,
    required this.startCode,
    required this.startSeat,
    required this.winner,
    required this.extraCode,
    required this.extraSeat,
    required this.history,
  });

  /// Rebuilds a view from [toJson]'s output, for example inside a web
  /// worker, which can only receive plain data.
  factory BigTwoView.fromJson(Map<String, Object?> json) {
    final rules = BigTwoRules.fromJson((json['rules'] as Map).cast<String, Object?>());
    List<int> ints(String key) => [for (final v in json[key] as List) v as int];
    Play playOf(List<int> codes) => codes.isEmpty ? Play.pass : rules.classifyCodes(codes)!;
    final cur = json['current'] as List?;
    final extra = ints('extra');
    return BigTwoView._raw(
      rules: rules,
      seat: json['seat'] as int,
      handCodes: List.unmodifiable(ints('hand')),
      counts: List.unmodifiable(ints('counts')),
      dealt: List.unmodifiable(ints('dealt')),
      bounds: List.unmodifiable(ints('bounds')),
      playedMasks: Uint8List.fromList(ints('played')),
      toMove: json['toMove'] as int,
      current: cur == null ? null : playOf([for (final v in cur) v as int]),
      lastPlayer: json['lastPlayer'] as int,
      passesInRow: json['passes'] as int,
      lockedMask: json['locked'] as int,
      firstPlay: json['first'] as bool,
      leaderChosen: json['chosen'] as bool,
      startCode: json['start'] as int,
      // Missing in older worker inputs: no starting card shown.
      startSeat: json['startSeat'] as int? ?? -1,
      winner: json['winner'] as int,
      extraCode: extra[0],
      extraSeat: extra[1],
      history: List.unmodifiable([
        for (final t in json['history'] as List)
          BigTwoTurn((t as List)[0] as int, playOf([for (final v in t.skip(2)) v as int]), forcedHighest: t[1] == 1),
      ]),
    );
  }

  /// Plain data (ints, bools, lists and maps) for [BigTwoView.fromJson].
  Map<String, Object?> toJson() => {
        'rules': rules.toJson(),
        'seat': seat,
        'hand': handCodes,
        'counts': counts,
        'dealt': dealt,
        'bounds': bounds,
        'played': [for (final m in playedMasks) m],
        'toMove': toMove,
        'current': current?.codes,
        'lastPlayer': lastPlayer,
        'passes': passesInRow,
        'locked': lockedMask,
        'first': firstPlay,
        'chosen': leaderChosen,
        'start': startCode,
        'startSeat': startSeat,
        'winner': winner,
        'extra': [extraCode, extraSeat],
        'history': [
          for (final t in history) [t.seat, t.forcedHighest ? 1 : 0, ...t.play.codes],
        ],
      };

  /// The rules of the deal.
  final BigTwoRules rules;

  /// Whose view this is.
  final int seat;

  /// This seat's cards as engine codes, lowest first.
  final List<int> handCodes;

  /// Cards held by each seat.
  final List<int> counts;

  /// Cards dealt to each seat.
  final List<int> dealt;

  /// Per seat, an exclusive upper bound on the codes they can hold (52 when
  /// nothing is known), from the last-card rule.
  final List<int> bounds;

  /// Cards played so far, as 13 rank masks.
  final Uint8List playedMasks;

  /// Whose turn it is.
  final int toMove;

  /// The play to beat, or null when [toMove] leads.
  final Play? current;

  /// Who made [current] (-1 before the first play).
  final int lastPlayer;

  /// Passes since [current] was played.
  final int passesInRow;

  /// Seats locked out of this trick (bit per seat).
  final int lockedMask;

  /// True until the first play of the deal.
  final bool firstPlay;

  /// True when a chosen seat led the deal instead of the holder of the
  /// starting card.
  final bool leaderChosen;

  /// The lowest card dealt, or -1 when nobody is told it. Every seat knows
  /// the same.
  ///
  /// Its holder leads with it, so the whole table knows it from the deal,
  /// rank and suit: with three or four players it is the lowest card in the
  /// deck; with two, where some cards stay unused, the lowest card dealt is
  /// found by naming low cards upward until someone holds one. With a
  /// chosen leader, three or four players still know the deck's lowest card
  /// (not who holds it), and two players know nothing.
  final int startCode;

  /// Who was dealt [startCode]'s card, or -1 under a chosen leader (nobody
  /// shows it then).
  final int startSeat;

  /// The starting card as every seat and spectator may know it (see
  /// [startCode]).
  static int publicStartOf(BigTwoState s) {
    // With three or four players every card is dealt: the lowest in the
    // deck is known even when a chosen seat leads (its holder isn't).
    if (s.leaderChosen) return s.players >= 3 ? s.startCode : -1;
    return s.startCode;
  }

  /// The winner, or -1 while the deal goes on.
  final int winner;

  /// The face-up card of a three-player deal (-1 if none) and who took it.
  final int extraCode, extraSeat;

  /// Every turn so far.
  final List<BigTwoTurn> history;

  /// This seat's cards, lowest first.
  List<Card> get hand => [for (final c in handCodes) rules.cardOf(c)];

  /// Number of seats.
  int get players => rules.players;

  /// True when it is this seat's turn.
  bool get isMyTurn => toMove == seat && winner < 0;

  /// The legal moves when it is this seat's turn (empty otherwise).
  List<Play> legalMoves() => isMyTurn ? BigTwoState.fromView(this, null).legalMoves() : const [];

  /// Whether a card has been played.
  bool isPlayed(int code) => playedMasks[code >> 2] & (1 << (code & 3)) != 0;

  /// The cards everyone has seen that are still in a hand (the same list
  /// as [BigTwoState.visibleCards], from the public facts alone).
  List<VisibleCard> get visibleCards => _visibleCards(
    leaderChosen: leaderChosen,
    startCode: startCode,
    startSeat: startSeat,
    extraCode: extraCode,
    extraSeat: extraSeat,
    isPlayed: isPlayed,
  );

  /// [BigTwoState.knownCards] from the public facts alone: the visible
  /// cards plus the card the taker of a three-player deal's 52nd card is
  /// known to hold.
  List<VisibleCard> get knownCards {
    final visible = visibleCards;
    return [
      ...visible,
      ..._impliedCards(
          players: players, extraCode: extraCode, extraSeat: extraSeat, visible: visible, isPlayed: isPlayed),
    ];
  }

  /// Engine codes this seat cannot place: not in its hand, not played, and
  /// not a known card another seat holds ([knownOtherCards]). These are
  /// the cards the coach deals out at random.
  List<int> unknownCodes() {
    final mine = masksOf(handCodes);
    final placed = knownOtherCards;
    return [
      for (var c = 0; c < 52; c++)
        if (mine[c >> 2] & (1 << (c & 3)) == 0 && !isPlayed(c) && !placed.contains(c)) c,
    ];
  }

  /// The known cards ([knownCards]) another seat still holds, lowest
  /// first.
  List<int> get knownOtherCards => [
    for (final v in knownCards)
      if (v.seat != seat) v.code,
  ]..sort();

  /// The cards another seat may hold, lowest first: the unknown ones and
  /// the known ones others hold. In a two-player deal a card below the
  /// starting card was never dealt, so it is left out.
  List<int> get opponentCodes {
    final deadBelow = players == 2 && startCode >= 0 ? startCode : 0;
    return [
      for (final c in [...unknownCodes(), ...knownOtherCards])
        if (c >= deadBelow) c,
    ]..sort();
  }
}
