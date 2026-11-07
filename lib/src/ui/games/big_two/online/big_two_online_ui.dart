/// Big Two in a room (registered in online_game_uis.dart): the same table
/// as the solo game (the felt, the seats, the plays piled in the middle with
/// their history, cards flying to the pile), the seated player's fanned hand
/// under it and their Pass, Clear and Play, the host's rules in the setup's
/// own rows, the host's bots and the spectators' coach.
///
/// A seated player plays as in the solo game's Free Play: a tap picks a
/// card (it pops up), dragging one moves it in the hand, the Sort button
/// sorts by rank or suit, Play plays the picked cards once they make a
/// legal play, and a pass that can't be avoided plays itself after a
/// moment ("Can't beat"). A spectator sees every person's hand face up (the
/// bots' only with the host's switch), and the coach for the seat on turn
/// when they turn it on (with Pass always listed).
///
/// Each deal opens with who goes first on every device, seated or watching
/// (big_two_opening.dart), at that device's Animations speed: the felt
/// shows the step, any play already made waits until it ends (then flies
/// to the pile), and the seated player's buttons are greyed out
/// meanwhile. The step needs nothing the views don't carry: the starting
/// card and its holder (and a three-player deal's face-up card) are public
/// from the deal, and with two players the cards called before it are all
/// those below it.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Card;

import '../../../../app/app_settings.dart';
import '../../../../games/big_two/app/big_two_grading.dart';
import '../../../../games/big_two/app/big_two_match.dart' show bigTwoStandardTarget;
import '../../../../games/big_two/app/big_two_online_jobs.dart';
import '../../../../games/big_two/big_two.dart';
import '../../../../games/big_two/online/big_two_runner.dart';
import '../../../../games/big_two/online/big_two_view_codec.dart';
import '../../../../kit/coach_answer.dart';
import '../../../../online/games/game_runner.dart';
import '../../../../kit/hand_order.dart';
import '../../../../kit/match.dart';
import '../../../../kit/seats.dart';
import '../../../../l10n/strings.dart';
import '../../../kit/card_flights.dart';
import '../../../kit/felt.dart';
import '../../../kit/game_sounds.dart';
import '../../../kit/help.dart';
import '../../../kit/kit_sheet.dart';
import '../../../kit/l10n/game_strings.dart';
import '../../../kit/l10n/kit_strings.dart';
import '../../../kit/match_view.dart';
import '../../../kit/table_pile.dart';
import '../../../online/online_game_ui.dart';
import '../../../online/room_scope.dart';
import '../../../online/runner_client.dart';
import '../../../table_controller.dart' show PlaybackSpeed;
import '../big_two_coach_view.dart' as coach_view;
import '../big_two_controller.dart' show arrangedHand;
import '../big_two_opening.dart';
import '../big_two_screen.dart' show BigTwoHandView;
import '../big_two_setup.dart' show BigTwoRuleRows;
import '../big_two_table.dart';
import '../l10n/big_two_strings.dart';

/// Big Two's online part, for online_game_uis.dart (which lists every
/// game's as nullable: a game shows online once its part is filled in).
// ignore: unnecessary_nullable_for_final_variable_declarations
final OnlineGameUi? bigTwoOnlineUi = BigTwoOnlineUi();

/// Big Two's online part (see the library comment).
class BigTwoOnlineUi extends OnlineGameUi {
  BigTwoOnlineUi([OnlineGame? online]) : online = online ?? bigTwoOnline!;

  @override
  final OnlineGame online;

  @override
  GameStrings strings(BuildContext context) => BigTwoStrings.of(context);

  /// While who goes first plays: "Who starts?" until the felt names the
  /// starter, then what it says ("Kai starts: 3♦").
  @override
  String? heldTurnText(BuildContext context, RunnerClient c) {
    final w = _wire(c);
    if (w == null) return null;
    final clock = _openingFor(c, w, AppSettings.of(context).speed);
    final step = clock.step;
    if (!clock.playing || step == null) return null;
    final strings = BigTwoStrings.of(context);
    if (!clock.named) return strings.whoStarts;
    final you = S.of(context).you;
    return bigTwoOpeningText(strings, w.rules, step, [
      for (var seat = 0; seat < w.players; seat++) seat == c.you ? you : c.nameOf(seat),
    ]);
  }

  /// Who goes first on this device (the clock the table plays; started
  /// here if the Game tab is built first).
  @override
  Listenable? tablePlayback(BuildContext context, RunnerClient c) {
    final w = _wire(c);
    return w == null ? _clockOf(c) : _openingFor(c, w, AppSettings.of(context).speed);
  }

  @override
  Map<String, Object?>? seatViewFrom(Map<String, Object?> spectatorView, int seat) =>
      bigTwoSeatViewFrom(spectatorView, seat);

  @override
  OnlineJob<Object?, Object?> botJob(Map<String, Object?> seatView, String level, {required int seed}) => OnlineJob(
    const BigTwoOnlineBotJob(),
    BigTwoOnlineInput(view: seatView, seed: seed, level: KitLevel.values.asNameMap()[level] ?? KitLevel.medium),
  );

  @override
  String botMove(Object? output) => output! as String;

  /// The Easy bot's move (a rule of thumb, no search), seeded like the
  /// bot job (the host's secret salt in it); Pass or the smallest play if
  /// even that fails.
  @override
  String fallbackMove(Map<String, Object?> seatView, {required int seed}) {
    final view = bigTwoEngineView(seatView);
    try {
      return bigTwoMove(
        view.seat,
        BigTwoBot(BotLevel.easy, seed: seed).chooseMove(view),
      );
    } on Object {
      final legal = view.legalMoves();
      return bigTwoMove(view.seat, legal.contains(Play.pass) ? Play.pass : legal.first);
    }
  }

  @override
  OnlineJob<Object?, Object?> coachJob(Map<String, Object?> seatView, {required int seed}) =>
      OnlineJob(const BigTwoOnlineCoachJob(), BigTwoOnlineInput(view: seatView, seed: seed));

  /// The coach's report as the solo game shows it, graded on its scoring's
  /// scale, with Pass always listed when it is legal.
  @override
  CoachAnswer toAnswer(Object? output) {
    final advice = output! as BigTwoOnlineAdvice;
    final answer = bigTwoAnswer(
      advice.report,
      advice.scoring == BigTwoScoring.pusoyDos ? bigTwoPusoyScale : bigTwoPenaltyScale,
    );
    return answer.withListed({
      for (final line in answer.lines)
        if (line.move.endsWith(':pass')) line.move,
    });
  }

  @override
  Widget table(BuildContext context, RunnerClient c) => BigTwoOnlineTable(client: c);

  @override
  Widget? bottom(BuildContext context, RunnerClient c) => BigTwoOnlineHand(client: c);

  @override
  Widget actions(BuildContext context, RunnerClient c) => BigTwoOnlineActions(client: c);

  @override
  Widget rulesForm(
    BuildContext context,
    Map<String, Object?> rules, {
    required bool enabled,
    required ValueChanged<Map<String, Object?>> onChange,
  }) => BigTwoOnlineRules(rules: rules, enabled: enabled, onChange: onChange);

  /// "7♣ 7♥", or "Pass".
  @override
  String moveLabel(BuildContext context, String move) => coach_view.moveLabel(BigTwoStrings.of(context), move);

  /// Who won the deal ("Ana wins", "You win"), and once a match is over who
  /// won it.
  @override
  String resultText(BuildContext context, RunnerClient c) {
    final k = KitStrings.of(context);
    final result = c.over?.result ?? const {};
    String name(int seat) => seat == c.you ? S.of(context).you : c.nameOf(seat);
    final winner = result['winner'];
    final deal = winner is! int ? null : (winner == c.you ? k.youWin : k.wins(c.nameOf(winner)));
    final winners = [for (final s in result['matchWinners'] as List? ?? const []) s as int];
    final match = switch (winners) {
      [] => null,
      [final w] => w == c.you ? k.youWinMatch : k.winsMatch(name(w)),
      _ => k.matchTie([for (final w in winners) name(w)]),
    };
    return [?deal, ?match].join(' · ');
  }
}

/// The view [c] holds, read (null: none yet, or not a Big Two view).
BigTwoWireView? _wire(RunnerClient c) {
  final view = c.view;
  if (view == null) return null;
  try {
    return BigTwoWireView.read(view);
  } on FormatException {
    return null;
  }
}

/// The seat drawn at the bottom of [c]'s table: the player's own, or for a
/// spectator the first seat.
int _bottomSeat(RunnerClient c) => c.you ?? 0;

/// The deal as the table draws it: an engine state rebuilt from [w] with
/// [bottom]'s seat as seat 0 (the solo table puts its player there), play
/// still going to the right. Hands this device can't see are made up of
/// cards it can't place (their backs are drawn; their faces never are),
/// and the history is replayed on top, so the pile, the passes, the cards
/// left and the cards everyone has seen (the starting card until it is
/// played, the face-up card) come out as the room's, each in its holder's
/// hand (BigTwoTableFacts.visibleIn). With [turns], only the first that
/// many turns are played on it (the rest held back while who goes first
/// shows), the hands still as dealt.
BigTwoState _tableState(BigTwoWireView w, int bottom, {int? turns}) {
  final rules = w.rules;
  final n = w.players;
  int rot(int seat) => (seat - bottom + n) % n;
  final hands = w.hands;
  final history = w.history;
  final extra = w.extra;
  final start = w.start;
  final played = <int, List<Card>>{for (var s = 0; s < n; s++) s: []};
  for (final turn in history) {
    played[turn.seat]!.addAll(turn.cards);
  }
  final known = <Card>{
    for (final hand in hands.values) ...hand,
    for (final cards in played.values) ...cards,
    ?extra?.card,
    ?start?.card,
  };
  final pool = [
    for (final card in fullDeck)
      if (!known.contains(card)) card,
  ];
  final counts = w.counts;
  final starting = List<List<int>>.filled(n, const []);
  for (var s = 0; s < n; s++) {
    final List<Card> now;
    if (hands[s] case final hand?) {
      now = hand;
    } else {
      // The face-up card and the starting card are in their holder's hand
      // until played: everyone saw where they went.
      final holdsExtra = extra != null && extra.seat == s && !played[s]!.contains(extra.card);
      final holdsStart =
          start != null && start.seat == s && start.card != extra?.card && !played[s]!.contains(start.card);
      final shown = [if (holdsExtra) extra.card, if (holdsStart) start.card];
      final missing = (counts[s] - shown.length).clamp(0, pool.length);
      now = [...shown, ...pool.take(missing)];
      pool.removeRange(0, missing);
    }
    starting[rot(s)] = [
      for (final card in [...now, ...played[s]!]) rules.codeOf(card),
    ];
  }
  final leader = rot(history.isEmpty ? w.toMove : history.first.seat);
  // Rebuilt with the first player as a chosen leader (the made-up hands
  // can't say who held the lowest card), then told the room's own facts:
  // a deal its starting card opened shows that card in its holder's seat.
  final chosen = w.json['chosen'] == true;
  final state = BigTwoState.fromCodes(rules, starting, leader: leader, keepHistory: true)
    ..winner = -1
    ..dragonWin = false
    ..leaderChosen = chosen
    ..firstPlay = !chosen
    ..startCode = start == null ? -1 : rules.codeOf(start.card)
    ..startSeat = start == null ? -1 : rot(start.seat);
  if (extra != null) {
    state
      ..extraCode = rules.codeOf(extra.card)
      ..extraSeat = rot(extra.seat);
  }
  for (final turn in history.take(turns ?? history.length)) {
    state.toMove = rot(turn.seat);
    state.applyTrusted(turn.cards.isEmpty ? Play.pass : rules.classify(turn.cards)!);
  }
  if (w.isOver && history.isEmpty) {
    // A dealt dragon won before anyone played.
    state
      ..winner = rot(w.winner)
      ..dragonWin = true;
  }
  return state;
}

/// What the seated player does with their hand on this device: the cards
/// picked and how the hand lies (sorted, or in their own order). Kept per
/// game ([RunnerClient]) while it runs, so the table, the hand and the
/// buttons share it.
class _HandModel extends ChangeNotifier {
  final Set<Card> selected = {};
  HandArrangement<Card> arrangement = const HandArrangement.sorted();
  int _round = -1;

  /// A new deal starts with nothing picked, sorted by the sort last chosen.
  void syncRound(int round) {
    if (round == _round) return;
    _round = round;
    selected.clear();
    arrangement = arrangement.dealt;
  }

  void toggle(Card card) {
    if (!selected.remove(card)) selected.add(card);
    notifyListeners();
  }

  void clear() {
    if (selected.isEmpty) return;
    selected.clear();
    notifyListeners();
  }

  void arrange(HandArrangement<Card> a) {
    arrangement = a;
    notifyListeners();
  }
}

final _models = Expando<_HandModel>('Big Two hands');

_HandModel _modelOf(RunnerClient c) => _models[c] ??= _HandModel();

/// Who goes first on this device, per game ([RunnerClient]), shared by the
/// table and the buttons: the step starts when a deal is first seen with
/// nobody having played yet (a device that comes in later sees only its
/// result), and lasts its length at this device's Animations speed (none
/// at Instant). It notifies when the step ends.
class _OpeningClock extends ChangeNotifier {
  int _round = -1;
  BigTwoOpeningTimer? _timer;

  /// This deal's step (null: none, a dealt dragon).
  BigTwoOpening? step;

  /// This deal's step, at this device's speed.
  Duration length = Duration.zero;

  /// The deal the clock last started for.
  int get round => _round;

  /// The step is playing: plays wait, the buttons are greyed out.
  bool get playing => _timer?.running ?? false;

  /// How far the step is, 0 to 1.
  double get progress => _timer?.progress ?? 1;

  /// The starter has been named (two players: the calls are over).
  bool get named => _timer?.named ?? true;

  /// [w], deal [round]'s view, has come: a deal not seen before starts its
  /// step (once per deal).
  void sync(int round, BigTwoWireView w, PlaybackSpeed speed) {
    if (round == _round) return;
    _round = round;
    _timer?.cancel();
    _timer = null;
    length = Duration.zero;
    step = null;
    if (w.isOver || w.history.isNotEmpty) return;
    final opening = step = BigTwoOpening.of(_tableState(w, 0));
    if (opening == null) return;
    length = opening.lengthAt(speed.factor);
    if (length <= Duration.zero) return;
    _timer = BigTwoOpeningTimer(length, namedAt: opening.namedAt, onNamed: notifyListeners, onEnd: notifyListeners);
  }
}

final _clocks = Expando<_OpeningClock>('Big Two openings');

_OpeningClock _clockOf(RunnerClient c) => _clocks[c] ??= _OpeningClock();

/// [c]'s who-goes-first clock, told of [w] (see _OpeningClock.sync).
_OpeningClock _openingFor(RunnerClient c, BigTwoWireView w, PlaybackSpeed speed) =>
    _clockOf(c)..sync(c.round, w, speed);

/// The seated player's hand as it lies, and the picked cards still in it.
({List<Card> hand, Set<Card> picked}) _handOf(RunnerClient c, BigTwoWireView w) {
  final model = _modelOf(c)..syncRound(c.round);
  final cards = w.hands[c.you] ?? const <Card>[];
  final sorted = [...cards]..sort((a, b) => w.rules.codeOf(a).compareTo(w.rules.codeOf(b)));
  return (
    hand: arrangedHand(w.rules, sorted, model.arrangement),
    picked: {
      for (final card in model.selected)
        if (cards.contains(card)) card,
    },
  );
}

/// The move the picked cards make when it is legal now (null otherwise),
/// whether Pass is legal now, and the legal moves.
({String? play, bool canPass, List<Play> legal}) _choices(
  RunnerClient c,
  BigTwoWireView w,
  Set<Card> picked, {
  bool opening = false,
}) {
  // Nobody plays while who goes first shows.
  if (!c.myTurn || opening) return (play: null, canPass: false, legal: const []);
  final List<Play> legal;
  try {
    legal = bigTwoEngineView(c.view!).legalMoves();
  } on FormatException {
    return (play: null, canPass: false, legal: const []);
  }
  final pick = picked.isEmpty ? null : w.rules.classify(picked.toList());
  return (
    play: pick != null && legal.contains(pick) ? bigTwoMove(c.you!, pick) : null,
    canPass: legal.contains(Play.pass),
    legal: legal,
  );
}

/// The table: the solo game's felt and seats ([BigTwoTable]) for the deal
/// in the room, the player at the bottom (a spectator: the first seat,
/// every hand they may see face up), each play flying to the pile from its
/// seat, with the deal's sounds while the screen is open. With a match, a
/// chip in the bottom right corner ("Deal 3 · To 100") opens the scores.
/// Each deal opens with who goes first (see the library comment): a play
/// made meanwhile flies once it ends.
class BigTwoOnlineTable extends StatefulWidget {
  const BigTwoOnlineTable({super.key, required this.client});

  final RunnerClient client;

  @override
  State<BigTwoOnlineTable> createState() => _BigTwoOnlineTableState();
}

class _BigTwoOnlineTableState extends State<BigTwoOnlineTable> {
  late final CardFlights _flights = CardFlights(speed: () => _speed);
  var _speed = PlaybackSpeed.normal;

  /// The deal and the number of turns last drawn (to fly the new ones).
  int _round = -1, _turns = 0;

  RunnerClient get _c => widget.client;

  /// Who goes first, on this device (shared with the buttons).
  _OpeningClock get _clock => _clockOf(_c);

  @override
  void initState() {
    super.initState();
    final w = _wire(_c);
    _round = _c.round;
    // Laid out again while the step plays: its held plays still fly after it.
    _turns = _clock.playing && _clock.round == _c.round ? 0 : w?.history.length ?? 0;
    _c.addListener(_onChange);
    _clock.addListener(_onOpeningEnd);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _speed = AppSettings.of(context).speed;
  }

  @override
  void didUpdateWidget(BigTwoOnlineTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.removeListener(_onChange);
      _clockOf(oldWidget.client).removeListener(_onOpeningEnd);
      widget.client.addListener(_onChange);
      _clock.addListener(_onOpeningEnd);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _clock.removeListener(_onOpeningEnd);
    _flights.dispose();
    super.dispose();
  }

  /// Who goes first is over: the plays it held back fly to the pile now.
  /// (The clock also tells when the starter is named, midway: not yet.)
  void _onOpeningEnd() {
    if (!mounted || _clock.playing) return;
    _showTurns();
    setState(() {});
  }

  /// A new view: the plays made since the last one fly from their seats to
  /// the pile (launched now, before the screen shows them), with their
  /// sounds; a new deal has its own sound.
  void _onChange() {
    final w = _wire(_c);
    if (w == null || !mounted) return;
    final history = w.history;
    final sounds = _c.onScreen;
    if (_c.round != _round) {
      _round = _c.round;
      _openingFor(_c, w, _speed);
      // A deal seen while its step plays shows its plays after it.
      _turns = _clock.playing ? 0 : history.length;
      if (sounds) GameSounds.play(SoundEffect.deal, speed: _speed);
      return;
    }
    // Plays made while who goes first shows wait for its end.
    if (_clock.playing) return;
    _showTurns();
  }

  /// The plays made since the last drawn fly from their seats to the pile
  /// (launched now, before the screen shows them), with their sounds.
  void _showTurns() {
    final w = _wire(_c);
    if (w == null) return;
    final history = w.history;
    final sounds = _c.onScreen;
    if (history.length <= _turns) {
      _turns = history.length;
      return;
    }
    final bottom = _bottomSeat(_c);
    final n = w.players;
    for (var i = _turns; i < history.length; i++) {
      final turn = history[i];
      if (turn.cards.isEmpty) {
        if (sounds) GameSounds.play(SoundEffect.pass, speed: _speed);
        continue;
      }
      final seat = (turn.seat - bottom + n) % n;
      unawaited(
        _flights.fly([
          for (final (k, card) in turn.cards.indexed)
            CardFlight(
              from: CardFlights.seatTag(seat),
              to: TablePile.flightTag(i, k),
              face: coach_view.bigTwoFace(card),
            ),
        ]),
      );
      if (sounds) GameSounds.play(_isBomb(w, i) ? SoundEffect.bomb : SoundEffect.cardsDown, speed: _speed);
    }
    _turns = history.length;
  }

  /// A bomb dropped on a smaller play (turn [i] of the deal).
  bool _isBomb(BigTwoWireView w, int i) {
    if (!w.rules.bombs) return false;
    final history = w.history;
    final play = w.rules.classify(history[i].cards);
    final before = history
        .take(i)
        .lastWhere((t) => t.cards.isNotEmpty, orElse: () => (seat: -1, cards: const [], forced: false));
    return play != null && play.isBomb && before.cards.isNotEmpty && before.cards.length < 5;
  }

  @override
  Widget build(BuildContext context) {
    final w = _wire(_c);
    if (w == null) return const FeltArea();
    final s = S.of(context);
    final strings = BigTwoStrings.of(context);
    final n = w.players;
    final bottom = _bottomSeat(_c);
    int handSeat(int d) => (d + bottom) % n;
    int rot(int seat) => (seat - bottom + n) % n;
    final clock = _openingFor(_c, w, _speed);
    // While who goes first shows, the deal is drawn as dealt.
    final held = clock.playing && !w.isOver;
    final state = _tableState(w, bottom, turns: held ? 0 : null);
    final names = [for (var d = 0; d < n; d++) handSeat(d) == _c.you ? s.you : _c.nameOf(handSeat(d))];
    final result = _c.over?.result;
    final points = switch (result?['points'] ?? result?['scores']) {
      final List<Object?> p when p.length == n => [for (var d = 0; d < n; d++) (p[handSeat(d)] as num).toInt()],
      _ => null,
    };
    final turn = _c.turn?.seat;
    final match = w.match;
    return CardFlightLayer(
      flights: _flights,
      child: Stack(
        children: [
          Positioned.fill(
            child: BigTwoOpeningStage(
              id: clock.round,
              playing: held,
              length: clock.length,
              from: clock.progress,
              builder: (context, opening) => BigTwoTable(
                key: const ValueKey('big two online table'),
                state: state,
                names: names,
                strings: strings,
                toAct: turn == null || held ? null : rot(turn),
                seed: mixSeed(_c.round, 7919, 0),
                points: state.isOver ? points : null,
                faceUpSeats: _c.you != null ? null : {for (final seat in w.hands.keys) rot(seat)},
                opening: opening,
              ),
            ),
          ),
          if (match != null)
            // The bottom right corner: the hand's Sort button rises over
            // the bottom left one, and no seat sits in it.
            Positioned(
              right: 8,
              bottom: 8,
              child: _MatchChip(
                match: match,
                deal: match.deals.length + (w.isOver ? 0 : 1),
                names: [for (var seat = 0; seat < n; seat++) seat == _c.you ? s.you : _c.nameOf(seat)],
                you: _c.you,
              ),
            ),
        ],
      ),
    );
  }
}

/// The match in the table's corner: "Deal 3 · To 100" (a tap: the scores,
/// every deal's points and the totals).
class _MatchChip extends StatelessWidget {
  const _MatchChip({required this.match, required this.deal, required this.names, required this.you});

  final MatchScore match;
  final int deal;
  final List<String> names;
  final int? you;

  @override
  Widget build(BuildContext context) {
    final k = KitStrings.of(context);
    return Material(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: const ValueKey('match chip'),
        borderRadius: BorderRadius.circular(10),
        mouseCursor: SystemMouseCursors.click,
        onTap: () => KitSheet.open(
          context,
          KitSheet(
            key: const ValueKey('scoreboard'),
            title: '${k.scores} · ${k.target(match.target)}',
            help: TermsHelpButton(title: k.playTo, terms: [k.entry(KitTerm.playTo)]),
            child: MatchTable(match: match, names: names, humans: {?you}, over: match.isOver),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            '${k.dealNumber(deal < 1 ? 1 : deal)} · ${k.target(match.target)}',
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

/// The seated player's hand under the table: the solo game's fan
/// ([BigTwoHandView]). A tap picks or unpicks a card, a drag moves it, the
/// Sort button sorts by rank or suit. After the deal it stays to see,
/// greyed out of reach.
class BigTwoOnlineHand extends StatelessWidget {
  const BigTwoOnlineHand({super.key, required this.client});

  final RunnerClient client;

  @override
  Widget build(BuildContext context) {
    final c = client;
    final w = _wire(c);
    if (w == null || c.you == null) return const SizedBox.shrink();
    final model = _modelOf(c);
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final (:hand, :picked) = _handOf(c, w);
        final live = !w.isOver && !c.ended && !c.gameOver;
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 6),
          child: BigTwoHandView(
            cards: hand,
            selected: picked,
            // The cards of the hand everyone has seen carry the eye.
            visible: w.isOver
                ? const {}
                : {
                    for (final v in w.visible)
                      if (v.seat == c.you) v.card,
                  },
            onToggle: live ? model.toggle : null,
            onReorder: live ? (from, to) => model.arrange(model.arrangement.moved(hand, from, to)) : null,
            sortOrder: model.arrangement.order,
            onSort: live ? () => model.arrange(model.arrangement.next) : null,
          ),
        );
      },
    );
  }
}

/// The seated player's buttons, in the solo game's order: Pass, Clear and
/// Play (the filled one on the right), greyed out when they can't be used
/// (Play until the picked cards make a legal play, Pass when leading or
/// off turn, Clear with nothing picked). A pass that can't be avoided says
/// "Can't beat" and plays itself after a moment, as in the solo game. With
/// a match, the scores under them.
class BigTwoOnlineActions extends StatefulWidget {
  const BigTwoOnlineActions({super.key, required this.client});

  final RunnerClient client;

  /// How long "Can't beat" shows before the pass plays itself.
  static const forcedPassDelay = Duration(milliseconds: 900);

  @override
  State<BigTwoOnlineActions> createState() => _BigTwoOnlineActionsState();
}

class _BigTwoOnlineActionsState extends State<BigTwoOnlineActions> {
  Timer? _forced;
  int? _forcedTurn;

  RunnerClient get _c => widget.client;

  @override
  void dispose() {
    _forced?.cancel();
    super.dispose();
  }

  /// At a turn where Pass is the only legal move, it plays itself once
  /// [BigTwoOnlineActions.forcedPassDelay] has passed (once per turn).
  void _maybeForcedPass(bool forced) {
    final turn = _c.turn?.turnId;
    if (!forced || turn == null) {
      if (!forced) {
        _forced?.cancel();
        _forcedTurn = null;
      }
      return;
    }
    if (_forcedTurn == turn) return;
    _forcedTurn = turn;
    _forced?.cancel();
    _forced = Timer(BigTwoOnlineActions.forcedPassDelay, () {
      if (mounted && _c.myTurn && _c.turn?.turnId == turn) _c.move(bigTwoMove(_c.you!, Play.pass));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final w = _wire(c);
    if (w == null || c.you == null) return const SizedBox.shrink();
    final strings = BigTwoStrings.of(context);
    final model = _modelOf(c);
    final clock = _openingFor(c, w, AppSettings.of(context).speed);
    return ListenableBuilder(
      listenable: Listenable.merge([model, clock]),
      builder: (context, _) {
        final (hand: _, :picked) = _handOf(c, w);
        final (:play, :canPass, :legal) = _choices(c, w, picked, opening: clock.playing);
        final forced = legal.length == 1 && legal.single.isPass;
        _maybeForcedPass(forced);
        Widget fit(String text) => FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1));
        final match = w.match;
        final s = S.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (forced)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  strings.cantBeat,
                  key: const ValueKey('cant beat'),
                  style: const TextStyle(color: Color(0xFFFFCC80)),
                ),
              ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: OutlinedButton(
                    key: const ValueKey('pass'),
                    onPressed: canPass
                        ? () {
                            model.clear();
                            c.move(bigTwoMove(c.you!, Play.pass));
                          }
                        : null,
                    child: fit(strings.pass),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: TextButton(
                    key: const ValueKey('clear'),
                    onPressed: picked.isNotEmpty && !w.isOver ? model.clear : null,
                    child: fit(strings.clear),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 4,
                  child: FilledButton(
                    key: const ValueKey('play'),
                    onPressed: play == null
                        ? null
                        : () {
                            model.clear();
                            c.move(play);
                          },
                    child: fit(strings.play),
                  ),
                ),
              ],
            ),
            if (match != null && match.deals.isNotEmpty) ...[
              const SizedBox(height: 12),
              MatchTable(
                key: const ValueKey('match scores'),
                match: match,
                names: [for (var seat = 0; seat < w.players; seat++) seat == c.you ? s.you : c.nameOf(seat)],
                humans: {?c.you},
                over: match.isOver,
                compact: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The host's Big Two rules in the room, in the solo setup's own rows
/// ([BigTwoRuleRows]): cards each (the room's seat count decides which are
/// allowed), the scoring and its doublings, the preset and every rule, and
/// the match's target (with what it comes to at this table). Greyed out
/// for everyone but the host before the game.
class BigTwoOnlineRules extends StatelessWidget {
  const BigTwoOnlineRules({super.key, required this.rules, required this.enabled, required this.onChange});

  final Map<String, Object?> rules;
  final bool enabled;
  final ValueChanged<Map<String, Object?>> onChange;

  @override
  Widget build(BuildContext context) {
    final BigTwoRoomRules room;
    try {
      room = BigTwoRoomRules.read(rules);
    } on FormatException {
      return const SizedBox.shrink();
    }
    final seatsNow = RoomScope.maybeOf(context)?.room?.game?.setup?['seats'];
    final seats = seatsNow is int && seatsNow >= 2 && seatsNow <= 4 ? seatsNow : 2;
    final atTable = room.rulesFor(seats);
    void change(BigTwoRoomRules next) => onChange(next.toJson());
    final rows = BigTwoRuleRows(
      context,
      rules: atTable,
      enabled: enabled,
      onChanged: (next) {
        // Another scoring counts other points: its own standard target,
        // keeping No limit and the scaling as they were (as the setup does).
        var match = room.match;
        if (next.scoring != atTable.scoring && match.points != null) {
          match = match.copyWith(points: () => bigTwoStandardTarget(next.scoring).points);
        }
        change(room.copyWith(rules: next, cards2: seats == 2 ? next.cardsEach : null, match: match));
      },
    );
    return Column(
      key: const ValueKey('big two rules'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        rows.cardsEach(),
        ...rows.scoring(),
        const SizedBox(height: 8),
        ...rows.ruleSwitches(),
        ...rows.match(
          room.match,
          target: room.targetFor(seats),
          onChanged: (match) {
            if (enabled) change(room.copyWith(match: match));
          },
        ),
      ],
    );
  }
}
