/// Blackjack's views in a room, as plain JSON: what the runner sends, how a
/// seat's view is rebuilt from the spectators' (the coach and the runner
/// test's harness use it), and the engine's view put back together from a
/// seat's view (the bots' and the coach's jobs work from it). Pure Dart.
///
/// Every player's cards are dealt face up, so a seat's view and the
/// spectators' differ only in who they are for: a seat's view says
/// `"you"`, and the spectators' holds the face-down hole card (`"hole"`)
/// while the host's "Spectators see bots' cards" switch is on, since the
/// dealer's card counts as the bots'. No view holds the shoe's order, a
/// card still to come, or a seed.
///
/// A view (version [blackjackOnlineGv]):
/// ```
/// {"rules": {...},                 the table's rules (BlackjackRules.toJson)
///  "round": 3,                     the round's number
///  "phase": "playing",             RoundPhase's name
///  "turn": [1, 0],                 the seat and hand to act (absent once over)
///  "legal": ["H", "S", "D"],       that hand's decisions (move letters)
///  "seats": [{"hands": [{"c": ["As", "Td"], "x2": true, "sp": true,
///              "sa": true, "sur": true, "done": true,
///              "out": "win", "net": 1}],        once over: outcome and net
///             "ins": true}],                     insurance taken (or false)
///  "dealer": ["7c"],               the dealer's cards that show
///  "holeDown": true,               a hole card lies face down
///  "peeked": true,                 the dealer checked: no blackjack
///  "seen": [0, 3, ...],            ranks seen since the shuffle, before this round
///  "left": 211,                    cards left in the shoe
///  "nets": [1.5, -1],              once over: each seat's net, insurance in
///  "you": 0  |  "hole": "Kd"}      a seat's view | the spectators' (switch on)
/// ```
/// Flags are written only when true, so a view stays small (seven seats
/// with every hand split take well under 4 KB).
library;

import '../blackjack.dart';
import '../moves.dart';

/// The version of the views and moves (the move notation is the solo
/// game's: `"<hand>:<letter>"`, see moves.dart).
const blackjackOnlineGv = 1;

/// Whole bets as whole numbers ("1", not "1.0", the same on the web).
num wireNumber(double v) => v == v.roundToDouble() ? v.toInt() : v;

/// [card] as the views write it ("As", "Td").
String cardText(Card card) => card.toString();

/// What everyone may see of [round] (number [roundNo]): every player's
/// cards, the dealer's that show, the round's offers and turn, and the
/// cards seen since the shuffle, but never the face-down hole card or the
/// shoe's order.
Map<String, Object?> blackjackPublicView(BlackjackRound round, {required int roundNo}) {
  final turn = round.turn;
  final over = round.isOver;
  // The engine's own view (for seat 0; every seat's public part is the
  // same) gives the cards seen exactly as a seat at the table counts them.
  final view = round.viewFor(0);
  final seen = Composition.ofCards(view.seenSinceShuffle).counts;
  final thisRound = Composition.ofCards(view.seenThisRound).counts;
  return {
    'rules': round.rules.toJson(),
    'round': roundNo,
    'phase': round.phase.name,
    if (turn != null) 'turn': [turn.seat, turn.hand],
    if (turn != null) 'legal': [for (final a in round.legalActions()) actionLetters[a]!],
    'seats': [
      for (final (s, seat) in round.seats.indexed)
        {
          'hands': [
            for (final (h, hand) in seat.hands.indexed)
              {
                'c': [for (final c in hand.cards) cardText(c)],
                if (hand.doubled) 'x2': true,
                if (hand.fromSplit) 'sp': true,
                if (hand.splitAces) 'sa': true,
                if (hand.surrendered) 'sur': true,
                if (hand.done) 'done': true,
                if (over) 'out': hand.outcome.name,
                if (over) 'net': wireNumber(round.result(s).handsNet[h]),
              },
          ],
          if (seat.insurance != null) 'ins': seat.insurance,
        },
    ],
    'dealer': [for (final c in round.dealerVisible) cardText(c)],
    if (round.holeCardHidden) 'holeDown': true,
    if (round.dealerPeeked) 'peeked': true,
    'seen': [for (var r = 0; r < rankCount; r++) seen[r] - thisRound[r]],
    'left': round.shoe.cardsLeft,
    if (over) 'nets': [for (var s = 0; s < round.seats.length; s++) wireNumber(round.result(s).net)],
  };
}

/// Hand seat [seat]'s view rebuilt from [spectatorView]: the same, less the
/// hole card, for [seat]. Every seat's cards are in the spectators' view,
/// so it is never null for a seat of the round (null only for a seat
/// that isn't in it, or a view that isn't one).
Map<String, Object?>? blackjackSeatViewFrom(Map<String, Object?> spectatorView, int seat) {
  final seats = spectatorView['seats'];
  if (seats is! List || seat < 0 || seat >= seats.length) return null;
  return {
    for (final e in spectatorView.entries)
      if (e.key != 'hole' && e.key != 'you') e.key: e.value,
    'you': seat,
  };
}

/// The decision a view's turn is for: its seat and hand, or null when
/// nobody acts (the round is over).
({int seat, int hand})? wireTurn(Map<String, Object?> view) => switch (view['turn']) {
  [final int seat, final int hand] => (seat: seat, hand: hand),
  _ => null,
};

/// The decisions open to the hand to act, as moves for that hand.
List<String> wireLegalMoves(Map<String, Object?> view) {
  final turn = wireTurn(view);
  final legal = view['legal'];
  if (turn == null || legal is! List) return const [];
  return [for (final l in legal) '${turn.hand}:$l'];
}

/// The engine's view for the seat [view] is for (`"you"`), put back
/// together from it: what the bots and the coach decide from, exactly what
/// the round's own `viewFor` gives that seat. Throws [FormatException] if
/// [view] isn't a seat's view.
BlackjackView blackjackViewFromWire(Map<String, Object?> view) {
  T need<T>(Object? v, String what) => v is T ? v : throw FormatException('blackjack view: bad $what');
  final rules = BlackjackRules.fromJson(view['rules']);
  final you = need<int>(view['you'], 'seat');
  final phase = RoundPhase.values.asNameMap()[view['phase']] ?? (throw const FormatException('blackjack view: phase'));
  Card card(Object? text) {
    try {
      return Card.parse(need<String>(text, 'card'));
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('blackjack view: bad card');
    }
  }

  final seats = <BlackjackSeat>[];
  final roundCards = <Card>[];
  for (final s in need<List<Object?>>(view['seats'], 'seats')) {
    final seat = need<Map<String, Object?>>(s, 'seat');
    final hands = <BlackjackHand>[];
    for (final h in need<List<Object?>>(seat['hands'], 'hands')) {
      final hand = need<Map<String, Object?>>(h, 'hand');
      final cards = [for (final c in need<List<Object?>>(hand['c'], 'cards')) card(c)];
      roundCards.addAll(cards);
      hands.add(
        BlackjackHand.restored(
          bet: 1,
          cards: cards,
          fromSplit: hand['sp'] == true,
          splitAces: hand['sa'] == true,
          doubled: hand['x2'] == true,
          surrendered: hand['sur'] == true,
          done: hand['done'] == true,
        ),
      );
    }
    seats.add(BlackjackSeat.restored(bet: 1, hands: hands, insurance: seat['ins'] as bool?));
  }
  if (you < 0 || you >= seats.length) throw const FormatException('blackjack view: no such seat');
  final dealer = [for (final c in need<List<Object?>>(view['dealer'], 'dealer')) card(c)];
  roundCards.addAll(dealer);
  final seenCounts = need<List<Object?>>(view['seen'], 'seen');
  if (seenCounts.length != rankCount) throw const FormatException('blackjack view: seen');
  // The cards seen before this round only count by rank (the coach's sums
  // and the count use ranks alone): one card of each rank stands for them.
  final before = <Card>[
    for (var r = 0; r < rankCount; r++)
      for (var i = need<int>(seenCounts[r], 'seen'); i > 0; i--) Card.of(r == tenIndex ? 10 : r + 1, 0),
  ];
  final holeDown = view['holeDown'] == true;
  final turn = wireTurn(view);
  final legal = turn == null || turn.seat != you
      ? const <BlackjackAction>[]
      : [
          for (final l in need<List<Object?>>(view['legal'], 'legal'))
            actionLetters.entries
                .firstWhere((e) => e.value == l, orElse: () => throw const FormatException('legal'))
                .key,
        ];
  return BlackjackView.restored(
    rules: rules,
    seat: you,
    phase: phase,
    turn: turn == null ? null : Turn(turn.seat, turn.hand),
    legalActions: legal,
    seats: seats,
    dealerVisible: dealer,
    holeCardHidden: holeDown,
    dealerPeeked: view['peeked'] == true,
    seenSinceShuffle: [...before, ...roundCards],
    seenThisRound: roundCards,
    unseenCount: need<int>(view['left'], 'left') + (holeDown ? 1 : 0),
  );
}
