import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_runner.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_cards.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_table.dart';
import 'package:pokerfection/src/ui/games/doudizhu/online/doudizhu_online_ui.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/online/online_game_screen.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_lobby_screen.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/room_widgets.dart' show roomGameKey;
import 'package:pokerfection/src/ui/online/runner_client.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../widget_test.dart' show setScreen;
import 'room_app.dart';
import 'room_kit.dart';

/// Fight the Landlord in a room, on the app's side, through the fake room
/// (a real RoomRegistry on a clock the test moves): the host picks it from
/// Home and its menu's Play, sets its rules in the solo setup's rows, sits
/// on the room's table with a guest and a bot, and plays a whole deal with
/// the solo buttons and the fanned hand while a spectator watches: the two
/// people's hands face up, the bot's face down until the host's switch is
/// on; the spectator's coach off at first, then rating the people's moves
/// (and the bot's once its cards show), "—" while they don't.

final _kit = KitStrings.forLanguage(AppLanguage.english);

RoomService _rooms(String name) => RoomService(
  settings: AppSettings()
    ..nickname = name
    ..speed = PlaybackSpeed.instant,
  gameUis: onlineGameUis,
  newJobs: () => Jobs.inline(),
);

Future<void> _show(WidgetTester tester, RoomService rooms, {Widget home = const HomeScreen()}) async {
  await tester.pumpWidget(roomApp(home, rooms: rooms));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester, TestServer server, [int steps = 8]) async {
  for (var i = 0; i < steps; i++) {
    server.clock.advance(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// The deal as [r]'s device has it (its own hand real, see DdzWireView).
DdzGame _game(RunnerClient r) => DdzWireView.read(r.view!).replay()!;

/// A quick opponent: [r]'s player declines in the auction and plays the
/// smallest legal play (passing when following and nothing beats).
void _autoPlay(RunnerClient? r) {
  if (r == null || !r.myTurn) return;
  final game = _game(r);
  final legal = game.legalMoves();
  final move = legal.firstWhere((m) => m is DdzPlay, orElse: () => legal.first);
  r.move(ddzOnlineMoveText(r.you!, move, move is DdzPlay ? _cardsFor(game.hands[r.you!], move.play) : const []));
}

List<int> _cardsFor(List<int> hand, Play play) {
  final left = [...hand]..sort();
  return [for (final rank in play.ranks) left.removeAt(left.indexWhere((id) => rankOfId(id) == rank))];
}

/// The hand's card [id] (the kit's fan keys a card by its face).
Finder _card(int id) => find.byKey(ValueKey('${ddzFace(id)}#1'));

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed != null;

Future<void> _end(WidgetTester tester, TestServer server, List<RoomService> rooms) async {
  for (final r in rooms) {
    unawaited(r.leave());
  }
  await server.wait(tester, const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await server.wait(tester, const Duration(seconds: 6));
}

void main() {
  testWidgets("Fight the Landlord is registered for rooms on both sides, at the same version: Home doesn't grey it "
      'out in a room any more', (tester) async {
    expect(onlineGameUis['doudizhu'], isA<DoudizhuOnlineUi>());
    expect(doudizhuOnlineUi!.gv, doudizhuOnline!.gv);
    final server = TestServer(games: {'doudizhu': doudizhuOnline!});
    final ann = _rooms('Ann');
    setScreen(tester, const Size(1280, 800));
    await _show(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    await _settle(tester, server);
    expect(own.room!.games['doudizhu'], doudizhuOnline!.gv);
    final info = games.firstWhere((g) => g.id == GameId.fightTheLandlord);
    expect(roomGameKey(info), 'doudizhu');
    expect(find.byKey(const ValueKey('game fightTheLandlord')), findsOneWidget);
    expect(find.byKey(const ValueKey('online soon fightTheLandlord')), findsNothing, reason: 'playable online');
    await _end(tester, server, [ann]);
  });

  testWidgets("a whole game: the host picks Fight the Landlord with its menu's Play (3 seats), sets the rules in the "
      "setup's rows, sits with a guest and a bot; the auction with the bid buttons, then the deal played by picking "
      "cards in the fanned hand (Play greyed until they make a legal play), Pass, and a pass that can't be avoided "
      "playing itself; the spectator sees both people's hands and the bot's backs, the coach off at first and '—' "
      "for the bot; the result and the points; with the host's switch on, the bot's hand shows from the next deal", (
    tester,
  ) async {
    final server = TestServer(games: {'doudizhu': doudizhuOnline!});
    final ann = _rooms('Ann'), ben = _rooms('Ben'), cy = _rooms('Cy');
    setScreen(tester, const Size(1280, 800));
    await _show(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    final benClient = server.client(), cyClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
    cy.enter(cyClient);
    await _settle(tester, server);

    // Home, the game's menu, Play: the room's game, with its 3 seats.
    await tester.tap(find.byKey(const ValueKey('game fightTheLandlord')));
    await _settle(tester, server);
    await tester.tap(find.descendant(of: find.byType(GameMenu), matching: find.byType(FilledButton)).first);
    await server.until(tester, () => own.room!.game?.key == 'doudizhu', 'the game picked');
    await _settle(tester, server);
    expect(find.byType(RoomLobbyScreen), findsOneWidget, reason: "the host is at the room's table");
    expect(own.room!.seats, hasLength(3));
    Map<String, Object?> rules() => (own.room!.game!.setup!['rules']! as Map).cast<String, Object?>();
    expect(rules(), DdzRules.standard.toJson());

    // The rules: the solo setup's rows. The Call & rob preset, the kitty kept hidden, then Standard again.
    await _tap(tester, find.byKey(const ValueKey('rules')));
    await _settle(tester, server);
    expect(find.byKey(const ValueKey('ddz rules')), findsOneWidget);
    await _tap(
      tester,
      find.descendant(of: find.byKey(const ValueKey('ddz rules')), matching: find.text('Call & rob')).first,
    );
    await _settle(tester, server);
    expect(rules()['bidding'], 'callRob');
    expect(ben.client!.room!.game!.setup!['rules'], rules(), reason: "the guests see the host's rules");
    await _tap(tester, find.byKey(const ValueKey('kitty shown')));
    await _settle(tester, server);
    expect(rules()['kittyShown'], isFalse);
    await _tap(tester, find.descendant(of: find.byKey(const ValueKey('ddz rules')), matching: find.text('Standard')));
    await _settle(tester, server);
    expect(rules(), DdzRules.standard.toJson());

    // Seats: the host sits from its empty seat's menu, Ben takes the next, a bot the last.
    await _tap(tester, find.byKey(const ValueKey('table seat 0')));
    await _settle(tester, server, 3);
    await tester.tap(find.byKey(const ValueKey('table sit 0')));
    await _settle(tester, server);
    benClient.send(const TakeSeat(1));
    own.send(const AddBot(style: 'easy'));
    await server.until(tester, () => own.room!.taken == 3, 'three seats taken');
    await _settle(tester, server);
    await _tap(tester, find.byKey(const ValueKey('start')));
    await server.until(
      tester,
      () => ann.runner?.state != null && ben.runner?.state != null && cy.runner?.state != null,
      'the deal',
    );
    await _settle(tester, server);
    expect(find.byType(OnlineGameScreen), findsOneWidget);
    expect(find.byType(LandlordTable), findsOneWidget);
    expect(find.byType(LandlordHand), findsOneWidget);
    expect(cy.runner!.spectating, isTrue);
    expect(ann.runner!.view!['hand'], hasLength(17));
    expect(ann.runner!.view!.containsKey('kitty'), isFalse, reason: 'nobody sees the kitty in the auction');
    // The seated player is "Player" at the bottom.
    expect(find.descendant(of: find.byKey(const ValueKey('seat 0')), matching: find.text('Player')), findsOneWidget);

    // The deal: Ann bids 3 (the landlord) and plays from her hand; Ben and the bot answer.
    var plays = 0, bids = 0;
    var spectatorChecked = false;
    for (var guard = 0; ann.runner!.over == null; guard++) {
      expect(guard, lessThan(600), reason: 'the deal ends');
      _autoPlay(ben.runner);
      await _settle(tester, server, 2);
      final r = ann.runner!;
      final c = cy.runner!;
      if (!spectatorChecked && c.over == null && c.view?['hands'] is Map) {
        // The spectator holds both people's hands, not the bot's (the switch is off).
        expect((c.view!['hands']! as Map).keys.toSet(), {'0', '1'});
        spectatorChecked = true;
      }
      if (!r.myTurn) continue;
      await tester.pump();
      final game = _game(r);
      if (game.phase == DdzPhase.bidding) {
        expect(_enabled(tester, 'bid 0'), isTrue);
        final key = _enabled(tester, 'bid 3') ? 'bid 3' : 'bid 0';
        await tester.tap(find.byKey(ValueKey(key)));
        await _settle(tester, server, 2);
        bids++;
        continue;
      }
      final legal = game.legalMoves();
      final cards = legal.whereType<DdzPlay>().toList();
      if (cards.isEmpty) {
        // Only Pass: "Can't beat", and it plays itself.
        expect(find.textContaining("Can't beat"), findsOneWidget);
        final turn = r.turn!.turnId;
        await _settle(tester, server, 14);
        expect(r.turn?.turnId != turn || r.over != null, isTrue, reason: 'the forced pass played itself');
        continue;
      }
      if (legal.contains(const DdzPass()) && plays.isOdd) {
        expect(_enabled(tester, 'pass'), isTrue);
        await tester.tap(find.byKey(const ValueKey('pass')));
        await _settle(tester, server, 2);
        continue;
      }
      expect(_enabled(tester, 'play'), isFalse, reason: 'greyed out until the cards make a legal play');
      final play = cards.first.play;
      final ids = _cardsFor(game.hands[r.you!], play);
      for (final id in ids) {
        await tester.tap(_card(id));
        await tester.pump();
      }
      expect(_enabled(tester, 'play'), isTrue);
      expect(_enabled(tester, 'clear'), isTrue);
      final before = (r.view!['moves']! as List).length;
      await tester.tap(find.byKey(const ValueKey('play')));
      await _settle(tester, server, 2);
      final moves = ann.runner!.view!['moves']! as List;
      expect(moves.length, greaterThan(before));
      expect(moves[before], [0, DdzPlay(play).encode(), ddzCardCodes(ids)]);
      plays++;
    }
    expect(bids, greaterThan(0));
    expect(plays, greaterThan(0));
    expect(spectatorChecked, isTrue);
    await tester.pump();
    final result = ann.runner!.over!.result;
    final lord = result['landlord']! as int, lordWon = result['winner'] == lord;
    final head = (lord == 0) == lordWon
        ? _kit.youWin
        : (lordWon ? 'Landlord ${ann.runner!.nameOf(lord)} wins' : 'Peasants win');
    expect(find.textContaining(head), findsOneWidget);
    final total = (result['stake']! as int) * (result['multiplier']! as int);
    expect(find.textContaining('×$total'), findsWidgets);
    // The deal's points: on the seats, adding up to nothing.
    final scores = [for (final s in own.room!.seats) s.score ?? 0];
    expect(scores.fold<num>(0, (a, b) => a + b), 0);
    expect(scores.any((s) => s != 0), isTrue);
    // Every hand is shown once the deal is over (to the spectator too).
    expect(cy.runner!.view!['left'], hasLength(3));

    // The spectator: the people's hands face up, the bot's backs; the coach off at first.
    cy.watch();
    await _show(tester, cy, home: const Scaffold(body: Text('home')));
    await server.until(tester, () => cy.runner!.round == 2 && cy.runner!.over == null, 'the next deal', limit: 400);
    cy.watch();
    await _settle(tester, server);
    expect(find.byType(LandlordTable), findsOneWidget);
    expect(find.byType(LandlordHand), findsNothing, reason: 'a spectator has no hand of their own');
    expect(find.byKey(const ValueKey('hand 0')), findsOneWidget, reason: "Ann's hand, at the bottom");
    expect(find.byKey(const ValueKey('hand 1')), findsOneWidget, reason: "Ben's hand");
    expect(find.byKey(const ValueKey('backs 2')), findsOneWidget, reason: "the bot's backs");
    expect(cy.runner!.coachOn, isFalse);
    expect(find.byKey(const ValueKey('coach on')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach chip')));
    await _settle(tester, server);
    expect(cy.runner!.coachOn, isTrue);
    var sawPerson = false, sawBot = false;
    for (var guard = 0; !(sawPerson && sawBot); guard++) {
      expect(guard, lessThan(400), reason: 'a turn of each');
      final turn = cy.runner!.turn;
      if (turn != null && !cy.runner!.coachThinking) {
        await tester.pump();
        if (turn.seat == 2 && cy.runner!.coachHidden) {
          expect(find.byKey(const ValueKey('coach hidden')), findsOneWidget);
          sawBot = true;
        } else if (turn.seat == 1 && cy.runner!.coach != null && ben.runner!.myTurn) {
          expect(find.byKey(const ValueKey('coach list')), findsOneWidget);
          final answer = cy.runner!.coach!;
          final listed = {
            for (final m in _game(ben.runner!).legalMoves())
              if (m is! DdzPlay) ddzOnlineMoveText(1, m),
          };
          expect(answer.listed, listed, reason: 'Pass and the bids are always listed');
          sawPerson = true;
        }
      }
      // Ben waits for the coach before he moves; Ann plays quickly.
      if (!cy.runner!.coachThinking) _autoPlay(ben.runner);
      _autoPlay(ann.runner);
      await _settle(tester, server, 1);
    }

    // The switch: from the next deal the bot's hand shows, and the coach covers it.
    own.send(const HostSettings(seeBots: true));
    final round = cy.runner!.round;
    for (var guard = 0; !(cy.runner!.round > round && cy.runner!.over == null); guard++) {
      expect(guard, lessThan(1200), reason: 'the next deal');
      _autoPlay(ben.runner);
      _autoPlay(ann.runner);
      await _settle(tester, server, 1);
    }
    await tester.pump();
    expect(find.byKey(const ValueKey('hand 2')), findsOneWidget, reason: "the bot's hand, face up");
    expect(find.byKey(const ValueKey('backs 2')), findsNothing);
    var coached = false;
    for (var guard = 0; !coached; guard++) {
      expect(guard, lessThan(400), reason: "the bot's turn coached");
      final turn = cy.runner!.turn;
      if (turn != null && turn.seat == 2 && cy.runner!.coach != null && !cy.runner!.coachThinking) {
        expect(cy.runner!.coachHidden, isFalse);
        await tester.pump();
        expect(find.byKey(const ValueKey('coach list')), findsOneWidget);
        coached = true;
      }
      _autoPlay(ben.runner);
      _autoPlay(ann.runner);
      await _settle(tester, server, 1);
    }
    await _end(tester, server, [ann, ben, cy]);
  });
}
