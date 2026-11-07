import 'dart:math';

import 'package:flutter/material.dart' hide Card;

import '../../../games/big_two/big_two.dart';
import '../../../kit/game_record.dart';
import '../../../l10n/strings.dart';
import '../../kit/card_flights.dart';
import '../../kit/cards.dart';
import '../../kit/felt.dart';
import '../../kit/fit_text.dart';
import '../../kit/table_pile.dart';
import 'big_two_coach_view.dart';
import 'big_two_opening.dart';
import 'l10n/big_two_strings.dart';

/// What the felt reads from a deal as it stands, for the game screen and
/// the review alike.
extension BigTwoTableFacts on BigTwoState {
  /// The last play made this deal and who made it, or null before the
  /// first. It is the play to beat unless everyone else has passed since.
  BigTwoTurn? get lastPlay => history.where((t) => !t.play.isPass).lastOrNull;

  /// The seats that passed since [lastPlay].
  Set<int> get passedSince {
    final turns = history;
    final i = turns.lastIndexWhere((t) => !t.play.isPass);
    return {
      for (final t in turns.skip(i + 1))
        if (t.play.isPass) t.seat,
    };
  }

  /// The trick each turn of [history] belongs to, counted from 0. A trick
  /// ends when everyone else has passed on its last play; a pass on lead
  /// (see BigTwoRules.noTopSingleFinish) belongs to the trick it opens.
  List<int> get trickOfTurns {
    final tricks = <int>[];
    var trick = -1, passes = 0;
    var leading = true, fresh = true;
    for (final turn in history) {
      if (fresh) {
        trick++;
        fresh = false;
      }
      tricks.add(trick);
      if (!turn.play.isPass) {
        leading = false;
        passes = 0;
      } else if (!leading && ++passes >= players - 1) {
        leading = true;
        passes = 0;
        fresh = true;
      }
    }
    return tricks;
  }

  /// The cards of [seat]'s hand everyone at the table has seen
  /// ([BigTwoState.visibleCards]: the starting card until it is played, a
  /// three-player deal's face-up card), lowest first. They show face up in
  /// that seat, or in the player's own fan, with the eye. None once the
  /// deal is over: every hand is face up then.
  List<Card> visibleIn(int seat) => isOver
      ? const []
      : [
          for (final v in visibleCards..sort((a, b) => a.code.compareTo(b.code)))
            if (v.seat == seat) rules.cardOf(v.code),
        ];

  /// The deal's who-goes-first step (BigTwoOpening) while nobody has played
  /// yet: the felt shows it, or its result, until the first play. Null once
  /// someone has played, and for a deal a dealt dragon won.
  BigTwoOpening? get openingNow => history.isEmpty && !isOver ? BigTwoOpening.of(this) : null;
}

/// The felt with the seats round it (2 to 4, by the rules) and the deal's
/// plays piled in the middle (the kit's TablePile): each lands a little
/// askew, so the earlier ones stay in sight under the latest, the play to
/// beat; a tap on the pile opens the deal's history. The player sits at the
/// bottom; play goes to the right: seat 1 on the right, seat 2 across, seat
/// 3 on the left (with three players, the two bots sit across, right then
/// left). Each bot's badge is the place its cards fly to the pile from.
///
/// Each bot shows its name, how many cards it holds (and their backs, as
/// set in Settings, when there is room), Pass when it passed on the play
/// to beat (a chip beside its badge, or in the badge when the felt is too
/// narrow for both), and the light while it is on turn. The pile is drawn
/// above the seats and fitted to the room between their badges, so the
/// play to beat always reads, even on a sideways phone's room felt. A card everyone has
/// seen (BigTwoTableFacts.visibleIn: the starting card until it is played,
/// a three-player deal's face-up card) shows face up in its holder's seat
/// with the eye, the kit's label under the mouse or on a long press, even
/// on a short felt with no room for the backs. After the deal every
/// hand is shown face up, with each seat's points; the Training option
/// Show cards and the review's All cards show them face up during the deal
/// too ([handsUp]). The game wraps each bot's seat so a tap opens its range
/// ([seatWrap]).
///
/// Before the first play the middle shows who goes first: the step
/// ([opening], see big_two_opening.dart) while it plays, the cards it shows
/// landing in the starter's seat at its end; then its result ("Kai starts:
/// 3♦", with a "?") until someone plays. The review's first step shows
/// that result.
///
/// A room's spectators have no hand of their own: with [faceUpSeats] the
/// bottom seat is drawn like the others (its backs, or its cards face up),
/// and the seats listed show their cards face up during the deal (every
/// person's, the bots' only with the host's switch).
class BigTwoTable extends StatelessWidget {
  const BigTwoTable({
    super.key,
    required this.state,
    required this.names,
    required this.strings,
    this.toAct,
    this.handsUp = false,
    this.seed = 0,
    this.points,
    this.seatWrap,
    this.faceUpSeats,
    this.opening,
  });

  /// The deal as it stands.
  final BigTwoState state;

  /// Each seat's name, seat 0 first (see [seatNames]).
  final List<String> names;
  final BigTwoStrings strings;

  /// The seat whose turn is lit; null: none.
  final int? toAct;

  /// The bots' hands face up before the deal is over (Show cards in
  /// Training, the review's All cards).
  final bool handsUp;

  /// Each seat's points for the finished deal, as the match counts them
  /// (bigTwoDealPoints: the penalties, or the winner's points); null: the
  /// deal's own scores, the winner collecting what the losers pay.
  final List<int>? points;

  /// Wraps the bot at `seat` (the game: a tap opens its range, RangeTap);
  /// null: the seats as they are. Never asked for the player's seat.
  final Widget Function(int seat, Widget child)? seatWrap;

  /// The deal's seed: each deal's pile lies its own way, the same on every
  /// redraw (and in the review).
  final int seed;

  /// A spectator's table (a room): the seats whose cards show face up
  /// during the deal, seat 0 drawn on the felt like the others (no hand
  /// strip under it); every hand face up once the deal is over. Null: the
  /// player's own table (seat 0's hand is under it, [handsUp] for the bots).
  final Set<int>? faceUpSeats;

  /// The who-goes-first step playing now: its progress from 0 to 1 (see
  /// BigTwoOpeningStage). Null: none plays (it is over, or the speed is
  /// Instant), and the middle names the starter until the first play.
  final Animation<double>? opening;

  /// The cards the step still has in the air (they show in the starter's
  /// seat once they land).
  Set<int> _inTheAir(BigTwoOpening? step) {
    final o = opening;
    if (o == null || step == null || o.value >= 0.96) return const {};
    return {...step.shown};
  }

  /// [seat]'s cards everyone has seen, as the seat shows them now (none
  /// still in the air in the step).
  List<Card> _visibleNow(int seat, Set<int> inTheAir) => [
    for (final card in state.visibleIn(seat))
      if (!inTheAir.contains(state.rules.codeOf(card))) card,
  ];

  /// Whether [seat]'s cards show face up on the felt.
  bool _faceUp(int seat) {
    if (state.countOf(seat) == 0) return false;
    final up = faceUpSeats;
    if (up == null) return (state.isOver || handsUp) && seat != 0;
    return state.isOver || up.contains(seat);
  }

  /// Whether [seat] shows its cards on the felt at all (face up, or backs).
  bool _onFelt(int seat) => seat != 0 || faceUpSeats != null;

  /// Every turn of the deal as the pile and its history show it.
  static List<PilePlay> pilePlays(BigTwoState state, BigTwoStrings strings) {
    final tricks = state.trickOfTurns;
    return [
      for (final (i, turn) in state.history.indexed)
        PilePlay(
          seat: turn.seat,
          cards: [for (final card in turn.play.cards) bigTwoFace(card)],
          pass: turn.play.isPass,
          label: turn.play.isPass ? null : strings.kind(turn.play.kind),
          trick: tricks[i],
        ),
    ];
  }

  /// The names [seats] are shown by: the player's own seat is "Player" in
  /// the app's language (S.you), whatever name its record keeps; the bots
  /// keep theirs.
  static List<String> seatNames(BuildContext context, List<SeatSpec> seats) => [
    for (final seat in seats) seat.human ? S.of(context).you : seat.name,
  ];

  /// Where each seat sits, by the number of players (seat 0 first).
  static List<Alignment> places(int players) => switch (players) {
    2 => const [Alignment.bottomCenter, Alignment.topCenter],
    3 => const [Alignment.bottomCenter, Alignment(0.9, -1), Alignment(-0.9, -1)],
    _ => const [Alignment.bottomCenter, Alignment(1, -0.15), Alignment.topCenter, Alignment(-1, -0.15)],
  };

  @override
  Widget build(BuildContext context) {
    final o = opening;
    if (o == null) return _felt(context);
    // The step moves the seats too (its cards land in one): all of the felt
    // follows it.
    return AnimatedBuilder(animation: o, builder: (context, _) => _felt(context));
  }

  Widget _felt(BuildContext context) {
    final step = state.openingNow;
    final inTheAir = _inTheAir(step);
    return FeltArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          // Cards in the middle: as large as the felt allows, within reason.
          final cardWidth = min(size.width / 9, size.height / 4.6).clamp(20.0, 58.0);
          final roomy = size.height >= 210;
          final places = BigTwoTable.places(state.players);
          final passes = _passLayout(context, size, places);
          // The pile keeps clear of the seats: the bots' badges (and their
          // backs, their Pass chips) above, the player's badge below, and
          // with four players the badges at the sides. Its cards are as
          // large as that room lets them be, so on a short felt (a sideways
          // phone, a room's felt beside its tabs) they never lie under a
          // badge. Where even its smallest cards don't fit between what the
          // seats show under their badges, it lies over that (never over a
          // badge): it is drawn above the seats, as the play to beat comes
          // first.
          var pileRoom = _pileRoom(size, cardWidth, roomy, chipTop: passes.chipTop, chipBottom: passes.chipBottom);
          final least = pileHeight(18, label: false) + 2;
          // (Before the first play the middle holds only who starts, which
          // keeps to the band.)
          if (state.lastPlay != null && size.height - pileRoom.vertical < least) {
            const minTop = _badgeRoom + 2;
            final minBottom = _badgeRoom + (faceUpSeats == null ? playerBadgeLift : 0);
            final spareTop = max(0.0, pileRoom.top - minTop), spareBottom = max(0.0, pileRoom.bottom - minBottom);
            final spare = spareTop + spareBottom;
            if (spare > 0) {
              final take = min(least - (size.height - pileRoom.vertical), spare);
              pileRoom = pileRoom.copyWith(
                top: pileRoom.top - take * spareTop / spare,
                bottom: pileRoom.bottom - take * spareBottom / spare,
              );
            }
          }
          final band = size.height - pileRoom.vertical;
          // Words under the pile only when the band holds them too.
          final pileLabel = band >= pileHeight(18, label: true);
          final pileCardWidth = fitPileCard(band, cardWidth, label: pileLabel);
          final faceSides = state.players == 4 && (state.isOver || handsUp || _faceUp(1) || _faceUp(3));
          return Stack(
            children: [
              for (var seat = 0; seat < state.players; seat++)
                Align(
                  alignment: places[seat],
                  child: _wrap(
                    seat,
                    _Seat(
                      key: ValueKey('seat $seat'),
                      table: this,
                      seat: seat,
                      cardWidth: cardWidth * 0.62,
                      roomy: roomy,
                      visible: _visibleNow(seat, inTheAir),
                      passInBadge: passes.inBadge.contains(seat),
                      maxWidth: places[seat].x.abs() == 1
                          ? sideSeatWidth(size, faces: state.isOver || handsUp || _faceUp(seat))
                          : _seatWidth(size, seat),
                      // Across, between the side seats (four players): its
                      // cards face up never reach over a side seat's badge.
                      cardsWidth: state.players == 4 && seat == 2
                          ? max(60.0, size.width - 2 * sideSeatWidth(size, faces: faceSides) - 8)
                          : null,
                    ),
                  ),
                ),
              Positioned.fill(
                child: Padding(
                  padding: pileRoom,
                  child: Center(
                    child: _Middle(
                      table: this,
                      cardWidth: pileCardWidth,
                      label: pileLabel,
                      step: opening == null ? step : null,
                    ),
                  ),
                ),
              ),
              if (step != null && opening != null)
                Positioned.fill(
                  child: BigTwoOpeningLayer(
                    opening: step,
                    progress: opening!.value,
                    rules: state.rules,
                    label: bigTwoOpeningText(strings, state.rules, step, names),
                    cardWidth: cardWidth * 1.1,
                    seatCardWidth: _Seat.backsWidth(cardWidth * 0.62, visible: true),
                    places: places,
                    sides: state.players == 4 ? sideSeatWidth(size, faces: faceSides) : 0,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _name(int seat) => seat < names.length ? names[seat] : '';

  /// The most width a seat above or below the pile takes on a felt [size]
  /// wide (the side seats': [sideSeatWidth]).
  double _seatWidth(Size size, int seat) => size.width * (state.players == 2 || seat == 0 ? 0.9 : 0.46);

  /// Where each seat above or below the pile that passed shows its Pass:
  /// a chip beside its badge when both fit; else in the badge, the badge
  /// drawn a little smaller if need be (down to [passScale]) but never cut
  /// ([inBadge]); else, for a very long name, a chip on a line of its own
  /// ([chipTop], [chipBottom]: the pile keeps clear of it). Side seats
  /// (four players) stack theirs under the badge, beside the pile.
  ({Set<int> inBadge, bool chipTop, bool chipBottom}) _passLayout(
    BuildContext context,
    Size size,
    List<Alignment> places,
  ) {
    final inBadge = <int>{};
    var chipTop = false, chipBottom = false;
    if (state.isOver) return (inBadge: inBadge, chipTop: false, chipBottom: false);
    final chip = textWidth(context, strings.pass, _PassChip.style) + 2 * _PassChip.padX;
    for (final seat in state.passedSince) {
      if (places[seat].x.abs() == 1) continue;
      final width = _seatWidth(size, seat) - 4;
      final plain = SeatBadge(name: _name(seat), cardsLeft: state.countOf(seat)).naturalWidth(context);
      if (plain + 4 + chip <= width) continue;
      final withPass = SeatBadge(name: _name(seat), cardsLeft: state.countOf(seat), role: strings.pass);
      if (withPass.naturalWidth(context) * passScale <= width) {
        inBadge.add(seat);
      } else if (seat == 0) {
        chipBottom = true;
      } else {
        chipTop = true;
      }
    }
    return (inBadge: inBadge, chipTop: chipTop, chipBottom: chipBottom);
  }

  Widget _wrap(int seat, Widget child) {
    final wrap = seatWrap;
    return wrap == null || seat == 0 ? child : wrap(seat, child);
  }

  /// The width of the pile's cards in a band [band] tall: the felt's
  /// [cardWidth], or smaller when the band can't hold the cards (and the
  /// words under them, "Pair · Kai", with [label]), but never under 18 px,
  /// so a card's corner still reads.
  static double fitPileCard(double band, double cardWidth, {required bool label}) =>
      min(cardWidth, max(18.0, (band - (label ? 18 : 0)) / (cardAspectRatio * _stray)));

  /// How much taller than its cards the pile lies, for their strays.
  static const _stray = 1.25;

  /// The height the pile needs for cards [cardWidth] wide, a little stray
  /// room, and the words under them with [label] (see [fitPileCard]).
  static double pileHeight(double cardWidth, {required bool label}) =>
      cardWidth * cardAspectRatio * _stray + (label ? 18 : 0);

  /// The width a side seat takes (four players): its badge, with what it
  /// shows stacked under it rather than beside it.
  static const _sideSeatWidth = 80.0;

  /// A side seat's width on a felt of [size]: [_sideSeatWidth], or with its
  /// cards face up ([faces]: Show cards, the review's All cards, the deal
  /// over) a sixth of a wide felt, their faces in two rows under the badge
  /// (see [_Seat]). The pile stays between the two side seats.
  static double sideSeatWidth(Size size, {required bool faces}) =>
      faces ? max(_sideSeatWidth, size.width * 0.17) : _sideSeatWidth;

  /// How far the player's badge sits above the felt's bottom edge: the
  /// hand's Sort button rises over that edge (its cards keep their size, see
  /// HandFan), and late in a deal, when the fan is short, it comes in under
  /// the badge. Enough for a gap of 2 px or more at every size checked.
  static const playerBadgeLift = 7.0;

  /// A seat's badge with its padding, as tall as the felt lays it out.
  static const _badgeRoom = 34.0;

  /// The least a badge showing Pass is scaled to (about 10 px words), on
  /// the smallest felts: smaller than that, Pass goes on a line of its own.
  static const passScale = 0.68;

  /// A Pass chip on a line of its own, with its gap.
  static const _chipLine = 23.0;

  /// The room the seats take at the felt's edges, which the pile stays out
  /// of; [chipTop] and [chipBottom]: a seat above or below it shows Pass on
  /// a line of its own.
  EdgeInsets _pileRoom(Size size, double cardWidth, bool roomy, {required bool chipTop, required bool chipBottom}) {
    const badge = _badgeRoom;
    // Under the top badges: the bots' backs when there is room for them;
    // after the deal (or with All cards in the review) their cards face up
    // whatever the room, so a short felt keeps room for those too, or the
    // top seat's last cards would lie on the winning play.
    final faceUp = state.isOver || handsUp || (faceUpSeats?.any((s) => s != 0 && _faceUp(s)) ?? false);
    // A visible card shows face up among a top seat's backs even on a short
    // felt, so the pile keeps clear of it too.
    final places = BigTwoTable.places(state.players);
    final topVisible = [
      for (var s = 1; s < state.players; s++)
        if (places[s].x.abs() != 1 && state.visibleIn(s).isNotEmpty) s,
    ].isNotEmpty;
    final cards = faceUp
        ? max(18.0, cardWidth * 0.62 * 0.8) * cardAspectRatio + 3
        : topVisible
        ? _Seat.backsWidth(cardWidth * 0.62, visible: true) * cardAspectRatio + 3
        : roomy
        ? cardWidth * 0.62 * 0.75 * cardAspectRatio + 3
        : 0.0;
    final top = badge + (chipTop ? _chipLine : 0) + cards + 2;
    // With four players the side seats (a badge, with its Pass chip and
    // backs under it) sit level with the pile, which stays between them.
    final side = state.players == 4
        ? sideSeatWidth(size, faces: faceUp && (faceUpSeats == null || _faceUp(1) || _faceUp(3)))
        : 4.0;
    // The pile keeps clear of the player's lifted badge too (on a short
    // felt its cards get smaller for it, see fitPileCard). A spectator's
    // bottom seat shows its cards above its badge too.
    final chip = chipBottom ? _chipLine : 0.0;
    final bottom = faceUpSeats == null
        ? badge + chip + playerBadgeLift
        : badge +
              chip +
              (_faceUp(0)
                  ? max(18.0, cardWidth * 0.62 * 0.8) * cardAspectRatio + 3
                  : state.visibleIn(0).isNotEmpty
                  ? _Seat.backsWidth(cardWidth * 0.62, visible: true) * cardAspectRatio + 3
                  : roomy
                  ? cardWidth * 0.62 * 0.75 * cardAspectRatio + 3
                  : 0.0);
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }
}

/// The deal's plays piled up (TablePile): the latest bright while it is the
/// play to beat, darkened once everyone else has passed (its maker leads
/// next); a tap opens the history. Nothing before the first play.
class _Middle extends StatelessWidget {
  const _Middle({required this.table, required this.cardWidth, required this.label, required this.step});

  final BigTwoTable table;
  final double cardWidth;

  /// Whether the words under the pile show (TablePile.showLabel).
  final bool label;

  /// Before the first play, once the step is over: who starts.
  final BigTwoOpening? step;

  @override
  Widget build(BuildContext context) {
    final state = table.state;
    if (step case final step?) {
      final seat = step.starter;
      return BigTwoOpeningNote(
        label: bigTwoOpeningText(table.strings, state.rules, step, table.names),
        strings: table.strings,
        who: table.strings.starts(table._name(seat), null),
        card: step.startCode < 0 ? null : state.rules.cardOf(step.startCode).label,
      );
    }
    if (state.lastPlay == null) return const SizedBox.shrink();
    return TablePile(
      key: const ValueKey('to beat'),
      plays: BigTwoTable.pilePlays(state, table.strings),
      names: table.names,
      cardWidth: cardWidth,
      // Lit while it is the play to beat, and the winning play at the end.
      toBeat: state.current != null,
      passLabel: table.strings.pass,
      seed: table.seed,
      showLabel: label,
    );
  }
}

/// One seat: its badge, then its cards (backs, or face up after the deal)
/// and its Pass chip or points. The player's own seat is only the badge:
/// the hand is in the strip below.
class _Seat extends StatelessWidget {
  const _Seat({
    super.key,
    required this.table,
    required this.seat,
    required this.cardWidth,
    required this.roomy,
    required this.maxWidth,
    required this.visible,
    this.cardsWidth,
    this.passInBadge = false,
  });

  final BigTwoTable table;
  final int seat;
  final double cardWidth;
  final bool roomy;

  /// The seat's cards everyone has seen, face up with the eye (those the
  /// who-goes-first step still has in the air come once they land).
  final List<Card> visible;

  /// The most width the seat may take: its cards face up squeeze into it.
  final double maxWidth;

  /// The most width its cards may take, when less than [maxWidth].
  final double? cardsWidth;

  /// It passed, and shows Pass in its badge (see BigTwoTable._passLayout).
  final bool passInBadge;

  /// The width of a seat's backs for a seat [cardWidth]: three quarters of
  /// it, or with a visible card among them ([visible]) at least 18 px, so
  /// that card's corner still reads on a sideways phone.
  static double backsWidth(double cardWidth, {required bool visible}) =>
      visible ? max(18.0, cardWidth * 0.75) : cardWidth * 0.75;

  @override
  Widget build(BuildContext context) {
    final state = table.state;
    final over = state.isOver;
    // A side seat (four players) stays narrow beside the pile.
    final atSide = BigTwoTable.places(state.players)[seat].x.abs() == 1;
    final passed = !over && state.passedSince.contains(seat);
    final inBadge = passed && passInBadge;
    Widget seatBadge = SeatBadge(
      key: inBadge ? const ValueKey('pass in badge') : null,
      name: table._name(seat),
      cardsLeft: state.countOf(seat),
      role: inBadge ? table.strings.pass : null,
      toAct: !over && table.toAct == seat,
      winner: over && state.winner == seat,
    );
    if (inBadge) {
      // Whole, scaled down to the seat's width rather than cut.
      final natural = (seatBadge as SeatBadge).naturalWidth(context);
      seatBadge = FittedBox(fit: BoxFit.scaleDown, child: SizedBox(width: natural, child: seatBadge));
    }
    final badge = FlightSpot(tag: CardFlights.seatTag(seat), child: seatBadge);
    final note = over
        ? _Points(points: (table.points ?? state.result.scores)[seat], winner: state.winner == seat)
        : passed && !inBadge
        ? _PassChip(label: table.strings.pass)
        : null;
    final faceUp = table._faceUp(seat);
    final faces = [for (final card in state.handOf(seat)) bigTwoFace(card)];
    // The cards everyone has seen: face up with the eye, among the backs or
    // where they are among the faces.
    final visible = [for (final card in this.visible) bigTwoFace(card)];
    Widget faceRow(List<CardFace> row) =>
        SeatHand(count: row.length, faces: row, cardWidth: max(18, cardWidth * 0.8), visibleToAll: visible);
    // Face up (squeezed to the seat's width; a side seat's in two rows when
    // it holds more than 7, so each corner still reads), or a short fan of
    // backs; on a short felt only the visible cards, never hidden.
    final cards = faceUp
        ? atSide && faces.length > 7
              ? Column(
                  key: const ValueKey('seat face rows'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    faceRow(faces.sublist(0, (faces.length + 1) ~/ 2)),
                    const SizedBox(height: 2),
                    faceRow(faces.sublist((faces.length + 1) ~/ 2)),
                  ],
                )
              : faceRow(faces)
        : !over && table._onFelt(seat) && state.countOf(seat) > 0 && (roomy || visible.isNotEmpty)
        ? SeatHand(
            count: state.countOf(seat),
            cardWidth: backsWidth(cardWidth, visible: visible.isNotEmpty),
            maxBacks: roomy ? 6 : 0,
            visibleToAll: visible,
          )
        : null;
    final atBottom = seat == 0;
    final extras = [?note];
    // A side seat stacks its chips under the badge, so it stays narrow
    // beside the pile; the others put them beside it while the badge keeps
    // its name there, else on the next line (a sideways phone's room,
    // where the felt is narrow): the name is never cut to a letter or two
    // to make room for a chip.
    final Widget header;
    if (atSide) {
      header = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          badge,
          for (final extra in extras) Padding(padding: const EdgeInsets.only(top: 3), child: extra),
        ],
      );
    } else if (extras.isEmpty) {
      header = badge;
    } else {
      final start = BigTwoTable.places(state.players)[seat].x < 0;
      header = Wrap(
        alignment: start ? WrapAlignment.start : WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        verticalDirection: atBottom ? VerticalDirection.up : VerticalDirection.down,
        spacing: 4,
        runSpacing: 3,
        // Each chip at its own width (a Wrap would stretch the card's).
        children: [badge, for (final extra in extras) IntrinsicWidth(child: extra)],
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(2, 2, 2, atBottom ? 2 + BigTwoTable.playerBadgeLift : 2),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          verticalDirection: atBottom ? VerticalDirection.up : VerticalDirection.down,
          children: [
            header,
            if (cards != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: cardsWidth == null
                    ? cards
                    : ConstrainedBox(constraints: BoxConstraints(maxWidth: cardsWidth!), child: cards),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Pass", beside (or under) the badge of a seat that passed on the play
/// to beat, unless the seat shows it in its badge.
class _PassChip extends StatelessWidget {
  const _PassChip({required this.label});

  final String label;

  static const style = TextStyle(fontSize: 12, color: Colors.white70);
  static const padX = 7.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pass chip'),
      padding: const EdgeInsets.symmetric(horizontal: padX, vertical: 2),
      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: style),
    );
  }
}

/// A seat's points for the deal, "+27" or "−9" (or a match's "+9" penalty),
/// green for the deal's winner.
class _Points extends StatelessWidget {
  const _Points({required this.points, required this.winner});

  final int points;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    final text = points > 0 ? '+$points' : (points < 0 ? '−${-points}' : '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: winner ? const Color(0xCC2E7D32) : Colors.black45,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
