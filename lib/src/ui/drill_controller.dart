part of 'table_controller.dart';

/// What came of playing a saved spot again: how long until it is due
/// again, and whether it was played right (Good or better); null when it
/// couldn't be graded (no GTO answer this time).
typedef DrillOutcome = ({Duration wait, bool? right});

/// A table to deal a drill's next hand at: its players (the user in seat
/// 0), stacks (chips) and button, its rules, and for a saved spot the spot.
typedef _DrillTable = ({
  List<PlayerInfo> players,
  List<int> stacks,
  int button,
  int ante,
  RaiseRule raiseRule,
  DrillSpot? spot,
});

/// A saved spot that can't be played again: dealt again, the hand goes
/// another way (the rules changed since).
class _SpotBroken implements Exception {
  const _SpotBroken();
}

/// Plays the mistake drills (see [Drills]). Each saved spot that is due,
/// most overdue first, is dealt again exactly (the same table, cards and
/// board) and its moves are replayed, the user's own too, up to the
/// decision it was saved at; GTO's answer is worked out again on the way
/// (behind the table, as in training: the hand doesn't wait for it). That
/// decision is graded like simple training (Show GTO waits until it is
/// played, so it can't give the answer away): played right (Good or
/// better), the spot comes back later and later; wrong, in 10 minutes (see
/// [outcome]). Played before its answer comes, it is graded when it does
/// ([gradePending] meanwhile; Next Hand works at once). Then the next one.
///
/// With nothing due, it deals random hands of simple training instead (a
/// random table size, position and stack, against GTO), whose mistakes
/// join the drills; a spot that falls due meanwhile is dealt next.
class DrillController extends TableController {
  DrillController(Drills drills, {super.speed, super.random, super.solutions})
      : super(TableConfig.quick(playerCount: 2, guessGto: true, opponentStyle: BotStyle.gto), drills: drills);

  @override
  Drills get drills => super.drills!;

  /// The saved spot being played again (null: a random hand).
  DrillSpot? spot;

  /// The spot was played: when it comes back.
  DrillOutcome? outcome;

  /// The spot was played before its answer came: its grade is on its way
  /// (the next hand can be dealt meanwhile).
  bool gradePending = false;

  /// The saved spot played before its answer came, and its hand: reviewed
  /// when the grade lands, on screen or not.
  ({DrillSpot spot, int hand})? _awaiting;

  /// The spot's recorded moves, and how many were replayed.
  List<DrillMove> _moves = const [];
  int _replayed = 0;

  /// While a saved spot's moves are replayed (quickly).
  bool get replaying => spot != null && _replayed < _moves.length;

  /// The next random table, picked ahead so that it is solved meanwhile.
  _DrillTable? _nextTable;
  bool _precomputed = false;

  /// The stacks a random table gets (one for everyone), in BB.
  static const _stacks = [10, 20, 40, 60, 100, 150, 200];

  /// Deals the spot due first, or else a random hand.
  @override
  Future<void> startNextHand() async {
    if (_busy) return;
    // A spot whose grade is still on its way isn't dealt again meanwhile.
    final next = drills.due.where((s) => !identical(s, _awaiting?.spot)).firstOrNull;
    final table = next != null ? _tableOf(next) : (_nextTable ?? _randomTable());
    // The random table picked ahead waits for the next random hand.
    if (next == null) _nextTable = null;
    _precomputed = false;
    spot = next;
    outcome = null;
    gradePending = false;
    _moves = next?.moves ?? const [];
    _replayed = 0;
    _seat(table);
    var broken = false;
    try {
      await super.startNextHand();
    } on _SpotBroken {
      _busy = false;
      broken = true;
    }
    if (_disposed || next == null) return;
    // The hand went another way (or ended before the decision): the spot
    // can't be played again. It goes, and the next one is dealt.
    if (broken || heroOptions == null) {
      drills.remove(next);
      return startNextHand();
    }
    // At the saved decision, its answer in: the next hand is solved
    // meanwhile (with the answer still to come, once it is: see
    // _answerCame).
    if (!answerPending) _precomputeNext();
    // No GTO answer this time: it isn't graded.
    if (heroSpot == null && !answerPending) _finish(right: null);
  }

  /// Sits the table for the next hand (Show All Cards stays as it was).
  void _seat(_DrillTable table) {
    final shown = allCardsShown;
    session.changeTable(TableConfig(
      players: table.players,
      ante: table.ante,
      raiseRule: table.raiseRule,
      guessGto: true,
    ));
    session.announced = (stacks: table.stacks, button: table.button);
    session.preset = switch (table.spot) {
      final spot? => (holeCards: {for (final (seat, cards) in spot.cards.indexed) seat: cards}, board: spot.board),
      null => null,
    };
    if (shown) session.revealedSeats.addAll([for (var seat = 1; seat < table.players.length; seat++) seat]);
    flying.clear();
    view = TableViewState([
      for (final (seat, player) in table.players.indexed) SeatView(info: player, stack: table.stacks[seat]),
    ]);
  }

  /// The table [spot] was saved at.
  static _DrillTable _tableOf(DrillSpot spot) => (
        players: [
          for (final (seat, name) in spot.names.indexed)
            PlayerInfo(
              name: name,
              stackBb: max(1, spot.stacks[seat] ~/ TableConfig.bigBlind),
              style: spot.styles[seat],
              isHero: seat == TableSession.heroSeat,
            ),
        ],
        stacks: spot.stacks,
        button: spot.button,
        ante: spot.ante,
        raiseRule: spot.raiseRule,
        spot: spot,
      );

  /// A random table: 2 to 8 players, one stack for everyone, the button
  /// anywhere; GTO opponents and the standard rules.
  _DrillTable _randomTable() {
    final n = 2 + _random.nextInt(7);
    final stackBb = _stacks[_random.nextInt(_stacks.length)];
    return (
      players: TableConfig.quickPlayers(count: n, stackBb: stackBb, style: BotStyle.gto),
      stacks: List.filled(n, stackBb * TableConfig.bigBlind),
      button: _random.nextInt(n),
      ante: 0,
      raiseRule: RaiseRule.standard,
      spot: null,
    );
  }

  /// A saved spot's moves, in order; then the user's turn at the saved
  /// decision. A move that doesn't fit the hand any more breaks the spot.
  @override
  PlayerAction? _recordedMove(int seat) {
    final spot = this.spot, hand = session.hand;
    if (spot == null || hand == null) return null;
    if (_replayed == _moves.length) {
      if (seat != TableSession.heroSeat || hand.board.length != spot.board.length) throw const _SpotBroken();
      return null;
    }
    final move = _moves[_replayed++];
    final legal = hand.legalActions();
    final fits = switch (move.action.type) {
      ActionType.fold => true,
      ActionType.check => legal.canCheck,
      ActionType.call => legal.canCall,
      ActionType.raise =>
        legal.canRaise && move.action.amount >= legal.minRaiseTo && move.action.amount <= legal.maxRaiseTo,
    };
    if (move.seat != seat || !fits) throw const _SpotBroken();
    return move.action;
  }

  /// A saved spot: the play is graded (as in simple training) and the
  /// hand stops there; before its answer comes, it is graded when it does.
  /// Random hands go on as usual.
  @override
  Future<void> playGraded(int choice, {PlayerAction? action}) async {
    final answer = heroSpot, spot = this.spot, d = _decision, menu = heroMenu;
    if (spot == null) return super.playGraded(choice, action: action);
    if (heroScore != null || gradePending || outcome != null) return;
    if (answer == null) {
      if (!answerPending || d == null || menu == null) return;
      _unscored.add((
        hand: d.hand,
        turnId: d.turnId,
        players: d.players,
        styles: d.styles,
        mix: [for (var i = 0; i < menu.length; i++) i == choice ? 1.0 : 0.0],
        choice: choice,
        drew: false,
        action: action,
        oneAction: true,
      ));
      _awaiting = (spot: spot, hand: d.hand);
      // The hand stays stopped at the decision, as once graded.
      heroOptions = null;
      heroMenu = null;
      gradePending = true;
      _notify();
      return;
    }
    submitMix([for (var i = 0; i < answer.actions.length; i++) i == choice ? 1.0 : 0.0],
        choice: choice, oneAction: true);
    heroAction = action;
  }

  /// At a saved spot, an answer that comes with no spot leaves it ungraded,
  /// as when there was none from the start. Either way the next hand's
  /// solves can start.
  @override
  void _answerCame(_Decision d, GtoAnswer a, PokerHand? at, {PostflopTracker? postflop}) {
    final showing = _showing(d);
    super._answerCame(d, a, at, postflop: postflop);
    if (spot == null || _disposed) return;
    if (a.spot == null) {
      if (showing && outcome == null) {
        _finish(right: null);
      } else if (_awaiting case final waited? when waited.hand == d.hand) {
        _awaiting = null;
        // Why, for the result area (the choices are gone already).
        if (waited.hand == _tableHand) answerNone = a.none;
        _review(waited.spot, waited.hand, right: null);
      }
    }
    if (d.hand == _tableHand) _precomputeNext();
  }

  /// A saved spot is graded, nothing else (see [playGraded]).
  @override
  Future<void> heroAct(PlayerAction action) async {
    if (spot == null) await super.heroAct(action);
  }

  /// A saved spot played: whether it was right decides when it comes back
  /// (graded after its move, from the copy of the hand at its decision).
  /// In a random hand, a mistake is saved as usual.
  @override
  void _scoredAt(DecisionScore score, PokerHand at, List<PlayerInfo> players, List<BotStyle?> styles) {
    final right = score.grade.index <= DecisionGrade.good.index;
    if (_awaiting case final waited? when waited.hand == at.handNumber) {
      _awaiting = null;
      return _review(waited.spot, waited.hand, right: right);
    }
    if (spot == null) return super._scoredAt(score, at, players, styles);
    _finish(right: right);
  }

  /// A saved spot is graded on screen, whatever the grade: when it is back
  /// shows with it.
  @override
  bool _showsLate(DecisionScore score, _Unscored played) =>
      (spot != null && played.hand == _tableHand) || super._showsLate(score, played);

  /// The grade of [saved] (played in hand [hand]) came: shown with its
  /// outcome if the spot is still on screen, else only recorded.
  void _review(DrillSpot saved, int hand, {required bool? right}) {
    if (identical(spot, saved) && hand == _tableHand) return _finish(right: right);
    drills.review(saved, right: right);
  }

  void _finish({required bool? right}) {
    outcome = (wait: drills.review(spot!, right: right), right: right);
    gradePending = false;
    _notify();
  }

  /// After a saved spot: the next one (or a random hand).
  @override
  Future<void> continueHand() async {
    if (spot == null) return super.continueHand();
    if (outcome != null || gradePending) await startNextHand();
  }

  /// Solves the next hand's whole preflop game meanwhile: the next spot
  /// due, or else the next random table (picked now).
  @override
  void _precomputeNext() {
    if (_precomputed) return;
    _precomputed = true;
    final table = switch ([for (final s in drills.due) if (s != spot && !identical(s, _awaiting?.spot)) s].firstOrNull) {
      final next? => _tableOf(next),
      null => _nextTable ??= _randomTable(),
    };
    final spec = PreflopAdvisor.specFor(
      stacksBySeat: table.stacks,
      buttonSeat: table.button,
      smallBlind: TableConfig.smallBlind,
      bigBlind: TableConfig.bigBlind,
      ante: table.ante,
      raiseRule: table.raiseRule,
    );
    // Failures show up when the hand needs the solve; nothing to do here.
    final owner = _nextOwner = SolveOwner(session.handNumber + 1);
    _quietly(_solutions.solve(spec, owner: owner, priority: SolvePriority.nextHand));
  }

  /// No pre-actions while a saved spot replays: its moves are set.
  @override
  bool get _preActionsOn => spot == null && super._preActionsOn;

  /// A saved spot's moves replay quickly.
  @override
  double get _factor => replaying ? min(super._factor, PlaybackSpeed.fast.factor) : super._factor;
}
