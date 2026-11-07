import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_analysis.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_jobs.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_online_jobs.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/games/gomoku/online/gomoku_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/ui/games/gomoku/online/gomoku_online_strings.dart';
import 'package:pokerfection/src/ui/games/gomoku/online/gomoku_online_ui.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';

import '../kit/shots.dart' show loadShotFonts;

/// Gomoku's online parts one at a time: the room's two jobs (the bot and a
/// spectator's coach, from the room's view), the app side's codec, bot and
/// coach plumbing, and the rules form in every language at the panel's
/// narrowest and widest.

/// Runs [job] on [input] as a worker would: through the request and reply.
Object? _run(GameJob<Object?, Object?> job, Object? input) {
  final reply = jsonDecode(
    runJobRequest(encodeRequest(1, job, input, platform: JobPlatform.desktop), kitJobs),
  ) as Map<String, Object?>;
  expect(reply['err'], isNull);
  return reply['out'];
}

/// The view of [moves] under [rules] for the seat to move, Black on [black].
Map<String, Object?> _view(String moves, {GomokuRules rules = GomokuRules.freestyle, int black = 0}) {
  final game = GomokuGame.fromMoves(rules, GomokuGame.parseMoves(moves));
  return {...gomokuPublicView(rules, black, game), 'you': game.toMove == Stone.black ? black : 1 - black};
}

void main() {
  setUpAll(loadShotFonts);
  const bot = GomokuOnlineBotJob(), coach = GomokuOnlineCoachJob();

  test('the room\'s bot and coach are Gomoku\'s jobs, registered by name (so the worker runs them), with views '
      'for the cross-platform check', () {
    expect(kitJobs['gomoku.onlineBot'], isA<GomokuOnlineBotJob>());
    expect(kitJobs['gomoku.onlineCoach'], isA<GomokuOnlineCoachJob>());
    expect(gomokuJobs, containsAll(gomokuOnlineJobs));
    for (final input in [
      ...bot.checkInputs(),
      ...coach.checkInputs().map((i) => GomokuOnlineBotInput(view: i.view, level: KitLevel.easy, seed: 0)),
    ]) {
      final view = GomokuOnlineView.fromJson(input.view);
      expect(view.game.isOver, isFalse);
      expect(view.you, view.seatToAct, reason: 'the seat to move');
    }
    expect(bot.checkInputs().length, greaterThanOrEqualTo(12));
  });

  test('the bot answers from its own view whichever seat has Black: it blocks a four, and under Renju never plays '
      'a forbidden point', () {
    for (final black in [0, 1]) {
      // White's four d10-g10: Black must block at h10 (or c10, the other end, is White's: c10 is Black's own).
      final out = _run(
        bot,
        GomokuOnlineBotInput(
          view: _view('c10 d10 h3 e10 j3 f10 l3 g10', black: black),
          level: KitLevel.easy,
          seed: 3,
        ),
      );
      expect(GomokuBotOutput.fromJson(out).move, 'h10', reason: 'Black on seat $black');
    }
    for (final level in KitLevel.values) {
      final out = _run(
        bot,
        GomokuOnlineBotInput(
          view: _view('h8 a1 j8 a2 i9 a3 i10 h15', rules: GomokuRules.renju),
          level: level,
          seed: 5,
        ),
      );
      expect(GomokuBotOutput.fromJson(out).move, isNot('i8'), reason: '$level: i8 is a double three');
    }
  });

  test("the coach ranks the side to move's moves, best first, as the solo coach does; the app shows them as the "
      'Best move list, a forced pass always listed', () {
    final out = _run(coach, GomokuOnlineCoachInput(view: _view('c10 d10 h3 e10 j3 f10 l3 g10'), seed: 1));
    final analysis = decodeGomokuAnalysis(out);
    expect(analysis.toMove, Stone.black);
    expect(analysis.best!.move.notation, 'h10');
    final ui = GomokuOnlineUi();
    final answer = ui.toAnswer(analysis);
    expect(answer.pick, 'h10');
    expect(answer.listed, isEmpty, reason: 'no pass to list');
    final pass = GomokuAnalysis(
      toMove: Stone.black,
      moves: const [
        MoveAnalysis(
          move: GomokuMove.pass,
          winChance: 0.4,
          score: -100,
          reasons: [MoveReason.mustPass],
          line: [GomokuMove.pass],
        ),
      ],
      depth: 0,
      nodes: 0,
      elapsed: Duration.zero,
    );
    expect(ui.toAnswer(pass).listed, {'pass'});
  });

  test("the app side: a seat's view is the spectators' with its seat; the bot's and the coach's jobs take the view "
      'as it came; the fallback move is legal and needs no job', () {
    final ui = GomokuOnlineUi();
    final spectators = gomokuPublicView(
      GomokuRules.renju,
      1,
      GomokuGame.fromMoves(GomokuRules.renju, GomokuGame.parseMoves('h8 a1 j8 a2 i9 a3 i10 a4')),
    );
    expect(ui.seatViewFrom(spectators, 1), {...spectators, 'you': 1});
    expect(ui.seatViewFrom(spectators, 2), isNull);
    final seatView = ui.seatViewFrom(spectators, 1)!;
    final botJob = ui.botJob(seatView, 'hard', seed: 9);
    expect(botJob.job.name, 'gomoku.onlineBot');
    expect((botJob.input! as GomokuOnlineBotInput).level, KitLevel.hard);
    expect(ui.coachJob(seatView, seed: 4).job.name, 'gomoku.onlineCoach');
    expect(ui.botMove(const GomokuBotOutput('h9')), 'h9');
    final fallback = ui.fallbackMove(seatView, seed: 3);
    final game = GomokuOnlineView.fromJson(seatView).game;
    expect(game.isLegal(GomokuMove.parse(fallback)), isTrue);
    expect(fallback, isNot('i8'), reason: "Black's forbidden double three");
    expect(fallback, 'a5', reason: 'it blocks White\'s four');
  });

  test('the rules form and its words, in every language', () {
    for (final language in AppLanguage.values) {
      final words = GomokuOnlineStrings.forLanguage(language).samples();
      expect(words, everyElement(isNotEmpty), reason: language.name);
      expect(words.toSet(), hasLength(words.length), reason: '${language.name}: each says something else');
    }
  });

  for (final width in [256.0, 420.0]) {
    testWidgets('the host\'s rules form fits $width wide in every language, greyed out for guests (nothing hidden)', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 600);
      addTearDown(tester.view.reset);
      final ui = GomokuOnlineUi();
      for (final language in AppLanguage.values) {
        for (final enabled in [true, false]) {
          Map<String, Object?>? changed;
          final settings = AppSettings()..language = language;
          await tester.pumpWidget(
            AppSettingsScope(
              settings: settings,
              child: MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Builder(
                      builder: (context) => ui.rulesForm(
                        context,
                        const GomokuOnlineRules(rules: GomokuRules.renju).toJson(),
                        enabled: enabled,
                        onChange: (r) => changed = r,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$language $width');
          final o = GomokuOnlineStrings.forLanguage(language);
          expect(find.text(o.blackRule(GomokuBlackRule.loser)), findsOneWidget);
          await tester.tap(find.text(o.blackRule(GomokuBlackRule.loser)));
          await tester.pump();
          expect(changed, enabled ? {'size': 15, 'win': 'renju', 'black': 'loser'} : isNull);
        }
      }
      expect(KitStrings.forLanguage(AppLanguage.english).draw, 'Draw');
    });
  }
}
