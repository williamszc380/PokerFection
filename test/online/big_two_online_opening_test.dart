/// Who goes first in a room: every device, seated or watching, opens each
/// deal with the step at its own Animations speed (big_two_opening.dart),
/// from nothing but the views' public facts. A seated starter's Play waits
/// for its end; a play the room already has (a bot's, which comes after
/// 600 ms) is held back until it ends and then flies to the pile. Then the
/// middle says who starts until the first play. Screenshots of the step
/// and its result at every size in every language with
/// `--dart-define=SHOTS=<folder>` (see test/kit/shots.dart); without it the
/// test still lays every screen out and checks that nothing overflows.
library;

import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_runner.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_coach_view.dart' show bigTwoFace;
import 'package:pokerfection/src/ui/games/big_two/big_two_opening.dart' show BigTwoOpeningLayer;
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/runner_client.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../kit/shots.dart' show loadShotFonts, shotTag, shotTheme, shotsFolder;
import 'room_app.dart';
import 'room_kit.dart';

const _sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

final _boundary = GlobalKey();
final _step = find.byKey(const ValueKey('opening step'));
final _note = find.byKey(const ValueKey('opening note'));
final _words = find.byKey(const ValueKey('opening words'));
final _pile = find.byKey(const ValueKey('to beat'));
final _hand = find.byKey(const ValueKey('hand'));

RoomService _rooms(String name, {AppLanguage language = AppLanguage.english}) => RoomService(
  settings: AppSettings()
    ..nickname = name
    ..language = language
    ..speed = PlaybackSpeed.normal,
  gameUis: onlineGameUis,
  newJobs: () => Jobs.inline(),
);

/// [rooms]'s app on its game screen (the room's Watch).
Future<void> _open(WidgetTester tester, RoomService rooms, {Size size = const Size(1280, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: roomApp(const HomeScreen(), rooms: rooms, theme: shotTheme()),
    ),
  );
  await tester.pump();
  rooms.watch();
  await tester.pump();
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

String _wordsIn(Finder finder) =>
    (find.descendant(of: finder, matching: find.byType(Text)).evaluate().first.widget as Text).data!;

/// The room's starting card and its holder, from [r]'s view.
({Card card, int seat}) _start(RunnerClient r) => BigTwoWireView.read(r.view!).start!;

Future<void> _end(WidgetTester tester, TestServer server, List<RoomService> rooms) async {
  for (final r in rooms) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
}

/// A room of two people (Ann the host and Ben, seated) and a spectator
/// (Cy), all at Normal speed in [language], dealt its first deal of
/// [seats] seats... with two people that is a two-player deal.
Future<({TestServer server, RoomService ann, RoomService ben, RoomService cy})> _peopleRoom(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.english,
  int seed = 3,
}) async {
  final server = TestServer(seed: seed, games: {'big_two': bigTwoOnline!});
  final ann = _rooms('Ann', language: language), ben = _rooms('Ben', language: language);
  final cy = _rooms('Cy', language: language);
  final own = server.client();
  await server.open(tester, own, const CreateRoom(name: 'Ann'));
  ann.enter(own);
  final benClient = server.client(), cyClient = server.client();
  await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
  ben.enter(benClient);
  await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
  cy.enter(cyClient);
  own.send(ChooseGame(game: 'big_two', setup: {'seats': 2, 'turnLimit': 0, 'rules': bigTwoOnline!.defaultRules}));
  await server.wait(tester, const Duration(seconds: 1));
  own.send(const TakeSeat(0));
  benClient.send(const TakeSeat(1));
  await server.until(tester, () => own.room!.taken == 2, 'seated');
  own.send(const StartGame());
  await server.until(
    tester,
    () => ann.runner?.view != null && ben.runner?.view != null && cy.runner?.view != null,
    'the deal',
  );
  return (server: server, ann: ann, ben: ben, cy: cy);
}

/// A room of Ben and three bots (Ann, the host, plays the bots from her
/// device without a seat) with Cy watching (the bots' cards hidden), all
/// at Normal speed in [language], dealt a deal a bot starts, with Ben's
/// screen open as it comes (Cy's with [spectator]). Null when no seed
/// under 12 gives one.
Future<({TestServer server, RoomService ann, RoomService ben, RoomService cy})?> _botRoom(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.english,
  bool spectator = false,
}) async {
  for (var seed = 1; seed < 12; seed++) {
    final server = TestServer(seed: seed, games: {'big_two': bigTwoOnline!});
    final ann = _rooms('Ann', language: language), ben = _rooms('Ben', language: language);
    final cy = _rooms('Cy', language: language);
    final own = server.client(), benClient = server.client(), cyClient = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
    cy.enter(cyClient);
    own.send(ChooseGame(game: 'big_two', setup: {'seats': 4, 'turnLimit': 0, 'rules': bigTwoOnline!.defaultRules}));
    await server.wait(tester, const Duration(seconds: 1));
    benClient.send(const TakeSeat(0));
    for (var b = 0; b < 3; b++) {
      own.send(const AddBot(style: 'easy'));
    }
    await server.until(tester, () => own.room!.taken == 4, 'seated');
    // The app is open as the deal comes, so its step starts with it.
    await _open(tester, spectator ? cy : ben);
    own.send(const StartGame());
    await server.until(tester, () => cy.runner?.view != null && ben.runner?.view != null, 'the deal');
    if (_start(cy.runner!).seat != 0) return (server: server, ann: ann, ben: ben, cy: cy);
    await _end(tester, server, [ann, ben, cy]);
  }
  return null;
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('two people: on each device the step calls low cards up to the starting card and names its holder; '
      "the starter's Play waits for its end; then the middle says who starts, on the spectator's too", (tester) async {
    addTearDown(tester.view.reset);
    final (:server, :ann, :ben, :cy) = await _peopleRoom(tester);
    final start = _start(cy.runner!);
    final starter = start.seat == 0 ? ann : ben, other = start.seat == 0 ? ben : ann;
    final starterName = start.seat == 0 ? 'Ann' : 'Ben';
    final label = start.card.label;

    // The starter: the step plays as the screen opens, and Play waits.
    await _open(tester, starter);
    expect(_step, findsOneWidget);
    await tester.tap(find.descendant(of: _hand, matching: find.byKey(ValueKey('${bigTwoFace(start.card)}#1'))));
    await tester.pump(const Duration(milliseconds: 1000));
    final play = find.byKey(const ValueKey('play'));
    expect(tester.widget<ButtonStyleButton>(play).onPressed, isNull, reason: 'greyed out while it shows');
    expect(_wordsIn(_words), 'Player starts: $label');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(_step, findsNothing);
    expect(_wordsIn(_note), 'Player starts: $label');
    expect(tester.widget<ButtonStyleButton>(play).onPressed, isNotNull, reason: 'the single starting card');

    // The other player and the spectator see it too, by the starter's name.
    for (final rooms in [other, cy]) {
      await _open(tester, rooms);
      expect(_step, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2100));
      expect(_wordsIn(_note), '$starterName starts: $label');
    }

    // The starter plays: the note goes, everywhere.
    await _open(tester, starter);
    // The screen's way in is over.
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<ButtonStyleButton>(play).onPressed, isNotNull, reason: 'still picked');
    await tester.ensureVisible(play);
    await tester.pump();
    await tester.tap(play);
    await tester.pump();
    await server.until(tester, () => (cy.runner!.view!['history']! as List).isNotEmpty, 'the first play');
    await _open(tester, cy);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_note, findsNothing);
    expect(_step, findsNothing, reason: 'a deal first seen after a play shows no step');
    await _end(tester, server, [ann, ben, cy]);
  });

  testWidgets('a screen laid out again midway (a phone turned) picks the step up where it is', (tester) async {
    addTearDown(tester.view.reset);
    final (:server, :ann, :ben, :cy) = await _peopleRoom(tester);
    await _open(tester, cy);
    await tester.pump(const Duration(milliseconds: 800));
    double progress() => tester.widget<BigTwoOpeningLayer>(find.byType(BigTwoOpeningLayer)).progress;
    final before = progress();
    expect(before, greaterThan(0.3));
    // Upright: the game screen lays the table out anew.
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump(const Duration(milliseconds: 16));
    expect(progress(), greaterThanOrEqualTo(before), reason: 'not back to its start');
    await tester.pump(const Duration(milliseconds: 1250));
    expect(_note, findsOneWidget, reason: 'over on time');
    await _end(tester, server, [ann, ben, cy]);
  });

  testWidgets("a bot that starts waits for the step: the room asks the host's device for its play only once the "
      'step is over on every screen, then it lands on the pile', (tester) async {
    addTearDown(tester.view.reset);
    final room = await _botRoom(tester);
    if (room == null) fail('no deal where a bot starts');
    final (:server, :ann, :ben, :cy) = room;
    expect(_step, findsOneWidget, reason: "Ben's screen was open as the deal came");
    List<Object?> history() => ben.runner!.view!['history']! as List;
    // The room waits the step's two seconds (and a little) before it asks.
    await server.wait(tester, const Duration(milliseconds: 1900));
    expect(history(), isEmpty, reason: 'nothing is played during the step');
    expect(_pile, findsNothing);
    await server.until(tester, () => history().isNotEmpty, "the bot's play", limit: 20);
    expect(_step, findsNothing, reason: 'the step was over before the play came');
    await server.wait(tester, const Duration(milliseconds: 1000));
    expect(_pile, findsOneWidget, reason: 'played out');
    await _end(tester, server, [ann, ben, cy]);
  });

  testWidgets('the views carry only the step\'s result: who starts and the cards shown, and no undealt card', (
    tester,
  ) async {
    final runner = BigTwoRunner(BigTwoRoomRules.standard, Random(5), seats: 2);
    for (var round = 1; round <= 20; round++) {
      runner.startRound(round, [false, false]);
      final s = runner.state;
      if (s.isOver) continue;
      final step = BigTwoOpening.of(s)!;
      for (final view in [runner.seatView(0), runner.seatView(1), runner.spectatorView(seesBots: true)]) {
        final w = BigTwoWireView.read(view);
        expect(w.start!.seat, step.starter);
        expect(w.rules.codeOf(w.start!.card), step.startCode);
        final text = view.toString();
        for (final card in runner.undealt) {
          expect(text, isNot(contains('"${card.short}"')), reason: 'undealt ${card.short}');
          expect(text, isNot(contains(' ${card.short},')), reason: 'undealt ${card.short}');
        }
      }
    }
  });

  group('screenshots', () {
    for (final language in AppLanguage.values) {
      testWidgets('two people and a spectator, mid-step and after (${language.code})', (tester) async {
        addTearDown(tester.view.reset);
        final (:server, :ann, :ben, :cy) = await _peopleRoom(tester, language: language, seed: 4);
        final strings = BigTwoStrings.forLanguage(language);
        final start = _start(cy.runner!);
        for (final (who, rooms) in [('ann', ann), ('ben', ben), ('cy', cy)]) {
          await _open(tester, rooms);
          await tester.pump(const Duration(milliseconds: 450));
          for (final size in _sizes) {
            tester.view.physicalSize = size;
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.takeException(), isNull, reason: '$who ${shotTag(size, language)}');
            await _shot(tester, 'b2o_order_${who}_mid_${shotTag(size, language)}');
          }
          await tester.pump(const Duration(milliseconds: 2000));
          expect(_note, findsOneWidget);
          expect(
            _wordsIn(_note),
            strings.starts(
              rooms.runner!.you == start.seat ? S.forLanguage(language).you : (start.seat == 0 ? 'Ann' : 'Ben'),
              start.card.label,
            ),
          );
          for (final size in _sizes) {
            tester.view.physicalSize = size;
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.takeException(), isNull, reason: '$who ${shotTag(size, language)}');
            await _shot(tester, 'b2o_order_${who}_result_${shotTag(size, language)}');
          }
        }
        await _end(tester, server, [ann, ben, cy]);
      });

      testWidgets('four seats, a bot starting, the seated player and a spectator (${language.code})', (tester) async {
        addTearDown(tester.view.reset);
        for (final who in ['ben', 'cy']) {
          final room = await _botRoom(tester, language: language, spectator: who == 'cy');
          if (room == null) fail('no deal where a bot starts');
          final (:server, :ann, :ben, :cy) = room;
          // The step a quarter in.
          await tester.pump(const Duration(milliseconds: 400));
          expect(_step, findsOneWidget);
          for (final size in _sizes) {
            tester.view.physicalSize = size;
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.takeException(), isNull, reason: '$who ${shotTag(size, language)}');
            await _shot(tester, 'b2o_order_bot_${who}_mid_${shotTag(size, language)}');
          }
          await tester.pump(const Duration(milliseconds: 2100));
          for (final size in _sizes) {
            tester.view.physicalSize = size;
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.takeException(), isNull, reason: '$who ${shotTag(size, language)}');
            await _shot(tester, 'b2o_order_bot_${who}_after_${shotTag(size, language)}');
          }
          await _end(tester, server, [ann, ben, cy]);
        }
      });
    }
  });
}
