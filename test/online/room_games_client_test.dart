/// The games' online client side: what a seated player and a spectator
/// see on the room's game screen, beyond what each game's own tests check.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart' as b2;
import 'package:pokerfection/src/games/big_two/online/big_two_runner.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_view_codec.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/games/blackjack/online/blackjack_runner.dart';
import 'package:pokerfection/src/games/blackjack/online/blackjack_view_codec.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart' as ddz;
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_runner.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_view_codec.dart';
import 'package:pokerfection/src/games/gomoku/online/gomoku_runner.dart';
import 'package:pokerfection/src/games/gomoku/online/gomoku_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/runner_client.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../kit/shots.dart' show loadShotFonts, shotTheme;
import 'room_app.dart';
import 'room_kit.dart';

RoomService _rooms(String name, {PlaybackSpeed speed = PlaybackSpeed.instant, AppLanguage? language}) => RoomService(
  settings: AppSettings()
    ..nickname = name
    ..speed = speed
    ..language = language ?? AppLanguage.english,
  gameUis: onlineGameUis,
  newJobs: () => Jobs.inline(),
);

Future<void> _pumpApp(WidgetTester tester, RoomService rooms) async {
  await tester.pumpWidget(roomApp(const HomeScreen(), rooms: rooms, theme: shotTheme()));
  await tester.pump();
}

String _status(WidgetTester tester) {
  final f = find.byKey(const ValueKey('game status'));
  return f.evaluate().isEmpty ? '' : tester.widget<Text>(f).data ?? '';
}

Future<void> _leaveAll(WidgetTester tester, TestServer server, List<RoomService> all) async {
  for (final r in all) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
}

String _ddzMove(RunnerClient r) {
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

void main() {
  setUpAll(loadShotFonts);

  testWidgets('Blackjack: the Game tab keeps the round\'s result back until the felt has played the dealer\'s '
      'cards out, as the felt\'s own result does (no spoiler at Normal speed)', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    final server = TestServer(games: {'blackjack': blackjackOnline!});
    final ann = _rooms('Ann', speed: PlaybackSpeed.normal);
    await _pumpApp(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    own.send(ChooseGame(game: 'blackjack', setup: {'seats': 1, 'turnLimit': 0, 'rules': const BlackjackRules().toJson()}));
    await server.wait(tester, const Duration(seconds: 1));
    own.send(const TakeSeat(0));
    await server.until(tester, () => own.room!.taken == 1, 'seated');
    own.send(const StartGame());
    await server.until(tester, () => ann.runner?.state != null, 'the deal');
    ann.watch();
    var checked = 0;
    for (var guard = 0; checked < 3; guard++) {
      expect(guard, lessThan(3000));
      final r = ann.runner!;
      final round = r.round;
      // Ann stands (or turns an offer down) at once.
      if (r.myTurn) {
        final legal = wireLegalMoves(r.view!);
        r.move(legal.firstWhere((m) => m.endsWith(':S') || m.endsWith(':N') || m.endsWith(':K')));
      }
      await server.wait(tester);
      if (r.over != null && r.round == round && find.byKey(const ValueKey('round result')).evaluate().isEmpty) {
        // The felt still plays the round out (its result not shown yet).
        expect(
          _status(tester),
          isNot(r.ui.resultText(tester.element(find.byKey(const ValueKey('game status'))), r)),
          reason: 'the Game tab already says how round $round ended while the felt still deals the dealer\'s cards',
        );
        checked++;
        // Once the felt has played it out, the Game tab tells it too.
        for (var i = 0; i < 100 && find.byKey(const ValueKey('round result')).evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (ann.runner!.round == round) {
          expect(
            _status(tester),
            r.ui.resultText(tester.element(find.byKey(const ValueKey('game status'))), r),
            reason: 'the felt shows the result of round $round, the Game tab still does not',
          );
        }
        // On to the next round.
        await server.until(tester, () => ann.runner!.round > round, 'the next round', limit: 400);
      }
    }
    await _leaveAll(tester, server, [ann]);
  });

  testWidgets('Fight the Landlord: once a deal is over, the screen shows each seat\'s total (the room\'s scores), '
      'as the other games do on their tags, pills or match chip', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    final server = TestServer(games: {'doudizhu': doudizhuOnline!});
    final ann = _rooms('Ann'), ben = _rooms('Ben');
    await _pumpApp(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    final benClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    own.send(ChooseGame(game: 'doudizhu', setup: {'seats': 3, 'turnLimit': 0, 'rules': doudizhuOnline!.defaultRules}));
    await server.wait(tester, const Duration(seconds: 1));
    own.send(const TakeSeat(0));
    benClient.send(const TakeSeat(1));
    own.send(const AddBot(style: 'easy'));
    await server.until(tester, () => own.room!.taken == 3, 'seated');
    own.send(const StartGame());
    await server.until(tester, () => ann.runner?.state != null, 'the deal');
    ann.watch();
    for (var guard = 0; ann.runner!.over == null; guard++) {
      expect(guard, lessThan(3000));
      for (final r in [ann.runner, ben.runner]) {
        if (r != null && r.myTurn) r.move(_ddzMove(r));
      }
      await server.wait(tester);
    }
    await server.wait(tester, const Duration(milliseconds: 500));
    final scores = [for (final s in own.room!.seats) s.score];
    expect(scores.whereType<num>().any((s) => s != 0), isTrue, reason: 'the room scored the deal: $scores');
    // Each nonzero total is on Ann's screen somewhere (table, Game tab).
    final texts = [
      for (final e in find.byType(RichText).evaluate()) (e.widget as RichText).text.toPlainText(),
    ].join(' | ');
    for (final score in scores.whereType<num>().where((s) => s != 0)) {
      // Written "+4", "4", "-4" or "−4".
      final shown = score.round().abs().toString();
      final sign = score < 0 ? '[-−]' : '[+]?';
      expect(
        RegExp('(^|[^0-9])$sign$shown([^0-9]|\$)').hasMatch(texts),
        isTrue,
        reason: 'the total $shown is not on the screen between deals; the screen says: $texts',
      );
    }
    await _leaveAll(tester, server, [ann, ben]);
  });

  testWidgets('Big Two at 512x320 in Spanish: the other players\' names on the felt are not cut to one letter',
      (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    final server = TestServer(games: {'big_two': bigTwoOnline!});
    final ann = _rooms('Ann', language: AppLanguage.spanish), ben = _rooms('Ben');
    await _pumpApp(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    final benClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    own.send(ChooseGame(game: 'big_two', setup: {'seats': 3, 'turnLimit': 0, 'rules': bigTwoOnline!.defaultRules}));
    await server.wait(tester, const Duration(seconds: 1));
    own.send(const TakeSeat(0));
    benClient.send(const TakeSeat(1));
    own.send(const AddBot(style: 'easy'));
    await server.until(tester, () => own.room!.taken == 3, 'seated');
    own.send(const StartGame());
    await server.until(tester, () => ann.runner?.state != null, 'the deal');
    // A few plays, so the face-up card sits beside a badge as in a real deal.
    for (var guard = 0; (ann.runner!.view!['history']! as List).length < 3 || !ann.runner!.myTurn; guard++) {
      expect(guard, lessThan(600));
      for (final r in [ann.runner, ben.runner]) {
        if (r != null && r.myTurn) {
          final legal = bigTwoEngineView(r.view!).legalMoves();
          r.move(bigTwoMove(r.you!, legal.firstWhere((p) => !p.isPass, orElse: () => b2.Play.pass)));
        }
      }
      await server.wait(tester);
    }
    tester.view.physicalSize = const Size(512, 320);
    ann.watch();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final table = find.byKey(const ValueKey('big two online table'));
    for (final name in ['Ben', 'Kai', 'Ann'].where((n) => n != 'Ann')) {
      final texts = find.descendant(of: table, matching: find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith(name[0])));
      final cut = [
        for (final e in texts.evaluate())
          if ((e.renderObject! as RenderParagraph).didExceedMaxLines) (e.widget as RichText).text.toPlainText(),
      ];
      expect(cut, isEmpty, reason: '$name\'s badge is cut');
    }
    await _leaveAll(tester, server, [ann, ben]);
  });

  testWidgets('Blackjack: at the player\'s turn the keys work at once (S stands), as the Game tab says (Keys H S D '
      'P R I N K), without clicking the table first', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    final server = TestServer(games: {'blackjack': blackjackOnline!});
    final ann = _rooms('Ann');
    await _pumpApp(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    own.send(ChooseGame(game: 'blackjack', setup: {'seats': 1, 'turnLimit': 0, 'rules': const BlackjackRules().toJson()}));
    await server.wait(tester, const Duration(seconds: 1));
    own.send(const TakeSeat(0));
    await server.until(tester, () => own.room!.taken == 1, 'seated');
    own.send(const StartGame());
    ann.watch();
    // A turn where Stand is open (no offer first).
    for (var guard = 0; ; guard++) {
      expect(guard, lessThan(2000));
      final r = ann.runner;
      if (r != null && r.myTurn) {
        final legal = wireLegalMoves(r.view!);
        if (legal.any((m) => m.endsWith(':S'))) break;
        r.move(legal.firstWhere((m) => m.endsWith(':N') || m.endsWith(':K'), orElse: () => legal.first));
      }
      await server.wait(tester);
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(ann.runner!.myTurn, isFalse, reason: 'S did not stand: the keys wait for a click in the Game tab');
    await _leaveAll(tester, server, [ann]);
  });

  testWidgets('Gomoku: at the player\'s turn the arrow keys aim and Enter places, as in the solo game, without '
      'clicking the board first', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    final server = TestServer(games: {'gomoku': gomokuOnline!});
    final ann = _rooms('Ann'), ben = _rooms('Ben');
    await _pumpApp(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    final benClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    own.send(ChooseGame(game: 'gomoku', setup: {'seats': 2, 'turnLimit': 0, 'rules': gomokuOnline!.defaultRules}));
    await server.wait(tester, const Duration(seconds: 1));
    own.send(const TakeSeat(0));
    benClient.send(const TakeSeat(1));
    await server.until(tester, () => own.room!.taken == 2, 'seated');
    own.send(const StartGame());
    ann.watch();
    for (var guard = 0; !(ann.runner?.myTurn ?? false); guard++) {
      expect(guard, lessThan(400));
      final b = ben.runner;
      if (b != null && b.myTurn) b.move('h8');
      await server.wait(tester);
    }
    await tester.pump(const Duration(seconds: 1));
    final before = GomokuOnlineView.fromJson(ann.runner!.view!).game.moves.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await server.wait(tester, const Duration(milliseconds: 300));
    expect(GomokuOnlineView.fromJson(ann.runner!.view!).game.moves.length, before + 1, reason: 'no stone placed');
    await _leaveAll(tester, server, [ann, ben]);
  });
}
