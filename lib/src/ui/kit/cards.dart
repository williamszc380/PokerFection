import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/app_settings.dart';
import '../../engine/cards.dart';
import '../widgets/card_view.dart';
import 'card_flights.dart';
import 'fit_text.dart';
import 'l10n/kit_strings.dart';

export '../../kit/hand_order.dart';
export '../widgets/card_view.dart' show cardAspectRatio;

/// What a card shows, for every card game: a rank and suit in poker's order,
/// or a joker. Each game converts its own cards (in its own folder):
/// - Big Two `Card` → `suited((rank + 1) % 13, {d: 1, c: 0, h: 2, s: 3}[suit])`;
/// - Fight the Landlord id 0–51 → `suited((rank + 1) % 13, id & 3)`, 52 the
///   little joker, 53 the big one;
/// - Blackjack: its rank and suit, mapped the same way.
@immutable
class CardFace {
  /// [rank] 0 = '2' … 12 = 'A'; [suit] 0 clubs, 1 diamonds, 2 hearts, 3 spades.
  const CardFace.suited(this.rank, this.suit) : big = false, assert(rank >= 0 && rank < 13 && suit >= 0 && suit < 4);

  const CardFace.joker({required this.big}) : rank = -1, suit = -1;

  final int rank;
  final int suit;

  /// For a joker: the big (red) one, else the little (black) one.
  final bool big;

  bool get isJoker => rank < 0;

  PlayingCard? get _card => isJoker ? null : PlayingCard.of(rank, suit);

  @override
  bool operator ==(Object other) => other is CardFace && other.rank == rank && other.suit == suit && other.big == big;

  @override
  int get hashCode => Object.hash(rank, suit, big);

  @override
  String toString() => isJoker ? (big ? 'BJ' : 'LJ') : _card.toString();
}

/// One card of any card game. Suited faces and backs are poker's CardView
/// (so they follow Settings); jokers are drawn here. Under the mouse it
/// lifts a little and shows a hand cursor when it can be tapped. A
/// [selected] card pops up, about a fifth of its height, with no outline:
/// the rise alone shows the pick. Rising and turning over follow the
/// Animations setting (quicker at Fast, at once at Instant).
///
/// A card everyone at the table can see ([visibleToAll]: Fight the
/// Landlord's face-up card, Big Two's starting card) carries an eye on its
/// top-left corner, and says so ("Everyone can see this card") while the
/// mouse is over it or on a long press. The label is drawn in the screen's
/// overlay and takes no taps or drags; a long press that showed it doesn't
/// pick the card when the finger lifts.
class GameCardView extends StatefulWidget {
  const GameCardView({
    super.key,
    required this.width,
    required this.face,
    this.faceUp = true,
    this.selected = false,
    this.dimmed = false,
    this.onTap,
    this.faceStyle,
    this.flightTag,
    this.gestures,
    this.dragging = false,
    this.visibleToAll = false,
  });

  final double width;
  final CardFace? face;
  final bool faceUp;
  final bool selected;

  /// Greyed (a card that can't be played now, or a guide's unused card).
  final bool dimmed;
  final VoidCallback? onTap;

  /// The faces' look; null: the player's (Settings). Settings' preview
  /// shows every look side by side.
  final CardFaceStyle? faceStyle;

  /// Names this card's place for card flights (see FlightSlot): cards fly
  /// from it, or land on it (it is drawn empty until they do). The place
  /// includes the card's rise, so a picked card flies from where it stands.
  final Object? flightTag;

  /// More gestures on the card, answering where [onTap] does (its risen top
  /// too): a hand's drag to move it.
  final Map<Type, GestureRecognizerFactory>? gestures;

  /// A card of its hand is being dragged: no card lifts under the mouse or
  /// shows the hand cursor, so the hand's grab cursor shows.
  final bool dragging;

  /// Everyone at the table can see this card: the eye on its top-left
  /// corner, and the label under the mouse or on a long press (face up only).
  final bool visibleToAll;

  /// The eye's diameter on a card [width] wide: 13 px on a sideways phone's
  /// smallest cards (about 27 px wide), up to 20 on a PC's.
  static double markSize(double width) => (width * 0.3).clamp(13.0, 20.0);

  /// How far the eye rises above the card's top edge: it sits on the
  /// corner like a tab, clear of the rank (a hand's Sort button goes
  /// higher over a marked card).
  static double markRise(double width) => markSize(width) * 0.8;

  /// How far the eye reaches left of the card's left edge.
  static double markLeft(double width) => markSize(width) * 0.1;

  /// How long a finger stays on a marked card before its label shows.
  static const labelPress = kLongPressTimeout;

  /// How far a card rises, as a share of its height: a little under the
  /// mouse, about a fifth when picked (both at once for a picked card
  /// under the mouse).
  static const hoverLift = 0.04, selectedLift = 0.2;

  /// The most a card rises: the room a hand keeps above its cards.
  static const maxLift = selectedLift + hoverLift;

  /// How long a card takes to pop up or settle at Normal speed.
  static const liftTime = Duration(milliseconds: 140);

  @override
  State<GameCardView> createState() => _GameCardViewState();
}

class _GameCardViewState extends State<GameCardView> {
  bool _hovered = false;

  /// The label shows from a long press (a finger, not the mouse).
  bool _pressed = false;
  Timer? _press;
  Offset _pressAt = Offset.zero;

  /// The finger that showed the label lifted: its tap doesn't pick the card.
  bool _swallowTap = false;

  final _label = OverlayPortalController()..show();

  bool get _marked => widget.visibleToAll && widget.faceUp && widget.face != null;

  @override
  void didUpdateWidget(GameCardView old) {
    super.didUpdateWidget(old);
    if (!_marked) _endPress();
  }

  @override
  void dispose() {
    _press?.cancel();
    super.dispose();
  }

  void _endPress() {
    _press?.cancel();
    _press = null;
    _pressed = false;
  }

  void _down(PointerDownEvent e) {
    _swallowTap = false;
    if (e.kind == PointerDeviceKind.mouse || e.kind == PointerDeviceKind.trackpad) return;
    _endPress();
    _pressAt = e.position;
    _press = Timer(GameCardView.labelPress, () {
      _press = null;
      if (mounted && _marked) setState(() => _pressed = true);
    });
  }

  void _move(PointerMoveEvent e) {
    if (_press == null && !_pressed) return;
    // The finger moved as far as a tap allows: a drag, not a press.
    if ((e.position - _pressAt).distance > kTouchSlop) setState(_endPress);
  }

  void _up(PointerUpEvent e) {
    // Comes before the card's tap: the gesture arena settles after every
    // listener has seen the finger lift.
    if (_pressed) _swallowTap = true;
    if (_press != null || _pressed) setState(_endPress);
  }

  void _cancelPress(PointerCancelEvent e) {
    if (_press != null || _pressed) setState(_endPress);
  }

  void _tap() {
    if (_swallowTap) {
      _swallowTap = false;
      return;
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final face = widget.face;
    final width = widget.width;
    final height = width * cardAspectRatio;
    final speed = AppSettings.of(context).speed.factor;
    final marked = _marked;
    Widget card = face != null && face.isJoker && widget.faceUp
        ? _JokerFace(width: width, big: face.big, style: widget.faceStyle)
        : CardView(width: width, card: face?._card, faceUp: widget.faceUp, faceStyle: widget.faceStyle);
    if (widget.dimmed) card = Opacity(opacity: 0.45, child: card);
    if (marked) {
      card = Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            left: -GameCardView.markLeft(width),
            top: -GameCardView.markRise(width),
            child: IgnorePointer(child: VisibleCardMark(size: GameCardView.markSize(width))),
          ),
        ],
      );
    }
    if (widget.flightTag case final tag?) card = FlightSlot(tag: tag, child: card);
    final lift =
        (widget.selected ? GameCardView.selectedLift : 0.0) +
        (_hovered && widget.onTap != null && !widget.dragging ? GameCardView.hoverLift : 0.0);
    card = AnimatedSlide(
      offset: Offset(0, -lift),
      duration: GameCardView.liftTime * speed,
      curve: Curves.easeOutCubic,
      child: card,
    );
    final tappable = !(widget.onTap == null && (widget.gestures?.isEmpty ?? true));
    if (!tappable) {
      final box = SizedBox(width: width, height: height, child: card);
      return marked ? _withLabel(context, box, lift * height, tappable: false) : box;
    }
    // The mouse and the finger reach the card where it is drawn: its risen
    // top answers (in a fan, the only part of a picked card above its
    // neighbours), the empty slot under a picked card doesn't. Under the
    // mouse the box also keeps the strip the card rose from, so the card
    // doesn't drop back and forth at its bottom edge.
    final rise = lift * height;
    final box = _RiseHitBox(
      size: Size(width, height),
      up: rise,
      down: widget.selected ? GameCardView.selectedLift * height : 0,
      child: MouseRegion(
        cursor: widget.dragging
            ? MouseCursor.defer
            : (widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.grab),
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: RawGestureDetector(
          behavior: HitTestBehavior.deferToChild,
          gestures: widget.gestures ?? const {},
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap == null ? null : (marked ? _tap : widget.onTap),
            child: Padding(
              padding: EdgeInsets.only(top: rise),
              child: SizedBox(width: width, height: height, child: card),
            ),
          ),
        ),
      ),
    );
    return marked ? _withLabel(context, box, rise, tappable: true) : box;
  }

  /// A marked card: the label under the mouse or a long-pressing finger,
  /// above the card as it is drawn (below it near the screen's top), kept
  /// on the screen. [rise]: how far the card is drawn above its box.
  Widget _withLabel(BuildContext context, Widget card, double rise, {required bool tappable}) {
    final text = KitStrings.of(context).visibleToAll;
    // The finger is only listened to: taps, picks and drags stay the card's.
    Widget child = Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancelPress,
      child: card,
    );
    if (!tappable) {
      // Opaque: the mouse over this card is not also over a visible card it
      // lies on (two visible cards side by side would both say so at once).
      child = MouseRegion(
        opaque: true,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: child,
      );
    }
    child = Semantics(label: text, child: child);
    if (Overlay.maybeOf(context) == null) return child;
    final showing = (_hovered && !widget.dragging) || _pressed;
    final above = rise + GameCardView.markRise(widget.width);
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _label,
      overlayChildBuilder: (context, info) {
        if (!showing) return const SizedBox.shrink();
        final size = info.childSize;
        final corners = [
          for (final p in [
            Offset(0, -above),
            Offset(size.width, -above),
            Offset(0, size.height),
            Offset(size.width, size.height),
          ])
            MatrixUtils.transformPoint(info.childPaintTransform, p),
        ];
        final rect = Rect.fromLTRB(
          corners.map((p) => p.dx).reduce(min),
          corners.map((p) => p.dy).reduce(min),
          corners.map((p) => p.dx).reduce(max),
          corners.map((p) => p.dy).reduce(max),
        );
        return IgnorePointer(
          child: CustomSingleChildLayout(
            delegate: _LabelPlace(rect),
            child: VisibleCardLabel(text: text),
          ),
        );
      },
      child: child,
    );
  }
}

/// Places a card's label centered above the card ([card], in the overlay),
/// below it when there is no room above, inside the overlay's edges.
class _LabelPlace extends SingleChildLayoutDelegate {
  _LabelPlace(this.card);

  final Rect card;

  static const gap = 4.0, margin = 4.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(max(0, min(220, constraints.maxWidth - 2 * margin)), constraints.maxHeight));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = (card.center.dx - childSize.width / 2).clamp(margin, max(margin, size.width - margin - childSize.width));
    var y = card.top - gap - childSize.height;
    if (y < margin) y = min(card.bottom + gap, size.height - margin - childSize.height);
    return Offset(x.toDouble(), max(0.0, y));
  }

  @override
  bool shouldRelayout(_LabelPlace old) => old.card != card;
}

/// The eye on a card everyone can see ([GameCardView.visibleToAll]): a dark
/// blue disc with a white rim, [size] across.
class VisibleCardMark extends StatelessWidget {
  const VisibleCardMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('visible mark'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: size < 16 ? 1 : 1.5),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Icon(Icons.visibility, size: size * 0.7, color: Colors.white),
    );
  }
}

/// What a card everyone can see says under the mouse or a long press:
/// "Everyone can see this card", with the eye.
class VisibleCardLabel extends StatelessWidget {
  const VisibleCardLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // Material for its text style only (the overlay has none above it).
    return Material(
      key: const ValueKey('visible label'),
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xF21B2328),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white30),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility, size: 14, color: Colors.white70),
            const SizedBox(width: 5),
            Flexible(
              child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white, height: 1.2)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card's box ([size]) whose hits rise with the card: its child is laid
/// out [up] taller and drawn [up] higher, so the child's box reaches the
/// risen card, and only points from [up] above the box down to [down]
/// above its bottom land (a picked card's empty slot isn't the card).
class _RiseHitBox extends SingleChildRenderObjectWidget {
  const _RiseHitBox({required this.size, required this.up, required this.down, super.child});

  final Size size;
  final double up, down;

  @override
  _RenderRiseHitBox createRenderObject(BuildContext context) => _RenderRiseHitBox(size, up, down);

  @override
  void updateRenderObject(BuildContext context, _RenderRiseHitBox renderObject) => renderObject
    ..boxSize = size
    ..up = up
    ..down = down;
}

class _RenderRiseHitBox extends RenderShiftedBox {
  _RenderRiseHitBox(this._boxSize, this._up, this.down) : super(null);

  Size _boxSize;
  set boxSize(Size value) {
    if (value == _boxSize) return;
    _boxSize = value;
    markNeedsLayout();
  }

  double _up;
  set up(double value) {
    if (value == _up) return;
    _up = value;
    markNeedsLayout();
  }

  /// Only for hit tests.
  double down;

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
    final child = this.child;
    if (child == null) return;
    child.layout(BoxConstraints.tight(Size(size.width, size.height + _up)));
    (child.parentData! as BoxParentData).offset = Offset(0, -_up);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!Rect.fromLTRB(0, -_up, size.width, size.height - down).contains(position)) return false;
    if (!hitTestChildren(result, position: position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

/// A joker: "JOKER" down the corner and a star in the middle; the little
/// joker in the spades' ink, the big one in the hearts'.
class _JokerFace extends StatelessWidget {
  const _JokerFace({required this.width, required this.big, this.style});

  final double width;
  final bool big;
  final CardFaceStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? AppSettings.of(context).cardFaces;
    final suit = big ? 2 : 3;
    final ink = style.ink(suit);
    final colored = style == CardFaceStyle.colored;
    return Container(
      width: width,
      height: width * cardAspectRatio,
      decoration: BoxDecoration(
        color: style.face(suit),
        borderRadius: BorderRadius.circular(width * 0.1),
        border: colored
            ? Border.all(color: Colors.white, width: max(1, width * 0.03))
            : Border.all(color: Colors.black26, width: 0.5),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Stack(
        children: [
          Positioned(
            left: width * 0.08,
            top: width * 0.06,
            child: Column(
              children: [
                for (final letter in 'JOKER'.split(''))
                  Text(
                    letter,
                    style: TextStyle(color: ink, fontSize: width * 0.2, fontWeight: FontWeight.w800, height: 1.0),
                  ),
              ],
            ),
          ),
          Positioned(
            right: width * 0.1,
            bottom: width * 0.12,
            child: CustomPaint(size: Size.square(width * 0.52), painter: _StarPainter(ink)),
          ),
        ],
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2, inner = outer * 0.42;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final angle = -pi / 2 + i * pi / 5;
      final point = center + Offset(cos(angle) * r, sin(angle) * r);
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StarPainter oldDelegate) => oldDelegate.color != color;
}

/// The player's hand, overlapped to fit the width it gets (at least 18% of
/// every card shows), as big as the height allows up to [maxCardWidth].
///
/// By default ([fanned]) the cards spread in a fan, as a hand is held: on
/// a gentle arc, each tilted a little more toward the ends, and always
/// overlapping a little, so a whole hand (up to 20 cards in the ~290 px
/// left of the panel on a sideways phone) reads as one. Unfanned, they lie
/// in a straight row with a small gap when there is room.
///
/// Tapping a card picks or unpicks it ([onToggle]); picked cards pop up
/// (inside the hand's box). Dragging a card moves it within the hand
/// ([onReorder]): it follows the finger or the mouse above the others,
/// they slide apart to make room, and on release it settles into its new
/// place (at the Animations speed; at once at Instant). The game owns the
/// order: it gets the card's old and new place and passes the cards back
/// in their new order. A drag that ends where it began is not a move, and
/// a picked card stays picked while it moves. Picking several cards is a
/// tap on each: a drag moves cards, so it no longer sweeps picks.
///
/// With a [sortOrder], the hand carries its Sort button (HandSortButton)
/// just above its left end, clear of every card even when picked. The
/// cards never get smaller for it: where the hand's box has no room above
/// them (a sideways phone), the button rises over the table's bottom edge,
/// drawn in the screen's overlay so it can still be tapped there.
///
/// Each card is a place for card flights ([flightTag]), so a play can fly
/// from the hand to the table.
class HandFan extends StatefulWidget {
  const HandFan({
    super.key,
    required this.cards,
    this.selected = const {},
    this.onToggle,
    this.onReorder,
    this.sortOrder,
    this.onSort,
    this.maxCardWidth = 72,
    this.dimmed = const {},
    this.fanned = true,
    this.showing = minShowing,
    this.visibleToAll = const {},
  });

  final List<CardFace> cards;

  /// Indexes of the selected cards.
  final Set<int> selected;
  final void Function(int index)? onToggle;

  /// The card at [from] was dragged to [to], its place once moved (as
  /// `cards.insert(to, cards.removeAt(from))`, see moveCard); never called
  /// with `from == to`. Null: cards can't be dragged.
  final void Function(int from, int to)? onReorder;

  /// The order the hand is in, shown on its Sort button; null: no button.
  final HandOrder? sortOrder;

  /// A tap on the Sort button; null: the button is greyed out.
  final VoidCallback? onSort;

  final double maxCardWidth;

  /// Indexes of greyed cards.
  final Set<int> dimmed;

  /// On an arc with a slight tilt (true), or in a straight row.
  final bool fanned;

  /// The least share of each card left showing: past it the cards get
  /// smaller rather than overlap more. A game asks for more than
  /// [minShowing] so its corners stay readable; how much a "10" needs
  /// depends on the card's size (at a sideways phone's smallest cards,
  /// even 30% can leave only its "1" in sight).
  final double showing;

  /// Indexes of the cards everyone at the table can see: each carries the
  /// eye on its corner and says so under the mouse or on a long press
  /// ([GameCardView.visibleToAll]).
  final Set<int> visibleToAll;

  /// The least share of each card left showing, unless a game asks for
  /// more ([showing]).
  static const minShowing = 0.18;

  /// A fan's tilt from one card to the next, and the most an end card
  /// tilts (radians: about 0.7° and 5.7°).
  static const tiltStep = 0.012, maxTilt = 0.10;

  /// The most a fan's end cards sit below its middle, as a share of a
  /// card's height.
  static const maxDrop = 0.08;

  /// A fan's widest step between cards, as a share of a card's width: its
  /// cards always overlap a little, even on a wide screen.
  static const fanStep = 0.62;

  /// How long the cards take to slide apart for a dragged card, and the
  /// dragged card to settle when dropped, at Normal speed.
  static const slideTime = Duration(milliseconds: 180);

  /// How much bigger a dragged card is drawn: held up, over the others.
  static const heldScale = 1.06;

  /// The flight tag of a card in the hand ([copy]: the second of two equal
  /// cards from two decks is 2). A game flies a play from the hand with
  /// `CardFlight(from: HandFan.flightTag(face), ...)`.
  static Object flightTag(CardFace face, [int copy = 1]) => ('hand', face, copy);

  /// The card width and the step between cards for [count] cards in [size],
  /// fanned or in a row.
  static ({double width, double step}) layout(
    int count,
    Size size,
    double maxCardWidth, {
    bool fanned = false,
    double showing = minShowing,
  }) {
    final g = HandFanGeometry(count, size, maxCardWidth, fanned: fanned, showing: showing);
    return (width: g.width, step: g.step);
  }

  @override
  State<HandFan> createState() => _HandFanState();
}

/// Where each card of a hand goes: its center and tilt in the hand's box.
/// A fan is a slice of a circle under the hand: card i sits on it at the
/// angle `(i - middle) × tilt`, so the step between cards stays even and
/// the ends dip by at most [HandFan.maxDrop] of a card.
///
/// With a [corner] size (the Sort button's), it also finds the button's
/// place: just above the left end of the hand, clear of the cards there
/// even when they are picked and under the mouse. The cards never get
/// smaller for it: when the box has no room above them (a sideways phone,
/// where the cards take the hand's whole height), the place rises above
/// the box's top, over the table's bottom edge.
class HandFanGeometry {
  factory HandFanGeometry(
    int count,
    Size size,
    double maxCardWidth, {
    bool fanned = true,
    double showing = HandFan.minShowing,
    Size? corner,
    Set<int> marked = const {},
  }) {
    final fit = HandFanGeometry._fit(count, size, maxCardWidth, fanned, showing);
    return corner == null ? fit : fit._placeCorner(corner, size.width, marked);
  }

  static HandFanGeometry _fit(int count, Size size, double maxCardWidth, bool fanned, double showing) {
    // Room above for a picked card to pop up, under the mouse too.
    const lift = GameCardView.maxLift;
    if (!fanned || count <= 1) {
      var width = min(maxCardWidth, size.height / (cardAspectRatio * (1 + lift)));
      var step = 0.0;
      if (count <= 1) {
        width = min(width, size.width);
      } else {
        // Shrink the cards only when even the tightest overlap is too wide.
        width = min(width, size.width / (1 + (count - 1) * showing));
        step = min(width * 1.04, (size.width - width) / (count - 1));
      }
      width = max(0, width);
      final left = (size.width - (width + step * max(0, count - 1))) / 2;
      final anchor = Offset(left + width / 2, size.height - width * cardAspectRatio / 2);
      return HandFanGeometry._(count, width, step, 0, anchor);
    }
    // The end cards' tilt pushes their corners out by about half a card's
    // height × sin(tilt) on each side, and down by the arc's depth.
    final sideways = cardAspectRatio * sin(HandFan.maxTilt);
    var width = min(
      maxCardWidth,
      size.height / (cardAspectRatio * (1 + lift + HandFan.maxDrop) + sin(HandFan.maxTilt) / 2),
    );
    width = max(0, min(width, size.width / (1 + (count - 1) * showing + sideways)));
    final height = width * cardAspectRatio;
    final step = min(width * HandFan.fanStep, (size.width - width * (1 + sideways)) / (count - 1));
    final middle = (count - 1) / 2;
    var tilt = min(HandFan.tiltStep, HandFan.maxTilt / middle);
    // On a circle of radius step / tilt the ends dip by about middle² × step × tilt / 2.
    final dip = middle * middle * step * tilt / 2;
    if (dip > HandFan.maxDrop * height) tilt *= HandFan.maxDrop * height / dip;
    final shape = HandFanGeometry._(count, width, step, tilt, Offset.zero);
    // The middle card's center: low enough to leave room to rise, high
    // enough that the dipped, tilted end cards stay inside.
    final end = shape._offset(count - 1), angle = middle * tilt;
    final lowest = max(height / 2, end.dy + height / 2 * cos(angle) + width / 2 * sin(angle));
    return HandFanGeometry._(count, width, step, tilt, Offset(size.width / 2, size.height - lowest));
  }

  HandFanGeometry._(this.count, this.width, this.step, this.tilt, this._anchor, [this.corner]);

  final int count;
  final double width;

  /// The step between neighbours' centers (along the arc).
  final double step;

  /// The tilt from one card to the next (radians); 0: a straight row.
  final double tilt;

  /// The first card's center in a row; the middle of the arc in a fan.
  final Offset _anchor;

  /// Where the corner (the Sort button) goes, when one was asked for, in
  /// the hand's box; a negative top rises above the box.
  final Rect? corner;

  /// The gap between the corner and the cards under it.
  static const cornerGap = 4.0;

  double get height => width * cardAspectRatio;

  double get _middle => (count - 1) / 2;

  /// This geometry with a corner of [size] placed above the left end of
  /// the cards (its top below 0 when the box has no room for it), clear of
  /// the eye on the [marked] cards' corners too.
  HandFanGeometry _placeCorner(Size size, double boxWidth, Set<int> marked) {
    final left = count == 0 ? 0.0 : bounds(0).left.clamp(0.0, max(0.0, boxWidth - size.width)).toDouble();
    // The cards under the corner, as high as they go: picked, under the mouse.
    var top = double.infinity;
    for (var i = 0; i < count; i++) {
      final b = bounds(i);
      if (b.right < left - cornerGap || b.left > left + size.width + cornerGap) continue;
      final mark = marked.contains(i) ? GameCardView.markRise(width) : 0.0;
      top = min(top, b.top - GameCardView.maxLift * height - mark);
    }
    // No cards (an empty hand): at the top of the box.
    if (top == double.infinity) top = cornerGap + size.height;
    return HandFanGeometry._(count, width, step, tilt, _anchor, Offset(left, top - cornerGap - size.height) & size);
  }

  /// Card [i]'s place relative to the anchor.
  Offset _offset(int i) {
    if (tilt == 0) return Offset(i * step, 0);
    final radius = step / tilt, angle = (i - _middle) * tilt;
    return Offset(radius * sin(angle), radius * (1 - cos(angle)));
  }

  /// Card [i]'s center in the hand's box.
  Offset center(int i) => _anchor + _offset(i);

  /// Card [i]'s tilt (radians, clockwise).
  double angle(int i) => tilt == 0 ? 0 : (i - _middle) * tilt;

  /// The box card [i] covers, tilted (not risen).
  Rect bounds(int i) {
    final a = angle(i).abs();
    return Rect.fromCenter(
      center: center(i),
      width: width * cos(a) + height * sin(a),
      height: height * cos(a) + width * sin(a),
    );
  }

  /// The place along the hand nearest [x]: where a dragged card whose
  /// center is at [x] would go.
  int slotAt(double x) {
    var best = 0;
    for (var i = 1; i < count; i++) {
      if ((center(i).dx - x).abs() < (center(best).dx - x).abs()) best = i;
    }
    return best;
  }

  /// The card drawn at [point] (the topmost, so the visible part of each
  /// card is its own), where a selected card is drawn (risen, its empty
  /// slot left to the cards under it); else, between the
  /// first card's left edge and the last's right one, the card by position
  /// along the hand; else null.
  int? indexAt(Offset point, {Set<int> selected = const {}}) {
    if (count == 0) return null;
    for (var i = count - 1; i >= 0; i--) {
      final local = _rotate(point - center(i), -angle(i));
      final rise = selected.contains(i) ? GameCardView.selectedLift * height : 0.0;
      final top = -height / 2 - rise, bottom = height / 2 - rise;
      if (local.dx.abs() <= width / 2 && local.dy >= top && local.dy <= bottom) return i;
    }
    final left = center(0).dx - width / 2, right = center(count - 1).dx + width / 2;
    if (point.dx < left || point.dx > right) return null;
    var best = 0;
    for (var i = 1; i < count; i++) {
      if (center(i).dx - width / 2 <= point.dx) best = i;
    }
    return best;
  }

  static Offset _rotate(Offset v, double angle) =>
      Offset(v.dx * cos(angle) - v.dy * sin(angle), v.dx * sin(angle) + v.dy * cos(angle));
}

class _HandFanState extends State<HandFan> {
  /// The card being dragged (its key), where the pointer took it (from the
  /// card's center), where the pointer is now (in the hand's box), and the
  /// place it would take if dropped now.
  String? _held;
  Offset _grab = Offset.zero, _pointer = Offset.zero;
  int _to = 0;

  /// The card just dropped, still settling into its place: drawn above the
  /// others until it lands.
  String? _landing;

  /// Shows the Sort button in the screen's overlay, pinned to the hand.
  final _portal = OverlayPortalController()..show();
  final _link = LayerLink();

  /// The last layout, for the drag's callbacks (they come between builds).
  HandFanGeometry? _geometry;
  List<String> _keys = const [];

  /// Keys follow the cards (a hover, a pop-up or a slide stays with its
  /// card when the hand is reordered); a second copy of a card (two decks)
  /// gets its own.
  static List<String> _keysOf(List<CardFace> cards) {
    final seen = <CardFace, int>{};
    return [for (final face in cards) '$face#${seen[face] = (seen[face] ?? 0) + 1}'];
  }

  Duration get _slide => HandFan.slideTime * AppSettings.of(context).speed.factor;

  Offset _local(Offset global) => (context.findRenderObject()! as RenderBox).globalToLocal(global);

  void _start(String key, Offset global) {
    final g = _geometry, from = _keys.indexOf(key);
    if (_held != null || g == null || from < 0) return;
    final at = _local(global);
    setState(() {
      _held = key;
      _landing = null;
      _grab = at - g.center(from);
      _pointer = at;
      _to = from;
    });
  }

  void _move(String key, Offset global) {
    final g = _geometry;
    if (key != _held || g == null) return;
    final at = _local(global);
    setState(() {
      _pointer = at;
      _to = g.slotAt(at.dx - _grab.dx);
    });
  }

  void _drop(String key) {
    final g = _geometry;
    if (key != _held || g == null) return;
    final from = _keys.indexOf(key), to = min(max(_to, 0), max(0, _keys.length - 1));
    // It settles from where it was let go, unless it is already there (or
    // the Animations setting is Instant).
    final settles = _slide > Duration.zero && (_pointer - _grab - g.center(to)).distance > 0.5;
    setState(() {
      _held = null;
      _landing = settles ? key : null;
    });
    if (from >= 0 && to != from) widget.onReorder?.call(from, to);
  }

  void _cancel(String key) {
    if (key == _held) setState(() => _held = null);
  }

  void _landed(String key) {
    if (mounted && _landing == key) setState(() => _landing = null);
  }

  /// The game can stop taking drags while a card is held (a bot plays out,
  /// the deal is thrown in). The card's drag recognizer goes with them,
  /// and no end or cancel ever comes, so the drag ends here: the card
  /// slides back to its place (at once when the Animations setting is
  /// Instant) and the hand stops showing the grab.
  @override
  void didUpdateWidget(HandFan old) {
    super.didUpdateWidget(old);
    if (widget.onReorder != null || _held == null) return;
    _landing = _slide > Duration.zero ? _held : null;
    _held = null;
  }

  @override
  Widget build(BuildContext context) {
    final speed = AppSettings.of(context).speed.factor;
    // Without an overlay (a hand shown on its own) the button is drawn in
    // the hand's box.
    final overlay = Overlay.maybeOf(context) != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = widget.cards.length;
        final size = constraints.biggest;
        final order = widget.sortOrder;
        final buttonHeight = HandSortButton.heightFor(size.height);
        final geometry = HandFanGeometry(
          n,
          size,
          widget.maxCardWidth,
          fanned: widget.fanned,
          showing: widget.showing,
          corner: order == null ? null : HandSortButton.sizeFor(context, order, height: buttonHeight),
          marked: widget.visibleToAll,
        );
        final keys = _keysOf(widget.cards);
        final copies = [for (final key in keys) int.parse(key.substring(key.lastIndexOf('#') + 1))];
        _geometry = geometry;
        _keys = keys;
        final width = geometry.width, height = geometry.height;

        // The dragged card, if it is still in the hand (a card that leaves
        // mid-drag ends the drag), and where every card is drawn meanwhile.
        var held = _held == null ? -1 : keys.indexOf(_held!);
        if (held < 0) _held = null;
        final to = held < 0 ? -1 : _to.clamp(0, n - 1);
        int place(int j) {
          if (held < 0 || j == held) return j == held ? to : j;
          if (held < to && j > held && j <= to) return j - 1;
          if (held > to && j >= to && j < held) return j + 1;
          return j;
        }

        final landing = _landing == null ? -1 : keys.indexOf(_landing!);
        final animate = held >= 0 || landing >= 0;
        final slide = HandFan.slideTime * speed;
        final reorder = widget.onReorder != null;
        // Left to right as they lie, the dragged (or landing) card on top.
        final drawn = [for (var j = 0; j < n; j++) j]..sort((a, b) => place(a).compareTo(place(b)));
        final top = held >= 0 ? held : landing;
        if (top >= 0) {
          drawn
            ..remove(top)
            ..add(top);
        }

        Widget card(int j) {
          final key = keys[j];
          final isHeld = j == held;
          return _CardPlace(
            key: ValueKey(('hand card', key)),
            center: isHeld ? _pointer - _grab : geometry.center(place(j)),
            angle: geometry.angle(place(j)),
            size: Size(width, height),
            // The dragged card follows the pointer at once; the others
            // slide while a card is being dragged or settles.
            duration: isHeld || !animate ? Duration.zero : slide,
            onEnd: j == landing ? () => _landed(key) : null,
            child: AnimatedScale(
              scale: isHeld ? HandFan.heldScale : 1,
              duration: GameCardView.liftTime * speed,
              child: GameCardView(
                key: ValueKey(key),
                width: width,
                face: widget.cards[j],
                selected: widget.selected.contains(j),
                dimmed: widget.dimmed.contains(j),
                visibleToAll: widget.visibleToAll.contains(j),
                onTap: widget.onToggle == null ? null : () => widget.onToggle!(j),
                flightTag: HandFan.flightTag(widget.cards[j], copies[j]),
                gestures: !reorder
                    ? null
                    : {
                        _CardDragRecognizer: GestureRecognizerFactoryWithHandlers<_CardDragRecognizer>(
                          () => _CardDragRecognizer(debugOwner: this),
                          (r) => r
                            ..dragStartBehavior = DragStartBehavior.down
                            ..onStart = ((d) => _start(key, d.globalPosition))
                            ..onUpdate = ((d) => _move(key, d.globalPosition))
                            ..onEnd = ((_) => _drop(key))
                            ..onCancel = (() => _cancel(key)),
                        ),
                      },
                // While a card is dragged no card lifts under the mouse, and
                // the hand shows the grab cursor.
                dragging: held >= 0,
              ),
            ),
          );
        }

        final corner = geometry.corner;
        final button = order == null || corner == null
            ? null
            : HandSortButton(
                key: const ValueKey('hand sort'),
                order: order,
                onPressed: widget.onSort,
                height: buttonHeight,
              );
        final hand = MouseRegion(
          opaque: false,
          cursor: held >= 0 ? SystemMouseCursors.grabbing : MouseCursor.defer,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (button != null && !overlay) Positioned.fromRect(rect: corner!, child: button),
              for (final j in drawn) card(j),
            ],
          ),
        );
        if (!overlay) return hand;
        // The button is drawn in the screen's overlay, pinned to the hand:
        // where it rises above the hand's box it can still be tapped.
        return OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (_) => button == null
              ? const SizedBox.shrink()
              : Positioned(
                  left: 0,
                  top: 0,
                  child: CompositedTransformFollower(
                    link: _link,
                    offset: corner!.topLeft,
                    showWhenUnlinked: false,
                    child: SizedBox.fromSize(size: corner.size, child: button),
                  ),
                ),
          child: CompositedTransformTarget(link: _link, child: hand),
        );
      },
    );
  }
}

/// A card's drag: it starts once the finger has gone as far as a tap
/// allows (Flutter's pan waits twice as long), and the mouse a few pixels
/// (Flutter's default is one, so a click that wobbles would lose its
/// pick); then the card follows the pointer every way.
class _CardDragRecognizer extends PanGestureRecognizer {
  _CardDragRecognizer({super.debugOwner});

  static const mouseSlop = 4.0;

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) =>
      globalDistanceMoved.abs() > max(computeHitSlop(pointerDeviceKind, gestureSettings), mouseSlop);
}

/// A card at [center] turned by [angle], sliding there over [duration]
/// from where it was (at once when [duration] is zero).
class _CardPlace extends ImplicitlyAnimatedWidget {
  const _CardPlace({
    super.key,
    required this.center,
    required this.angle,
    required this.size,
    required super.duration,
    super.onEnd,
    required this.child,
  }) : super(curve: Curves.easeOutCubic);

  final Offset center;
  final double angle;
  final Size size;
  final Widget child;

  @override
  AnimatedWidgetBaseState<_CardPlace> createState() => _CardPlaceState();
}

class _CardPlaceState extends AnimatedWidgetBaseState<_CardPlace> {
  Tween<Offset>? _center;
  Tween<double>? _angle;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _center = visitor(_center, widget.center, (v) => Tween<Offset>(begin: v as Offset)) as Tween<Offset>?;
    _angle = visitor(_angle, widget.angle, (v) => Tween<double>(begin: v as double)) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final center = _center!.evaluate(animation);
    return Positioned(
      left: center.dx - widget.size.width / 2,
      top: center.dy - widget.size.height / 2,
      // Always turned (by 0 in a row, or for a fan's middle card), so a
      // card keeps its state as it moves along the hand.
      child: Transform.rotate(angle: _angle!.evaluate(animation), child: widget.child),
    );
  }
}

/// The hand's Sort button: a small pill above the left end of the cards,
/// showing the order the hand is in ("Rank", "Suit") and switching it; once
/// the player has dragged a card the order is theirs and it reads "Sort",
/// to sort the hand again. The hand cursor and a highlight under the mouse;
/// greyed out without [onPressed]. HandFan places it ([HandFan.sortOrder]).
class HandSortButton extends StatelessWidget {
  const HandSortButton({super.key, required this.order, this.onPressed, this.height = 26});

  final HandOrder order;
  final VoidCallback? onPressed;

  /// Its height; the words, the icon and the padding grow with it.
  final double height;

  /// The height for a hand's box [handHeight] tall: 26 on a sideways phone
  /// (where it rises over the table's edge, so the cards keep their size),
  /// up to 36 beside a PC's big cards.
  static double heightFor(double handHeight) => handHeight < 100 ? 26 : (handHeight < 140 ? 30 : 36);

  static double _icon(double height) => (height * 0.58).roundToDouble();
  static double _padding(double height) => (height * 0.38).roundToDouble();
  static TextStyle _style(double height) =>
      TextStyle(fontSize: (height * 0.44).roundToDouble(), fontWeight: FontWeight.w600, height: 1.1);

  /// The button's size for [order] at [height], its words in the player's
  /// language.
  static Size sizeFor(BuildContext context, HandOrder order, {double height = 26}) {
    final words = textWidth(context, KitStrings.of(context).handOrder(order), _style(height));
    return Size((2 * _padding(height) + _icon(height) + 5 + words + 2).ceilToDouble(), height);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final on = onPressed != null;
    const shape = StadiumBorder();
    return Opacity(
      opacity: on ? 1 : 0.45,
      child: Material(
        // A tint of the theme's green over the dark of the table's edge: it
        // stands out from the felt and the cards without looking like Play.
        color: Color.alphaBlend(primary.withValues(alpha: 0.32), const Color(0xFF1B2328)),
        shape: StadiumBorder(
          side: BorderSide(color: primary.withValues(alpha: on ? 0.9 : 0.3), width: 1.2),
        ),
        elevation: on ? 2 : 0,
        child: InkWell(
          customBorder: shape,
          mouseCursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
          hoverColor: Colors.white.withValues(alpha: 0.18),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _padding(height)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.sort, size: _icon(height), color: on ? Colors.white : primary),
                const SizedBox(width: 5),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      KitStrings.of(context).handOrder(order),
                      maxLines: 1,
                      softWrap: false,
                      style: _style(height).copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cards played together (a trick, a dealer's hand), half overlapped, with
/// an optional [label] under them ("Pair of 7s", "Pass").
class TrickRow extends StatelessWidget {
  const TrickRow({super.key, required this.cards, this.label, this.cardWidth = 40});

  final List<CardFace> cards;
  final String? label;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final step = cardWidth * 0.5;
    final width = cards.isEmpty ? 0.0 : cardWidth + step * (cards.length - 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (cards.isNotEmpty)
          SizedBox(
            width: width,
            height: cardWidth * cardAspectRatio,
            child: Stack(
              children: [
                for (var i = 0; i < cards.length; i++)
                  Positioned(
                    left: i * step,
                    child: GameCardView(width: cardWidth, face: cards[i]),
                  ),
              ],
            ),
          ),
        if (label case final text?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
      ],
    );
  }
}

/// An opponent's hand at their seat: a short fan of backs (at most
/// [maxBacks] of them, however many they hold: the badge says how many), or,
/// once [faces] are given (the deal is over, or the Training option shows
/// them), every card face up and overlapped, drawn smaller when they don't
/// fit the width the seat has.
///
/// The cards everyone can see ([visibleToAll]: Fight the Landlord's face-up
/// card, the kitty in the landlord's hand, Big Two's starting card) show
/// face up even among backs, after them (on top, whole), each with the eye
/// on its corner and the label under the mouse or on a long press. Among
/// [faces] they carry the eye where they are.
class SeatHand extends StatelessWidget {
  const SeatHand({
    super.key,
    required this.count,
    this.faces,
    required this.cardWidth,
    this.maxBacks = 6,
    this.visibleToAll = const [],
  });

  /// How many cards they hold (the visible ones included).
  final int count;

  /// Their cards face up; null: backs.
  final List<CardFace>? faces;
  final double cardWidth;
  final int maxBacks;

  /// The cards of theirs everyone can see (still in their hand).
  final List<CardFace> visibleToAll;

  /// What the seat draws, left to right: each card's face (null: a back)
  /// and whether it carries the eye.
  List<({CardFace? face, bool marked})> _cards() {
    final faces = this.faces;
    if (faces != null) return [for (final f in faces) (face: f, marked: visibleToAll.contains(f))];
    final backs = (count - visibleToAll.length).clamp(0, maxBacks);
    return [
      for (var i = 0; i < backs; i++) (face: null, marked: false),
      for (final f in visibleToAll) (face: f, marked: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards();
    final n = cards.length;
    if (n == 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Faces need room to show their corners (almost half a card each);
        // backs only a sliver. Squeezed to the width when there is too
        // little: the overlap first (down to 18% of a card), then the cards.
        var width = cardWidth;
        final shares = [for (var i = 0; i < n - 1; i++) cards[i].face == null ? 0.32 : 0.45];
        final spread = shares.fold(0.0, (a, b) => a + b);
        var squeeze = 1.0;
        final room = constraints.maxWidth;
        if (room.isFinite && width * (1 + spread) > room) {
          if (n > 1) squeeze = ((room - width) / (width * spread)).clamp(0.18 / shares.reduce(min), 1.0);
          if (width * (1 + squeeze * spread) > room) {
            // Still too wide: smaller cards, keeping the overlap.
            width *= room / (width * (1 + squeeze * spread));
          }
        }
        final lefts = <double>[0];
        for (final share in shares) {
          lefts.add(lefts.last + width * share * squeeze);
        }
        final marked = cards.any((c) => c.marked);
        return SizedBox(
          key: ValueKey(faces == null ? 'seat backs' : 'seat faces'),
          width: width * (1 + squeeze * spread),
          height: width * cardAspectRatio,
          child: Stack(
            // The eye rises above a visible card's corner.
            clipBehavior: marked ? Clip.none : Clip.hardEdge,
            children: [
              for (var i = 0; i < n; i++)
                Positioned(
                  left: lefts[i],
                  child: GameCardView(
                    width: width,
                    face: cards[i].face,
                    faceUp: cards[i].face != null,
                    visibleToAll: cards[i].marked,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A seat at a card table: the name, the cards left, a role ("Landlord"),
/// in a room the seat's total, lit while it is the seat's turn, and gold
/// for the winner.
///
/// On a small felt ("Ana · Terrateniente · 17" in about 120 px on a
/// sideways phone) it first gets smaller, down to [minScale], then cuts
/// the name and, if that isn't enough, the role; the card count and the
/// total always show whole. Squeezed past even that (three letters of the name, the
/// count), it only gets smaller: drawn tiny rather than spilling out.
class SeatBadge extends StatelessWidget {
  const SeatBadge({
    super.key,
    required this.name,
    this.cardsLeft,
    this.toAct = false,
    this.role,
    this.winner = false,
    this.score,
  });

  final String name;
  final int? cardsLeft;
  final bool toAct;
  final String? role;
  final bool winner;

  /// The seat's total so far ("12", "−4"), after the card count: a room's
  /// scores, which the solo games keep in their scoreboard instead.
  final String? score;

  /// The smallest the badge gets before its words are cut.
  static const minScale = 0.75;

  static const _nameStyle = TextStyle(fontWeight: FontWeight.w600);
  static const _roleStyle = TextStyle(fontSize: 11);
  static const _countStyle = TextStyle(fontSize: 12, color: Colors.white70);
  static const _scoreStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);

  /// The badge's padding and border, the gaps, the role chip's padding, the
  /// cards icon: everything but the words.
  double _chrome() =>
      2 * 8 + 2 * 2 + (role == null ? 0 : 6 + 2 * 5) + (cardsLeft == null ? 0 : 6 + 14 + 2) + (score == null ? 0 : 6);

  /// The width the badge takes with nothing cut or scaled, so a game can
  /// tell whether something more (a role chip) still fits its seat.
  double naturalWidth(BuildContext context) =>
      _chrome() +
      textWidth(context, name, _nameStyle) +
      (role == null ? 0.0 : textWidth(context, role!, _roleStyle)) +
      _countWidth(context) +
      2;

  double _countWidth(BuildContext context) =>
      (cardsLeft == null ? 0.0 : textWidth(context, '$cardsLeft', _countStyle)) +
      (score == null ? 0.0 : textWidth(context, score!, _scoreStyle));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!width.isFinite) return _badge(context);
        final nameWidth = textWidth(context, name, _nameStyle);
        final roleWidth = role == null ? 0.0 : textWidth(context, role!, _roleStyle);
        // What always shows whole: the count and the total.
        final countWidth = _countWidth(context);
        final natural = _chrome() + nameWidth + roleWidth + countWidth + 2;
        if (natural <= width) return _badge(context);
        // Smaller first, then laid out in the room it has at [minScale],
        // but never narrower than its count and a few letters of its name
        // (the chrome and the count don't shrink: the row would spill).
        final least = min(natural, _chrome() + countWidth + 2 + min(nameWidth, 30.0));
        final room = max((width / minScale).clamp(0.0, natural), least);
        final words = room - _chrome() - countWidth - 2;
        // The name gives way first, down to 3 letters' room, then the role.
        final roleRoom = (words - nameWidth.clamp(0.0, 30.0)).clamp(0.0, roleWidth);
        final nameRoom = (words - roleRoom).clamp(0.0, nameWidth);
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: room,
            child: _badge(context, nameRoom: nameRoom, roleRoom: roleRoom),
          ),
        );
      },
    );
  }

  Widget _badge(BuildContext context, {double? nameRoom, double? roleRoom}) {
    final theme = Theme.of(context);
    final edge = winner
        ? const Color(0xFFFFD54F)
        : toAct
        ? theme.colorScheme.primary
        : Colors.white24;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xCC12171B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: edge, width: toAct || winner ? 2 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: nameRoom ?? double.infinity),
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _nameStyle),
            ),
          ),
          if (role case final text?) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: BoxConstraints(maxWidth: roleRoom == null ? double.infinity : roleRoom + 10),
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: _roleStyle),
            ),
          ],
          if (cardsLeft case final left?) ...[
            const SizedBox(width: 6),
            const Icon(Icons.style, size: 14, color: Colors.white60),
            const SizedBox(width: 2),
            Text('$left', style: _countStyle),
          ],
          if (score case final total?) ...[
            const SizedBox(width: 6),
            Text(total, key: const ValueKey('seat score'), style: _scoreStyle),
          ],
        ],
      ),
    );
  }
}
