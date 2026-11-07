/// The four games' online screens at the smallest sideways phone
/// (512x320, the room's table beside the docked panel) and the others the
/// rooms promise, for the seated host, a seated guest and a spectator with
/// the coach on, in every language: nothing may overflow. PNGs only with
/// `--dart-define=SHOTS=<folder>`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart' as b2;
import 'package:pokerfection/src/games/big_two/online/big_two_runner.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_view_codec.dart';
import 'package:pokerfection/src/games/blackjack/online/blackjack_runner.dart';
import 'package:pokerfection/src/games/blackjack/online/blackjack_view_codec.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart' as ddz;
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_runner.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_view_codec.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/games/gomoku/online/gomoku_runner.dart';
import 'package:pokerfection/src/games/gomoku/online/gomoku_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/runner_client.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../kit/shots.dart' show loadShotFonts, shotTag, shotTheme, shotsFolder;
import 'room_app.dart';
import 'room_kit.dart';

const _sizes = [Size(512, 320), Size(568, 320), Size(390, 844)];

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

Future<List<String>> _everywhere(WidgetTester tester, RoomService rooms, String name, [List<Size> sizes = _sizes]) async {
  final problems = <String>[];
  for (final language in AppLanguage.values) {
    rooms.settings.update((s) => s.language = language);
    await _pumpApp(tester, rooms);
    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await _pumps(tester);
      rooms.watch();
      await _pumps(tester);
      await _shot(tester, '${name}_${shotTag(size, language)}');
      final e = tester.takeException();
      if (e != null) problems.add('$name ${shotTag(size, language)}: ${e.toString().split('\n').first}');
    }
  }
  rooms.settings.update((s) => s.language = AppLanguage.english);
  return problems;
}

String? _gomokuMove(RunnerClient r) {
  final view = GomokuOnlineView.fromJson(r.view!);
  final size = view.game.rules.size;
  final c = size ~/ 2;
  for (var d = 0; d < size; d++) {
    for (var x = c - d; x <= c + d; x++) {
      for (var y = c - d; y <= c + d; y++) {
        if (x < 0 || y < 0 || x >= size || y >= size) continue;
        final m = GomokuMove(x, y);
        if (view.game.isLegal(m)) return m.notation;
      }
    }
  }
  return GomokuMove.pass.notation;
}

String? _bigTwoMove(RunnerClient r) {
  final legal = bigTwoEngineView(r.view!).legalMoves();
  return bigTwoMove(r.you!, legal.firstWhere((p) => !p.isPass, orElse: () => b2.Play.pass));
}

String? _ddzMove(RunnerClient r) {
  final game = DdzWireView.read(r.view!).replay()!;
  final legal = game.legalMoves();
  final move = legal.firstWhere((m) => m is ddz.DdzPlay, orElse: () => legal.first);
  List<int> cards = const [];
  if (move is ddz.DdzPlay) {
    final left = [...game.hands[r.you!]]..sort();
    cards = [for (final rank in move.play.ranks) left.removeAt(left.indexWhere((id) => ddz.rankOfId(id) == rank))];
  }
  return ddzOnlineMoveText(r.you!, move, cards);
}

String? _blackjackMove(RunnerClient r) {
  final legal = wireLegalMoves(r.view!);
  if (legal.isEmpty) return null;
  return legal.firstWhere((m) => m.endsWith(':H') && legal.length > 3, orElse: () => legal.firstWhere(
    (m) => m.endsWith(':S') || m.endsWith(':N') || m.endsWith(':K'),
    orElse: () => legal.first,
  ));
}

void _auto(RunnerClient? r, String? Function(RunnerClient) pick) {
  if (r == null || !r.myTurn) return;
  final m = pick(r);
  if (m != null) r.move(m);
}

Future<void> _game(
  WidgetTester tester, {
  required String key,
  required OnlineGame online,
  required int seats,
  required bool bot,
  int bots = 1,
  List<Size> sizes = _sizes,
  String tag = '',
  required String? Function(RunnerClient) pick,
}) async {
  addTearDown(tester.view.reset);
  final server = TestServer(games: {key: online});
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
  own.send(ChooseGame(game: key, setup: {'seats': seats, 'turnLimit': 0, 'rules': online.defaultRules}));
  await server.wait(tester, const Duration(seconds: 1));
  own.send(const TakeSeat(0));
  benClient.send(const TakeSeat(1));
  if (bot) {
    for (var b = 0; b < bots; b++) {
      own.send(const AddBot(style: 'easy'));
    }
  }
  await server.until(tester, () => own.room!.taken == seats, 'seated');
  own.send(const StartGame());
  await server.until(tester, () => ann.runner?.state != null && cy.runner?.state != null, 'the deal');
  for (var guard = 0; guard < 12; guard++) {
    _auto(ann.runner, pick);
    _auto(ben.runner, pick);
    await server.wait(tester, const Duration(milliseconds: 800));
  }
  for (var guard = 0; !(ann.runner!.myTurn || ann.runner!.over != null); guard++) {
    expect(guard, lessThan(400), reason: 'Ann to act');
    _auto(ben.runner, pick);
    await server.wait(tester);
  }
  cy.runner!.setCoach(true);
  final problems = [
    ...await _everywhere(tester, ann, '${key}_review_host$tag', sizes),
    ...await _everywhere(tester, ben, '${key}_review_guest$tag', sizes),
    ...await _everywhere(tester, cy, '${key}_review_spectator$tag', sizes),
  ];
  for (final r in [ann, ben, cy]) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
  expect(problems, isEmpty);
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('Gomoku fits at 512x320, 568x320 and 390x844', (tester) async {
    await _game(tester, key: 'gomoku', online: gomokuOnline!, seats: 2, bot: false, pick: _gomokuMove);
  });
  testWidgets('Big Two fits at 512x320, 568x320 and 390x844', (tester) async {
    await _game(tester, key: 'big_two', online: bigTwoOnline!, seats: 3, bot: true, pick: _bigTwoMove);
  });
  testWidgets('Fight the Landlord fits at 512x320, 568x320 and 390x844', (tester) async {
    await _game(tester, key: 'doudizhu', online: doudizhuOnline!, seats: 3, bot: true, pick: _ddzMove);
  });
  testWidgets('Blackjack fits at 512x320, 568x320 and 390x844', (tester) async {
    await _game(tester, key: 'blackjack', online: blackjackOnline!, seats: 3, bot: true, pick: _blackjackMove);
  });
  testWidgets('Blackjack with seven seats (Ann, Ben and five bots) at every size', (tester) async {
    await _game(
      tester,
      key: 'blackjack',
      online: blackjackOnline!,
      seats: 7,
      bot: true,
      bots: 5,
      pick: _blackjackMove,
      sizes: const [Size(512, 320), Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)],
      tag: '_7',
    );
  });
}


