/// The four games in a room, side by side: each game is
/// played through the fake room (Ann hosts and sits, Ben sits, a bot fills
/// the rest, Cy watches with the coach on and the host's switch on), and
/// every screen (a seated player's, a spectator's, a round's end) is laid
/// out at every size and in every language. Nothing may overflow.
/// PNGs are written only with `--dart-define=SHOTS=<folder>`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/kit/cards.dart' show GameCardView, SeatBadge;
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/runner_client.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../kit/shots.dart' show loadShotFonts, shotTag, shotTheme, shotsFolder;
import 'room_app.dart';
import 'room_kit.dart';

const _sizes = [Size(512, 320), Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

final _boundary = GlobalKey();

RoomService _rooms(String name) => RoomService(
  settings: AppSettings()
    ..nickname = name
    ..speed = PlaybackSpeed.instant,
  gameUis: onlineGameUis,
  newJobs: () => Jobs.inline(),
);

Future<void> _pumpApp(WidgetTester tester, RoomService rooms) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: roomApp(const HomeScreen(), rooms: rooms, theme: shotTheme()),
    ),
  );
  await tester.pump();
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (shotsFolder.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(shotsFolder).createSync(recursive: true);
    File('$shotsFolder/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _pumps(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The pile's cards (the play to beat and those under it) that lie on a
/// seat's badge, or a seat's Pass chip on them, on the screen now: the
/// player must read what they have to beat, and whose seat is whose.
List<String> _pileCovered(WidgetTester tester) {
  final pile = find.byKey(const ValueKey('to beat'));
  if (pile.evaluate().isEmpty) return const [];
  final cards = [
    for (final e in find.descendant(of: pile, matching: find.byType(GameCardView)).evaluate())
      tester.getRect(find.byWidget(e.widget)).deflate(1),
  ];
  final seats = [
    for (final e in find.byType(SeatBadge).evaluate()) ('badge', tester.getRect(find.byWidget(e.widget))),
    for (final e in find.byKey(const ValueKey('pass chip')).evaluate())
      ('Pass', tester.getRect(find.byWidget(e.widget))),
  ];
  return [
    for (final card in cards)
      for (final (what, rect) in seats)
        if (card.overlaps(rect) && card.intersect(rect).width > 2 && card.intersect(rect).height > 2)
          'a pile card at $card under a $what at $rect',
  ];
}

/// Every overflow or other error at each size and language, collected.
Future<List<String>> _everywhere(WidgetTester tester, RoomService rooms, String name) async {
  final problems = <String>[];
  final reported = FlutterError.onError;
  // With --dart-define=FULL=true: each error in full, to find the widget.
  if (const bool.fromEnvironment('FULL')) {
    FlutterError.onError = (details) {
      debugPrint('$name: ${details.toString()}');
      reported!(details);
    };
  }
  for (final language in AppLanguage.values) {
    rooms.settings.update((s) => s.language = language);
    await _pumpApp(tester, rooms);
    for (final size in _sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await _pumps(tester);
      rooms.watch();
      await _pumps(tester);
      await _shot(tester, '${name}_${shotTag(size, language)}');
      final e = tester.takeException();
      if (e != null) {
        problems.add('$name ${shotTag(size, language)}: ${'$e'.split('\n').first}');
      }
      for (final covered in _pileCovered(tester).take(1)) {
        problems.add('$name ${shotTag(size, language)}: $covered');
      }
    }
  }
  FlutterError.onError = reported;
  rooms.settings.update((s) => s.language = AppLanguage.english);
  return problems;
}

/// [r]'s player makes the game's own quick legal move.
void _autoPlay(RunnerClient? r) {
  if (r == null || !r.myTurn) return;
  r.move(r.ui.fallbackMove(r.view!, seed: 0));
}

Future<void> _review(WidgetTester tester, String key, int seats, int movesIn) async {
  final tag = '${key}_$seats';
  addTearDown(tester.view.reset);
  final ui = onlineGameUis[key]!;
  final server = TestServer(games: {key: ui.online});
  final ann = _rooms('Annabelle'), ben = _rooms('Benedict'), cy = _rooms('Cy');
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  await _pumpApp(tester, ann);
  final own = server.client();
  await server.open(tester, own, const CreateRoom(name: 'Annabelle'));
  ann.enter(own);
  final benClient = server.client(), cyClient = server.client();
  await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Benedict'));
  ben.enter(benClient);
  await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
  cy.enter(cyClient);
  own.send(ChooseGame(game: key, setup: {'seats': seats, 'turnLimit': 0, 'rules': ui.online.defaultRules}));
  await server.wait(tester, const Duration(seconds: 1));
  own.send(const HostSettings(seeBots: true));
  own.send(const TakeSeat(0));
  benClient.send(const TakeSeat(1));
  for (var b = 2; b < seats; b++) {
    own.send(const AddBot(style: 'easy'));
  }
  await server.until(tester, () => own.room!.taken == seats, 'seated');
  own.send(const StartGame());
  await server.until(tester, () => ann.runner?.state != null && cy.runner?.state != null, 'the deal');
  for (var guard = 0, moved = 0; ; guard++) {
    expect(guard, lessThan(2000));
    final r = ann.runner!;
    if (r.myTurn && moved >= movesIn) break;
    if (r.over != null) {
      await server.wait(tester);
      continue;
    }
    if (r.myTurn) {
      _autoPlay(r);
      moved++;
    }
    if (ben.runner?.myTurn ?? false) {
      _autoPlay(ben.runner);
      moved++;
    }
    await server.wait(tester);
  }
  cy.runner!.setCoach(true);
  final problems = <String>[
    ...await _everywhere(tester, ann, '${tag}_seated_host'),
    ...await _everywhere(tester, ben, '${tag}_seated_guest'),
    ...await _everywhere(tester, cy, '${tag}_spectator'),
  ];
  for (var guard = 0; ann.runner!.over == null; guard++) {
    expect(guard, lessThan(4000));
    _autoPlay(ann.runner);
    _autoPlay(ben.runner);
    await server.wait(tester);
  }
  problems
    ..addAll(await _everywhere(tester, ann, '${tag}_over_host'))
    ..addAll(await _everywhere(tester, cy, '${tag}_over_spectator'));
  for (final r in [ann, ben, cy]) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
  expect(problems, isEmpty);
}

/// A guest's view of the host's rules for [key] on the room's table
/// (and the host's own once the game is under way): every "?" in the
/// game's rules still opens its explanation, though the rules are greyed
/// out.
Future<void> _guestRules(WidgetTester tester, String key, int seats) async {
  addTearDown(tester.view.reset);
  final ui = onlineGameUis[key]!;
  final server = TestServer(games: {key: ui.online});
  final ann = _rooms('Ann'), ben = _rooms('Ben');
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  final own = server.client();
  await server.open(tester, own, const CreateRoom(name: 'Ann'));
  ann.enter(own);
  final benClient = server.client();
  await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
  ben.enter(benClient);
  own.send(ChooseGame(game: key, setup: {'seats': seats, 'turnLimit': 0, 'rules': ui.online.defaultRules}));
  await _pumpApp(tester, ben);
  await server.wait(tester, const Duration(seconds: 1));
  final rules = find.byKey(const ValueKey('rules'));
  await tester.ensureVisible(rules);
  await tester.pump();
  await tester.tap(rules);
  await server.wait(tester, const Duration(milliseconds: 500));
  await _shot(tester, '${key}_rules_guest');
  final unreachable = <int>[];
  final helps = find.descendant(of: rules, matching: find.byIcon(Icons.help_outline));
  final count = helps.evaluate().length;
  expect(count, greaterThan(0));
  for (var i = 0; i < count; i++) {
    await tester.ensureVisible(helps.at(i));
    await tester.pump();
    await tester.tap(helps.at(i), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    if (find.byType(Dialog).evaluate().isEmpty) {
      unreachable.add(i);
      continue;
    }
    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await tester.pump(const Duration(milliseconds: 400));
  }
  for (final r in [ann, ben]) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
  expect(unreachable, isEmpty, reason: 'the "?"s (of $count) a guest cannot open');
}

/// The host's rules for [key] on the room's table, at every size and in
/// every language, scrolled to each "?" in turn: nothing may overflow.
Future<void> _hostRules(WidgetTester tester, String key, int seats) async {
  addTearDown(tester.view.reset);
  final ui = onlineGameUis[key]!;
  final server = TestServer(games: {key: ui.online});
  final ann = _rooms('Ann');
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  final own = server.client();
  await server.open(tester, own, const CreateRoom(name: 'Ann'));
  ann.enter(own);
  own.send(ChooseGame(game: key, setup: {'seats': seats, 'turnLimit': 0, 'rules': ui.online.defaultRules}));
  final problems = <String>[];
  for (final language in AppLanguage.values) {
    ann.settings.update((s) => s.language = language);
    await _pumpApp(tester, ann);
    await server.wait(tester, const Duration(seconds: 1));
    ann.watch();
    await server.wait(tester, const Duration(seconds: 1));
    for (final size in _sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await _pumps(tester);
      final rules = find.byKey(const ValueKey('rules'));
      // Further down the Game tab's list: scrolled to.
      final lists = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
      for (var k = 0; rules.evaluate().isEmpty && k < lists.evaluate().length; k++) {
        for (var n = 0; n < 30 && rules.evaluate().isEmpty; n++) {
          await tester.drag(lists.at(k), const Offset(0, -80), warnIfMissed: false);
          await tester.pump();
        }
      }
      if (rules.evaluate().isEmpty) {
        await _shot(tester, '${key}_rules_host_missing_${shotTag(size, language)}');
        problems.add('${shotTag(size, language)}: no Rules');
        continue;
      }
      if (find.descendant(of: rules, matching: find.byIcon(Icons.help_outline)).evaluate().isEmpty) {
        await tester.ensureVisible(rules);
        await tester.pump();
        await tester.tap(rules);
        await _pumps(tester);
      }
      final helps = find.descendant(of: rules, matching: find.byIcon(Icons.help_outline));
      final count = helps.evaluate().length;
      for (var i = 0; i < count; i += 3) {
        await tester.ensureVisible(helps.at(i));
        await _pumps(tester);
        await _shot(tester, '${key}_rules_host_${i}_${shotTag(size, language)}');
        final e = tester.takeException();
        if (e != null) problems.add('${shotTag(size, language)} at "?" $i: ${'$e'.split('\n').first}');
      }
    }
  }
  unawaited(ann.leave());
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
  expect(problems, isEmpty);
}

void main() {
  setUpAll(loadShotFonts);

  for (final (key, seats) in const [('gomoku', 2), ('big_two', 3), ('doudizhu', 3), ('blackjack', 3)]) {
    testWidgets('$key: the host rules fit every size in every language', (tester) => _hostRules(tester, key, seats));
  }

  for (final (key, seats) in const [('gomoku', 2), ('big_two', 3), ('doudizhu', 3), ('blackjack', 3)]) {
    testWidgets('$key: a guest opens every "?" of the greyed-out rules', (tester) => _guestRules(tester, key, seats));
  }

  testWidgets('Gomoku in a room fits every size in every language', (tester) => _review(tester, 'gomoku', 2, 6));
  testWidgets('Big Two in a room fits every size in every language', (tester) => _review(tester, 'big_two', 3, 3));
  testWidgets(
    'Fight the Landlord in a room fits every size in every language',
    (tester) => _review(tester, 'doudizhu', 3, 3),
  );
  testWidgets('Blackjack in a room fits every size in every language', (tester) => _review(tester, 'blackjack', 3, 0));
  testWidgets(
    'Blackjack at seven seats fits every size in every language',
    (tester) => _review(tester, 'blackjack', 7, 0),
  );
  testWidgets('Big Two at four seats fits every size in every language', (tester) => _review(tester, 'big_two', 4, 3));
  testWidgets('Big Two at two seats fits every size in every language', (tester) => _review(tester, 'big_two', 2, 3));
}
