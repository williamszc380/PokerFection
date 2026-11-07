/// Big Two's starting card in a room: everyone saw where it went, so it
/// shows face up with the kit's eye in its holder's seat on every device
/// (a seated player's, a spectator's, a hidden bot's seat among its backs)
/// and on its holder's own fan, until it is played. Screenshots with
/// `--dart-define=SHOTS=<folder>` (see test/kit/shots.dart); without it the
/// test still lays every screen out and checks that nothing overflows.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_runner.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_coach_view.dart' show bigTwoFace;
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/runner_client.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../kit/shots.dart' show loadShotFonts, shotTag, shotTheme, shotsFolder;
import 'room_app.dart';
import 'room_kit.dart';

const _sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

final _boundary = GlobalKey();
final _mark = find.byKey(const ValueKey('visible mark'));
final _label = find.byKey(const ValueKey('visible label'));
final _hand = find.byKey(const ValueKey('hand'));
Finder _seat(int seat) => find.byKey(ValueKey('seat $seat'));

/// The face-up card in [within] that carries the eye, showing [card].
Finder _markedCard(Finder within, Card card) => find.descendant(
  of: within,
  matching: find.byWidgetPredicate(
    (w) => w is GameCardView && w.faceUp && w.visibleToAll && w.face == bigTwoFace(card),
  ),
);

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

/// [name] shot of [rooms]'s game screen at every size in every language,
/// with [check] run on each (and nothing overflowing). [hover]: a mouse on
/// the card it finds, the label showing, in a second shot.
Future<void> _everywhere(
  WidgetTester tester,
  RoomService rooms,
  String name, {
  required void Function() check,
  Finder Function()? hover,
}) async {
  for (final language in AppLanguage.values) {
    rooms.settings.update((s) => s.language = language);
    await _pumpApp(tester, rooms);
    for (final size in _sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await _pumps(tester);
      rooms.watch();
      await _pumps(tester);
      check();
      await _shot(tester, '${name}_${shotTag(size, language)}');
      expect(tester.takeException(), isNull, reason: '$name ${shotTag(size, language)}');
      if (hover != null) {
        final rect = tester.getRect(hover().first);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset(rect.left + rect.width * 0.2, rect.center.dy));
        await tester.pump(const Duration(milliseconds: 50));
        expect(_label, findsOneWidget, reason: '$name ${shotTag(size, language)}');
        expect(find.text(KitStrings.forLanguage(language).visibleToAll), findsOneWidget);
        await _shot(tester, '${name}_hover_${shotTag(size, language)}');
        await mouse.removePointer();
        await tester.pump();
      }
    }
  }
  rooms.settings.update((s) => s.language = AppLanguage.english);
}

/// The room's starting card and its holder, from [r]'s view.
({Card card, int seat}) _start(RunnerClient r) => BigTwoWireView.read(r.view!).start!;

void main() {
  setUpAll(loadShotFonts);

  testWidgets(
    'two people: the leader sees the eye on the starting card in their fan, the other player and a spectator see '
    'it face up in the leader\'s seat, the label under the mouse; once played, no eye anywhere',
    (tester) async {
      addTearDown(tester.view.reset);
      final server = TestServer(games: {'big_two': bigTwoOnline!});
      final ann = _rooms('Ann'), ben = _rooms('Ben'), cy = _rooms('Cy');
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      await _pumpApp(tester, ann);
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
      final start = _start(cy.runner!);
      expect(_start(ann.runner!), start);
      expect(_start(ben.runner!), start);
      final leader = start.seat == 0 ? ann : ben, other = start.seat == 0 ? ben : ann;

      await _everywhere(
        tester,
        leader,
        'b2o_vis_leader_hand',
        check: () {
          expect(_markedCard(_hand, start.card), findsOneWidget);
          expect(_mark, findsOneWidget, reason: 'their own seat on the felt shows no card');
        },
        hover: () => _markedCard(_hand, start.card),
      );
      await _everywhere(
        tester,
        other,
        'b2o_vis_other_seat',
        // The leader sits across, seat 1 from the other player's side.
        check: () => expect(_markedCard(_seat(1), start.card), findsOneWidget),
        hover: () => _markedCard(_seat(1), start.card),
      );
      await _everywhere(
        tester,
        cy,
        'b2o_vis_spectator_people',
        // A person's hand is face up for the spectators: marked where it lies.
        check: () => expect(_markedCard(_seat(start.seat), start.card), findsOneWidget),
      );

      // The leader plays (the first play must hold it): no eye anywhere.
      final r = leader.runner!;
      final legal = bigTwoEngineView(r.view!).legalMoves();
      r.move(bigTwoMove(r.you!, legal.firstWhere((p) => !p.isPass)));
      await server.until(tester, () => (cy.runner!.view!['history']! as List).isNotEmpty, 'the first play');
      for (final rooms in [ann, ben, cy]) {
        await _pumpApp(tester, rooms);
        rooms.watch();
        await _pumps(tester);
        expect(_mark, findsNothing);
        expect(BigTwoWireView.read(rooms.runner!.view!).visible, isEmpty);
      }

      for (final r in [ann, ben, cy]) {
        unawaited(r.leave());
      }
      await server.wait(tester, const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await server.wait(tester, const Duration(seconds: 6));
    },
  );

  testWidgets('a spectator with the host\'s switch off sees a bot leader\'s starting card face up among its backs, '
      'with the eye', (tester) async {
    addTearDown(tester.view.reset);
    // The host's device has no app here, so nobody answers the bot's turn
    // and its starting card stays in its hand while the shots are taken.
    for (var seed = 1; seed < 12; seed++) {
      final server = TestServer(seed: seed, games: {'big_two': bigTwoOnline!});
      final cy = _rooms('Cy');
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      await _pumpApp(tester, cy);
      final own = server.client(), benClient = server.client(), cyClient = server.client();
      await server.open(tester, own, const CreateRoom(name: 'Ann'));
      await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
      await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
      cy.enter(cyClient);
      own.send(ChooseGame(game: 'big_two', setup: {'seats': 4, 'turnLimit': 0, 'rules': bigTwoOnline!.defaultRules}));
      await server.wait(tester, const Duration(seconds: 1));
      benClient.send(const TakeSeat(0));
      for (var b = 0; b < 3; b++) {
        own.send(const AddBot(style: 'easy'));
      }
      await server.until(tester, () => own.room!.taken == 4, 'seated');
      own.send(const StartGame());
      await server.until(tester, () => cy.runner?.view != null, 'the deal');
      final start = _start(cy.runner!);
      if (start.seat != 0) {
        await _everywhere(
          tester,
          cy,
          'b2o_vis_spectator_bot',
          check: () {
            expect((cy.runner!.view!['history']! as List), isEmpty, reason: 'the bot has not played yet');
            final seat = _seat(start.seat);
            expect(_markedCard(seat, start.card), findsOneWidget);
            final hand = tester.widget<SeatHand>(find.descendant(of: seat, matching: find.byType(SeatHand)));
            expect(hand.faces, isNull, reason: 'its other cards are backs');
            expect(hand.visibleToAll, [bigTwoFace(start.card)]);
          },
          hover: () => _markedCard(_seat(start.seat), start.card),
        );
      }
      unawaited(cy.leave());
      await server.wait(tester, const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await server.wait(tester, const Duration(seconds: 6));
      if (start.seat != 0) return;
    }
    fail('no deal where a bot leads');
  });
}
