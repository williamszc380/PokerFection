import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../table_controller.dart' show PlaybackSpeed;
import 'cards.dart';

/// One card on its way: from a place on the screen to another, each named
/// by a tag. A tag names a card's place ([FlightSlot]: a card in the hand,
/// a card of a play on the table) or a whole spot ([FlightSpot]: a bot's
/// seat, the shoe). Tags are any value with equality: the kit's are
/// [HandFan.flightTag], [TablePile.flightTag], [CardFlights.seatTag] and
/// [CardFlights.shoeTag].
@immutable
class CardFlight {
  const CardFlight({required this.from, required this.to, this.face, this.faceUp = true});

  /// Where the card starts: read when the flight is launched, before the
  /// move changes the screen (the card still in the hand).
  final Object from;

  /// Where it lands: read once the screen shows the move (the card's place
  /// in the play on the table). That place stays empty until it lands.
  final Object to;

  /// The card drawn on the way; null: a back.
  final CardFace? face;
  final bool faceUp;
}

/// Cards flying across a game's screen: from the hand (or a bot's seat, or
/// the shoe) to their place on the table, at the Animations setting's speed
/// (Instant: none).
///
/// A game launches them where it plays a move (TurnController.applyMove,
/// with the controller's [TurnController.flights]); the scaffold draws
/// them over the table and the hand. Flights never hold up the turns: the
/// move is played at once, and the landing place just stays empty until
/// its card arrives. A game that must wait for one (Blackjack dealing card
/// after card) awaits [fly], which ends when the cards land, at once when
/// Instant or when there is nothing to fly.
class CardFlights extends ChangeNotifier {
  CardFlights({PlaybackSpeed Function()? speed}) : _speed = speed ?? (() => PlaybackSpeed.normal);

  final PlaybackSpeed Function() _speed;

  /// One card's flight at Normal speed, and the gap before the next card of
  /// the same play leaves (so a play reads as cards, not a block).
  static const duration = Duration(milliseconds: 380), stagger = Duration(milliseconds: 45);

  /// A bot's seat, to fly its plays from: wrap its badge in
  /// `FlightSpot(tag: CardFlights.seatTag(seat))`.
  static Object seatTag(int seat) => ('seat', seat);

  /// The shoe or the deck, to deal from.
  static const Object shoeTag = 'shoe';

  /// The key of a card in the air on its way to [to] (for tests).
  static Key flyingKey(Object to) => ValueKey(('flying', to));

  /// The flights of the nearest layer, or null outside one (a review, a
  /// guide, a test): nothing flies there.
  static CardFlights? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FlightScope>()?.flights;

  final _places = <Object, _PlaceState>{};
  final _landing = <Object, int>{};
  final _batches = <_Batch>[];
  _CardFlightLayerState? _layer;
  var _disposed = false;

  /// Whether a card is on its way to [tag] (its place is drawn empty).
  bool isLanding(Object tag) => _landing.containsKey(tag);

  /// Whether any card is in the air.
  bool get flying => _batches.isNotEmpty;

  /// Launches [flights] together (one play: its cards leave one after the
  /// other) and completes when they have all landed. Nothing flies, and it
  /// completes at once, when the speed is Instant, no game screen shows
  /// these flights, or a flight's start isn't on the screen.
  Future<void> fly(Iterable<CardFlight> flights) {
    final layer = _layer;
    final factor = _speed().factor;
    if (_disposed || layer == null || !layer.mounted || factor <= 0) return Future.value();
    final cards = <_Card>[];
    for (final flight in flights) {
      // One card at a time to a place.
      if (isLanding(flight.to) || cards.any((c) => c.flight.to == flight.to)) continue;
      final start = _places[flight.from]?.place(layer);
      if (start == null) continue;
      cards.add(_Card(flight, start));
    }
    if (cards.isEmpty) return Future.value();
    final batch = _Batch(cards, factor);
    _batches.add(batch);
    // Their places stay empty from the first frame that shows them.
    for (final card in cards) {
      _landing.update(card.flight.to, (n) => n + 1, ifAbsent: () => 1);
    }
    notifyListeners();
    // The landing places exist once the screen has drawn the move.
    SchedulerBinding.instance.addPostFrameCallback((_) => _launch(batch));
    SchedulerBinding.instance.ensureVisualUpdate();
    return batch.done.future;
  }

  void _launch(_Batch batch) {
    final layer = _layer;
    if (_disposed || layer == null || !layer.mounted || !_batches.contains(batch)) return _end(batch);
    for (final card in batch.cards) {
      card.end = _places[card.flight.to]?.place(layer);
    }
    // A card whose place isn't drawn has nowhere to go: it doesn't fly.
    for (final card in batch.cards.where((c) => c.end == null).toList()) {
      batch.cards.remove(card);
      _unland(card.flight.to);
    }
    if (batch.cards.isEmpty) return _end(batch);
    final total = duration + stagger * (batch.cards.length - 1);
    batch.controller = AnimationController(vsync: layer, duration: total * batch.factor)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _end(batch);
      })
      ..forward();
    notifyListeners();
  }

  void _end(_Batch batch) {
    if (!_batches.remove(batch)) return;
    for (final card in batch.cards) {
      _unland(card.flight.to);
    }
    // Stopped now, disposed once the frame that drops its cards is drawn
    // (this may run inside its own status callback).
    if (batch.controller case final controller?) {
      controller.stop();
      SchedulerBinding.instance.addPostFrameCallback((_) => controller.dispose());
      SchedulerBinding.instance.ensureVisualUpdate();
    }
    batch.controller = null;
    if (!batch.done.isCompleted) batch.done.complete();
    if (!_disposed) notifyListeners();
  }

  void _unland(Object tag) {
    final n = _landing[tag];
    if (n == null) return;
    n <= 1 ? _landing.remove(tag) : _landing[tag] = n - 1;
  }

  /// Ends every flight now (the layer is gone, or the game is).
  void _endAll() {
    for (final batch in [..._batches]) {
      _end(batch);
    }
  }

  @override
  void dispose() {
    _endAll();
    _disposed = true;
    super.dispose();
  }
}

/// Where a card is drawn, in the layer's coordinates.
class _Place {
  const _Place(this.center, this.size, this.angle);

  final Offset center;
  final Size size;
  final double angle;
}

class _Card {
  _Card(this.flight, this.start);

  final CardFlight flight;
  final _Place start;
  _Place? end;
}

class _Batch {
  _Batch(this.cards, this.factor);

  final List<_Card> cards;
  final double factor;
  final done = Completer<void>();
  AnimationController? controller;
}

/// Draws a game's card flights over [child] (the scaffold puts it round
/// the table and the hand). Places marked inside it can be flown from and to.
class CardFlightLayer extends StatefulWidget {
  const CardFlightLayer({super.key, required this.flights, required this.child});

  final CardFlights flights;
  final Widget child;

  @override
  State<CardFlightLayer> createState() => _CardFlightLayerState();
}

class _CardFlightLayerState extends State<CardFlightLayer> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.flights._layer = this;
  }

  @override
  void didUpdateWidget(CardFlightLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flights != widget.flights) {
      if (oldWidget.flights._layer == this) {
        oldWidget.flights._layer = null;
        oldWidget.flights._endAll();
      }
      widget.flights._layer = this;
    }
  }

  @override
  void dispose() {
    if (widget.flights._layer == this) {
      widget.flights._layer = null;
      widget.flights._endAll();
    }
    super.dispose();
  }

  RenderBox? get _box {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  @override
  Widget build(BuildContext context) {
    final flights = widget.flights;
    return _FlightScope(
      flights: flights,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: ListenableBuilder(
              listenable: flights,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final batch in flights._batches)
                    for (final (i, card) in batch.cards.indexed)
                      // Until the landing place is known (the frame that
                      // shows the move), a card waits where it was.
                      if (batch.controller != null || card.start.size.width > 0)
                        _FlyingCard(
                          key: CardFlights.flyingKey(card.flight.to),
                          card: card,
                          animation: switch (batch.controller) {
                            final controller? => _interval(controller, i, batch),
                            null => const AlwaysStoppedAnimation(0.0),
                          },
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Card [i]'s share of its batch's time: it leaves after the ones before.
  static Animation<double> _interval(AnimationController controller, int i, _Batch batch) {
    final total = CardFlights.duration + CardFlights.stagger * (batch.cards.length - 1);
    final from = (CardFlights.stagger * i).inMicroseconds / total.inMicroseconds;
    final to = (CardFlights.stagger * i + CardFlights.duration).inMicroseconds / total.inMicroseconds;
    return CurvedAnimation(
      parent: controller,
      curve: Interval(from, min(1.0, to), curve: Curves.easeOutCubic),
    );
  }
}

/// One card in the air: from its start to its place, turning to the
/// place's tilt, on a slight arc.
class _FlyingCard extends StatelessWidget {
  const _FlyingCard({super.key, required this.card, required this.animation});

  final _Card card;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final start = card.start, end = card.end ?? card.start;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        final distance = (end.center - start.center).distance;
        final lift = sin(pi * t) * min(36.0, distance * 0.12);
        final center = Offset.lerp(start.center, end.center, t)! - Offset(0, lift);
        final width = end.size.width;
        final height = width * cardAspectRatio;
        // A spot (a seat) has no card size: the card grows out of it.
        final from = start.size.width > 0 ? start.size.width / width : 0.6;
        final scale = from + (1 - from) * t;
        final angle = start.angle + (end.angle - start.angle) * t;
        return Positioned(
          left: center.dx - width / 2,
          top: center.dy - height / 2,
          width: width,
          height: height,
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: GameCardView(width: width, face: card.flight.face, faceUp: card.flight.faceUp),
            ),
          ),
        );
      },
    );
  }
}

class _FlightScope extends InheritedWidget {
  const _FlightScope({required this.flights, required super.child});

  final CardFlights flights;

  @override
  bool updateShouldNotify(_FlightScope oldWidget) => oldWidget.flights != flights;
}

/// A card's place that cards fly from or to, named by [tag]: drawn empty
/// while a card is on its way to it. GameCardView makes one for itself when
/// given a flightTag (the hand and the pile do).
class FlightSlot extends StatefulWidget {
  const FlightSlot({super.key, required this.tag, required this.child});

  final Object tag;
  final Widget child;

  @override
  State<FlightSlot> createState() => _SlotState();
}

/// A spot cards fly from or to as a whole, named by [tag] (a bot's seat
/// badge, the shoe): a card leaving it grows out of its middle.
class FlightSpot extends StatefulWidget {
  const FlightSpot({super.key, required this.tag, required this.child});

  final Object tag;
  final Widget child;

  @override
  State<FlightSpot> createState() => _SpotState();
}

abstract class _PlaceState<T extends StatefulWidget> extends State<T> {
  CardFlights? _flights;
  Object? _tag;

  Object get tag;

  /// Spots report no size: the flying card takes its landing size.
  bool get sized;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register(CardFlights.maybeOf(context), tag);
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _register(_flights, tag);
  }

  void _register(CardFlights? flights, Object tag) {
    if (flights == _flights && tag == _tag) return;
    _unregister();
    _flights = flights;
    _tag = tag;
    flights?._places[tag] = this;
  }

  void _unregister() {
    final flights = _flights, tag = _tag;
    if (flights != null && tag != null && flights._places[tag] == this) flights._places.remove(tag);
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  /// Where this is drawn now, in [layer]'s coordinates (with any tilt and
  /// scale of the widgets round it), or null when it isn't laid out.
  _Place? place(_CardFlightLayerState layer) {
    final box = context.findRenderObject();
    final root = layer._box;
    if (box is! RenderBox || !box.hasSize || !box.attached || root == null) return null;
    final matrix = box.getTransformTo(root);
    final size = box.size;
    final center = MatrixUtils.transformPoint(matrix, size.center(Offset.zero));
    final across = MatrixUtils.transformPoint(matrix, size.centerRight(Offset.zero)) - center;
    final scale = size.width == 0 ? 1.0 : across.distance / (size.width / 2);
    return _Place(center, sized ? size * scale : Size.zero, sized ? atan2(across.dy, across.dx) : 0);
  }
}

class _SlotState extends _PlaceState<FlightSlot> {
  @override
  Object get tag => widget.tag;

  @override
  bool get sized => true;

  @override
  Widget build(BuildContext context) {
    final flights = _flights;
    if (flights == null) return widget.child;
    return ListenableBuilder(
      listenable: flights,
      builder: (context, child) => Opacity(opacity: flights.isLanding(widget.tag) ? 0 : 1, child: child),
      child: widget.child,
    );
  }
}

class _SpotState extends _PlaceState<FlightSpot> {
  @override
  Object get tag => widget.tag;

  @override
  bool get sized => false;

  @override
  Widget build(BuildContext context) => widget.child;
}
