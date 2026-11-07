import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../kit/coach_answer.dart';
import '../../kit/game_record.dart';
import '../../kit/grading.dart';
import '../../kit/jobs/jobs.dart';
import '../../kit/jobs/jobs_core.dart';
import '../../kit/seats.dart';
import '../../l10n/strings.dart';
import '../strategy_panel.dart' show gradeColor;
import 'coach_panel.dart';
import 'game_scaffold.dart' show GameScaffold;
import 'kit_scope.dart';
import 'l10n/game_strings.dart';
import 'l10n/kit_strings.dart';
import 'move_feedback.dart';
import 'turn_controller.dart' show JobRequest;

/// One step of a review: the game as it stood before move [index], and the
/// move made there.
class ReviewStep {
  const ReviewStep({
    required this.index,
    required this.position,
    required this.next,
    required this.seat,
    required this.mark,
    required this.allCards,
  });

  /// 0 to the number of moves (the last step: the game over).
  final int index;

  /// The game before move [index] (`record.upTo(index)`): what the table shows.
  final GameRecord position;

  /// The move made here, for the table to point out; null at the last step.
  final String? next;

  /// Who made it; null at the last step.
  final int? seat;

  /// Its grade, when it was graded (the player's moves in Training).
  final MoveMark? mark;

  /// Card games: show every hand, not only the player's.
  final bool allCards;

  bool get atEnd => next == null;
}

/// Builds a review's table (or hand) for a step.
typedef ReviewBuilder = Widget Function(BuildContext context, ReviewStep step);

/// The coach's job for a review's step: [position], [seat] to move, [seed]
/// (the one the game's coach had there). Null: no answer here (a bot's
/// move, Blackjack's Deal). It runs as a deep job (JobKind.coachDeep).
typedef ReviewCoachRequest = JobRequest? Function(GameRecord position, int seat, int seed);

/// Walks through a finished (or left) game, step by step: the position,
/// the move made, its grade, and the coach's answer when asked for. It
/// starts no job until the coach is switched on; each step's answer is
/// kept while the review is open, and moving on cancels the step left
/// behind.
class ReviewController extends ChangeNotifier {
  ReviewController({
    required this.record,
    required this.jobs,
    required this.seatOf,
    this.coachRequest,
    this.toAnswer,
    this.prepareCoach,
    this.listedMoves,
    int start = 0,
  }) : _step = start.clamp(0, record.moves.length);

  final GameRecord record;

  /// Disposed of with the controller.
  final Jobs jobs;

  /// The seat that made move i.
  final int Function(GameRecord record, int move) seatOf;
  final ReviewCoachRequest? coachRequest;
  final CoachAnswer Function(Object? output)? toAnswer;

  /// Work the coach needs once, before its first answer (Blackjack: the
  /// strategy chart for the game's rules), run with the review's [jobs]
  /// when the coach is first switched on. Its jobs stop with the review; if
  /// it fails the coach goes on without it.
  final Future<void> Function(Jobs jobs)? prepareCoach;

  /// The choices the coach list always shows when rated (Pass, No bid) at
  /// [position] for [seat], as in the game (TurnController.listedMoves).
  final Iterable<String> Function(GameRecord position, int seat)? listedMoves;

  int _step;
  Future<void>? _preparing;
  var _prepared = false;
  var _coachOn = false;
  var _allCards = false;
  var _disposed = false;
  final _answers = <int, CoachAnswer>{};

  /// The step whose answer is being worked out, and its job.
  int? _thinkingStep;
  JobHandle<Object?>? _job;

  /// The steps: 0 to [last] (the game over).
  int get last => record.moves.length;
  int get step => _step;

  /// Whether the game has a coach for reviews.
  bool get hasCoach => coachRequest != null && toAnswer != null;

  /// Whether the coach can answer here (else its chip is greyed out): the
  /// game has one, and jobs run in the background. Its answers are deep
  /// jobs, greyed out on a page with no worker, as Think longer is: there
  /// they would get 300 ms each and freeze the screen while they run.
  bool get canAsk => hasCoach && jobs.background;

  bool get coachOn => _coachOn && canAsk;
  set coachOn(bool on) {
    if (!canAsk || on == _coachOn) return;
    _coachOn = on;
    if (on) {
      _ask();
    } else {
      _cancel();
    }
    notifyListeners();
  }

  bool get allCards => _allCards;
  set allCards(bool on) {
    if (on == _allCards) return;
    _allCards = on;
    notifyListeners();
  }

  /// The coach's answer for this step, once it has one (and is on).
  CoachAnswer? get answer => coachOn ? _answers[_step] : null;

  /// The coach is working on this step.
  bool get thinking => coachOn && _thinkingStep == _step;

  ReviewStep get current => stepAt(_step);

  ReviewStep stepAt(int i) {
    final atEnd = i >= last;
    return ReviewStep(
      index: i,
      position: record.upTo(i),
      next: atEnd ? null : record.moves[i],
      seat: atEnd ? null : seatOf(record, i),
      mark: atEnd ? null : record.marks[i],
      allCards: _allCards,
    );
  }

  /// The average score of the graded moves, or null when none was graded.
  int? get averageScore {
    final scores = [for (final mark in record.marks) ?mark?.score];
    if (scores.isEmpty) return null;
    return (scores.reduce((a, b) => a + b) / scores.length).round();
  }

  void goTo(int i) {
    final next = i.clamp(0, last);
    if (next == _step) return;
    _step = next;
    // The step left behind is no longer wanted.
    if (_thinkingStep != null && _thinkingStep != next) _cancel();
    if (coachOn) _ask();
    notifyListeners();
  }

  void next() => goTo(_step + 1);
  void previous() => goTo(_step - 1);

  /// Starts the coach's job for this step, unless it has its answer or the
  /// step gets none.
  void _ask() {
    final i = _step;
    if (!canAsk || i >= last || _answers.containsKey(i) || _thinkingStep == i) return;
    if (prepareCoach != null && !_prepared) {
      // The step shows the coach thinking; it is asked once that is done.
      _thinkingStep = i;
      _preparing ??= _prepare();
      return;
    }
    final request = coachRequest!(record.upTo(i), seatOf(record, i), mixSeed(record.seed, i, 99));
    if (request == null) return;
    final job = jobs.start(request.job, request.input, lane: JobLane.coach, kind: JobKind.coachDeep);
    _thinkingStep = i;
    _job = job;
    job.result.then(
      (output) {
        if (_disposed || _job != job) return;
        _answers[i] = toAnswer!(output).withListed({...?listedMoves?.call(record.upTo(i), seatOf(record, i))});
        _thinkingStep = null;
        _job = null;
        notifyListeners();
      },
      onError: (Object _) {
        // Cancelled, or it failed: nothing to show; coming back asks again.
        if (_disposed || _job != job) return;
        _thinkingStep = null;
        _job = null;
        notifyListeners();
      },
    );
  }

  Future<void> _prepare() async {
    try {
      await prepareCoach!(jobs);
    } on Object catch (error, stack) {
      if (_disposed || error is JobCancelled) return;
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'game kit',
        context: ErrorDescription("while preparing a review's coach"),
      ));
    }
    if (_disposed) return;
    _prepared = true;
    if (_job == null) _thinkingStep = null;
    if (coachOn) _ask();
    notifyListeners();
  }

  void _cancel() {
    _job?.cancel();
    _job = null;
    _thinkingStep = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    jobs.dispose();
    super.dispose();
  }
}

/// A game's review screen (the game menu's Last game): the same split as
/// the game's screen, the table built for the step, and a panel with the
/// step's move and grade, the coach's answer when its chip is on, and the
/// step slider with ◀ ▶ (keys ← →, Home, End) at the bottom. Above the
/// slider, a tick in the grade's color marks each graded move.
///
/// Each game fills it in from its own `<key>_review.dart`.
class ReviewScaffold extends StatefulWidget {
  const ReviewScaffold({
    super.key,
    required this.title,
    required this.strings,
    required this.record,
    required this.unit,
    required this.seatOf,
    required this.table,
    this.bottom,
    this.coachRequest,
    this.toAnswer,
    this.look = const CoachLook(),
    this.cards = false,
    this.resultText,
    this.squareTable = false,
    this.start = 0,
    this.stepTitle,
    this.prepareCoach,
    this.listedMoves,
  });

  /// The game's name.
  final String title;
  final GameStrings strings;

  /// The game to review (LastGames.load).
  final GameRecord record;

  /// The unit of the grades' losses.
  final ValueUnit unit;

  /// The seat that made move i.
  final int Function(GameRecord record, int move) seatOf;

  /// The board, or the felt, for a step.
  final ReviewBuilder table;

  /// Card games: the player's hand for a step, under the table.
  final ReviewBuilder? bottom;

  /// The coach for a step; without it (or [toAnswer]) the chip is greyed out.
  final ReviewCoachRequest? coachRequest;
  final CoachAnswer Function(Object? output)? toAnswer;
  final CoachLook look;

  /// A card game: an All cards switch shows every hand.
  final bool cards;

  /// The last step's headline; default: from `record.result['winners']`
  /// ("You win", "Ana wins", "Draw").
  final String? Function(BuildContext context, GameRecord record)? resultText;

  /// Upright: the table as tall as it is wide (Gomoku's board).
  final bool squareTable;

  /// The step to open at.
  final int start;

  /// A step's headline (not the last step's: [resultText]); null (or a null
  /// answer): "Move 12 · Ana". Blackjack, with one player: "Round 3 · Move 12".
  final String? Function(BuildContext context, ReviewStep step)? stepTitle;

  /// See ReviewController.prepareCoach.
  final Future<void> Function(Jobs jobs)? prepareCoach;

  /// See ReviewController.listedMoves.
  final Iterable<String> Function(GameRecord position, int seat)? listedMoves;

  /// Below this width the All cards chip shows its icon alone.
  static const iconChipsBelow = 480.0;

  @override
  State<ReviewScaffold> createState() => _ReviewScaffoldState();
}

class _ReviewScaffoldState extends State<ReviewScaffold> {
  late final ReviewController _controller = ReviewController(
    record: widget.record,
    jobs: KitScope.of(context).newJobs(),
    seatOf: widget.seatOf,
    coachRequest: widget.coachRequest,
    toAnswer: widget.toAnswer,
    prepareCoach: widget.prepareCoach,
    listedMoves: widget.listedMoves,
    start: widget.start,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = KitStrings.of(context);
    final c = _controller;
    final size = MediaQuery.sizeOf(context);
    final short = size.height < 500;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12171B),
        toolbarHeight: short ? 44 : null,
        titleSpacing: 4,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(widget.title, maxLines: 1),
        ),
        actions: [
          if (widget.cards)
            _Chip(
              key: const ValueKey('all cards'),
              label: k.allCards,
              icon: Icons.style,
              selected: c.allCards,
              onSelected: (on) => c.allCards = on,
              // A narrow upright screen: its icon alone, so the title keeps room.
              iconOnly: size.width < ReviewScaffold.iconChipsBelow,
            ),
          _Chip(
            key: const ValueKey('coach chip'),
            label: widget.strings.pickLabel,
            icon: c.coachOn ? Icons.visibility : Icons.visibility_off,
            selected: c.coachOn,
            onSelected: c.canAsk ? (on) => c.coachOn = on : null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): c.previous,
          const SingleActivator(LogicalKeyboardKey.arrowRight): c.next,
          const SingleActivator(LogicalKeyboardKey.home): () => c.goTo(0),
          const SingleActivator(LogicalKeyboardKey.end): () => c.goTo(c.last),
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(top: false, child: LayoutBuilder(builder: _layout)),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final step = _controller.current;
    return GameScaffold.split(
      constraints: constraints,
      table: widget.table(context, step),
      bottom: widget.bottom?.call(context, step),
      squareTable: widget.squareTable,
      panel: (compact) => _panel(context, step, compact: compact),
    );
  }

  /// The step's headline and move, its grade, the coach, the slider.
  Widget _panel(BuildContext context, ReviewStep step, {required bool compact}) {
    final s = S.of(context);
    final k = KitStrings.of(context);
    final c = _controller;
    final theme = Theme.of(context);
    final record = widget.record;
    final average = c.averageScore;
    final headline = step.atEnd
        ? (widget.resultText ?? _result)(context, record) ?? ''
        : widget.stepTitle?.call(context, step) ??
            [k.moveNumber(step.index + 1), if (step.seat case final seat?) _name(seat)].join(' · ');
    final mark = step.mark;
    final played = step.next;
    final showCoach = c.coachOn && !step.atEnd && (c.answer != null || c.thinking);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(10, compact ? 4 : 8, 10, compact ? 2 : 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  headline,
                  key: const ValueKey('review headline'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (average != null) ...[
                const SizedBox(width: 8),
                Text(s.score(average), style: const TextStyle(color: Color(0xFFFFE082), fontSize: 13)),
              ],
            ],
          ),
        ),
        if (played != null)
          Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, compact ? 2 : 4),
            child: mark != null
                ? MoveFeedback(
                    key: const ValueKey('review mark'),
                    mark: mark,
                    unit: widget.unit,
                    strings: widget.strings,
                    look: widget.look,
                    inline: compact,
                    moveIndex: step.index,
                  )
                // Not graded (a bot's move, Free Play): just the move.
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      widget.look.markText?.call(played, step.index) ?? widget.look.moveText(played),
                      key: const ValueKey('review move'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, area) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: showCoach
                  ? CoachList(
                      answer: c.answer,
                      strings: widget.strings,
                      look: widget.look,
                      maxRows: compact ? 3 : 5,
                      // Compact: the rows that fit, a listed Pass among them.
                      fitHeight: compact ? area.maxHeight : null,
                      dense: compact,
                      thinking: c.thinking,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        _StepBar(controller: c, compact: compact),
      ],
    );
  }

  String _name(int seat) {
    final seats = widget.record.seats;
    return seat < seats.length ? seats[seat].name : '';
  }

  /// "You win", "Ana wins", "You lose" or "Draw", from the record's result.
  String? _result(BuildContext context, GameRecord record) {
    final k = KitStrings.of(context);
    final winners = [
      for (final w in record.result?['winners'] as List? ?? const [])
        if (w is int) w,
    ];
    if (record.result == null) return null;
    if (winners.isEmpty) return k.draw;
    bool human(int seat) => seat < record.seats.length && record.seats[seat].human;
    if (winners.any(human)) return k.youWin;
    if (winners.length == 1) return k.wins(_name(winners.single));
    return k.youLose;
  }
}

/// ◀, the step slider with a tick per graded move, ▶.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.controller, required this.compact});

  final ReviewController controller;
  final bool compact;

  /// The slider's track starts and ends this far in, so the ticks line up.
  static const _inset = 12.0;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final last = c.last;
    final marks = c.record.marks;
    return Padding(
      padding: EdgeInsets.fromLTRB(2, 0, 2, compact ? 0 : 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('step back'),
            icon: const Icon(Icons.chevron_left),
            onPressed: c.step > 0 ? c.previous : null,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The grades along the game: a tick in each graded move's color.
                SizedBox(
                  height: 6,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _inset),
                    child: CustomPaint(
                      painter: _TicksPainter(marks: marks, steps: last),
                    ),
                  ),
                ),
                Slider(
                  key: const ValueKey('step slider'),
                  value: c.step.toDouble(),
                  max: last == 0 ? 1 : last.toDouble(),
                  divisions: last == 0 ? null : last,
                  padding: const EdgeInsets.symmetric(horizontal: _inset),
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  onChanged: last == 0 ? null : (v) => c.goTo(v.round()),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('step next'),
            icon: const Icon(Icons.chevron_right),
            onPressed: c.step < last ? c.next : null,
          ),
        ],
      ),
    );
  }
}

class _TicksPainter extends CustomPainter {
  _TicksPainter({required this.marks, required this.steps});

  final List<MoveMark?> marks;
  final int steps;

  @override
  void paint(Canvas canvas, Size size) {
    if (steps == 0) return;
    for (final (i, mark) in marks.indexed) {
      if (mark == null) continue;
      final x = size.width * i / steps;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, size.height / 2), width: 3, height: size.height),
          const Radius.circular(1.5),
        ),
        Paint()..color = gradeColor(mark.grade),
      );
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) => old.marks != marks || old.steps != steps;
}

/// A top-bar toggle (the coach, All cards), greyed out without [onSelected].
class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    this.onSelected,
    this.iconOnly = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  /// Its icon alone (named [label] for screen readers).
  final bool iconOnly;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: FilterChip(
      label: iconOnly ? Icon(icon, size: 16, semanticLabel: label) : Text(label, maxLines: 1, softWrap: false),
      selected: selected,
      showCheckmark: false,
      avatar: iconOnly ? null : Icon(icon, size: 16),
      mouseCursor: WidgetStateMouseCursor.clickable,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: onSelected,
    ),
  );
}
