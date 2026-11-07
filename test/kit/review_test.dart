import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/grading.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/blackjack/l10n/blackjack_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/felt.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/kit/move_feedback.dart';
import 'package:pokerfection/src/ui/kit/review_kit.dart';
import 'package:pokerfection/src/ui/kit/turn_controller.dart' show JobRequest;

import 'fakes.dart' show ManualBackend;
import 'nim.dart';
import 'shots.dart';

/// A finished game of Nim (a pile of 7, take 1 to 3): the player (seat 0)
/// took 2 (a Mistake: 3 wins), Ana 1, the player 3, Ana 1. Ana took the
/// last stone.
GameRecord _record() => GameRecord(
      game: 'nim',
      version: 1,
      seed: 12345,
      rules: {'pile': 7, 'take': 3},
      seats: const [SeatSpec(human: true, name: 'You'), SeatSpec(human: false, level: KitLevel.easy, name: 'Ana')],
      moves: const ['2', '1', '3', '1'],
      marks: const [
        MoveMark(grade: DecisionGrade.mistake, loss: 0.12, score: 30, played: '2', best: '3'),
        null,
        MoveMark(grade: DecisionGrade.best, loss: 0, score: 100, played: '3', best: '3'),
        null,
      ],
      result: {
        'winners': [1],
      },
    );

const _look = CoachLook(moveText: _take);
String _take(String move) => 'Take $move';

/// The player's moves get the coach; Ana's don't.
JobRequest? _coach(GameRecord position, int seat, int seed) => seat == 0
    ? JobRequest(const NimCoachJob(), {'record': position.jobJson(), 'seat': seat, 'deep': true}, JobKind.coach)
    : null;

CoachAnswer _answer(Object? output) => CoachAnswer(
      unit: ValueUnit.winChance,
      lines: [
        for (final line in (output! as List).cast<Map<String, Object?>>())
          CoachLine(move: line['move']! as String, value: (line['value']! as num).toDouble()),
      ],
    );

/// The steps the table was built for, and with which All cards.
final _built = <ReviewStep>[];

Widget _review({
  bool cards = false,
  bool coach = true,
  int start = 0,
  String? Function(BuildContext context, ReviewStep step)? stepTitle,
  Future<void> Function(Jobs jobs)? prepareCoach,
  String title = 'Nim',
  AppLanguage language = AppLanguage.english,
}) =>
    ReviewScaffold(
      title: title,
      strings: BlackjackStrings.forLanguage(language),
      record: _record(),
      unit: ValueUnit.winChance,
      seatOf: (record, move) => move % 2,
      table: (context, step) {
        _built.add(step);
        return FeltArea(child: Center(child: Text('${nimLeft(step.position.jobJson())} left')));
      },
      bottom: cards
          ? (context, step) => const HandFan(cards: [CardFace.suited(12, 3), CardFace.suited(11, 2)])
          : null,
      coachRequest: coach ? _coach : null,
      toAnswer: coach ? _answer : null,
      look: _look,
      cards: cards,
      start: start,
      stepTitle: stepTitle,
      prepareCoach: prepareCoach,
    );

/// [review] with jobs the test answers by hand.
Future<ManualBackend> _pump(
  WidgetTester tester,
  Widget review, {
  Size size = const Size(1280, 800),
  AppLanguage language = AppLanguage.english,
}) async {
  final backend = ManualBackend(nimJobs);
  await pumpShot(
    tester,
    review,
    size: size,
    language: language,
    wrap: (child) => KitScope(newJobs: () => Jobs.using(backend), lastGames: LastGames(), child: child),
  );
  await tester.pump();
  return backend;
}

/// Lets a job's reply reach the screen (widget tests run on a fake clock,
/// so frames, not waiting, move things on).
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

String _headline(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('review headline'))).data!;

void main() {
  setUpAll(loadShotFonts);
  setUp(_built.clear);

  testWidgets('it opens at the first move: the position before it, who made it, and its grade; no job runs',
      (tester) async {
    final backend = await _pump(tester, _review());
    expect(_headline(tester), 'Move 1 · You');
    expect(find.text('7 left'), findsOneWidget);
    expect(_built.last.next, '2');
    expect(find.byType(MoveFeedback), findsOneWidget);
    expect(find.text('Mistake'), findsOneWidget);
    expect(find.text('Best move: Take 3'), findsNothing, reason: "Blackjack's strings say Basic strategy");
    expect(find.text('Basic strategy: Take 3'), findsOneWidget);
    expect(find.text('Score 65'), findsOneWidget, reason: 'the average of the graded moves');
    expect(backend.started, isEmpty, reason: 'the coach answers only when asked');
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('step back'))).onPressed, isNull);
  });

  testWidgets('◀ ▶, the arrow keys, Home and End walk through the moves; the last step shows the result',
      (tester) async {
    await _pump(tester, _review());
    await tester.tap(find.byKey(const ValueKey('step next')));
    await tester.pump();
    expect(_headline(tester), 'Move 2 · Ana');
    expect(find.text('5 left'), findsOneWidget);
    expect(find.byKey(const ValueKey('review move')), findsOneWidget, reason: "Ana's move isn't graded");
    expect(find.text('Take 1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_headline(tester), 'Move 3 · You');
    expect(find.text('Best'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_headline(tester), 'Move 2 · Ana');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(_headline(tester), 'Ana wins');
    expect(find.text('0 left'), findsOneWidget);
    expect(_built.last.atEnd, isTrue);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('step next'))).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(_headline(tester), 'Move 1 · You');
  });

  testWidgets('the slider goes straight to a step', (tester) async {
    await _pump(tester, _review());
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('step slider')));
    expect(slider.divisions, 4);
    slider.onChanged!(2);
    await tester.pump();
    expect(_headline(tester), 'Move 3 · You');
  });

  testWidgets(
      "the coach on demand: its chip starts a deep job for this step; the answer stays for the review's life; "
      'moving on cancels the step left behind', (tester) async {
    final backend = await _pump(tester, _review());
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await tester.pump();
    expect(backend.running, hasLength(1));
    final first = backend.running.single;
    expect(first.name, 'nim.coach');
    expect(first.request, contains('"moves":[]'), reason: 'the position before move 1');
    expect(first.request, contains('"deep":true'));
    expect(find.byType(LinearProgressIndicator), findsOneWidget, reason: 'thinking');
    backend.answer(first);
    await _flush(tester);
    expect(find.text('Take 3'), findsOneWidget, reason: "the coach's pick");
    expect(find.text('Basic strategy'), findsNWidgets(2), reason: 'the chip, and the pick tag');

    // Ana's move gets no coach: no job.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(backend.running, isEmpty);
    // The player's next move: a job, cancelled when the slider moves on.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final third = backend.running.single;
    expect(third.request, contains('"moves":["2","1"]'));
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(third.token.isCancelled, isTrue);
    // Back at the first move: its answer is still there, and no job starts.
    expect(backend.started, hasLength(2));
    expect(find.text('Take 3'), findsOneWidget);
    // A late reply from the cancelled job changes nothing.
    backend.answer(third);
    await _flush(tester);
    expect(find.text('Take 3'), findsOneWidget);

    // Off: the coach's rows go, nothing runs.
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await tester.pump();
    expect(find.text('Take 3'), findsNothing);
  });

  test("the game's listed moves (Pass) are pinned in the review's answers, as in the game", () async {
    final review = ReviewController(
      record: _record(),
      jobs: Jobs.inline(extra: nimJobs),
      seatOf: (record, move) => move % 2,
      coachRequest: _coach,
      toAnswer: _answer,
      listedMoves: (position, seat) => const ['1'],
    );
    review.coachOn = true;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(review.answer!.listed, {'1'});
    expect([for (final l in review.answer!.shown(1)) l.move], ['3', '1'], reason: 'the pick, and Pass pinned');
    review.dispose();
  });

  testWidgets('a job that fails shows nothing, and coming back asks again', (tester) async {
    final backend = await _pump(tester, _review());
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await tester.pump();
    backend.fail(backend.running.single);
    await _flush(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(backend.running, hasLength(1));
  });

  testWidgets('without a coach its chip is greyed out; leaving the review stops its jobs', (tester) async {
    final backend = ManualBackend(nimJobs);
    await pumpShot(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _review(coach: false))),
            child: const Text('open'),
          ),
        ),
      ),
      size: const Size(1280, 800),
      wrap: (child) => KitScope(newJobs: () => Jobs.using(backend), lastGames: LastGames(), child: child),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final chip = tester.widget<FilterChip>(find.descendant(
      of: find.byKey(const ValueKey('coach chip')),
      matching: find.byType(FilterChip),
    ));
    expect(chip.onSelected, isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(backend.disposed, isTrue);
  });

  testWidgets(
      'on a page with no worker the coach chip is greyed out, as Think longer is: '
      'its deep jobs would get 300 ms each and freeze the screen', (tester) async {
    final backend = _PageBackend(nimJobs, background: false);
    await pumpShot(
      tester,
      _review(),
      size: const Size(1280, 800),
      wrap: (child) => KitScope(newJobs: () => Jobs.using(backend), lastGames: LastGames(), child: child),
    );
    await tester.pump();
    final chip = find.descendant(of: find.byKey(const ValueKey('coach chip')), matching: find.byType(FilterChip));
    expect(tester.widget<FilterChip>(chip).onSelected, isNull);
    await tester.tap(chip, warnIfMissed: false);
    await tester.pump();
    expect(backend.started, isEmpty);
  });

  testWidgets("a browser finds out there's no worker with the first job: the chip greys out and the coach goes off",
      (tester) async {
    final backend = _PageBackend(nimJobs, background: true);
    await pumpShot(
      tester,
      _review(),
      size: const Size(1280, 800),
      wrap: (child) => KitScope(newJobs: () => Jobs.using(backend), lastGames: LastGames(), child: child),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await tester.pump();
    backend.background = false;
    backend.answer(backend.running.single);
    await _flush(tester);
    final chip = tester.widget<FilterChip>(
      find.descendant(of: find.byKey(const ValueKey('coach chip')), matching: find.byType(FilterChip)),
    );
    expect(chip.onSelected, isNull);
    expect(chip.selected, isFalse);
    expect(find.text('Take 3'), findsNothing, reason: 'the coach is off');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(backend.started, hasLength(1), reason: 'no more jobs on the page');
  });

  testWidgets('card games: All cards reaches the table; other games have no such switch', (tester) async {
    await _pump(tester, _review(cards: true));
    expect(_built.last.allCards, isFalse);
    await tester.tap(find.byKey(const ValueKey('all cards')));
    await tester.pump();
    expect(_built.last.allCards, isTrue);
    expect(find.byType(HandFan), findsOneWidget);
  });

  testWidgets("a game's own step headline replaces \"Move n · seat\"; the last step still shows the result",
      (tester) async {
    await _pump(tester, _review(stepTitle: (context, step) => 'Round ${step.index ~/ 2 + 1} · Move ${step.index + 1}'));
    expect(_headline(tester), 'Round 1 · Move 1');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(_headline(tester), 'Ana wins');
  });

  testWidgets("the coach's preparation runs once, with the review's jobs, before the first step's job",
      (tester) async {
    final ready = Completer<void>();
    final given = <Jobs>[];
    final backend = await _pump(tester, _review(prepareCoach: (jobs) {
      given.add(jobs);
      return ready.future;
    }));
    expect(given, isEmpty, reason: 'nothing runs until the coach is switched on');
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await tester.pump();
    expect(given, hasLength(1));
    expect(backend.started, isEmpty, reason: 'the step waits for it');
    expect(find.byType(LinearProgressIndicator), findsOneWidget, reason: 'thinking meanwhile');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    ready.complete();
    await _flush(tester);
    expect(given, hasLength(1), reason: 'once');
    expect(backend.running.single.request, contains('"moves":["2","1"]'), reason: 'the step on show now');
    backend.answer(backend.running.single);
    await _flush(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(backend.running, hasLength(1), reason: 'straight to the job');
    expect(given, hasLength(1));
  });

  testWidgets('a narrow upright screen shows All cards as its icon, so the title stays readable in Spanish',
      (tester) async {
    await _pump(
      tester,
      _review(cards: true, title: 'Blackjack', language: AppLanguage.spanish),
      size: const Size(390, 844),
      language: AppLanguage.spanish,
    );
    expect(tester.takeException(), isNull);
    final allCards = find.byKey(const ValueKey('all cards'));
    expect(find.descendant(of: allCards, matching: find.byIcon(Icons.style)), findsOneWidget);
    expect(find.descendant(of: allCards, matching: find.byType(Text)), findsNothing);
    expect(tester.getRect(find.text('Blackjack')).height, greaterThanOrEqualTo(14), reason: 'not shrunk to ~9 px');
    await tester.tap(allCards);
    await tester.pump();
    expect(_built.last.allCards, isTrue, reason: 'it still works');
    await shot(tester, 'review_bar_es_390x844');
  });

  testWidgets('◀ ▶, the slider and the chips show the hand under the mouse', (tester) async {
    await _pump(tester, _review(cards: true));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final key in ['step next', 'step slider', 'all cards', 'coach chip']) {
      await mouse.moveTo(tester.getCenter(find.byKey(ValueKey(key))));
      await tester.pump();
      expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click, reason: key);
    }
  });

  testWidgets('a game with no moves: one step, the slider greyed out', (tester) async {
    final backend = ManualBackend(nimJobs);
    await pumpShot(
      tester,
      ReviewScaffold(
        title: 'Nim',
        strings: BlackjackStrings.forLanguage(AppLanguage.english),
        record: GameRecord(game: 'nim', version: 1, seed: 1, rules: {'pile': 7, 'take': 3}),
        unit: ValueUnit.winChance,
        seatOf: (record, move) => move % 2,
        table: (context, step) => const SizedBox.expand(),
        coachRequest: _coach,
        toAnswer: _answer,
      ),
      size: const Size(800, 360),
      wrap: (child) => KitScope(newJobs: () => Jobs.using(backend), lastGames: LastGames(), child: child),
    );
    await tester.pump();
    expect(tester.widget<Slider>(find.byKey(const ValueKey('step slider'))).onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await tester.pump();
    expect(backend.started, isEmpty, reason: 'nothing to ask at the end of a game');
    expect(tester.takeException(), isNull);
  });

  for (final language in AppLanguage.values) {
    for (final size in [...shotSizes, const Size(800, 360)]) {
      final tag = shotTag(size, language);
      testWidgets('review $tag: the hand strip, a grade and the coach fit with no overflow', (tester) async {
        final backend = ManualBackend(nimJobs);
        await pumpShot(
          tester,
          ReviewScaffold(
            title: 'Blackjack',
            strings: BlackjackStrings.forLanguage(language),
            record: _record(),
            unit: ValueUnit.winChance,
            seatOf: (record, move) => move % 2,
            table: (context, step) => FeltArea(
              child: Center(child: TrickRow(cards: const [CardFace.suited(12, 3), CardFace.joker(big: true)])),
            ),
            bottom: (context, step) =>
                const HandFan(cards: [CardFace.suited(12, 3), CardFace.suited(11, 2), CardFace.suited(3, 1)]),
            coachRequest: _coach,
            toAnswer: _answer,
            look: _look,
            cards: true,
          ),
          size: size,
          language: language,
          wrap: (child) => KitScope(newJobs: () => Jobs.using(backend), lastGames: LastGames(), child: child),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('coach chip')));
        await tester.pump();
        backend.answer(backend.running.single);
        await _flush(tester);
        await shot(tester, 'review_$tag');
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('step slider')), findsOneWidget);
        final bar = tester.getRect(find.byKey(const ValueKey('step slider')));
        expect(bar.bottom, lessThanOrEqualTo(size.height), reason: 'the slider stays on screen');
      });
    }
  }
}

/// Jobs whose [background] the test sets: false is a browser page with no
/// worker, where jobs run on the page itself.
class _PageBackend extends ManualBackend {
  _PageBackend(super.jobs, {required this._background});

  bool _background;

  @override
  bool get background => _background;
  set background(bool on) => _background = on;
}
