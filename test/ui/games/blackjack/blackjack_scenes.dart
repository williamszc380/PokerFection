/// Blackjack screens in known states, for the widget tests and the
/// screenshots: the game with a chosen shoe (its seed), jobs on the test's
/// thread, and records in memory.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_jobs.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_controller.dart';
import 'package:pokerfection/src/ui/games/blackjack/blackjack_screen.dart';
import 'package:pokerfection/src/ui/kit/game_scaffold.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';

import '../../../kit/shots.dart';

/// Shoes (seeds of the default 6-deck game) whose first round is:
/// a hard 16 against a ten,
const seed16v10 = 80;

/// a pair of eights against a 2 to 6,
const seedEights = 534;

/// the dealer showing an ace (insurance offered),
const seedInsurance = 15;

/// the player's blackjack against the dealer's ace (even money offered).
const seedEvenMoney = 126;

/// a long hand: five hits make a seven-card 19, and the dealer draws to
/// four cards against it.
const seedLong = 9683;

/// A single-deck shoe where, three moves in (the chart's plays), the cards
/// seen change the play: 14 against a 2, the chart stands, the count hits.
const seedSeen = 2;

/// A game with the coach chip on (it starts off: the best plays are the
/// player's to ask for).
const coachOn = BlackjackSettings(toggles: {'coach': true});

/// The three sizes each game is checked at: a sideways phone, a phone
/// upright (browsers), a PC.
const gameSizes = [Size(568, 320), Size(390, 844), Size(1280, 800)];

/// The chart job, counting how often it runs.
class CountingChartJob extends BlackjackChartJob {
  CountingChartJob();

  var runs = 0;

  @override
  BasicStrategyChart run(BlackjackRules input, JobContext context) {
    runs++;
    return super.run(input, context);
  }
}

/// A Random that always gives [seed]: the game's shoe is then known.
class FixedSeed implements Random {
  FixedSeed(this.seed);

  final int seed;

  @override
  int nextInt(int max) => seed % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

/// [child] with jobs on the test's thread and records in [store].
Widget Function(Widget child) kitWrap(LastGames store) =>
    (child) => KitScope(newJobs: Jobs.inline, lastGames: store, child: child);

/// Lets the jobs (the chart, the coach) finish and the screen settle: on
/// a game screen, until the move's cards have all flown in and the hole
/// card has turned over.
Future<void> settleGame(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  final scaffold = find.byType(GameScaffold);
  for (var i = 0; i < 100; i++) {
    if (scaffold.evaluate().isEmpty) return;
    final game = gameOf(tester);
    if (!game.dealing.active && !game.flights.flying) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The game on the screen.
BlackjackController gameOf(WidgetTester tester) =>
    tester.widget<GameScaffold>(find.byType(GameScaffold)).controller as BlackjackController;

/// Shows a game of [settings] with the shoe of [seed], at [size] in
/// [language], ready for the first deal (the chart made).
Future<BlackjackController> pumpGame(
  WidgetTester tester, {
  required Size size,
  AppLanguage language = AppLanguage.english,
  BlackjackSettings settings = const BlackjackSettings(),
  int seed = seed16v10,
  LastGames? store,
}) async {
  await pumpShot(
    tester,
    BlackjackScreen(settings: settings, random: FixedSeed(seed)),
    size: size,
    language: language,
    wrap: kitWrap(store ?? LastGames()),
  );
  await settleGame(tester);
  return gameOf(tester);
}

/// Plays [move] and lets the screen settle.
Future<void> play(WidgetTester tester, String move) async {
  gameOf(tester).humanMove(move);
  await settleGame(tester);
}

/// Plays the coach's pick (the chart's play), or deals, [count] times.
Future<void> playChart(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    final game = gameOf(tester);
    final legal = game.play.legalMoves();
    final pick = game.coach?.pick;
    await play(tester, pick != null && legal.contains(pick) ? pick : legal.first);
  }
}

/// Plays the whole shoe by the chart, to its end.
Future<void> playToEnd(WidgetTester tester) async {
  while (!gameOf(tester).isOver) {
    await playChart(tester, 1);
  }
}

/// Pumps frames for [ms] milliseconds, 16 ms apart, as a screen draws
/// them (one long pump would start each animation at its end).
Future<void> frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Closes the screen and lets its last save go out (no timer left behind).
Future<void> closeGame(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// The decision now is [action] for hand 0.
String move0(BlackjackAction action) => handMove(0, action);

/// Lets the cards finish turning over (they flip in 0.4 s), then saves a
/// screenshot (only with --dart-define=SHOTS).
Future<void> snap(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  await shot(tester, name);
}
