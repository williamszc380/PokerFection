/// Fight the Landlord's who-bids-first step in a room: every deal opens as
/// in the solo game, on every device at its own Animations speed, for the
/// seats and the spectators alike. The cards go round from the stack, the
/// face-up card lands in its holder's seat, then "Ann bids first", and only
/// then do the player's buttons wake. Moves the room sends meanwhile wait
/// for the step. A deal thrown in (everyone passed) opens again. It needs
/// nothing the views don't carry already: the first bidder and the face-up
/// card (the runner test checks the views hold nothing more).
///
/// Screenshots with `--dart-define=SHOTS=<folder>` (see test/kit/shots.dart):
/// a guest and a spectator mid-step (the face-up card landed, the stack
/// still dealing) and at its result, at a sideways phone, a browser, a PC
/// and an upright phone, in every language. Without it the test still lays
/// every screen out and checks that nothing overflows.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_runner.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_opening.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_table.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/games/doudizhu/online/doudizhu_online_ui.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../kit/shots.dart' show loadShotFonts, shotTag, shotTheme, shotsFolder;
import 'room_app.dart';
import 'room_kit.dart';

const _sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

final _boundary = GlobalKey();
final _stack = find.byKey(const ValueKey('deal stack'));
final _words = find.byKey(const ValueKey('first bidder'));

RoomService _rooms(String name, PlaybackSpeed speed) => RoomService(
  settings: AppSettings()
    ..nickname = name
    ..speed = speed,
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

/// The deal the table draws now.
DdzGame _drawn(WidgetTester tester) =>
    tester.widget<LandlordTable>(find.byKey(const ValueKey('ddz online table'))).felt.game;

/// The cards each display seat's badge counts.
List<int?> _badges(WidgetTester tester) => [
  for (var s = 0; s < 3; s++) tester.widget<SeatBadge>(find.byKey(ValueKey('seat $s'))).cardsLeft,
];

void main() {
  setUpAll(loadShotFonts);

  testWidgets('every deal opens with who bids first on every device at its own speed; the buttons wait for it; '
      'moves sent meanwhile show after; a deal thrown in opens again (screenshots)', (tester) async {
    addTearDown(tester.view.reset);
    final server = TestServer(games: {'doudizhu': doudizhuOnline!});
    // The host plays at Instant, the guest and the spectator at Normal.
    final ann = _rooms('Ann', PlaybackSpeed.instant);
    final ben = _rooms('Ben', PlaybackSpeed.normal), cy = _rooms('Cy', PlaybackSpeed.normal);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    final benClient = server.client(), cyClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
    cy.enter(cyClient);
    own.send(ChooseGame(game: 'doudizhu', setup: {'seats': 3, 'turnLimit': 0, 'rules': doudizhuOnline!.defaultRules}));
    await server.wait(tester, const Duration(seconds: 1));
    own.send(const TakeSeat(0));
    benClient.send(const TakeSeat(1));
    own.send(const AddBot(style: 'easy'));
    await server.until(tester, () => own.room!.taken == 3, 'seated');
    await _pumpApp(tester, ben);
    own.send(const StartGame());
    await server.until(tester, () => ben.runner?.state != null && cy.runner?.state != null, 'the deal');
    // The table opens by itself when the game starts.
    await tester.pump();
    final benSeen = DdzOnlineSeen.of(ben.runner!);
    final benSeat = ben.runner!.you!;

    // Ben's device deals: the stack in the middle, cards going out, his
    // buttons greyed out even if he opens the auction.
    expect(benSeen.dealing, isNotNull, reason: 'the step runs on Ben\'s device (Normal)');
    expect(_stack, findsOneWidget);
    final first = benSeen.dealing!.order.firstBidder; // display seat
    final firstHand = (first + benSeat) % 3;
    expect(benSeen.dealing!.game.faceUp == null || benSeen.dealing!.dealt > 0, isTrue);
    final bid = find.byKey(const ValueKey('bid 1'));
    expect(bid, findsOneWidget);
    expect(tester.widget<FilledButton>(bid).onPressed, isNull, reason: 'Ben waits for the deal');
    final counts = _badges(tester);
    expect(counts.every((n) => n! < 17), isTrue, reason: 'the hands are still being dealt: $counts');

    // The host's device plays at Instant: no step there, its bot bids at
    // once if it opens. Ben's table still draws no bid until his step ends.
    await server.wait(tester, const Duration(milliseconds: 900));
    // The face-up card lands (a screen turned while a card is in the air
    // would remount the table's flight layer: see the requests file).
    while (benSeen.flights.flying) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(benSeen.dealing, isNotNull);
    expect(_drawn(tester).history, isEmpty, reason: 'moves wait for the step');
    expect(_words, findsOneWidget, reason: 'the face-up card has landed: its holder named');
    final named = firstHand == benSeat ? 'Player' : ben.runner!.nameOf(firstHand);
    final s = LandlordStrings.forLanguage(AppLanguage.english);
    expect(
      find.descendant(of: _words, matching: find.text(s.firstToBid(named, BiddingStyle.points))),
      findsOneWidget,
      reason: "Ben's own seat is named Player",
    );

    // Mid-step and at the result, at every size and language (the step's
    // time stands still between these pumps).
    Future<void> everywhere(RoomService rooms, String name) async {
      for (final language in AppLanguage.values) {
        rooms.settings.update((x) => x.language = language);
        await _pumpApp(tester, rooms);
        for (final size in _sizes) {
          tester.view.physicalSize = size;
          await tester.pump();
          await tester.pump();
          final tag = shotTag(size, language);
          expect(tester.takeException(), isNull, reason: '$name $tag');
          expect(_words, findsOneWidget, reason: '$name $tag');
          await _shot(tester, '${name}_$tag');
        }
      }
      rooms.settings.update((x) => x.language = AppLanguage.english);
      tester.view.physicalSize = const Size(1280, 800);
      await _pumpApp(tester, rooms);
    }

    await everywhere(ben, 'online_guest_step_dealing');
    expect(_stack, findsOneWidget, reason: 'still dealing');
    // The step's end: every card out, the auction opens on Ben's device.
    await server.wait(tester, LandlordDealClock.total(1) - const Duration(milliseconds: 900) - LandlordDealClock.hold);
    expect(_stack, findsNothing);
    expect(_badges(tester), [17, 17, 17]);
    await everywhere(ben, 'online_guest_step_result');
    await server.wait(tester, const Duration(seconds: 1));
    expect(benSeen.dealing, isNull, reason: 'about two seconds in all');
    expect(
      _drawn(tester).history,
      hasLength(DdzWireView.read(ben.runner!.view!).moves.length),
      reason: 'the moves made meanwhile show now',
    );

    // The spectator's device opens its table now: it is shown how the deal
    // opened too, at its own speed, then where the deal is.
    await _pumpApp(tester, cy);
    cy.watch();
    await tester.pump();
    final cySeen = DdzOnlineSeen.of(cy.runner!);
    if (DdzWireView.read(cy.runner!.view!).lord == null) {
      expect(cySeen.dealing, isNotNull, reason: 'the auction is on: the spectator sees the deal open');
      await server.wait(tester, const Duration(milliseconds: 900));
      while (cySeen.flights.flying) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await everywhere(cy, 'online_spectator_step_dealing');
      await server.wait(tester, const Duration(seconds: 2));
      expect(cySeen.dealing, isNull);
    }

    // Everyone passes: the deal is thrown in, dealt again, and opens again
    // on Ben's device with a new face-up card.
    await _pumpApp(tester, ben);
    ben.watch();
    await tester.pump();
    final redealsBefore = DdzWireView.read(ben.runner!.view!).redeals;
    var opened = false;
    for (var guard = 0; guard < 400 && !opened; guard++) {
      for (final r in [ann.runner, ben.runner]) {
        if (r == null || !r.myTurn) continue;
        final game = DdzWireView.read(r.view!).replay()!;
        if (game.phase != DdzPhase.bidding) continue;
        r.move(ddzOnlineMoveText(r.you!, const DdzBid(0)));
      }
      await server.wait(tester);
      final wire = DdzWireView.read(ben.runner!.view!);
      if (wire.redeals > redealsBefore) {
        expect(benSeen.dealing, isNotNull, reason: 'the new deal opens again');
        expect(_stack, findsOneWidget);
        opened = true;
      } else if (wire.lord != null) {
        break; // The bot took it: no deal thrown in this time.
      }
    }
    // This room's shuffles (its seeded Random) give a deal the bot passes too.
    expect(opened, isTrue, reason: 'everyone passed');
    await server.wait(tester, const Duration(seconds: 3));
    expect(benSeen.dealing, isNull);

    for (final r in [ann, ben, cy]) {
      unawaited(r.leave());
    }
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await server.wait(tester, const Duration(seconds: 6));
  });

  test('a thrown-in deal is shown long enough for its step before the next clock starts', () {
    expect(DoudizhuRunner.redealMs, greaterThanOrEqualTo(LandlordDealClock.total(1).inMilliseconds));
  });
}
