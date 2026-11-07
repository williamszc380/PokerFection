/// What one player may know about a deal, and the card counter built from
/// it. Bots and the coach work only from a view, so they can never peek.
library;

import 'cards.dart';
import 'game.dart';
import 'plays.dart';
import 'rules.dart';

/// One seat's knowledge of a deal at one moment. Immutable.
class DdzView {
  DdzView({
    required this.seat,
    required this.rules,
    required this.phase,
    required this.toAct,
    required this.hand,
    required this.handSizes,
    required this.landlord,
    required this.kitty,
    required this.stake,
    required this.bombs,
    required this.current,
    required this.currentPlayer,
    required this.playsBySeat,
    required this.history,
    required this.legalMoves,
    required this.highBidder,
    required this.firstBidder,
    this.faceUp,
    required this.result,
    List<int>? removed,
  }) : removed = removed ?? List<int>.filled(Rank.count, 0);

  /// Whose view this is.
  final int seat;
  final DdzRules rules;
  final DdzPhase phase;

  /// The seat to act.
  final int toAct;

  /// This seat's own cards (ids, sorted).
  final List<int> hand;

  /// How many cards each seat holds.
  final List<int> handSizes;

  /// The landlord, or null during the auction.
  final int? landlord;

  /// The kitty's cards when this seat may see them, else null.
  final List<int>? kitty;

  /// The bid (or the auction's high bid so far).
  final int stake;

  /// Bombs and rockets played so far.
  final int bombs;

  /// The play to beat, or null when the player to act leads.
  final Play? current;

  /// Who made [current].
  final int? currentPlayer;

  /// Plays made by each seat (for spring and anti-spring).
  final List<int> playsBySeat;

  /// The public history: bids, plays and passes in order.
  final List<DdzAction> history;

  /// This seat's legal moves when it is its turn, else empty.
  final List<DdzMove> legalMoves;

  /// The high bidder (or landlord-to-be) during the auction.
  final int? highBidder;

  /// The seat that opened the auction.
  final int firstBidder;

  /// The card dealt face up to [firstBidder], which everyone sees (null for
  /// a set-up deal with none).
  final int? faceUp;

  /// The result once the deal is over.
  final DdzResult? result;

  /// Rank counts of cards left out of a set-up deal (all zero normally).
  final List<int> removed;

  /// This seat's rank counts.
  List<int> get counts => countsOfIds(hand);

  /// Whether it is this seat's turn.
  bool get myTurn => seat == toAct && (phase == DdzPhase.bidding || phase == DdzPhase.playing);

  /// Whether this seat is the landlord.
  bool get isLandlord => seat == landlord;

  /// The other peasant, when this seat is a peasant (null otherwise).
  int? get partner {
    final lord = landlord;
    if (lord == null || lord == seat) return null;
    return 3 - lord - seat;
  }

  /// Whether [a] and [b] are on the same side.
  bool sameTeam(int a, int b) => a == b || (a != landlord && b != landlord);

  /// The cards of [s]'s hand everyone at the table has seen, from public
  /// facts only (the same rule as DdzGame.visibleIn, which it always
  /// equals): the face-up card while [firstBidder] still holds it, and the
  /// landlord's kitty cards not yet played when the rules show the kitty.
  /// Sorted ids.
  List<int> visibleIn(int s) {
    final played = {
      for (final a in history) ...a.cardIds,
    };
    final kitty = this.kitty;
    final out = <int>{
      if (faceUp case final id? when s == firstBidder) id,
      if (s == landlord && rules.kittyShown && kitty != null) ...kitty,
    }..removeAll(played);
    // This seat's own: never a card it doesn't hold (the same anyway).
    if (s == seat) out.retainAll(hand);
    return out.toList()..sort();
  }

  /// The card counter for this seat (computed on demand).
  DdzCardCount get cardCount => DdzCardCount.of(this);

  /// The view as JSON, to send it to a worker (where the coach runs) or
  /// over the network. [DdzView.fromJson] reads it back.
  Map<String, Object?> toJson() => {
        'seat': seat,
        'rules': rules.toJson(),
        'phase': phase.name,
        'toAct': toAct,
        'hand': hand,
        'handSizes': handSizes,
        'landlord': landlord,
        'kitty': kitty,
        'stake': stake,
        'bombs': bombs,
        'current': current?.encode(),
        'currentPlayer': currentPlayer,
        'playsBySeat': playsBySeat,
        'history': [
          for (final a in history) [a.seat, a.move.encode(), if (a.cardIds.isNotEmpty) a.cardIds],
        ],
        'legalMoves': [for (final m in legalMoves) m.encode()],
        'highBidder': highBidder,
        'firstBidder': firstBidder,
        'faceUp': ?faceUp,
        'removed': removed,
        if (result != null)
          'result': {
            'landlord': result!.landlord,
            'winner': result!.winner,
            'stake': result!.stake,
            'multiplier': result!.multiplier,
            'bombs': result!.bombs,
            'spring': result!.spring,
            'antiSpring': result!.antiSpring,
            'points': result!.points,
          },
      };

  /// Reads [toJson].
  factory DdzView.fromJson(Map<String, Object?> json) {
    List<int> ints(Object? o) => [for (final x in o! as List) x as int];
    final rules = DdzRules.fromJson((json['rules']! as Map).cast<String, Object?>());
    final r = json['result'] as Map?;
    return DdzView(
      seat: json['seat']! as int,
      rules: rules,
      phase: DdzPhase.values.byName(json['phase']! as String),
      toAct: json['toAct']! as int,
      hand: ints(json['hand']),
      handSizes: ints(json['handSizes']),
      landlord: json['landlord'] as int?,
      kitty: json['kitty'] == null ? null : ints(json['kitty']),
      stake: json['stake']! as int,
      bombs: json['bombs']! as int,
      current: json['current'] == null ? null : Play.decode(json['current']! as String, rules),
      currentPlayer: json['currentPlayer'] as int?,
      playsBySeat: ints(json['playsBySeat']),
      history: [
        for (final e in json['history']! as List)
          DdzAction((e as List)[0] as int, DdzMove.decode(e[1] as String, rules), e.length > 2 ? ints(e[2]) : const []),
      ],
      legalMoves: [for (final m in json['legalMoves']! as List) DdzMove.decode(m as String, rules)],
      highBidder: json['highBidder'] as int?,
      firstBidder: json['firstBidder']! as int,
      faceUp: json['faceUp'] as int?,
      removed: ints(json['removed']),
      result: r == null
          ? null
          : DdzResult(
              landlord: r['landlord'] as int,
              winner: r['winner'] as int,
              stake: r['stake'] as int,
              multiplier: r['multiplier'] as int,
              bombs: r['bombs'] as int,
              spring: r['spring'] as bool,
              antiSpring: r['antiSpring'] as bool,
              points: ints(r['points']),
            ),
    );
  }
}

/// Card counting from one seat's point of view: what has been played, by
/// whom, and what is still out. The app shows it as the card counter; the
/// coach deals hidden hands from it.
class DdzCardCount {
  DdzCardCount._({
    required this.played,
    required this.playedBy,
    required this.unseen,
    required this.knownInHand,
    required this.handSizes,
  });

  /// Counts from [view].
  factory DdzCardCount.of(DdzView view) {
    final played = List<int>.filled(Rank.count, 0);
    final playedBy = [for (var s = 0; s < 3; s++) List<int>.filled(Rank.count, 0)];
    for (final a in view.history) {
      final m = a.move;
      if (m is DdzPlay) {
        for (final r in m.play.ranks) {
          played[r]++;
          playedBy[a.seat][r]++;
        }
      }
    }
    final mine = view.counts;
    final unseen = [
      for (var r = 0; r < Rank.count; r++) deckCountOf(r) - mine[r] - played[r] - view.removed[r],
    ];
    // The cards everyone has seen that another seat still holds (the
    // face-up card, the shown kitty in the landlord's hand), by id: the
    // history names the very cards played, so a kitty 7 is still known
    // after the landlord played a different 7.
    final known = [for (var s = 0; s < 3; s++) List<int>.filled(Rank.count, 0)];
    for (var s = 0; s < 3; s++) {
      if (s == view.seat) continue;
      for (final id in view.visibleIn(s)) {
        known[s][rankOfId(id)]++;
      }
    }
    return DdzCardCount._(
      played: played,
      playedBy: playedBy,
      unseen: unseen,
      knownInHand: known,
      handSizes: [...view.handSizes],
    );
  }

  /// Cards of each rank played so far.
  final List<int> played;

  /// Cards of each rank played by each seat.
  final List<List<int>> playedBy;

  /// Cards of each rank this seat can't see: in other hands (or still in
  /// the kitty during the auction).
  final List<int> unseen;

  /// Cards of each rank known to be in another seat's hand, per seat: the
  /// cards everyone has seen that it still holds (DdzView.visibleIn: the
  /// face-up card, the shown kitty cards the landlord hasn't played). This
  /// seat's own entry is empty.
  final List<List<int>> knownInHand;

  /// Cards each seat holds.
  final List<int> handSizes;

  /// Unseen cards whose holder is unknown.
  List<int> get unknown {
    final u = [...unseen];
    for (final k in knownInHand) {
      for (var r = 0; r < Rank.count; r++) {
        u[r] -= k[r];
      }
    }
    return u;
  }

  /// Total unseen cards.
  int get unseenTotal => unseen.fold(0, (a, b) => a + b);

  /// Whether both jokers are still out (unseen), so a rocket may exist.
  bool get rocketOut => unseen[Rank.littleJoker] > 0 && unseen[Rank.bigJoker] > 0;

  /// Ranks of which all four are unseen, so a bomb may be out there.
  List<int> get possibleBombs => [for (var r = 0; r <= Rank.two; r++) if (unseen[r] == 4) r];

  /// The highest unseen rank, or -1 when nothing is unseen.
  int get highestUnseen {
    for (var r = Rank.count - 1; r >= 0; r--) {
      if (unseen[r] > 0) return r;
    }
    return -1;
  }
}
