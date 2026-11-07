/// Shared helpers for Gomoku's widget tests: pumping a screen at a size and
/// in a language with inline jobs, waiting for the bot and the coach, and
/// reading what the board paints.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/widgets/gomoku_board.dart';

import '../../../kit/shots.dart';

/// The three sizes each game checks: a sideways phone, a phone upright (a
/// browser), a PC.
const gomokuSizes = [Size(568, 320), Size(390, 844), Size(1280, 800)];

/// Shows [screen] at [size] in [language], with inline jobs and [lastGames]
/// (in memory by default).
Future<void> pumpGomoku(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(1280, 800),
  AppLanguage language = AppLanguage.english,
  LastGames? lastGames,
}) async {
  final games = lastGames ?? LastGames();
  await pumpShot(
    tester,
    screen,
    size: size,
    language: language,
    wrap: (child) => KitScope(newJobs: Jobs.inline, lastGames: games, child: child),
  );
  await settleGomoku(tester);
}

/// Lets the jobs run and the bot's pause pass (about 600 ms at Normal speed).
Future<void> settleGomoku(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

/// Takes the screen down and lets its timers end (no timer may be left).
Future<void> closeGomoku(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// What the game's board paints now.
GomokuBoardPainter boardPainter(WidgetTester tester, {Finder? board}) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: board ?? find.byKey(const ValueKey('gomoku board')), matching: find.byType(CustomPaint)).first,
  );
  return paint.painter! as GomokuBoardPainter;
}

/// The centre of board point (column, row from the top) on the screen.
Offset pointOnScreen(WidgetTester tester, (int, int) point) {
  final board = find.byKey(const ValueKey('gomoku board'));
  final painter = boardPainter(tester);
  final box = tester.getRect(board);
  final geometry = GomokuBoardGeometry(box.size, painter.lines, coordinates: painter.coordinates);
  return box.topLeft + geometry.at(point);
}

/// Whether [finder]'s widget is wholly inside the window.
bool onScreen(WidgetTester tester, Finder finder) {
  final window = Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final rect = tester.getRect(finder);
  return window.inflate(0.5).contains(rect.topLeft) && window.inflate(0.5).contains(rect.bottomRight);
}
