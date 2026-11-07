/// Helpers for Big Two's widget tests: a game screen with a seeded deal,
/// inline jobs and no pauses, and ways to move it on.
library;

import 'dart:math';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/match.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_coach_view.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_review.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_screen.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';

/// The sizes the game's screens are checked at: a phone sideways, a phone
/// upright (browsers), a PC.
const bigTwoSizes = [Size(568, 320), Size(390, 844), Size(1280, 800)];

/// A controller whose deals come from [seed], with no sound, and no pauses
/// or card flights unless [speed] asks for them. [match]: the setup's
/// target (default the scoring's standard, a match to 100).
BigTwoController seededGame({
  BigTwoRules? rules,
  bool training = true,
  int seed = 3,
  Map<String, Object?> toggles = const {},
  LastGames? lastGames,
  PlaybackSpeed speed = PlaybackSpeed.instant,
  MatchTarget? match,
}) {
  GameSounds.output = (_) {};
  return BigTwoController(
    setup: BigTwoSetup(
      rules: rules ?? BigTwoRules.standard(),
      level: KitLevel.easy,
      training: training,
      toggles: toggles,
      match: match,
    ),
    jobs: Jobs.inline(),
    lastGames: lastGames ?? LastGames(),
    speed: () => speed,
    random: Random(seed),
  );
}

/// Shows the game screen for [game] at [size] in [language].
Future<void> pumpGame(
  WidgetTester tester,
  BigTwoController game, {
  Size size = const Size(1280, 800),
  AppLanguage language = AppLanguage.english,
}) async {
  await pumpShot(
    tester,
    BigTwoScreen(setup: game.setup, controller: game),
    size: size,
    language: language,
  );
  await settleGame(tester);
}

/// Lets the jobs and bots run.
Future<void> settleGame(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

/// On to the player's turn with something to play and (in Training) the
/// coach's answer, passing on turns where passing is all there is.
Future<void> toMyPlayableTurn(WidgetTester tester, BigTwoController game) async {
  for (var guard = 0; guard < 200; guard++) {
    await settleGame(tester);
    if (!game.myTurn) continue;
    final legal = game.state.legalMoves();
    // A forced pass gets no coach answer: pass on at once.
    if (legal.length == 1 && legal.single.isPass) {
      game.passTurn();
      continue;
    }
    if (game.training && game.coach == null) continue;
    if (legal.any((p) => !p.isPass)) return;
    game.passTurn();
  }
  fail('never reached a playable turn');
}

/// Plays the deal out, the player following the coach (or the first legal move).
Future<void> playToEnd(WidgetTester tester, BigTwoController game) async {
  for (var guard = 0; guard < 400 && !game.isOver; guard++) {
    await settleGame(tester);
    if (game.myTurn) game.humanMove(game.coach?.pick ?? bigTwoMoveText(0, game.state.legalMoves().first));
  }
  await settleGame(tester);
  expect(game.isOver, isTrue);
}

/// Closes the screen (disposing its controller) at the end of a test.
Future<void> closeGame(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

/// The hand's key text for [card] (HandFan keys a card by its face).
String bigTwoFaceKey(Card card) => bigTwoFace(card).toString();

/// [child] with jobs on the test's thread and records in [store].
Widget Function(Widget child) bigTwoKit(LastGames store) =>
    (child) => KitScope(newJobs: Jobs.inline, lastGames: store, child: child);

/// A deal played to its end on the game screen and saved, as the menu's
/// Last game finds it. The player plays the coach's last-rated move every
/// other turn (so some grades are below Best), else its pick (or, in Free
/// Play, the first legal move).
Future<GameRecord> savedDeal(WidgetTester tester, {bool training = true, int seed = 9, BigTwoRules? rules}) async {
  final store = LastGames();
  final game = seededGame(training: training, seed: seed, rules: rules, lastGames: store);
  await pumpGame(tester, game);
  var turn = 0;
  for (var guard = 0; guard < 400 && !game.isOver; guard++) {
    await settleGame(tester);
    if (!game.myTurn) continue;
    final legal = game.state.legalMoves();
    if (training && legal.length > 1 && game.coach == null) continue;
    final coach = game.coach;
    game.humanMove(
      coach == null
          ? bigTwoMoveText(0, legal.first)
          : (turn++).isOdd
          ? coach.lines.last.move
          : coach.pick,
    );
  }
  await settleGame(tester);
  expect(game.isOver, isTrue);
  await closeGame(tester);
  return (await loadLastBigTwo(store))!;
}
