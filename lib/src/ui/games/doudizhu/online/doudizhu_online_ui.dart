/// Fight the Landlord in a room, on the app's side: the solo game's table,
/// hand and buttons, fed from the room's views instead of a controller.
///
/// - The table is the solo LandlordTable: the two others at the top
///   corners, the kitty between them, the deal's plays piled in the middle
///   (a tap opens the history, the bids included), the player's badge at
///   the bottom right. Turned so the player sits at the bottom; a spectator
///   sees the first seat there, with every hand they may see face up under
///   its badge. Plays fly in from the seats, the kitty to the landlord.
///   The cards everyone has seen (the face-up card that decided the first
///   bidder, the shown kitty) show face up in their holder's seat with the
///   kit's eye, for every seat and spectator, a hidden bot's too.
/// - Every deal opens with who bids first, as in the solo game
///   (doudizhu_opening.dart), at this device's Animations speed: the cards
///   go round from the stack, the face-up card to its holder, then "Ana
///   bids first". It needs nothing the view doesn't carry (the first bidder
///   and the face-up card; the order the cards go out is made up from
///   them and this device's own cards). Moves the room sends meanwhile
///   show once it is over, and the player's buttons wait for it.
/// - A seated player's hand is the solo fanned hand: a tap picks a card,
///   a drag moves it, the Sort button sorts by rank or suit. The buttons
///   are the solo ones (the bids, then Pass, Clear and Play), greyed out
///   unless they can be used; a pass that can't be avoided plays itself
///   after a moment, as in the solo game. The card counter is under them.
/// - A spectator's coach (off at first, the room's chip) rates the acting
///   seat's moves from that seat's view rebuilt from what the spectator
///   sees: never a hidden bot.
/// - Nothing here ever holds a card its device wasn't sent: each view is
///   replayed on stand-ins for the cards it doesn't show
///   (doudizhu_view_codec.dart), and only the cards it does show are drawn
///   face up.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../app/app_settings.dart';
import '../../../../games/doudizhu/app/doudizhu_analysis.dart';
import '../../../../games/doudizhu/app/doudizhu_grading.dart';
import '../../../../games/doudizhu/app/doudizhu_online_jobs.dart';
import '../../../../games/doudizhu/doudizhu.dart';
import '../../../../games/doudizhu/online/doudizhu_runner.dart';
import '../../../../games/doudizhu/online/doudizhu_view_codec.dart';
import '../../../../kit/coach_answer.dart';
import '../../../../kit/hand_order.dart';
import '../../../../online/games/game_runner.dart';
import '../../../kit/card_flights.dart';
import '../../../kit/cards.dart';
import '../../../kit/felt.dart';
import '../../../kit/game_sounds.dart';
import '../../../kit/l10n/game_strings.dart';
import '../../../kit/l10n/kit_strings.dart';
import '../../../kit/match_view.dart' show totalText;
import '../../../kit/table_pile.dart';
import '../../../online/online_game_ui.dart';
import '../../../online/runner_client.dart';
import '../../../table_controller.dart' show PlaybackSpeed;
import '../doudizhu_cards.dart';
import '../doudizhu_coach_view.dart';
import '../doudizhu_opening.dart';
import '../doudizhu_setup.dart';
import '../doudizhu_table.dart';
import '../l10n/doudizhu_strings.dart';
import 'doudizhu_online_strings.dart';

/// Fight the Landlord's online part (registered in online_game_uis.dart).
// ignore: unnecessary_nullable_for_final_variable_declarations
final OnlineGameUi? doudizhuOnlineUi = DoudizhuOnlineUi();

/// The rules a move's words are read under: every variant allowed, so a
/// play legal under the room's rules always reads (the labels only name
/// moves the room let through).
const _anyRules = DdzRules(fourWithTwo: true, rocketAsKickers: true);

class DoudizhuOnlineUi extends OnlineGameUi {
  DoudizhuOnlineUi();

  @override
  OnlineGame get online => doudizhuOnline!;

  @override
  GameStrings strings(BuildContext context) => LandlordStrings.of(context);

  @override
  Map<String, Object?>? seatViewFrom(Map<String, Object?> spectatorView, int seat) =>
      ddzSeatViewFrom(spectatorView, seat);

  @override
  OnlineJob<Object?, Object?> botJob(Map<String, Object?> seatView, String level, {required int seed}) =>
      OnlineJob(const DdzOnlineBotJob(), DdzOnlineBotInput(view: seatView, level: level, seed: seed));

  @override
  String botMove(Object? output) => output! as String;

  /// The Easy bot's rule of thumb, inline (it searches nothing), drawing
  /// from [seed] like the bot job (the host's secret salt in it); the
  /// room's auto move if even that fails.
  @override
  String fallbackMove(Map<String, Object?> seatView, {required int seed}) {
    try {
      final view = ddzOnlineJobView(seatView);
      return ddzOnlineMoveFor(view, DdzBot(DdzLevel.easy, random: Random(seed)).chooseMove(view));
    } on Object {
      return ddzAutoMove(DdzWireView.read(seatView).replay()!);
    }
  }

  @override
  OnlineJob<Object?, Object?> coachJob(Map<String, Object?> seatView, {required int seed}) =>
      OnlineJob(const DdzOnlineCoachJob(), DdzOnlineCoachInput(view: seatView, seed: seed));

  /// The solo coach's answer, with the choices that aren't plays (Pass, No
  /// bid, the bids) always listed.
  @override
  CoachAnswer toAnswer(Object? output) {
    final answer = ddzAnswer(output! as DdzAdvice);
    return answer.withListed({
      for (final line in answer.lines)
        if (!line.move.contains(':x')) line.move,
    });
  }

  @override
  Widget table(BuildContext context, RunnerClient c) =>
      _LandlordOnlineTable(seen: DdzOnlineSeen.of(c, speed: AppSettings.of(context).speed));

  @override
  Widget? bottom(BuildContext context, RunnerClient c) =>
      c.you == null ? null : _LandlordOnlineHand(seen: DdzOnlineSeen.of(c, speed: AppSettings.of(context).speed));

  @override
  Widget actions(BuildContext context, RunnerClient c) =>
      _LandlordOnlineButtons(seen: DdzOnlineSeen.of(c, speed: AppSettings.of(context).speed));

  @override
  Widget rulesForm(
    BuildContext context,
    Map<String, Object?> rules, {
    required bool enabled,
    required ValueChanged<Map<String, Object?>> onChange,
  }) => Column(
    key: const ValueKey('ddz rules'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: landlordRulesRows(context, DdzRules.fromJson(rules), (r) => onChange(r.toJson()), enabled: enabled),
  );

  @override
  String moveLabel(BuildContext context, String move) => ddzMoveLabel(LandlordStrings.of(context), move, _anyRules);

  /// While the cards go round, nothing (the face-up card hasn't landed:
  /// nobody knows who bids first yet); once it has, what the felt says
  /// ("Ann bids first") until the step is over.
  @override
  String? heldTurnText(BuildContext context, RunnerClient c) {
    final seen = DdzOnlineSeen.of(c, speed: AppSettings.of(context).speed);
    final dealing = seen.dealing;
    if (dealing == null) return null;
    if (!dealing.landed) return '';
    final g = dealing.game;
    return LandlordStrings.of(context).firstToBid(c.nameOf(seen.handSeat(dealing.order.firstBidder)), g.rules.bidding);
  }

  /// The step that opens the deal, on this device (the same one the table
  /// plays: made here first if the Game tab is built before the table).
  @override
  Listenable tablePlayback(BuildContext context, RunnerClient c) =>
      DdzOnlineSeen.of(c, speed: AppSettings.of(context).speed);

  /// "You win", "Landlord Ann wins" or "Peasants win", then the stake
  /// times the doublings ("×4") and a spring when there was one.
  @override
  String resultText(BuildContext context, RunnerClient c) {
    final r = c.over?.result ?? const {};
    final lord = r['landlord'], winner = r['winner'];
    if (lord is! int || winner is! int) return '';
    final s = LandlordStrings.of(context);
    final lordWon = winner == lord;
    final you = c.you;
    final head = you != null && (you == lord) == lordWon
        ? KitStrings.of(context).youWin
        : (lordWon
              ? LandlordOnlineStrings.of(context).landlordWins(c.nameOf(lord))
              : LandlordOnlineStrings.of(context).peasantsWin);
    final stake = r['stake'], multiplier = r['multiplier'];
    return [
      head,
      if (stake is int && multiplier is int) s.multiplier(stake * multiplier),
      if (r['spring'] == true) s.spring,
      if (r['antiSpring'] == true) s.antiSpring,
    ].join(' · ');
  }
}

/// What one device has made of the room's latest view of the deal (one
/// per RunnerClient, for as long as it lives): the view read and replayed,
/// the same turned so this player sits at the bottom, the seated player's
/// picked cards and hand order; and as each move comes in, its cards'
/// flights and sound (only while the game's screen is open).
class DdzOnlineSeen extends ChangeNotifier {
  DdzOnlineSeen._(this.c, this.speed) {
    c.addListener(_update);
    _update();
  }

  static final _all = Expando<DdzOnlineSeen>();

  /// The one for [c]; [speed]: the Animations setting now (the first deal's
  /// step runs at it, so it is given before the first view is read).
  static DdzOnlineSeen of(RunnerClient c, {PlaybackSpeed? speed}) {
    final seen = _all[c] ??= DdzOnlineSeen._(c, speed ?? PlaybackSpeed.normal);
    if (speed != null) seen.speed = speed;
    return seen;
  }

  final RunnerClient c;

  /// The table's card flights, at the Animations setting's speed (the
  /// screen sets [speed]).
  late final CardFlights flights = CardFlights(speed: () => speed);
  PlaybackSpeed speed;

  /// The step that opens the deal on this device, while it runs
  /// (doudizhu_opening.dart): its cards dealt so far, seen from the
  /// bottom seat ([display]'s seats); null once it is over.
  LandlordDealing? get dealing => _clock?.now;
  LandlordDealClock? _clock;

  Map<String, Object?>? _view;

  /// The latest view, read (null before the first, or if it can't be read).
  DdzWireView? wire;

  /// That view replayed, in the round's hand seats: this player's hand and
  /// legal moves are the real ones (see DdzWireView.replay).
  DdzGame? game;

  /// The hand seat at the bottom of the table: the player's, or the first
  /// for a spectator.
  int base = 0;

  /// The view turned so [base] is seat 0, replayed: what the table draws.
  DdzGame? display;

  int _round = -1, _redeals = -1, _moves = 0;
  int? _turnSounded;
  bool _overSounded = false;
  Timer? _forced;
  int? _forcedTurn;

  /// The cards the seated player picked (ids).
  Set<int> selected = const {};

  /// How the seated player's hand is laid out (rank, suit, or their own
  /// order once they drag a card); a new deal starts sorted again.
  HandArrangement<int> arrangement = const HandArrangement<int>.sorted();

  /// The hand seat [display] seat [seat] is.
  int handSeat(int seat) => (seat + base) % 3;

  /// The seated player's cards as the hand shows them (while the deal
  /// opens, the cards dealt so far: the bottom seat's).
  List<int> get hand {
    final g = game, you = c.you;
    if (g == null || you == null) return const [];
    final cards = dealing?.game.hands[0] ?? g.hands[you];
    return arrangement.arrange(ddzHandSorted(cards, arrangement.sort));
  }

  /// Whether the player may act now: their turn, and the deal's first
  /// step over.
  bool get myTurn => c.myTurn && dealing == null;

  /// Whether it is the player's turn to play cards.
  bool get canPlay {
    final g = game;
    return myTurn && g != null && g.phase == DdzPhase.playing && g.toAct == c.you;
  }

  /// The play the picked cards make that may be played now, or null.
  Play? get selectedPlay {
    final g = game;
    if (!canPlay || g == null || selected.isEmpty) return null;
    final play = readPlay([for (final id in selected) rankOfId(id)], g.current, g.rules);
    return play != null && g.isLegal(DdzPlay(play)) ? play : null;
  }

  /// The player [move]s now, if it is legal: a play with the cards picked.
  void play(DdzMove move, [List<int> cards = const []]) {
    final g = game, you = c.you;
    if (!myTurn || g == null || you == null || !g.isLegal(move)) return;
    c.move(ddzOnlineMoveText(you, move, cards));
    selected = const {};
    notifyListeners();
  }

  /// Plays the picked cards, if they make a legal play.
  void playSelection() {
    final play = selectedPlay;
    if (play != null) this.play(DdzPlay(play), [...selected]..sort());
  }

  /// Picks or unpicks card [id].
  void toggle(int id) {
    final g = game, you = c.you;
    if (dealing != null || g == null || you == null || !g.hands[you].contains(id)) return;
    selected = selected.contains(id) ? ({...selected}..remove(id)) : {...selected, id};
    notifyListeners();
  }

  /// Clear: the picked cards go down.
  void clearSelection() {
    if (selected.isEmpty) return;
    selected = const {};
    notifyListeners();
  }

  /// The card at [from] in [hand] was dragged to [to].
  void reorder(int from, int to) {
    if (dealing != null) return;
    arrangement = arrangement.moved(hand, from, to);
    notifyListeners();
  }

  /// The Sort button: Rank and Suit take turns; from the player's own
  /// order, back to the sort last chosen.
  void sortTap() {
    if (dealing != null) return;
    arrangement = arrangement.next;
    notifyListeners();
  }

  void _sound(SoundEffect effect) {
    if (c.onScreen) GameSounds.play(effect, speed: speed);
  }

  void _update() {
    if (c.gameOver) {
      _forced?.cancel();
      _clock?.cancel();
      _clock = null;
      notifyListeners();
      return;
    }
    final view = c.view;
    if (!identical(view, _view)) {
      _view = view;
      _read(view);
    }
    _turn();
    notifyListeners();
  }

  /// Reads a new view: replays it, and flies and sounds what is new.
  void _read(Map<String, Object?>? view) {
    final before = display;
    DdzWireView? wire;
    try {
      wire = view == null ? null : DdzWireView.read(view);
    } on Object {
      wire = null;
    }
    this.wire = wire;
    base = c.you ?? 0;
    game = wire?.replay();
    display = wire?.rotated(base).replay();
    final shown = display;
    if (wire == null || shown == null) return;
    final you = c.you, g = game;
    if (you != null && g != null) selected = {...selected.where(g.hands[you].contains)};
    if (c.round != _round || wire.redeals != _redeals) {
      // A new deal (a new round, or one dealt again): sorted again, and
      // opened with who bids first while its auction is on (a device that
      // comes in during the auction, its screen opening a moment after the
      // deal, is shown how the deal opened too, then where it is).
      _clock?.cancel();
      _clock = null;
      if (shown.phase == DdzPhase.bidding) _open(shown);
      _round = c.round;
      _redeals = wire.redeals;
      _moves = wire.moves.length;
      selected = const {};
      arrangement = arrangement.dealt;
      _overSounded = false;
      if (_moves <= 1) _sound(SoundEffect.deal);
      return;
    }
    // Moves made while the deal still opens show when it is over, at once.
    if (wire.moves.length == _moves + 1 && dealing == null) _fly(shown, before);
    _moves = wire.moves.length;
    final result = g?.result;
    if (result != null && !_overSounded) {
      _overSounded = true;
      if (you != null) _sound(result.wonBy(you) ? SoundEffect.win : SoundEffect.lose);
    }
  }

  /// Opens the deal on [shown] (the view turned, the auction on): its
  /// cards go round from hand seat 0's place, at this device's speed (none
  /// at Instant); then the latest view shows, and the player's turn opens.
  void _open(DdzGame shown) {
    final seated = c.you != null;
    final clock = _clock = LandlordDealClock(
      start: shown,
      order: DdzDealOrder.of(shown, firstSeat: (3 - base) % 3),
      factor: speed.factor,
      fanSeat: seated ? 0 : null,
      onChange: notifyListeners,
      // The player's fan is outside the table's flights: their own card
      // just comes into the hand.
      onFaceUp: (id) {
        final holder = shown.firstBidder;
        if (seated && holder == 0) return;
        unawaited(
          flights.fly([
            CardFlight(from: LandlordTable.deckTag, to: LandlordTable.faceUpTag(holder), face: ddzFace(id)),
          ]),
        );
      },
    );
    unawaited(
      clock.run().then((_) {
        if (!identical(_clock, clock)) return;
        _clock = null;
        _moves = wire?.moves.length ?? _moves;
        _turn();
        notifyListeners();
      }),
    );
  }

  /// The move just made on [shown]: its cards fly from the seat to the
  /// pile; when it made a landlord, the kitty flies to them.
  void _fly(DdzGame shown, DdzGame? before) {
    final action = shown.history.last;
    final move = action.move;
    if (move is DdzPlay) {
      final index = shown.history.length - 1;
      unawaited(
        flights.fly([
          for (final (k, id) in ddzPlayOrder(action.cardIds, move.play).indexed)
            CardFlight(from: CardFlights.seatTag(action.seat), to: TablePile.flightTag(index, k), face: ddzFace(id)),
        ]),
      );
    }
    final lord = shown.landlord;
    if (before?.landlord == null && lord != null) {
      final up = wire?.kitty != null;
      unawaited(
        flights.fly([
          for (final (k, id) in ddzSorted(shown.kitty).indexed)
            CardFlight(
              from: LandlordTable.kittyTag(k),
              to: LandlordTable.lordCardTag(lord, k),
              face: up ? ddzFace(id) : null,
              faceUp: up,
            ),
        ]),
      );
    }
    _sound(switch (move) {
      DdzPlay(:final play) when play.isBombLike => SoundEffect.bomb,
      DdzPlay() => SoundEffect.cardsDown,
      DdzPass() || DdzBid(isPass: true) || DdzCall(yes: false) || DdzRob(yes: false) => SoundEffect.pass,
      _ => SoundEffect.chips,
    });
  }

  /// The player's turn: its sound once, and a pass that can't be avoided
  /// (nothing in hand beats the table: 要不起) played after a moment, as in
  /// the solo game.
  void _turn() {
    final turn = c.turn;
    if (!myTurn || turn == null) return;
    if (_turnSounded != turn.turnId) {
      _turnSounded = turn.turnId;
      _sound(SoundEffect.yourTurn);
    }
    final g = game;
    if (g == null || g.phase != DdzPhase.playing || _forcedTurn == turn.turnId) return;
    final legal = g.legalMoves();
    if (legal.length != 1 || legal.single is! DdzPass) return;
    _forcedTurn = turn.turnId;
    _forced?.cancel();
    _forced = Timer(cantBeatPause, () {
      if (c.myTurn && c.turn?.turnId == turn.turnId) play(const DdzPass());
    });
  }

  /// How long "Can't beat" shows before its pass plays itself.
  static const cantBeatPause = Duration(milliseconds: 900);

  /// Whether the player can only pass now (the buttons say so).
  bool get cantBeat {
    final g = game;
    if (!myTurn || g == null || g.phase != DdzPhase.playing) return false;
    final legal = g.legalMoves();
    return legal.length == 1 && legal.single is DdzPass;
  }
}

/// The table: the solo LandlordTable on the room's view, with its card
/// flights.
class _LandlordOnlineTable extends StatelessWidget {
  const _LandlordOnlineTable({required this.seen});

  final DdzOnlineSeen seen;

  @override
  Widget build(BuildContext context) {
    seen.speed = AppSettings.of(context).speed;
    final s = LandlordStrings.of(context);
    return ListenableBuilder(
      listenable: seen,
      builder: (context, _) {
        final dealing = seen.dealing;
        final game = dealing?.game ?? seen.display, wire = seen.wire;
        final c = seen.c;
        if (game == null || wire == null) return const FeltArea();
        final result = game.result;
        final turn = c.turn;
        final total = game.stake == 0 ? null : game.stake * game.multiplier;
        final table = LandlordTable(
          key: const ValueKey('ddz online table'),
          felt: LandlordFelt(
            game: game,
            names: [for (var d = 0; d < 3; d++) c.nameOf(seen.handSeat(d))],
            toAct: dealing != null
                ? (dealing.landed ? dealing.order.firstBidder : null)
                : (result != null || turn == null ? null : (turn.seat - seen.base) % 3),
            dealing: dealing,
            over: result != null,
            winners: [
              for (var d = 0; d < 3; d++)
                if (result != null && result.wonBy(d)) d,
            ],
            seed: c.round * 7919 + wire.redeals,
            bottomName: c.you == null ? c.nameOf(seen.base) : null,
            faceUpSeats: {
              for (var d = 0; d < 3; d++)
                if (c.you == null && wire.hands.containsKey(seen.handSeat(d))) d,
            },
            bottomHand: c.you == null,
            kittyUp: wire.kitty != null,
            note: total != null
                ? s.multiplier(total)
                : (wire.redeals > 0 && game.history.isEmpty ? s.everyonePassed : null),
            playerSpot: true,
            // The room's scores on the badges, as Gomoku's and Blackjack's
            // seats show them.
            scores: [
              for (var d = 0; d < 3; d++)
                if (c.seatInfo(seen.handSeat(d))?.score case final score?) totalText(score.round()) else null,
            ],
          ),
          strings: s,
        );
        return CardFlightLayer(
          flights: seen.flights,
          child: LayoutBuilder(
            builder: (context, box) {
              // On a sideways phone the room's bar and the hand leave the
              // felt less height than the solo screen does: it is laid out
              // at the least height its seats and pile need, and drawn a
              // little smaller, rather than cut.
              if (!box.maxHeight.isFinite || box.maxHeight >= leastHeight) return table;
              final scale = box.maxHeight / leastHeight;
              return FittedBox(
                child: SizedBox(width: box.maxWidth / scale, height: leastHeight, child: table),
              );
            },
          ),
        );
      },
    );
  }

  /// The least height the felt is laid out at (see build).
  static const leastHeight = 190.0;
}

/// The seated player's hand: the solo fanned hand.
class _LandlordOnlineHand extends StatelessWidget {
  const _LandlordOnlineHand({required this.seen});

  final DdzOnlineSeen seen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: seen,
    builder: (context, _) {
      final game = seen.game, you = seen.c.you, dealing = seen.dealing;
      final live = game != null && game.result == null && you != null && dealing == null;
      return LandlordHand(
        cards: seen.hand,
        // The cards everyone has seen (the face-up card, the shown kitty),
        // while the deal is on; while it opens, the face-up card once dealt.
        visible: dealing != null
            ? {...dealing.game.visibleIn(0)}
            : (live ? {...game.visibleIn(you)} : const {}),
        selected: seen.selected,
        onToggle: live ? seen.toggle : null,
        onReorder: live ? seen.reorder : null,
        sortOrder: seen.arrangement.order,
        onSort: live ? seen.sortTap : null,
      );
    },
  );
}

/// The seated player's buttons in the Game tab: the solo game's. In the
/// auction No bid and the bids (or Call / No call, Rob / No rob); in play
/// Pass, Clear and Play. Greyed out when they can't be used, never hidden.
/// Above them the player's side and the stake ("Landlord · ×4"), under
/// them the card counter.
class _LandlordOnlineButtons extends StatelessWidget {
  const _LandlordOnlineButtons({required this.seen});

  final DdzOnlineSeen seen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: seen,
    builder: (context, _) {
      final game = seen.game, you = seen.c.you;
      if (game == null || you == null) return const SizedBox(height: 48);
      final s = LandlordStrings.of(context);
      final mine = seen.myTurn && game.toAct == you && game.phase != DdzPhase.finished;
      final legal = mine ? game.legalMoves() : const <DdzMove>[];

      Widget button(String label, DdzMove? move, {VoidCallback? onPressed, bool primary = false, required Key key}) {
        final enabled = onPressed != null || (move != null && legal.contains(move));
        final action = onPressed ?? (move == null ? null : () => seen.play(move));
        final style = const ButtonStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
          visualDensity: VisualDensity.compact,
          mouseCursor: WidgetStateMouseCursor.clickable,
        );
        final text = FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1));
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: primary
                ? FilledButton(key: key, onPressed: enabled ? action : null, style: style, child: text)
                : OutlinedButton(key: key, onPressed: enabled ? action : null, style: style, child: text),
          ),
        );
      }

      final List<Widget> buttons;
      if (game.phase == DdzPhase.bidding) {
        buttons = switch (game.rules.bidding) {
          BiddingStyle.points => [
            button(s.noBid, const DdzBid(0), key: const ValueKey('bid 0')),
            for (var b = 1; b <= 3; b++) button(s.bid(b), DdzBid(b), key: ValueKey('bid $b'), primary: true),
          ],
          BiddingStyle.callRob when game.isRobbing => [
            button(s.noRob, const DdzRob(false), key: const ValueKey('rob 0')),
            button(s.rob, const DdzRob(true), key: const ValueKey('rob 1'), primary: true),
          ],
          BiddingStyle.callRob => [
            button(s.noCall, const DdzCall(false), key: const ValueKey('call 0')),
            button(s.call, const DdzCall(true), key: const ValueKey('call 1'), primary: true),
          ],
        };
      } else {
        buttons = [
          button(s.pass, const DdzPass(), key: const ValueKey('pass')),
          button(
            s.clear,
            null,
            key: const ValueKey('clear'),
            onPressed: seen.selected.isEmpty || game.result != null ? null : seen.clearSelection,
          ),
          button(
            s.play,
            null,
            key: const ValueKey('play'),
            primary: true,
            onPressed: seen.selectedPlay == null ? null : seen.playSelection,
          ),
        ];
      }
      final lord = game.landlord;
      final total = game.stake == 0 ? null : game.stake * game.multiplier;
      final partner = lord == null || lord == you ? null : 3 - lord - you;
      final line = [
        if (lord != null) lord == you ? s.landlord : s.peasant,
        if (total != null) s.multiplier(total),
        if (partner != null && game.result == null)
          '${s.partner}: ${seen.c.nameOf(partner)} · ${s.cardsLeft(game.handSize(partner))}',
        if (seen.cantBeat) s.cantBeat,
      ].join(' · ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (line.isNotEmpty)
            Text(
              line,
              key: const ValueKey('ddz side'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
            child: SizedBox(
              height: 38,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons),
            ),
          ),
          LandlordCardCounter(
            count: game.viewFor(you).cardCount,
            strings: s,
            help: [s.entry(LandlordTerm.cardCounter)],
          ),
        ],
      );
    },
  );
}
