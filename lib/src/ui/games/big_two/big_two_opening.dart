/// Who goes first, on the felt: the short step every deal opens with
/// (BigTwoOpening), then a note in the middle until the first play.
///
/// - The step ([BigTwoOpeningLayer], driven by [BigTwoOpeningStage]) plays
///   at the Animations speed: about two seconds at Normal, faster at Fast,
///   none at Instant. With three or four players the starting card turns
///   up in the middle (with a three-player deal's face-up card beside it),
///   the headline names its holder ("Kai starts: 3♦"), and the cards fly to
///   that seat. With two players low cards are called from the bottom up,
///   each turning up in the middle, the ones nobody holds greyed out, until
///   the one somebody holds: only that card goes to its holder's seat.
///   Under a chosen leader only the name shows.
/// - The note ([BigTwoOpeningNote]) is the step's result: "Kai starts: 3♦"
///   with a "?" (the Starting card entry, which says how two players find
///   it), in the middle of the felt until the first play. It is all there
///   is at Instant, and what the review's first step shows.
library;

import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart' hide Card;

import '../../../games/big_two/big_two.dart';
import '../../kit/cards.dart';
import '../../kit/help.dart';
import 'big_two_coach_view.dart' show bigTwoFace;
import 'l10n/big_two_strings.dart';

/// [opening]'s words: "Kai starts: 3♦" (a chosen leader: "Kai starts"),
/// by the seat's name in [names], the player's seat too ("Player starts:
/// 3♦"), as the seat badge says.
String bigTwoOpeningText(BigTwoStrings strings, BigTwoRules rules, BigTwoOpening opening, List<String> names) {
  final card = opening.startCode < 0 ? null : rules.cardOf(opening.startCode).label;
  final seat = opening.starter;
  return strings.starts(seat < names.length ? names[seat] : '', card);
}

/// Times one who-goes-first step of [length]: it says when the starter is
/// named ([onNamed], at [namedAt] of the way) and when the step is over
/// ([onEnd]). It counts in short ticks rather than starting one long
/// timer, so a screen laid out again midway (a phone turned, a window
/// resized) picks the animation up where the step is ([progress]).
class BigTwoOpeningTimer {
  BigTwoOpeningTimer(this.length, {double namedAt = 0, this.onNamed, required this.onEnd})
    : _namedAt = length * namedAt,
      named = namedAt <= 0 {
    _timer = Timer.periodic(tick, (_) => _tick());
  }

  /// How often the time is counted.
  static const tick = Duration(milliseconds: 20);

  final Duration length;
  final Duration _namedAt;
  final VoidCallback? onNamed;
  final VoidCallback onEnd;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  /// The starter has been named (the calls, if any, are over).
  bool named;

  /// The step is still going on.
  bool get running => _timer != null;

  /// How far the step is, 0 to 1.
  double get progress =>
      length <= Duration.zero ? 1 : (_elapsed.inMicroseconds / length.inMicroseconds).clamp(0.0, 1.0);

  void _tick() {
    _elapsed += tick;
    if (!named && _elapsed >= _namedAt) {
      named = true;
      onNamed?.call();
    }
    if (_elapsed >= length) {
      cancel();
      onEnd();
    }
  }

  /// Stops it without a word (a new deal, the screen gone).
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Runs a who-goes-first step on screen: an animation of [length] from 0
/// to 1 while [playing], from [from] (where the step is when the stage is
/// built midway, see BigTwoOpeningTimer.progress), started again whenever
/// [id] changes (a new deal), handed to [builder]; null to [builder] when
/// no step plays (the step is over, or the speed is Instant).
class BigTwoOpeningStage extends StatefulWidget {
  const BigTwoOpeningStage({
    super.key,
    required this.id,
    required this.playing,
    required this.length,
    required this.builder,
    this.from = 0,
  });

  /// The deal the step belongs to: a new one starts the step again.
  final Object id;
  final bool playing;
  final Duration length;

  /// Where the step is as the stage starts it (0: at its start).
  final double from;
  final Widget Function(BuildContext context, Animation<double>? opening) builder;

  @override
  State<BigTwoOpeningStage> createState() => _BigTwoOpeningStageState();
}

class _BigTwoOpeningStageState extends State<BigTwoOpeningStage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _sync(null);
  }

  @override
  void didUpdateWidget(BigTwoOpeningStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(oldWidget);
  }

  void _sync(BigTwoOpeningStage? old) {
    final w = widget;
    if (!w.playing || w.length <= Duration.zero) {
      _controller.stop();
      return;
    }
    if (old == null || old.id != w.id || !old.playing) {
      _controller
        ..duration = w.length
        ..forward(from: old == null ? w.from : 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.playing && widget.length > Duration.zero ? _controller : null);
}

/// Where a card shown in the step lands for [seat] on a felt of [size]
/// with the seats at [places] (BigTwoTable.places): the seat's cards, under
/// a top seat's badge, beside a side seat's, or the bottom edge for the
/// player (whose fan is under the felt).
Offset bigTwoOpeningTarget(Size size, List<Alignment> places, int seat, double seatCardHeight) {
  final place = places[seat];
  final at = place.alongSize(size);
  const badge = badgeHeight;
  if (seat == 0) return Offset(size.width / 2, size.height - 6);
  if (place.x.abs() == 1) return Offset(place.x > 0 ? size.width - 40 : 40, at.dy + badge + seatCardHeight / 2);
  final half = min(size.width / 2, 80.0);
  return Offset(at.dx.clamp(half, size.width - half), badge + 6 + seatCardHeight / 2);
}

/// How tall a seat's badge is with its padding, as the felt lays it out.
const badgeHeight = 34.0;

/// The step in the middle of the felt, at [progress] (0 to 1): see the
/// library comment. It takes no taps; the felt under it shows the seats.
class BigTwoOpeningLayer extends StatelessWidget {
  const BigTwoOpeningLayer({
    super.key,
    required this.opening,
    required this.progress,
    required this.rules,
    required this.label,
    required this.cardWidth,
    required this.places,
    required this.seatCardWidth,
    this.sides = 0,
  });

  final BigTwoOpening opening;
  final double progress;
  final BigTwoRules rules;

  /// The step's words ([bigTwoOpeningText]).
  final String label;

  /// The size the cards turn up at, and the size they land at.
  final double cardWidth, seatCardWidth;
  final List<Alignment> places;

  /// The width each side seat takes (four players; 0 for none): on a short
  /// felt the step keeps to the middle between them.
  final double sides;

  /// How many cards of a two-player call show at once (the latest ones).
  static const callsShown = 5;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final o = opening;
    final named = p >= o.namedAt;
    final fly = Curves.easeInOut.transform(((p - BigTwoOpening.flyFrom) / (1 - BigTwoOpening.flyFrom)).clamp(0.0, 1.0));
    // The words come up as the starter is named and go as the cards land.
    final labelOpacity = o.kind == BigTwoOpeningKind.chosen
        ? (min(p / 0.15, (1 - p) / 0.15)).clamp(0.0, 1.0)
        : named
        ? (1 - ((p - 0.9) / 0.1).clamp(0.0, 1.0))
        : 0.0;
    return IgnorePointer(
      key: const ValueKey('opening step'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final fontSize = size.height < 210 ? 12.0 : 14.0;
          final wordsHeight = fontSize + 10;
          const gap = 6.0, under = 6.0;
          // A short felt (a sideways phone, a room's felt under its seats
          // bar): the cards keep to the band between the badges' rows, a
          // little smaller if need be, with the words beside them when they
          // fit, else across their foot. Otherwise the words go under them.
          final compact = size.height < 210;
          const badgesTop = 36.0, badgesBottom = 44.0;
          final band = size.height - badgesTop - badgesBottom;
          var w = compact ? min(cardWidth, max(18.0, (band - 4) / cardAspectRatio)) : cardWidth;
          final count = switch (o.kind) {
            BigTwoOpeningKind.startingCard => o.shown.length,
            BigTwoOpeningKind.lowestCalled => min(o.called.length, callsShown),
            BigTwoOpeningKind.chosen => 0,
          };
          final rowWidth = count == 0 ? 0.0 : count * w + (count - 1) * gap;
          final wordsWidth =
              (TextPainter(
                text: TextSpan(
                  text: label,
                  style: DefaultTextStyle.of(context).style
                      .merge(TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600)),
                ),
                textDirection: Directionality.of(context),
                maxLines: 1,
              )..layout()).width +
              20;
          // The room the step has across: the whole felt, or with four
          // players the middle between the side seats' badges.
          final middle = sides > 0 ? size.width - 2 * sides - 8 : size.width - 16;
          final beside = compact && count > 0 && rowWidth + 10 + wordsWidth <= middle;
          // Four players on a short felt, the words wider than the middle:
          // under the side seats' badges, across the felt, when that band
          // is free of them; else the felt has no room for them and the
          // headline (the Game tab in a room) says them alone.
          Rect? lower;
          var wordsOnFelt = true;
          if (compact && sides > 0 && !beside && wordsWidth > middle && o.kind != BigTwoOpeningKind.chosen) {
            final sideBottom = (size.height - badgeHeight) * (1 + places[1].y) / 2 + badgeHeight;
            final top = sideBottom + 2, bottom = size.height - badgesBottom;
            if (bottom - top >= wordsHeight) {
              lower = Rect.fromLTRB(8, top, size.width - 8, bottom);
              w = min(w, max(18.0, (top - badgesTop - 4) / cardAspectRatio));
            } else {
              wordsOnFelt = false;
            }
          }
          final h = w * cardAspectRatio;
          final Offset centre, wordsAt;
          if (o.kind == BigTwoOpeningKind.chosen) {
            centre = wordsAt = size.center(Offset.zero);
          } else if (lower != null) {
            centre = Offset(size.width / 2, (badgesTop + lower.top) / 2);
            wordsAt = lower.center;
          } else if (!compact) {
            centre = Offset(size.width / 2, size.height / 2 - (under + wordsHeight) / 2);
            wordsAt = Offset(size.width / 2, centre.dy + h / 2 + under + wordsHeight / 2);
          } else if (beside) {
            final y = badgesTop + band / 2;
            centre = Offset(size.width / 2 - (10 + wordsWidth) / 2, y);
            wordsAt = Offset(centre.dx + rowWidth / 2 + 10 + wordsWidth / 2, y);
          } else {
            final y = badgesTop + band / 2;
            centre = Offset(size.width / 2, y);
            wordsAt = Offset(size.width / 2, y + h / 2 - wordsHeight / 2);
          }
          final landW = seatCardWidth, landH = seatCardWidth * cardAspectRatio;
          final target = bigTwoOpeningTarget(size, places, o.starter, landH);
          final children = <Widget>[];

          // The cards on show: [codes] in a row centred on [centre], the
          // last [held] of them going to the starter's seat once it is named.
          void row(List<int> codes, {required int held, required double appear}) {
            final total = codes.length * w + (codes.length - 1) * gap;
            for (final (i, code) in codes.indexed) {
              final from = Offset(centre.dx - total / 2 + w / 2 + i * (w + gap), centre.dy);
              final goes = i >= codes.length - held;
              final at = goes ? Offset.lerp(from, target, fly)! : from;
              final cw = goes ? lerpDouble(w, landW, fly)! : w;
              final ch = cw * cardAspectRatio;
              // A call nobody answered greys out as the next is made, and
              // fades as the held card goes.
              final grey = o.kind == BigTwoOpeningKind.lowestCalled && i < codes.length - 1;
              final appearAt = o.kind == BigTwoOpeningKind.lowestCalled ? o.callAt(o.called.indexOf(code)) : 0.0;
              final shown = ((p - appearAt) / max(appear, 0.01)).clamp(0.0, 1.0);
              final opacity = grey ? shown * (1 - fly) * 0.45 : shown * (1 - ((p - 0.96) / 0.04).clamp(0.0, 1.0));
              children.add(
                Positioned(
                  left: at.dx - cw / 2,
                  top: at.dy - ch / 2,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: 0.7 + 0.3 * Curves.easeOut.transform(shown),
                      child: GameCardView(
                        key: ValueKey(('opening card', code)),
                        width: cw,
                        face: bigTwoFace(rules.cardOf(code)),
                        dimmed: grey,
                        visibleToAll: goes && named,
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          switch (o.kind) {
            case BigTwoOpeningKind.startingCard:
              row(o.shown, held: o.shown.length, appear: o.namedAt);
            case BigTwoOpeningKind.lowestCalled:
              // The calls so far, the latest few; the starting card is the
              // last call, the one somebody holds.
              final made = [
                for (final (i, code) in o.called.indexed)
                  if (p >= o.callAt(i)) code,
              ];
              final window = made.length > callsShown ? made.sublist(made.length - callsShown) : made;
              row(window, held: named ? 1 : 0, appear: o.namedAt / o.called.length);
            case BigTwoOpeningKind.chosen:
              break;
          }
          if (labelOpacity > 0 && wordsOnFelt) {
            final half = min(wordsWidth, size.width - 16) / 2;
            children.add(
              Positioned(
                left: wordsAt.dx.clamp(8 + half, max(8 + half, size.width - 8 - half)),
                top: wordsAt.dy.clamp(wordsHeight / 2, max(wordsHeight / 2, size.height - wordsHeight / 2)),
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: size.width - 16),
                    child: Opacity(
                      opacity: labelOpacity,
                      child: _Words(label, key: const ValueKey('opening words'), size: fontSize),
                    ),
                  ),
                ),
              ),
            );
          }
          return Stack(clipBehavior: Clip.none, children: children);
        },
      ),
    );
  }
}

/// The step's result, in the middle of the felt until the first play:
/// "Kai starts: 3♦" with a "?" (the Starting card entry), lit under the
/// mouse.
class BigTwoOpeningNote extends StatelessWidget {
  const BigTwoOpeningNote({super.key, required this.label, required this.strings, this.who, this.card});

  /// "Kai starts: 3♦".
  final String label;
  final BigTwoStrings strings;

  /// The same in two lines for a narrow middle (four players on a
  /// sideways phone, between the side seats): "Kai starts", then "3♦".
  /// Null: one line always (a chosen leader has no card).
  final String? who, card;

  /// Narrower than this, the note takes two lines when it can.
  static const twoLinesBelow = 160.0;

  /// The least the note is scaled to before it drops the name line.
  static const leastScale = 0.8;

  @override
  Widget build(BuildContext context) {
    final help = TermsHelpButton(
      title: strings.term(BigTwoTerm.startingCard),
      terms: [strings.entry(BigTwoTerm.startingCard)],
      all: strings.glossary,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final who = this.who, card = this.card;
        final twoLines = who != null && card != null && constraints.maxWidth < twoLinesBelow;
        // Narrower still (four players on the smallest felts, between the
        // side seats): the name would shrink past reading. The starter's
        // badge is lit and holds the card with the eye, so the note keeps
        // the card, its "?" under it.
        if (twoLines && _Words.widthOf(context, who) * leastScale > constraints.maxWidth) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              key: const ValueKey('opening note'),
              mainAxisSize: MainAxisSize.min,
              children: [_Words(card, tight: true), help],
            ),
          );
        }
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: twoLines
              ? Column(
                  key: const ValueKey('opening note'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Words(who),
                    const SizedBox(height: 2),
                    Row(mainAxisSize: MainAxisSize.min, children: [_Words(card), help]),
                  ],
                )
              : Row(
                  key: const ValueKey('opening note'),
                  mainAxisSize: MainAxisSize.min,
                  children: [_Words(label), help],
                ),
        );
      },
    );
  }
}

/// The step's words on a dark chip, readable over the felt.
class _Words extends StatelessWidget {
  const _Words(this.text, {super.key, this.size = 14, this.tight = false});

  final String text;

  /// The words' font size.
  final double size;

  /// Less room at the chip's sides (a short word in a narrow middle).
  final bool tight;

  static const _weight = FontWeight.w600;

  /// The chip's width for [text] at [size].
  static double widthOf(BuildContext context, String text, {double size = 14}) =>
      (TextPainter(
            text: TextSpan(
              text: text,
              style: DefaultTextStyle.of(context).style.merge(TextStyle(fontSize: size, fontWeight: _weight)),
            ),
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout())
          .width +
      20;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: tight ? 6 : 10, vertical: 3),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}
