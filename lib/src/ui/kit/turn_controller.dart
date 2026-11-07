import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../app/last_games.dart';
import '../../kit/coach_answer.dart';
import '../../kit/game_record.dart';
import '../../kit/grading.dart';
import '../../kit/jobs/jobs.dart';
import '../../kit/jobs/jobs_core.dart';
import '../../kit/match.dart';
import '../../kit/range.dart';
import '../../kit/seats.dart';
import '../table_controller.dart' show PlaybackSpeed;
import 'card_flights.dart';
import 'game_sounds.dart';

/// A job to start, as a game asks for it.
class JobRequest {
  JobRequest(this.job, this.input, this.kind);

  final GameJob job;
  final Object? input;
  final JobKind kind;
}

/// Runs a game's turns: bots on the bot lane, the coach on the coach lane,
/// grading, cancelling, pauses, sounds and saving the most recent game.
/// Each game extends it with its engine; at this level moves are strings
/// in the game's own notation.
///
/// The game starts with [newGame] (the screen calls it). After that the
/// loop runs by itself: a bot's turn starts its job, waits a little so the
/// bot looks like it thinks, plays and moves on; the player's turn (in
/// Training) starts the coach's answer for the position, even while the
/// coach is hidden, because that answer grades the move. When an animation
/// runs, the game answers null from [seatToAct] and calls [resume] after.
abstract class TurnController extends ChangeNotifier {
  TurnController({
    required this.gameKey,
    required this.training,
    required this.jobs,
    required this.lastGames,
    PlaybackSpeed Function()? speed,
    this._random,
  }) : _speed = speed ?? (() => PlaybackSpeed.normal);

  // ---- the game provides ----

  /// The seat to act, or null (game over, the dealer playing, an animation
  /// running: call [resume] when it ends).
  int? get seatToAct;

  bool isHuman(int seat);
  bool get isOver;

  /// The seats that won, once [isOver] (empty: a draw).
  List<int> get winners;

  /// The result kept in the record once the game is over.
  Map<String, Object?> get result => {'winners': winners};

  /// Card games: a finished deal is followed by another ([between], Next
  /// deal), with the same seats, rules and toggles.
  bool get playsRounds => false;

  /// Starts a new game or deal and gives its record (no moves yet); the
  /// engine is reset to it. [previous]: the finished deal (Next deal), or
  /// null. Seeds come from [nextGameSeed].
  GameRecord deal({GameRecord? previous});

  /// Work to finish before the first turn (Blackjack: the strategy chart
  /// job). The first turn waits for it: until it ends, [preparing] is true,
  /// no bot or coach job starts and [humanMove] throws. If it throws, the
  /// error is reported and the game goes on without it.
  Future<void> prepare() async {}

  /// Plays [move] for [seat] on the engine and plays its sound; throws if
  /// it is illegal (nothing changes then).
  void applyMove(int seat, String move);

  JobRequest botRequest(int seat, int seed);

  /// The bot job's output as a move (default: the output is the move).
  String toBotMove(Object? output) => output! as String;

  /// The move played when a bot job fails: the Easy bot, run here (fast).
  String fallbackBotMove(int seat);

  /// Whether this position gets a coach answer (Blackjack: not on "Deal").
  bool coachWanted(int seat) => true;

  /// The move the player has no choice but to make now (a peasant who can't
  /// beat the table has only Pass: 要不起), or null. The kit plays it by
  /// itself after the bots' pause (none when Instant), with no coach job
  /// and no grade; the player may still make it sooner. Asked on each of
  /// the player's turns.
  String? forcedMove(int seat) => null;

  /// The coach job for [seat] in [position] (the game up to a move, see
  /// GameRecord.upTo). [include]: a move that must be rated, to grade a
  /// move the first answer left out; [deep]: Think longer.
  JobRequest coachRequest(GameRecord position, int seat, {String? include, bool deep = false, required int seed});

  CoachAnswer toAnswer(Object? output);
  GradeScale get scale;

  /// The choices that aren't card plays (Pass, No bid, a bid), legal for
  /// [seat] now: the coach list always shows them, however low they rank.
  /// When the coach's answer leaves one out, the kit asks the coach again
  /// with it included and adds its line (see CoachAnswer.withLine). Asked
  /// when the coach starts on the player's turn.
  List<String> listedMoves(int seat) => const [];

  /// A match for a new game (Next deal keeps the one going): the target,
  /// already scaled for the table (MatchTarget.forPlayers), and who wins;
  /// null: no match, the deals just go on. Asked after [deal].
  MatchScore? startMatch() => null;

  /// The points each seat takes from the deal just finished, for the
  /// match (Big Two: the penalty for the cards left; Fight the Landlord:
  /// what each won or lost). Asked once per deal, when it is over.
  List<int>? dealPoints() => null;

  /// The job that works out [seat]'s range (OpponentRange) in [position],
  /// from the player's view only (never the cards the Training option
  /// shows); null: this game has no ranges.
  JobRequest? rangeRequest(GameRecord position, int seat, {required int seed}) => null;

  /// The range job's output as a range (default: it is one).
  OpponentRange toRange(Object? output) => output! as OpponentRange;

  /// The grade of [played]; Gomoku and Blackjack override it with their
  /// engine's grading. Null: not rated (never guessed).
  MoveMark? grade(CoachAnswer answer, String played) => scale.mark(answer, played);

  // ---- the kit provides ----

  final String gameKey;

  /// Training (grades and the coach) or Free Play, fixed for the game.
  final bool training;

  /// This screen's jobs; disposed of with the controller.
  final Jobs jobs;
  final LastGames lastGames;
  final PlaybackSpeed Function() _speed;
  final Random? _random;

  GameRecord? _record;
  var _generation = 0;
  var _disposed = false;
  var _finished = false;
  var _preparing = false;
  var _lastMoverBot = false;
  bool _botBusy = false;
  int? _botSeat;

  /// The move count at which a forced move is waiting to be played.
  int? _forcedAt;
  JobHandle<Object?>? _bot;
  final _show = <int, _ShowTask>{};
  final _ranges = <int, _RangeTask>{};
  String? _chosen;
  (Map<String, Object?>, MatchScore?)? _matchRead;
  final _grades = <int, JobHandle<Object?>>{};
  final _sessionMarks = <MoveMark>[];

  PlaybackSpeed get speed => _speed();

  /// Whether the coach shows in a game with no choice on record (the first
  /// game, or the player never touched the chip): hidden.
  static const coachShownAtFirst = false;

  /// This game's card flights (from the hand or a seat to the table), at
  /// [speed]: GameScaffold draws them. A game launches them in [applyMove];
  /// they never hold up the turns.
  late final CardFlights flights = CardFlights(speed: () => speed);

  /// Whether a game has been dealt.
  bool get started => _record != null;

  /// The game is dealt but [prepare] hasn't finished: nobody moves yet (the
  /// scaffold greys out the game's buttons and keys meanwhile).
  bool get preparing => _preparing;

  /// The game so far (rules, seats, deal, moves, marks, result, extra).
  GameRecord get record => _record ?? (throw StateError('No game yet: call newGame'));

  /// A new game seed (see freshGameSeed).
  int nextGameSeed() => freshGameSeed(_random);

  String seatName(int seat) => seat < record.seats.length ? record.seats[seat].name : '';

  /// Whether the coach shows (its chip); kept in `record.extra['coach']`
  /// once the player sets it, and carried into the next game with the
  /// other toggles. Hidden until then ([coachShownAtFirst]): the best moves
  /// are the player's to ask for. The grade after a move doesn't depend on
  /// it.
  bool get coachVisible => _record?.extra['coach'] as bool? ?? coachShownAtFirst;
  set coachVisible(bool visible) => setExtra('coach', visible);

  _ShowTask? get _current {
    final record = _record;
    final seat = record == null || isOver ? null : seatToAct;
    if (seat == null || !isHuman(seat)) return null;
    return _show[record!.moves.length];
  }

  /// The coach's answer for the player's turn now, once it has come.
  CoachAnswer? get coach => _current?.answer;

  /// The coach is working on the answer for the player's turn (or on a
  /// listed move its first answer left out).
  bool get coachThinking {
    final task = _current;
    return task != null && !task.failed && (task.answer == null || task.completing.isNotEmpty);
  }

  /// Think longer can run: jobs on another thread, Training, and a normal
  /// answer for this turn (not already a long one).
  bool get canThinkLonger => jobs.background && training && (_current?.deep == false);

  /// The bot that is thinking (its job or its pause), or null.
  int? get thinkingSeat => _botBusy ? _botSeat : null;

  List<MoveMark?> get marks => _record?.marks ?? const [];

  /// The player's last graded move in this deal.
  MoveMark? get lastMark => marks.lastWhere((m) => m != null, orElse: () => null);

  /// The average score of the graded moves this session (deals included).
  int? get averageScore {
    final scores = [for (final m in _sessionMarks) m.score, for (final m in marks) ?m?.score];
    if (scores.isEmpty) return null;
    return (scores.reduce((a, b) => a + b) / scores.length).round();
  }

  /// A deal ended and another follows: the panel shows Next deal. Not
  /// once the match is over (New match).
  bool get between => _record != null && isOver && playsRounds && !matchOver;

  // ---- choosing from the coach list ----

  /// A choice lit up by a tap on a coach row (Pass, a bid, Hit), waiting
  /// for a double tap, Enter or its button; null: none. Card plays are
  /// shown by picking their cards instead. Cleared by every move and deal.
  String? get chosen => _chosen;

  /// Lights up [move] (null: nothing). The game's button for it reads this.
  void choose(String? move) {
    if (move == _chosen) return;
    _chosen = move;
    _notify();
  }

  /// Plays [chosen] (Enter); false when nothing is chosen or it can't be
  /// played now.
  bool playChosen() {
    final move = _chosen;
    return move != null && playFromCoach(move);
  }

  /// Whether the player can move now (their turn, the game ready).
  bool get playerToMove {
    final seat = _record == null || _preparing || isOver ? null : seatToAct;
    return seat != null && isHuman(seat);
  }

  /// Plays a coach row's [move] (a double tap): false, and nothing changes,
  /// when it isn't the player's turn or the move is no longer legal.
  bool playFromCoach(String move) {
    if (!playerToMove) return false;
    try {
      humanMove(move);
      return true;
    } on Object {
      return false;
    }
  }

  // ---- the Training option to see the opponents' cards ----

  /// Where the record's extra keeps the toggle.
  static const showCardsKey = 'showCards';

  /// The opponents' cards are shown face up: Training only (always false in
  /// Free Play), off until the player turns it on in the menu. Only the
  /// screen reads it: the coach, the grades and the ranges never see those
  /// cards.
  bool get showOpponentCards => training && _record?.extra[showCardsKey] == true;
  set showOpponentCards(bool show) {
    if (training) setExtra(showCardsKey, show);
  }

  // ---- ranges ----

  /// Whether tapping [seat] can show its range: Training, a game that has
  /// ranges, a seat that isn't the player's.
  bool canShowRange(int seat) =>
      training &&
      _record != null &&
      seat >= 0 &&
      seat < record.seats.length &&
      !isHuman(seat) &&
      rangeRequest(record, seat, seed: 0) != null;

  /// Starts working out [seat]'s range for the position now, unless it is
  /// already done or on its way. The answer comes through [rangeOf] (the
  /// controller notifies). The range sheet asks as it opens and after every
  /// move while it stays open.
  void askRange(int seat) {
    if (!canShowRange(seat)) return;
    final at = record.moves.length;
    final old = _ranges[seat];
    if (old != null && old.at == at && !old.failed) return;
    old?.handle.cancel();
    final generation = _generation;
    final request = rangeRequest(record, seat, seed: mixSeed(record.seed, at, 50 + seat))!;
    final handle = jobs.start(request.job, request.input, lane: JobLane.coach, kind: JobKind.range);
    final task = _RangeTask(at, handle);
    _ranges[seat] = task;
    handle.result.then(
      (output) {
        if (generation != _generation || _ranges[seat] != task) return;
        try {
          task.range = toRange(output);
        } on Object {
          task.failed = true;
        }
        _notify();
      },
      onError: (Object _) {
        if (generation != _generation || _ranges[seat] != task) return;
        task.failed = true;
        _notify();
      },
    );
  }

  /// [seat]'s range for the position now, once it has come.
  OpponentRange? rangeOf(int seat) {
    final task = _ranges[seat];
    return task != null && _record != null && task.at == record.moves.length ? task.range : null;
  }

  /// The range job for [seat] failed for the position now (the sheet says so).
  bool rangeFailed(int seat) {
    final task = _ranges[seat];
    return task != null && _record != null && task.at == record.moves.length && task.failed;
  }

  // ---- the match ----

  /// The match going on (or just over), from the record's extra; null when
  /// the game plays no match.
  MatchScore? get match {
    final extra = _record?.extra;
    if (extra == null) return null;
    final read = _matchRead;
    if (read != null && identical(read.$1, extra)) return read.$2;
    final score = MatchScore.fromJson(extra[MatchScore.extraKey]);
    _matchRead = (extra, score);
    return score;
  }

  /// The deal is over and a total reached the target: New match.
  bool get matchOver => _record != null && isOver && (match?.isOver ?? false);

  /// A new game (and a new match) from the setup's choices. The screen's
  /// toggles carry over.
  Future<void> newGame() async {
    _sessionMarks.clear();
    await _start(null);
  }

  /// Card games: the next deal, with the same seats, rules and toggles.
  Future<void> nextRound() async {
    if (!between) return;
    _sessionMarks.addAll(record.marks.whereType<MoveMark>());
    await _start(record);
  }

  Future<void> _start(GameRecord? previous) async {
    _cancelAll();
    final old = _record;
    final fresh = deal(previous: previous);
    final extra = {...?old?.extra, ...fresh.extra};
    // A new game starts a new match; Next deal keeps the one going.
    if (previous == null) {
      if (startMatch() case final match?) {
        extra[MatchScore.extraKey] = match.toJson();
      } else {
        extra.remove(MatchScore.extraKey);
      }
    }
    // Stamped here, so no game has to remember to (the record's default is 1970).
    _record = fresh.copyWith(extra: extra, played: DateTime.now());
    _finished = false;
    _lastMoverBot = false;
    _preparing = true;
    _save();
    _notify();
    final generation = _generation;
    try {
      await prepare();
    } on Object catch (error, stack) {
      // Left (or started again) meanwhile: its work was cancelled with the
      // game, which is no error.
      if (generation != _generation || _disposed) return;
      // The game goes on without what prepare() made (Blackjack's coach
      // then builds its chart itself); the error still shows in the log.
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'game kit',
        context: ErrorDescription('while preparing a $gameKey game'),
      ));
    }
    if (generation != _generation || _disposed) return;
    _preparing = false;
    _advance();
  }

  /// The player plays [move]. Throws (and changes nothing) if it is illegal.
  void humanMove(String move) {
    final seat = _record == null || _preparing || isOver ? null : seatToAct;
    if (seat == null || !isHuman(seat)) throw StateError('Not your turn');
    final i = record.moves.length;
    applyMove(seat, move);
    _record = record.withMove(move);
    _lastMoverBot = false;
    _chosen = null;
    if (training) {
      // Graded without waiting: now if the answer is here, else when it
      // comes (or once the coach has rated the listed move just played).
      if (_show[i] case final task?) {
        final answer = task.answer;
        if (answer != null && !task.completing.contains(move)) {
          _show.remove(i);
          task.cancel();
          _grade(i, seat, answer, move);
        } else if (answer == null && task.failed) {
          _show.remove(i);
        } else {
          task.waitingMove = move;
        }
      }
    }
    _dropPassedShows();
    _save();
    _advance();
  }

  /// Replaces this turn's answer with a longer search. Only the answer on
  /// show is replaced: a grading job for an earlier move keeps running.
  void thinkLonger() {
    final task = _current;
    if (task == null || !canThinkLonger) return;
    _show.remove(task.index);
    task.cancel();
    _startShow(task.index, task.seat, deep: true).waitingMove = task.waitingMove;
    _notify();
  }

  /// Keeps a toggle in the record ('coach', 'sort', 'counter', 'count'),
  /// so it is saved and carried into the next game.
  void setExtra(String key, Object? value) {
    _record = record.withExtra(key, value);
    _save();
    _notify();
  }

  /// The game's animation ended: the turns go on.
  void resume() => _advance();

  /// Plays [effect] unless the speed is Instant.
  void playSound(SoundEffect effect) => GameSounds.play(effect, speed: speed);

  @override
  void dispose() {
    _cancelAll();
    _disposed = true;
    flights.dispose();
    jobs.dispose();
    unawaited(lastGames.flush());
    super.dispose();
  }

  // ---- the loop ----

  void _advance() {
    if (_disposed || _record == null || _preparing) return;
    if (isOver) {
      _finish();
      _notify();
      return;
    }
    final seat = seatToAct;
    if (seat == null) {
      _notify();
      return;
    }
    if (isHuman(seat)) {
      final i = record.moves.length;
      final forced = forcedMove(seat);
      if (forced != null) {
        // No choice to coach or grade: it plays itself after a pause.
        if (_forcedAt != i) unawaited(_forcedTurn(seat, i, forced));
      } else if (training && coachWanted(seat) && !_show.containsKey(i)) {
        _startShow(i, seat, deep: false);
      }
      if (_lastMoverBot && forced == null) {
        _lastMoverBot = false;
        playSound(SoundEffect.yourTurn);
      }
    } else if (!_botBusy) {
      unawaited(_botTurn(seat));
    }
    _notify();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _record = record.withResult(result);
    // The deal's points go to the match's totals, once.
    if (match case final match?) {
      if (dealPoints() case final points?) _record = record.withExtra(MatchScore.extraKey, match.add(points).toJson());
    }
    _save();
    final won = winners;
    if (won.any(isHuman)) {
      playSound(SoundEffect.win);
    } else if (won.isNotEmpty) {
      playSound(SoundEffect.lose);
    }
  }

  Future<void> _botTurn(int seat) async {
    final generation = _generation;
    _botBusy = true;
    _botSeat = seat;
    final clock = Stopwatch()..start();
    String? move;
    try {
      final request = botRequest(seat, mixSeed(record.seed, record.moves.length, seat));
      final handle = jobs.start(request.job, request.input, lane: JobLane.bot, kind: request.kind);
      _bot = handle;
      move = toBotMove(await handle.result);
    } on Object {
      move = null; // A timeout or an error: the Easy bot plays instead.
    }
    if (generation != _generation) return;
    // Bots look like they think: about 600 ms in all (none when Instant).
    final pause = Duration(milliseconds: (600 * speed.factor).round()) - clock.elapsed;
    if (pause > Duration.zero) {
      await Future<void>.delayed(pause);
      if (generation != _generation || _disposed) return;
    }
    _botBusy = false;
    _botSeat = null;
    _bot = null;
    if (isOver || seatToAct != seat) return _advance();
    var played = move ?? fallbackBotMove(seat);
    try {
      applyMove(seat, played);
    } on Object {
      if (move == null) rethrow;
      played = fallbackBotMove(seat);
      applyMove(seat, played);
    }
    _record = record.withMove(played);
    _lastMoverBot = true;
    _chosen = null;
    _dropPassedShows();
    _save();
    _advance();
  }

  /// Plays [move] for the player at move [i] after the bots' pause, unless
  /// the player made a move first or the game moved on.
  Future<void> _forcedTurn(int seat, int i, String move) async {
    final generation = _generation;
    _forcedAt = i;
    final pause = Duration(milliseconds: (600 * speed.factor).round());
    if (pause > Duration.zero) {
      await Future<void>.delayed(pause);
    } else {
      await Future<void>.microtask(() {});
    }
    if (generation != _generation || _disposed || _forcedAt != i) return;
    _forcedAt = null;
    if (_preparing || isOver || record.moves.length != i || seatToAct != seat) return;
    applyMove(seat, move);
    _record = record.withMove(move);
    _lastMoverBot = false;
    _chosen = null;
    _dropPassedShows();
    _save();
    _advance();
  }

  _ShowTask _startShow(int i, int seat, {required bool deep}) {
    final generation = _generation;
    final request = coachRequest(record.upTo(i), seat, deep: deep, seed: mixSeed(record.seed, i, 99));
    final handle = jobs.start(
      request.job,
      request.input,
      lane: JobLane.coach,
      kind: deep ? JobKind.coachDeep : request.kind,
    );
    final task = _ShowTask(i, seat, handle, deep: deep);
    _show[i] = task;
    final listed = listedMoves(seat).toSet();
    handle.result.then(
      (output) {
        if (generation != _generation || _show[i] != task) return;
        try {
          task.answer = toAnswer(output).withListed(listed);
        } on Object {
          task.failed = true;
        }
        if (task.waitingMove case final move?) {
          _show.remove(i);
          if (task.answer case final answer?) _grade(i, seat, answer, move);
        } else if (task.answer case final answer?) {
          for (final move in listed) {
            if (!answer.rates(move)) _completeShow(task, move, generation);
          }
        }
        _notify();
      },
      onError: (Object _) {
        if (generation != _generation || _show[i] != task) return;
        // No answer: the move made here stays ungraded.
        task.failed = true;
        if (task.waitingMove != null) _show.remove(i);
        _notify();
      },
    );
    return task;
  }

  /// Asks the coach to rate [move], a listed move [task]'s answer left out,
  /// and adds its line to the answer. If the player made that move
  /// meanwhile, it is graded once the line is in.
  void _completeShow(_ShowTask task, String move, int generation) {
    final i = task.index, seat = task.seat;
    final request = coachRequest(
      record.upTo(i),
      seat,
      include: move,
      deep: task.deep,
      seed: mixSeed(record.seed, i, 99),
    );
    final handle = jobs.start(
      request.job,
      request.input,
      lane: JobLane.coach,
      kind: task.deep ? JobKind.coachDeep : request.kind,
    );
    task.completing.add(move);
    task.extras.add(handle);
    void done() {
      task.completing.remove(move);
      if (task.waitingMove == move) {
        _show.remove(i);
        task.cancel();
        if (task.answer case final answer?) _grade(i, seat, answer, move);
      }
      _notify();
    }

    handle.result.then(
      (output) {
        if (generation != _generation || _show[i] != task) return;
        try {
          if (toAnswer(output).lineFor(move) case final line?) task.answer = task.answer!.withLine(line);
        } on Object {
          // Left out: the list goes on without it.
        }
        done();
      },
      onError: (Object _) {
        if (generation == _generation && _show[i] == task) done();
      },
    );
  }

  /// Grades move [i]; if the answer didn't rate it, asks again with the move
  /// included, from the position before it. Still not rated (an engine
  /// without `include`): the move stays ungraded.
  void _grade(int i, int seat, CoachAnswer answer, String move) {
    final mark = grade(answer, move);
    if (mark != null) return _setMark(i, mark);
    final generation = _generation;
    final request = coachRequest(record.upTo(i), seat, include: move, seed: mixSeed(record.seed, i, 99));
    final handle = jobs.start(request.job, request.input, lane: JobLane.coach, kind: request.kind);
    _grades[i] = handle;
    handle.result.then(
      (output) {
        if (generation != _generation || _grades[i] != handle) return;
        _grades.remove(i);
        MoveMark? again;
        try {
          again = grade(toAnswer(output), move);
        } on Object {
          again = null;
        }
        if (again != null) _setMark(i, again);
      },
      onError: (Object _) {
        if (generation == _generation && _grades[i] == handle) _grades.remove(i);
      },
    );
  }

  void _setMark(int i, MoveMark mark) {
    _record = record.withMark(i, mark);
    _save();
    _notify();
  }

  /// Answers for turns gone by that nothing waits on to grade.
  void _dropPassedShows() {
    final now = record.moves.length;
    _show.removeWhere((i, task) {
      final passed = i < now && task.waitingMove == null;
      if (passed) task.cancel();
      return passed;
    });
  }

  void _cancelAll() {
    _generation++;
    for (final task in _show.values) {
      task.cancel();
    }
    for (final handle in [..._grades.values, ?_bot, for (final task in _ranges.values) task.handle]) {
      handle.cancel();
    }
    _show.clear();
    _grades.clear();
    _ranges.clear();
    _chosen = null;
    _bot = null;
    _botBusy = false;
    _botSeat = null;
    _forcedAt = null;
  }

  void _save() {
    if (_record case final record?) lastGames.save(record);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- for tests ----

  /// Coach jobs alive now: 'show:3', 'deep:3', 'list:3' (a listed move
  /// being added), 'grade:1', 'range:1' (seat 1's) (to check what is
  /// cancelled and what isn't).
  @visibleForTesting
  List<String> get coachJobs => [
        for (final task in _show.values) ...[
          if (!task.handle.isDone) '${task.deep ? 'deep' : 'show'}:${task.index}',
          for (final extra in task.extras)
            if (!extra.isDone) 'list:${task.index}',
        ],
        for (final MapEntry(key: seat, value: task) in _ranges.entries)
          if (!task.handle.isDone) 'range:$seat',
        for (final MapEntry(key: i, value: handle) in _grades.entries)
          if (!handle.isDone) 'grade:$i',
      ];
}

/// The coach's answer for the player's position at move [index]: shown,
/// and used to grade the move made there.
class _ShowTask {
  _ShowTask(this.index, this.seat, this.handle, {required this.deep});

  final int index;
  final int seat;
  final JobHandle<Object?> handle;
  final bool deep;
  CoachAnswer? answer;
  bool failed = false;

  /// The move made here, waiting for this answer to be graded.
  String? waitingMove;

  /// Listed moves the coach is still being asked to rate, and those jobs.
  final completing = <String>{};
  final extras = <JobHandle<Object?>>[];

  void cancel() {
    handle.cancel();
    for (final extra in extras) {
      extra.cancel();
    }
  }
}

/// A range on its way (or come) for one seat, at move [at].
class _RangeTask {
  _RangeTask(this.at, this.handle);

  final int at;
  final JobHandle<Object?> handle;
  OpponentRange? range;
  bool failed = false;
}
