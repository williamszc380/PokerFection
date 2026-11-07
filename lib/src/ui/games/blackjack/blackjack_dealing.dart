import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../games/blackjack/app/blackjack_record.dart';
import '../../../games/blackjack/blackjack.dart';
import '../../kit/card_flights.dart';
import '../../table_controller.dart' show PlaybackSpeed;
import 'blackjack_table.dart' show blackjackFace;

/// Where a card of the felt is, for its flight: the dealer's card [i] of
/// round [round] ...
Object dealerCardTag(int round, int i) => ('blackjack dealer', round, i);

/// ... or card [i] of the player's hand [hand]. The round is in the tag, so
/// a card still landing from the last round never holds up one of the next.
Object handCardTag(int round, int hand, int i) => ('blackjack hand', round, hand, i);

/// What the felt looked like before a move: enough to tell which cards the
/// move brought.
@immutable
class FeltBefore {
  const FeltBefore({
    required this.round,
    required this.hands,
    required this.dealer,
    required this.holeHidden,
    required this.over,
    this.turnHand,
  });

  /// The felt of [play] now.
  factory FeltBefore.of(BlackjackPlay play) {
    final round = play.round;
    return FeltBefore(
      round: play.rounds,
      hands: [for (final hand in round?.seats[playerSeat].hands ?? const <BlackjackHand>[]) hand.cards.length],
      dealer: round?.dealerCards.length ?? 0,
      holeHidden: round?.holeCardHidden ?? false,
      over: round?.isOver ?? true,
      turnHand: play.handToPlay,
    );
  }

  /// The rounds dealt ([BlackjackPlay.rounds]): a new number is a new deal.
  final int round;

  /// The cards in each of the player's hands.
  final List<int> hands;

  /// The dealer's cards, the hole card included.
  final int dealer;
  final bool holeHidden;

  /// No round being played (none yet, or the last one settled).
  final bool over;

  /// The hand to play (the one a Split splits).
  final int? turnHand;
}

/// One beat of a move on the felt.
sealed class DealStep {
  const DealStep();
}

/// A card flies to its place: from the shoe, or (the second card of a
/// split pair) from the hand it leaves.
class DealCard extends DealStep {
  const DealCard({required this.to, required this.from, required this.card, required this.hand, this.faceUp = true});

  /// The card's place ([dealerCardTag] or [handCardTag]).
  final Object to;
  final Object from;
  final Card card;

  /// The player's hand it goes to; null: the dealer.
  final int? hand;
  final bool faceUp;
}

/// The dealer turns the hole card over.
class TurnHoleCard extends DealStep {
  const TurnHoleCard();
}

/// How a move plays out on the felt: what shows before its first card
/// flies, then its cards one after another, as a dealer deals them.
@immutable
class DealPlan {
  const DealPlan({
    required this.round,
    required this.hands,
    required this.dealer,
    required this.holeDown,
    required this.steps,
    required this.dealing,
    required this.dealerPlays,
  });

  /// The round the cards belong to (for their tags).
  final int round;

  /// The cards showing in each hand, and the dealer's, before the first step.
  final List<int> hands;
  final int dealer;

  /// The hole card shows its back until the plan turns it over.
  final bool holeDown;
  final List<DealStep> steps;

  /// The plan deals a new round.
  final bool dealing;

  /// The plan ends the round: the dealer turns the hole card over and
  /// draws (or the round ended on a bust, a blackjack or a surrender).
  final bool dealerPlays;

  /// Nothing moves: a Stand to the next hand already dealt to, a refused
  /// insurance.
  bool get isEmpty => steps.isEmpty;

  /// The plan for the move that took the felt from [before] to [play]:
  ///
  /// * a deal: a card to the player, the dealer's upcard, a second card to
  ///   the player, the hole card face down (hole card games), as the
  ///   engine deals them;
  /// * a Split: the second card moves over to the new hand, then the first
  ///   hand gets its second card (split aces: both hands);
  /// * a Hit or Double: its card; a Stand: the next split hand's card;
  /// * once the player is done, the hole card turns over and the dealer's
  ///   cards come one by one (without a hole card, the dealer's second card
  ///   is the first of them).
  factory DealPlan.of(FeltBefore before, BlackjackPlay play, {bool split = false}) {
    final round = play.round!;
    final tag = play.rounds;
    final hands = round.seats[playerSeat].hands;
    final dealer = round.dealerCards;
    final steps = <DealStep>[];
    DealCard toHand(int h, int i, {Object? from}) =>
        DealCard(to: handCardTag(tag, h, i), from: from ?? CardFlights.shoeTag, card: hands[h].cards[i], hand: h);
    DealCard toDealer(int i, {bool faceUp = true}) =>
        DealCard(to: dealerCardTag(tag, i), from: CardFlights.shoeTag, card: dealer[i], hand: null, faceUp: faceUp);

    if (before.round != tag) {
      // A new round: dealt round the table, the hole card last.
      final hole = round.rules.holeCard;
      steps.addAll([toHand(0, 0), toDealer(0), toHand(0, 1), if (hole) toDealer(1, faceUp: false)]);
      if (hole && !round.holeCardHidden) steps.add(const TurnHoleCard());
      for (var i = hole ? 2 : 1; i < dealer.length; i++) {
        steps.add(toDealer(i));
      }
      return DealPlan(
        round: tag,
        hands: List.filled(hands.length, 0),
        dealer: 0,
        holeDown: hole,
        steps: steps,
        dealing: true,
        dealerPlays: round.isOver,
      );
    }

    // The same round: which cards each hand had (after a split, the hands
    // after the split one moved one place along).
    final s = split ? before.turnHand : null;
    final shown = <int>[
      for (var j = 0; j < hands.length; j++)
        if (s == null)
          j < before.hands.length ? before.hands[j] : 0
        else if (j < s)
          before.hands[j]
        else if (j == s)
          1
        else if (j == s + 1)
          0
        else
          before.hands[j - 1],
    ];
    if (s != null) {
      // The pair's second card slides over to its own hand.
      steps.add(toHand(s + 1, 0, from: handCardTag(tag, s, 1)));
    }
    for (var j = 0; j < hands.length; j++) {
      for (var i = s != null && j == s + 1 ? 1 : shown[j]; i < hands[j].cards.length; i++) {
        steps.add(toHand(j, i));
      }
    }
    if (before.holeHidden && !round.holeCardHidden) steps.add(const TurnHoleCard());
    for (var i = before.dealer; i < dealer.length; i++) {
      steps.add(toDealer(i));
    }
    return DealPlan(
      round: tag,
      hands: shown,
      dealer: before.dealer,
      holeDown: before.holeHidden,
      steps: steps,
      dealing: false,
      dealerPlays: round.isOver && !before.over,
    );
  }
}

/// Plays a move out on the felt: the cards it brought fly in one after
/// another from the shoe, the hole card turns over before the dealer draws,
/// and each hand's total counts only the cards that have landed. The
/// engine has the whole move at once; this only holds back what the felt
/// shows, so the turns never wait for it (except that the panel's buttons
/// wait out a deal and the dealer's turn: see [busy]).
///
/// At the Animations setting's speed; at Instant nothing is held back.
class BlackjackDealing extends ChangeNotifier {
  BlackjackDealing({required this.flights, required this._speed, this._onDone});

  final CardFlights flights;
  final PlaybackSpeed Function() _speed;
  final VoidCallback? _onDone;

  /// The time from one card leaving the shoe to the next (Normal speed):
  /// a little over half a card's flight, as a dealer pitches them.
  static const gap = Duration(milliseconds: 230);

  /// A face-down card turning over (the card view's own flip).
  static const turnOver = Duration(milliseconds: 400);

  DealPlan? _plan;
  List<int> _hands = const [];
  var _dealer = 0;
  var _holeDown = false;
  var _generation = 0;
  Future<void>? _lastFlight;
  Timer? _timer;
  Completer<void>? _waiting;
  var _disposed = false;

  /// A move is still playing out: the felt shows [shownInHand] cards, not
  /// all the engine has.
  bool get active => _plan != null;

  /// The panel's buttons wait: the round is being dealt, or the dealer is
  /// playing (its result would show before its cards).
  bool get busy => _plan != null && (_plan!.dealing || _plan!.dealerPlays);

  /// The dealer is playing out the round ("Dealer…").
  bool get dealerPlaying => _plan?.dealerPlays ?? false;

  /// The round being played out (its cards' tags).
  int? get round => _plan?.round;

  /// How many of hand [hand]'s [cards] cards show.
  int shownInHand(int hand, int cards) {
    if (_plan == null) return cards;
    return hand < _hands.length ? _hands[hand].clamp(0, cards) : cards;
  }

  /// How many of the dealer's [cards] cards show.
  int shownDealer(int cards) => _plan == null ? cards : _dealer.clamp(0, cards);

  /// The hole card shows its back though the engine has turned it over.
  bool get holeDown => _plan != null && _holeDown;

  /// Plays [plan] out, ending any plan still playing (its cards show at
  /// once). Its first card leaves now, while the screen still shows the
  /// felt before the move (a split card flies from where it was).
  void start(DealPlan plan) {
    finish();
    if (_disposed || _speed().factor <= 0 || plan.isEmpty) return;
    _plan = plan;
    _hands = [...plan.hands];
    _dealer = plan.dealer;
    _holeDown = plan.holeDown;
    unawaited(_run(plan, ++_generation));
  }

  /// Shows everything now (a new move, a new shoe); cards in the air still
  /// land.
  void finish() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    if (_waiting case final waiting? when !waiting.isCompleted) waiting.complete();
    _waiting = null;
    _lastFlight = null;
    if (_plan == null) return;
    _plan = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(DealPlan plan, int generation) async {
    final factor = _speed().factor;
    for (final step in plan.steps) {
      if (generation != _generation) return;
      switch (step) {
        case DealCard():
          final hand = step.hand;
          if (hand == null) {
            _dealer++;
          } else if (hand < _hands.length) {
            _hands[hand]++;
          }
          notifyListeners();
          _lastFlight = flights.fly([
            CardFlight(from: step.from, to: step.to, face: blackjackFace(step.card), faceUp: step.faceUp),
          ]);
          await _wait(gap * factor);
        case TurnHoleCard():
          // The hole card turns over once it is down, not in the air.
          await _lastFlight;
          if (generation != _generation) return;
          _holeDown = false;
          notifyListeners();
          await _wait(turnOver * factor);
      }
    }
    if (generation != _generation) return;
    await _lastFlight;
    if (generation != _generation) return;
    _plan = null;
    _lastFlight = null;
    notifyListeners();
    _onDone?.call();
  }

  Future<void> _wait(Duration time) {
    final waiting = _waiting = Completer<void>();
    _timer = Timer(time, () {
      if (!waiting.isCompleted) waiting.complete();
    });
    return waiting.future;
  }

  @override
  void dispose() {
    finish();
    _disposed = true;
    super.dispose();
  }
}
