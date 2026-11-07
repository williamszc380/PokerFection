/// The step that opens every deal of Fight the Landlord: who bids first.
///
/// Pagat: one card is turned face up in the stack, the players draw their
/// cards in turn, and whoever draws the face-up card bids first. The table
/// shows it as it happens, the same for everyone (the solo game, a room's
/// seats and its spectators), at the Animations setting's speed:
/// - the cards go round the table one at a time from the stack in the
///   middle (DdzDealOrder): the hands grow, the badges count up;
/// - the face-up card flies out face up and lands in its holder's seat,
///   where it stays with the kit's eye until it is played;
/// - then a few words name the first bidder ("Ana bids first"), and the
///   auction starts.
///
/// At Normal it takes about two seconds in all ([cardGap] a card, then
/// [hold]), at Fast about 0.7 s, and at Instant nothing moves: the table
/// shows the result straight away (the card in its seat, the words in the
/// middle until the first bid). Deals thrown in (everyone passed) are dealt
/// again, and the step runs again with the new face-up card.
library;

import 'dart:async';

import '../../../games/doudizhu/doudizhu.dart';
import '../../kit/card_flights.dart';

/// One moment of the step: the cards out so far, and the deal as the table
/// draws it then ([game]: the hands as far as they are dealt, no move made).
class LandlordDealing {
  LandlordDealing._(this.order, this.dealt, this.game, {required this.landed});

  /// The deal's start [start] with the first [dealt] cards of [order] out.
  /// [fanSeat]: the seat whose cards show in a hand fan (the player's; null
  /// for a spectator): the face-up card enters the fan as it leaves the
  /// stack, its place in the fan staying empty until it lands; any other
  /// seat gets it once it has landed (its seat has no place to keep empty).
  factory LandlordDealing.at(DdzGame start, DdzDealOrder order, int dealt, {int? fanSeat}) {
    final at = order.faceUpAt;
    final landed = at == null || dealt > at + landingCards || dealt >= order.cards.length;
    final hands = [
      for (var s = 0; s < 3; s++)
        [
          for (final (i, c) in order.cards.take(dealt).indexed)
            if (c.seat == s && (i != at || landed || s == fanSeat)) c.id,
        ],
    ];
    final faceUp = order.faceUp;
    final held = faceUp != null && hands[order.firstBidder].contains(faceUp);
    final game = DdzGame.fromCards(
      rules: start.rules,
      hands: hands,
      kitty: start.kitty,
      firstBidder: order.firstBidder,
      faceUp: held ? faceUp : null,
    );
    return LandlordDealing._(order, dealt, game, landed: landed);
  }

  final DdzDealOrder order;

  /// Cards dealt so far (0 to [DdzDealOrder.cards]' length).
  final int dealt;

  /// The deal as drawn now: a game only for the table to draw (its hands
  /// are the cards dealt so far; nobody moves on it).
  final DdzGame game;

  /// The face-up card has landed in its holder's seat: the first bidder is
  /// named from then on (always true for a deal without one).
  final bool landed;

  /// Every card is out: the step only holds the result a moment longer.
  bool get allOut => dealt >= order.cards.length;

  /// The cards left in the stack in the middle.
  int get inStack => order.cards.length - dealt;

  /// Cards dealt while the face-up card is in the air (it lands as the
  /// [landingCards]th card after it leaves): the flight's time over a
  /// card's.
  static final landingCards = (CardFlights.duration.inMicroseconds / LandlordDealClock.cardGap.inMicroseconds).ceil();
}

/// Runs the step's time at a speed: a card every [cardGap] (times the
/// speed's factor), then [hold]; at Instant (factor 0) nothing, at once.
/// [onChange] after every card, [onFaceUp] as the face-up card leaves the
/// stack (to fly it), [cancel] to stop early (a new deal, the screen
/// closed): [run]'s future completes either way.
class LandlordDealClock {
  LandlordDealClock({
    required this.start,
    required this.order,
    required this.factor,
    this.fanSeat,
    this.onChange,
    this.onFaceUp,
  }) : _dealt = factor > 0 ? 0 : order.cards.length;

  /// A card's time at Normal: 51 cards in about 1.3 s.
  static const cardGap = Duration(milliseconds: 26);

  /// How long the result stays before the auction starts, at Normal: with
  /// the cards, about two seconds in all.
  static const hold = Duration(milliseconds: 650);

  /// The whole step at [factor] (Normal 1, Fast 0.35, Instant 0) for a deal
  /// of [cards] cards.
  static Duration total(double factor, {int cards = 51}) =>
      factor <= 0 ? Duration.zero : cardGap * factor * cards + hold * factor;

  final DdzGame start;
  final DdzDealOrder order;
  final double factor;
  final int? fanSeat;
  final void Function()? onChange;
  final void Function(int id)? onFaceUp;

  int _dealt;
  Timer? _timer;
  final _done = Completer<void>();
  LandlordDealing? _now;

  /// The step now; null once it is over (or at Instant: there was none).
  LandlordDealing? get now {
    if (_done.isCompleted) return null;
    final cached = _now;
    if (cached != null && cached.dealt == _dealt) return cached;
    return _now = LandlordDealing.at(start, order, _dealt, fanSeat: fanSeat);
  }

  /// Whether the step is still on.
  bool get running => !_done.isCompleted;

  /// Starts the step; completes when it is over (or cancelled).
  Future<void> run() {
    if (_done.isCompleted) return _done.future;
    if (factor <= 0 || order.cards.isEmpty) {
      _done.complete();
      return _done.future;
    }
    _timer = Timer.periodic(cardGap * factor, (timer) {
      _dealt++;
      if (_dealt - 1 == order.faceUpAt) onFaceUp?.call(order.faceUp!);
      if (_dealt >= order.cards.length) {
        timer.cancel();
        _timer = Timer(hold * factor, _finish);
      }
      onChange?.call();
    });
    return _done.future;
  }

  /// Stops the step where it is: its future completes.
  void cancel() => _finish();

  void _finish() {
    _timer?.cancel();
    _timer = null;
    if (!_done.isCompleted) _done.complete();
  }
}
