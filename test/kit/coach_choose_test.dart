import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/games/gomoku/l10n/gomoku_strings.dart';
import 'package:pokerfection/src/ui/kit/coach_panel.dart';
import 'package:pokerfection/src/ui/kit/game_scaffold.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import 'fakes.dart';
import 'nim.dart';
import 'shots.dart';

/// Nim whose take of 1 plays the part of Pass: a choice the coach list must
/// always show when it is legal, even when the coach leaves it out.
class _PassNim extends NimController {
  _PassNim({required super.jobs, super.top, super.pile, super.speed});

  @override
  List<String> listedMoves(int seat) => left >= 1 ? const ['1'] : const [];
}

final _strings = GomokuStrings.forLanguage(AppLanguage.english);

CoachAnswer _answer(List<(String, double)> lines, {Set<String> listed = const {}}) => CoachAnswer(
      unit: ValueUnit.winChance,
      lines: [for (final (move, value) in lines) CoachLine(move: move, value: value)],
    ).withListed(listed);

/// The coach rows on screen, top to bottom, by their move.
List<String> _rows(WidgetTester tester) => [
      for (final row in tester.widgetList(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == '_CoachRow'),
      ))
        if (row.key case ValueKey<String>(:final value)) value,
    ];

Finder _row(String move) => find.byKey(ValueKey(move));

void main() {
  setUpAll(loadShotFonts);

  group('the answer', () {
    test('a listed move (Pass) is among the rows however low it ranks, in its place by rank', () {
      final answer = _answer([('a', .9), ('b', .8), ('c', .7), ('d', .6), ('e', .5), ('pass', .1)], listed: {'pass'});
      expect([for (final l in answer.shown(3)) l.move], ['a', 'b', 'pass']);
      expect([for (final l in answer.shown(6)) l.move], ['a', 'b', 'c', 'd', 'e', 'pass']);
    });

    test('the pick always shows, and listed moves never push it out: the list grows instead', () {
      final answer = CoachAnswer(
        unit: ValueUnit.points,
        pick: 'c',
        lines: [for (final (m, v) in [('a', 3.0), ('b', 2.0), ('c', 1.0), ('x', 0.0), ('y', -1.0)]) CoachLine(move: m, value: v)],
      ).withListed({'x', 'y'});
      expect([for (final l in answer.shown(3)) l.move], ['c', 'x', 'y'], reason: 'the pick and both listed moves');
      expect([for (final l in answer.shown(2)) l.move], ['c', 'x', 'y'], reason: 'more listed moves than rows');
    });

    test('a line added later goes before the first line worth less; the pick stays', () {
      final answer = _answer([('a', .9), ('b', .5)]).withLine(const CoachLine(move: 'pass', value: .7));
      expect([for (final l in answer.lines) l.move], ['a', 'pass', 'b']);
      expect(answer.pick, 'a');
      final last = _answer([('a', .9)]).withLine(const CoachLine(move: 'pass', value: .1));
      expect([for (final l in last.lines) l.move], ['a', 'pass']);
      final replaced = last.withLine(const CoachLine(move: 'pass', value: .95));
      expect([for (final l in replaced.lines) l.move], ['pass', 'a'], reason: 'one line per move');
    });
  });

  group('a coach row', () {
    Future<(List<String>, List<String>)> pumpList(WidgetTester tester, {String? selected}) async {
      final selects = <String>[], plays = <String>[];
      await pumpShot(
        tester,
        Scaffold(
          body: CoachList(
            answer: _answer([('3', .9), ('2', .5), ('1', .2)]),
            strings: _strings,
            look: CoachLook(onSelect: selects.add, onPlay: plays.add, selected: selected),
          ),
        ),
        size: const Size(400, 300),
      );
      return (selects, plays);
    }

    testWidgets('in a short panel (a sideways phone) it shows the rows that fit, a low-ranked Pass in sight among them',
        (tester) async {
      // Rows with a reason line are about half as tall again: three fit in
      // 160 px, so the list is the top two and Pass, not five rows with
      // Pass cut off below the fold.
      final answer = CoachAnswer(
        unit: ValueUnit.winChance,
        lines: [
          for (final (move, value) in [('a', .9), ('b', .8), ('c', .7), ('d', .6), ('pass', .1)])
            CoachLine(move: move, value: value, reasons: const ['why']),
        ],
      ).withListed({'pass'});
      Future<void> pumpIn(double height, {bool reasons = true}) => pumpShot(
            tester,
            Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 264,
                  height: height,
                  child: LayoutBuilder(
                    builder: (context, area) => SingleChildScrollView(
                      child: CoachList(
                        answer: answer,
                        strings: _strings,
                        dense: true,
                        fitHeight: area.maxHeight,
                        look: CoachLook(reasonText: reasons ? (code) => 'Keeps the 2 for last' : null),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            size: const Size(568, 320),
          );
      await pumpIn(160);
      expect(_rows(tester), ['a', 'b', 'pass']);
      expect(tester.getRect(_row('pass')).bottom, lessThanOrEqualTo(160), reason: 'Pass in sight, not below the fold');
      await pumpIn(160, reasons: false);
      expect(_rows(tester), ['a', 'b', 'c', 'd', 'pass'], reason: 'shorter rows: five fit');
      expect(tester.getRect(_row('pass')).bottom, lessThanOrEqualTo(160));
      await pumpIn(90);
      expect(_rows(tester), ['a', 'pass'], reason: 'not even three fit: the best move and Pass');
    });

    testWidgets('a lit choice button sits on a solid fill, so its label never looks greyed out', (tester) async {
      Future<Decoration?> ring({required bool lit}) async {
        await pumpShot(
          tester,
          Scaffold(
            body: Center(
              child: ChosenRing(lit: lit, child: OutlinedButton(onPressed: () {}, child: const Text('Pass'))),
            ),
          ),
          size: const Size(400, 300),
        );
        await tester.pump(const Duration(milliseconds: 300));
        return tester
            .widget<Container>(find.descendant(of: find.byType(ChosenRing), matching: find.byType(Container)).first)
            .decoration;
      }

      final lit = await ring(lit: true) as BoxDecoration;
      expect(lit.color, ChosenRing.fill, reason: 'opaque, under the see-through outlined button');
      final out = await ring(lit: false) as BoxDecoration;
      expect(out.color?.a ?? 0, 0, reason: 'unlit: nothing behind the button');
    });

    testWidgets('a single tap selects its move and never plays it, however long the player waits', (tester) async {
      final (selects, plays) = await pumpList(tester);
      await tester.tap(_row('2'));
      await tester.pump(const Duration(seconds: 2));
      expect(selects, ['2']);
      expect(plays, isEmpty);
    });

    testWidgets('a double tap plays its move (the first tap selected it)', (tester) async {
      final (selects, plays) = await pumpList(tester);
      await tester.tap(_row('1'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(_row('1'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(selects, ['1']);
      expect(plays, ['1']);
    });

    testWidgets('two taps far apart are two selects, not a play; a tap on another row is a select', (tester) async {
      final (selects, plays) = await pumpList(tester);
      await tester.tap(_row('3'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(_row('3'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_row('2'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(selects, ['3', '3', '2']);
      expect(plays, isEmpty, reason: 'the second and third taps were on different rows');
    });

    testWidgets("the selected move's row is lit", (tester) async {
      await pumpList(tester, selected: '2');
      final lit = find.byKey(const ValueKey('selected row'));
      expect(lit, findsOneWidget);
      expect(find.descendant(of: _row('2'), matching: lit), findsOneWidget);
    });

    testWidgets('in a review (no onPlay) a double tap only selects', (tester) async {
      final selects = <String>[];
      await pumpShot(
        tester,
        Scaffold(
          body: CoachList(
            answer: _answer([('3', .9), ('2', .5)]),
            strings: _strings,
            look: CoachLook(onSelect: selects.add),
          ),
        ),
        size: const Size(400, 300),
      );
      await tester.tap(_row('2'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_row('2'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(selects, ['2', '2']);
    });
  });

  group('in a game', () {
    Future<NimController> pumpGame(WidgetTester tester, NimController game, {CoachLook look = const CoachLook()}) async {
      await game.newGame();
      game.coachVisible = true;
      await pumpShot(
        tester,
        GameScaffold(
          title: 'Nim',
          strings: _strings,
          controller: game,
          table: const SizedBox.expand(),
          panel: ListenableBuilder(
            listenable: game,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.all(8),
              child: ChosenRing(
                lit: game.chosen == '1',
                child: FilledButton(onPressed: () => game.humanMove('1'), child: const Text('Pass')),
              ),
            ),
          ),
          look: look,
        ),
        size: const Size(900, 420),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      return game;
    }

    /// Ends the test's game: its timers (the bot's pause, saving) with it.
    Future<void> close(WidgetTester tester, NimController game) async {
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      game.dispose();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets("a tap lights a choice (the kit's choose) and its button; a double tap plays it", (tester) async {
      final game = await pumpGame(tester, _PassNim(jobs: Jobs.inline(extra: nimJobs)));
      await tester.tap(_row('1'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(game.chosen, '1');
      expect(game.record.moves, isEmpty, reason: 'a single tap never plays');
      expect(find.byKey(const ValueKey('chosen ring')), findsOneWidget, reason: 'the button lights up');
      expect(find.descendant(of: _row('1'), matching: find.byKey(const ValueKey('selected row'))), findsOneWidget);
      await shot(tester, 'choose_lit_en_900x420');
      await tester.tap(_row('1'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(_row('1'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.record.moves.first, '1');
      expect(game.chosen, isNull, reason: 'a move clears the choice');
      await close(tester, game);
    });

    testWidgets('Enter plays the lit choice before the game\'s own Enter', (tester) async {
      final entered = <String>[];
      final game = _PassNim(jobs: Jobs.inline(extra: nimJobs));
      await game.newGame();
      game.coachVisible = true;
      await pumpShot(
        tester,
        GameScaffold(
          title: 'Nim',
          strings: _strings,
          controller: game,
          table: const SizedBox.expand(),
          panel: const SizedBox(height: 40),
          shortcuts: {const SingleActivator(LogicalKeyboardKey.enter): () => entered.add('game')},
        ),
        size: const Size(900, 420),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(entered, ['game'], reason: 'nothing chosen: the game\'s Enter');
      game.choose('2');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(game.record.moves.first, '2');
      expect(entered, ['game'], reason: 'the choice was played instead');
      await close(tester, game);
    });

    testWidgets("the game's own select (picking cards) runs on a tap, and a lit choice goes out", (tester) async {
      final picked = <String>[];
      final game = await pumpGame(
        tester,
        _PassNim(jobs: Jobs.inline(extra: nimJobs)),
        look: CoachLook(onSelect: picked.add),
      );
      game.choose('1');
      await tester.tap(_row('3'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(picked, ['3']);
      expect(game.chosen, isNull, reason: 'picking cards drops the Pass lit before');
      expect(game.record.moves, isEmpty);
      await close(tester, game);
    });

    testWidgets('a double tap out of turn plays nothing and throws nothing', (tester) async {
      final game = await pumpGame(tester, _PassNim(jobs: Jobs.inline(extra: nimJobs), speed: PlaybackSpeed.normal));
      game.humanMove('3');
      await tester.pump();
      expect(game.playFromCoach('1'), isFalse, reason: "the bot's turn");
      expect(game.record.moves, ['3']);
      await close(tester, game);
    });

    testWidgets('Pass left out by the coach is asked for, and shows with its value', (tester) async {
      // The coach rates only its best take; the take of 1 (our Pass) is added.
      final game = await pumpGame(tester, _PassNim(jobs: Jobs.inline(extra: nimJobs), top: 1, pile: 7));
      expect(game.coach!.rates('1'), isTrue);
      expect(game.coach!.rates('2'), isFalse, reason: 'only the listed move is added');
      expect(_rows(tester), containsAllInOrder(['3', '1']));
      expect(
        find.descendant(of: _row('1'), matching: find.text(formatValue(ValueUnit.winChance, game.coach!.lineFor('1')!.value))),
        findsOneWidget,
      );
      await close(tester, game);
    });
  });

  group('the controller', () {
    late ManualBackend backend;
    late Jobs jobs;

    setUp(() {
      backend = ManualBackend(nimJobs);
      jobs = Jobs.using(backend);
    });

    Future<_PassNim> started({int? top = 1}) async {
      final game = _PassNim(jobs: jobs, top: top);
      await game.newGame();
      await settle();
      return game;
    }

    test('a listed move the answer left out gets a second coach job, with the move included', () async {
      final game = await started();
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      expect(game.coach!.listed, {'1'});
      expect(game.coach!.rates('1'), isFalse);
      expect(game.coachJobs, ['list:0']);
      expect(game.coachThinking, isTrue, reason: 'the bar runs until Pass is in');
      expect(backend.on(JobLane.coach)!.request, contains('"include":"1"'));
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      expect(game.coach!.rates('1'), isTrue);
      expect(game.coach!.pick, '3', reason: 'the pick is unchanged');
      expect(game.coachThinking, isFalse);
      game.dispose();
    });

    test('an answer that rates every listed move asks for nothing more', () async {
      final game = await started(top: null);
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      expect(game.coach!.rates('1'), isTrue);
      expect(game.coachJobs, isEmpty);
      game.dispose();
    });

    test('Pass played while its line is on the way is graded once it comes, with no third job', () async {
      final game = await started();
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      game.humanMove('1');
      await settle();
      expect(game.marks.first, isNull, reason: 'waiting for its line');
      final before = backend.started.length;
      backend.answer(backend.started.firstWhere((j) => j.request.contains('"include":"1"')));
      await settle();
      expect(game.marks.first, isNotNull);
      expect(
        backend.started.skip(before).where((j) => j.name == 'nim.coach'),
        isEmpty,
        reason: 'no grading job of its own',
      );
      game.dispose();
    });

    test('another move played meanwhile is graded at once, and the Pass job is cancelled', () async {
      final game = await started();
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      final pass = backend.on(JobLane.coach)!;
      game.humanMove('3');
      await settle();
      expect(game.marks.first, isNotNull);
      expect(pass.token.isCancelled, isTrue);
      game.dispose();
    });

    test('a new deal cancels the listed move\'s job and drops the choice', () async {
      final game = await started();
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      game.choose('1');
      final pass = backend.on(JobLane.coach)!;
      await game.newGame();
      expect(pass.token.isCancelled, isTrue);
      expect(game.chosen, isNull);
      game.dispose();
    });
  });
}
