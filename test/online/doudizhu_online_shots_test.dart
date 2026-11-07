/// Screenshots of Fight the Landlord in a room: the host's rules on the
/// room's table, the seated host in the auction and in play (cards picked
/// in the hand), the seated guest, a spectator with the host's switch off
/// and on (the coach on), and a deal's end, at a sideways phone, a browser,
/// a PC and an upright phone, in every language. PNGs are written only with
/// `--dart-define=SHOTS=<folder>` (see test/kit/shots.dart); without it the
/// test still lays every screen out and checks that nothing overflows.
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
import 'package:pokerfection/src/ui/games/doudizhu/online/doudizhu_online_ui.dart';
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

/// [name] shot for [rooms]'s app at every size in every language
/// ([prepare] runs after each layout).
Future<void> _everywhere(
  WidgetTester tester,
  RoomService rooms,
  String name, {
  Future<void> Function()? prepare,
  List<Size> sizes = _sizes,
}) async {
  for (final language in AppLanguage.values) {
    rooms.settings.update((s) => s.language = language);
    await _pumpApp(tester, rooms);
    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await _pumps(tester);
      await prepare?.call();
      await _pumps(tester);
      await _shot(tester, '${name}_${shotTag(size, language)}');
      expect(tester.takeException(), isNull, reason: '$name ${shotTag(size, language)}');
    }
  }
  rooms.settings.update((s) => s.language = AppLanguage.english);
}

DdzGame _game(RunnerClient r) => DdzWireView.read(r.view!).replay()!;

List<int> _cardsFor(List<int> hand, Play play) {
  final left = [...hand]..sort();
  return [for (final rank in play.ranks) left.removeAt(left.indexWhere((id) => rankOfId(id) == rank))];
}

/// [r]'s player plays: declining in the auction, else the smallest play.
void _autoPlay(RunnerClient? r) {
  if (r == null || !r.myTurn) return;
  final game = _game(r);
  final legal = game.legalMoves();
  final move = legal.firstWhere((m) => m is DdzPlay, orElse: () => legal.first);
  r.move(ddzOnlineMoveText(r.you!, move, move is DdzPlay ? _cardsFor(game.hands[r.you!], move.play) : const []));
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('Fight the Landlord in the room: the rules, the auction, a seated player, the guest, a spectator with '
      "the switch off and on, a deal's end", (tester) async {
    addTearDown(tester.view.reset);
    final server = TestServer(games: {'doudizhu': doudizhuOnline!});
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
    own.send(ChooseGame(game: 'doudizhu', setup: {'seats': 3, 'turnLimit': 30, 'rules': doudizhuOnline!.defaultRules}));
    await server.wait(tester, const Duration(seconds: 1));

    // The host's rules, opened on the room's table.
    await _everywhere(
      tester,
      ann,
      'ddz_rules_host',
      prepare: () async {
        final rules = find.byKey(const ValueKey('rules'));
        if (rules.evaluate().isEmpty) return;
        if (find.byKey(const ValueKey('ddz rules')).evaluate().isEmpty) {
          await tester.ensureVisible(rules);
          await tester.pump();
          await tester.tap(rules);
          await _pumps(tester);
        }
        await tester.ensureVisible(find.byKey(const ValueKey('kitty shown')));
      },
    );

    // Ann and Ben sit with a bot; Cy watches.
    own.send(const TakeSeat(0));
    benClient.send(const TakeSeat(1));
    own.send(const AddBot(style: 'medium'));
    await server.until(tester, () => own.room!.taken == 3, 'seated');
    own.send(const StartGame());
    await server.until(tester, () => ann.runner?.state != null && cy.runner?.state != null, 'the deal');
    // The auction: Ann opens it in round 1.
    await server.until(tester, () => ann.runner!.myTurn, "Ann's bid");
    await _everywhere(tester, ann, 'ddz_seated_auction', prepare: () async => ann.watch());

    // Ann bids 3: the landlord takes the kitty (shown to all) and leads; she picks a pair.
    ann.runner!.move('0:b3');
    await server.until(tester, () => ann.runner!.myTurn, "Ann's lead");
    final seen = DdzOnlineSeen.of(ann.runner!);
    final game = _game(ann.runner!);
    final pair =
        game.legalMoves().whereType<DdzPlay>().where((m) => m.play.type == PlayType.pair).firstOrNull ??
        game.legalMoves().whereType<DdzPlay>().first;
    cy.runner!.setCoach(true);
    var picked = false;
    await _everywhere(
      tester,
      ann,
      'ddz_seated_play',
      prepare: () async {
        ann.watch();
        await _pumps(tester);
        if (!picked) {
          picked = true;
          for (final id in _cardsFor(game.hands[0], pair.play)) {
            seen.toggle(id);
          }
        }
      },
    );
    await _everywhere(tester, ben, 'ddz_guest', prepare: () async => ben.watch());
    await _everywhere(tester, cy, 'ddz_spectator_switch_off', prepare: () async => cy.watch());

    // A few plays on, then the deal's end: every hand face up, the result.
    while (ann.runner!.over == null) {
      _autoPlay(ann.runner);
      _autoPlay(ben.runner);
      await server.wait(tester);
    }
    await _everywhere(tester, ann, 'ddz_deal_over', prepare: () async => ann.watch());

    // The switch on: from the next deal the bot's hand shows to spectators.
    own.send(const HostSettings(seeBots: true));
    final round = cy.runner!.round;
    for (var guard = 0; !(cy.runner!.round > round && (cy.runner!.view!['moves']! as List).length >= 6); guard++) {
      expect(guard, lessThan(2000));
      _autoPlay(ann.runner);
      _autoPlay(ben.runner);
      await server.wait(tester);
    }
    await server.until(tester, () => ben.runner!.myTurn || ann.runner!.myTurn, "a person's turn");
    await _everywhere(tester, cy, 'ddz_spectator_switch_on', prepare: () async => cy.watch());

    for (final r in [ann, ben, cy]) {
      unawaited(r.leave());
    }
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await server.wait(tester, const Duration(seconds: 6));
  });
}
