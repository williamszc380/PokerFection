/// Blackjack in a room, on the app's side, through the fake room setup: the
/// host (Ann) and a guest (Ben) seated with a bot, a spectator (Cy)
/// watching, first with the host's "Spectators see bots' cards" switch off
/// and then on; the game's felt, buttons, rules and coach at phone,
/// browser and PC sizes in every language. PNGs are written only with
/// `--dart-define=SHOTS=<folder>` (see test/kit/shots.dart); without it the
/// test still lays every screen out and checks that nothing overflows.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart' show BlackjackRules;
import 'package:pokerfection/src/games/blackjack/online/blackjack_runner.dart';
import 'package:pokerfection/src/games/blackjack/online/blackjack_view_codec.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/games/blackjack/online/blackjack_online_table.dart';
import 'package:pokerfection/src/ui/games/blackjack/online/blackjack_online_ui.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/online/online_game_screen.dart';
import 'package:pokerfection/src/ui/online/online_game_uis.dart';
import 'package:pokerfection/src/ui/online/room_scope.dart';
import 'package:pokerfection/src/ui/online/runner_client.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../kit/shots.dart' show loadShotFonts, shotTag, shotTheme, shotsFolder;
import '../widget_test.dart' show setScreen, testSolutions;
import 'room_app.dart';
import 'room_kit.dart';

const _sizes = [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)];

final _boundary = GlobalKey();

RoomService _rooms(String name, {PlaybackSpeed speed = PlaybackSpeed.instant}) => RoomService(
  settings: AppSettings()
    ..nickname = name
    ..speed = speed,
  gameUis: {'blackjack': blackjackOnlineUi!},
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

/// Screens and timers settle (the server's clock stands still).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [name]'s screen at every size in every language ([prepare] after each
/// change), each checked for overflow.
Future<void> _everywhere(
  WidgetTester tester,
  RoomService rooms,
  String name, {
  Future<void> Function()? prepare,
}) async {
  for (final language in AppLanguage.values) {
    rooms.settings.update((s) => s.language = language);
    await _pumpApp(tester, rooms);
    for (final size in _sizes) {
      setScreen(tester, size);
      await _settle(tester);
      await prepare?.call();
      await _settle(tester);
      await _shot(tester, '${name}_${shotTag(size, language)}');
      expect(tester.takeException(), isNull, reason: '$name ${shotTag(size, language)}');
    }
  }
  rooms.settings.update((s) => s.language = AppLanguage.english);
}

/// The button inside the decision keyed [key].
ButtonStyleButton _button(WidgetTester tester, String key) => tester.widget<ButtonStyleButton>(
  find.descendant(of: find.byKey(ValueKey(key)), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
);

/// The card drawn at [tag] on the felt on screen (null: none there).
GameCardView? _cardAt(Object tag) {
  final found = find.byWidgetPredicate((w) => w is GameCardView && w.flightTag == tag).evaluate();
  return found.isEmpty ? null : found.first.widget as GameCardView;
}

/// The face-down hole card on screen never shows its face to a seat; it
/// shows to a spectator only while the host's switch is on.
void _checkHole(RunnerClient c, {required bool spectatorSees}) {
  final view = c.view;
  if (view == null || view['holeDown'] != true) return;
  final hole = _cardAt(onlineDealerTag(c.round, 1));
  if (hole == null) return;
  final sees = spectatorSees && c.spectating;
  expect(hole.faceUp, sees, reason: 'the hole card on ${c.spectating ? 'a spectator' : 'a seat'}\'s screen');
  if (!sees) expect(hole.face, isNull, reason: 'its face isn\'t even known here');
}

/// Ben plays from his device (off screen): Stand, or turning an offer down.
void _benPlays(RunnerClient ben) {
  if (!ben.myTurn) return;
  final legal = wireLegalMoves(ben.view!);
  final move = legal.firstWhere((m) => m.endsWith(':S') || m.endsWith(':N') || m.endsWith(':K'));
  ben.move(move);
}

/// Ann's decision: Hit below 12, else Stand; No insurance; Keep playing.
/// The key of its button.
String _annChoice(RunnerClient ann) {
  final view = ann.view!;
  final legal = wireLegalMoves(view);
  if (legal.any((m) => m.endsWith(':N'))) return 'offer noInsurance';
  if (legal.any((m) => m.endsWith(':K'))) return 'offer keepPlaying';
  final hand = blackjackViewFromWire({...view, 'you': ann.you}).handToPlay!;
  return hand.total.value < 12 && legal.any((m) => m.endsWith(':H')) ? 'action hit' : 'action stand';
}

/// Ann plays her decision with its button on her screen.
Future<void> _annTaps(WidgetTester tester, RunnerClient ann) async {
  final button = find.byKey(ValueKey(_annChoice(ann)));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}

/// Ann plays her decision from her device (her screen not shown).
void _annPlays(RunnerClient ann) {
  if (!ann.myTurn) return;
  final key = _annChoice(ann);
  final letter = switch (key) {
    'offer noInsurance' => 'N',
    'offer keepPlaying' => 'K',
    'action hit' => 'H',
    _ => 'S',
  };
  ann.move(wireLegalMoves(ann.view!).firstWhere((m) => m.endsWith(':$letter')));
}

/// Plays until [rounds] more rounds are over on Ann's device, checking the
/// hole card on the screen shown ([shown], the app pumped) at every step.
Future<void> _play(
  WidgetTester tester,
  TestServer server, {
  required RunnerClient ann,
  required RunnerClient ben,
  required RunnerClient shown,
  required int rounds,
  required bool seeBots,
  void Function()? each,
}) async {
  final target = ann.round + rounds;
  await server.until(
    tester,
    () {
      _benPlays(ben);
      _checkHole(shown, spectatorSees: seeBots);
      each?.call();
      return ann.round >= target && ann.over != null;
    },
    '$rounds rounds',
    limit: 3000,
  );
  await tester.pump();
}

void main() {
  setUpAll(loadShotFonts);

  testWidgets('a whole game of blackjack in a room: Ann (the host) and Ben seated with a bot, Cy watching; the hole '
      'card hidden from every seat, from Cy too until the host\'s switch shows the bots\' cards; Cy\'s coach off at '
      'first, then on; every screen at four sizes in three languages', (tester) async {
    addTearDown(tester.view.reset);
    final server = TestServer(games: {'blackjack': blackjackOnline!});
    final ann = _rooms('Ann'), ben = _rooms('Ben'), cy = _rooms('Cy');
    setScreen(tester, const Size(1280, 800));
    await _pumpApp(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    final benClient = server.client(), cyClient = server.client();
    await server.open(tester, benClient, JoinRoom(code: own.room!.code, name: 'Ben'));
    ben.enter(benClient);
    await server.open(tester, cyClient, JoinRoom(code: own.room!.code, name: 'Cy'));
    cy.enter(cyClient);
    own.send(
      ChooseGame(game: 'blackjack', setup: {'seats': 4, 'turnLimit': 30, 'rules': const BlackjackRules().toJson()}),
    );
    await server.wait(tester, const Duration(seconds: 1));
    expect(own.room!.game?.key, 'blackjack');

    // The room's table before the game, and the host's rules (the solo
    // setup's rows), in every language.
    own.send(const TakeSeat());
    benClient.send(const TakeSeat());
    own.send(const AddBot(style: 'medium'));
    await server.until(tester, () => own.room!.taken == 3, 'seated');
    await _everywhere(tester, ann, 'bj_room_host', prepare: () async => ann.watch());
    for (final language in AppLanguage.values) {
      ann.settings.update((s) => s.language = language);
      await _pumpApp(tester, ann);
      setScreen(tester, const Size(1024, 600));
      ann.watch();
      await _settle(tester);
      // The Rules part, at the end of the Game tab's list.
      final rules = find.byKey(const ValueKey('rules'));
      await tester.scrollUntilVisible(
        rules,
        200,
        scrollable: find
            .descendant(of: find.byKey(const ValueKey('seats panel')), matching: find.byType(Scrollable))
            .first,
      );
      await tester.ensureVisible(rules);
      await tester.pump();
      final form = find.byKey(const ValueKey('blackjack rules'));
      // Opened once, it stays open as the language changes.
      if (form.evaluate().isEmpty) await tester.tap(rules);
      await _settle(tester);
      expect(form, findsOneWidget, reason: "the host's rules, the solo setup's rows");
      await tester.ensureVisible(form);
      await _settle(tester);
      await _shot(tester, 'bj_rules_host_${shotTag(const Size(1024, 600), language)}');
      expect(tester.takeException(), isNull);
    }
    ann.settings.update((s) => s.language = AppLanguage.english);
    // Ben sees the same rows, greyed out: only the host changes the rules.
    await _pumpApp(tester, ben);
    ben.watch();
    await _settle(tester);
    final benRules = find.byKey(const ValueKey('rules'));
    await tester.scrollUntilVisible(
      benRules,
      200,
      scrollable: find
          .descendant(of: find.byKey(const ValueKey('seats panel')), matching: find.byType(Scrollable))
          .first,
    );
    await tester.ensureVisible(benRules);
    await tester.pump();
    await tester.tap(benRules);
    await _settle(tester);
    final benForm = find.byKey(const ValueKey('blackjack rules'));
    expect(benForm, findsOneWidget);
    final switches = find.descendant(of: benForm, matching: find.byType(Switch));
    expect(switches, findsWidgets);
    for (final e in switches.evaluate()) {
      expect((e.widget as Switch).onChanged, isNull, reason: 'greyed out for a guest');
    }
    await tester.ensureVisible(benForm);
    await _settle(tester);
    await _shot(tester, 'bj_rules_guest_${shotTag(const Size(1024, 600), AppLanguage.english)}');
    setScreen(tester, const Size(1280, 800));
    await _pumpApp(tester, ann);

    own.send(const StartGame());
    await server.until(tester, () => ann.runner != null && ben.runner != null && cy.runner != null, 'the game');
    final annGame = ann.runner!, benGame = ben.runner!, cyGame = cy.runner!;
    ann.watch();
    await _settle(tester);
    expect(find.byType(OnlineGameScreen), findsOneWidget);
    expect(find.byType(BlackjackOnlineTable), findsOneWidget);
    expect(annGame.lineup, hasLength(3), reason: 'the round is dealt to the three seats taken');

    // Switch off: a few rounds, Ann playing with the buttons on her screen.
    var cyStates = 0;
    void cyNeverSeesHole() {
      if (cyGame.view case final view?) {
        cyStates++;
        expect(view.containsKey('hole'), isFalse, reason: 'Cy never gets the hole card with the switch off');
      }
    }

    // At Ann's turn on her own screen: her decisions are open, Ben's
    // device has them greyed out.
    await server.until(tester, () {
      _benPlays(benGame);
      return annGame.myTurn;
    }, 'Ann\'s turn');
    await _settle(tester);
    expect(_button(tester, 'action stand').onPressed, isNotNull, reason: "Ann's decisions are open");
    await _everywhere(tester, ann, 'bj_seated_host', prepare: () async => ann.watch());
    await _pumpApp(tester, ann);
    setScreen(tester, const Size(1280, 800));
    ann.watch();
    await _settle(tester);
    await _annTaps(tester, annGame);
    await server.until(tester, () {
      _annPlays(annGame);
      cyNeverSeesHole();
      return benGame.myTurn;
    }, 'Ben\'s turn');
    // Ben's screen at his turn (his buttons open).
    await _everywhere(tester, ben, 'bj_seated_guest', prepare: () async => ben.watch());
    // Cy's screen, switch off: the hole card face down, the coach off.
    await _everywhere(tester, cy, 'bj_spectator', prepare: () async => cy.watch());
    expect(cyGame.coachOn, isFalse, reason: 'the coach starts off');
    expect(find.byKey(const ValueKey('coach on')), findsOneWidget);
    _checkHole(cyGame, spectatorSees: false);

    // Ann's screen again; a few rounds played through.
    setScreen(tester, const Size(1280, 800));
    await _pumpApp(tester, ann);
    ann.watch();
    await _settle(tester);
    for (var r = 0; r < 4; r++) {
      await _play(
        tester,
        server,
        ann: annGame,
        ben: benGame,
        shown: annGame,
        rounds: 1,
        seeBots: false,
        each: () {
          cyNeverSeesHole();
          _annPlays(annGame);
        },
      );
    }
    expect(cyStates, greaterThan(3));
    // A round over on Ann's screen: the result line, everyone's results on the felt.
    expect(find.byKey(const ValueKey('game status')), findsOneWidget);
    await _shot(tester, 'bj_result_host_en_1280x800');
    final scores = [for (var s = 0; s < 3; s++) annGame.seatInfo(s)?.score];
    expect(scores.every((s) => s != null), isTrue, reason: 'every seat has a score');

    // The switch on: from the next deal Cy sees the hole card face up.
    own.send(const HostSettings(seeBots: true));
    await server.until(
      tester,
      () {
        _benPlays(benGame);
        _annPlays(annGame);
        return cyGame.view?['hole'] != null;
      },
      'Cy sees the hole card',
      limit: 3000,
    );
    // Cy's screen with it face up, and the coach turned on: the seat to
    // act's decisions, every legal one listed (the bots' too: their cards
    // are face up anyway).
    await _pumpApp(tester, cy);
    cy.watch();
    await _settle(tester);
    _checkHole(cyGame, spectatorSees: true);
    expect(_cardAt(onlineDealerTag(cyGame.round, 1))?.faceUp, isTrue);
    await tester.tap(find.byKey(const ValueKey('coach on')));
    await _settle(tester);
    expect(cyGame.coachOn, isTrue);
    // Until Ben's turn (he waits there for the screenshots), the coach
    // answered for him, the hole card face up on Cy's screen.
    await server.until(
      tester,
      () {
        _annPlays(annGame);
        if (benGame.myTurn && cyGame.view?['hole'] == null) _benPlays(benGame);
        return benGame.myTurn && cyGame.view?['hole'] != null && cyGame.coach != null && !cyGame.coachThinking;
      },
      "the coach's answer at Ben's turn",
      limit: 3000,
    );
    await _settle(tester);
    expect(find.byKey(const ValueKey('coach list')), findsOneWidget);
    expect(cyGame.coach!.lines.map((l) => l.move), containsAll(wireLegalMoves(cyGame.seatViewOrSpectators)));
    await _everywhere(tester, cy, 'bj_spectator_switch_coach', prepare: () async => cy.watch());
    // The seats still never see it.
    expect(annGame.view?.containsKey('hole'), isFalse);
    expect(benGame.view?.containsKey('hole'), isFalse);

    // End game: the room goes back to its table, scores and all.
    own.send(const EndGame());
    await server.until(tester, () => annGame.gameOver, 'the game\'s end', limit: 3000);
    for (final r in [ann, ben, cy]) {
      unawaited(r.leave());
    }
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await server.wait(tester, const Duration(seconds: 6));
  });

  testWidgets('at the Normal speed the deal flies in card by card from the shoe and the buttons wait for it, as in '
      'the solo game', (tester) async {
    addTearDown(tester.view.reset);
    final server = TestServer(games: {'blackjack': blackjackOnline!});
    final ann = _rooms('Ann', speed: PlaybackSpeed.normal);
    setScreen(tester, const Size(1280, 800));
    await _pumpApp(tester, ann);
    final own = server.client();
    await server.open(tester, own, const CreateRoom(name: 'Ann'));
    ann.enter(own);
    own.send(ChooseGame(game: 'blackjack', setup: {'seats': 2, 'rules': const BlackjackRules().toJson()}));
    own.send(const TakeSeat());
    own.send(const AddBot(style: 'easy'));
    await server.until(tester, () => own.room!.taken == 2, 'seated');
    own.send(const StartGame());
    await server.until(tester, () => ann.runner != null, 'the game');
    final game = ann.runner!;
    ann.watch();
    await _settle(tester);
    // Round 1 was shown as it came (the first view seen); the next deal
    // plays out.
    await server.until(
      tester,
      () {
        if (game.myTurn) {
          final legal = wireLegalMoves(game.view!);
          game.move(legal.firstWhere((m) => m.endsWith(':S') || m.endsWith(':N') || m.endsWith(':K')));
        }
        return game.round >= 2;
      },
      'round 2',
      limit: 3000,
    );
    await tester.pump();
    final round = game.round;
    final dealt = [
      for (var s = 0; s < 2; s++)
        for (var i = 0; i < 2; i++) onlineHandTag(round, s, 0, i),
    ];
    final first = [for (final tag in dealt) _cardAt(tag) != null];
    expect(first.where((shown) => shown).length, lessThan(4), reason: 'the cards come one by one');
    if (game.myTurn && find.byKey(const ValueKey('action stand')).evaluate().isNotEmpty) {
      expect(_button(tester, 'action stand').onPressed, isNull, reason: 'the buttons wait for the deal');
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect([for (final tag in dealt) _cardAt(tag) != null], everyElement(isTrue), reason: 'all landed');
    for (final r in [ann]) {
      unawaited(r.leave());
    }
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await server.wait(tester, const Duration(seconds: 6));
  });

  testWidgets('in a room Home no longer greys Blackjack out: it is in the app\'s registry at the version the room '
      'runs, so its tile opens', (tester) async {
    expect(onlineGameUis['blackjack'], same(blackjackOnlineUi));
    final server = TestServer(games: {'blackjack': blackjackOnline!});
    setScreen(tester, const Size(1280, 800));
    final settings = AppSettings()
      ..nickname = 'Ben'
      ..speed = PlaybackSpeed.instant;
    final rooms = RoomService(settings: settings, solutions: testSolutions());
    await tester.pumpWidget(PokerFectionApp(settings: settings, rooms: rooms, newJobs: () => Jobs.inline()));
    await tester.pump();
    final host = server.client();
    await server.open(tester, host, const CreateRoom(name: 'Ann'));
    final client = server.client();
    await server.open(tester, client, JoinRoom(code: host.room!.code, name: 'Ben'));
    rooms.enter(client);
    await server.wait(tester, const Duration(milliseconds: 800));
    expect(rooms.stage, RoomStage.open);
    bool opens(GameId id) =>
        tester
            .widget<InkWell>(
              find.descendant(of: find.byKey(ValueKey('game ${id.name}')), matching: find.byType(InkWell)),
            )
            .onTap !=
        null;
    expect(opens(GameId.blackjack), isTrue);
    expect(find.byKey(const ValueKey('online soon blackjack')), findsNothing);
    unawaited(rooms.leave());
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await server.wait(tester, const Duration(seconds: 6));
  });
}

extension on RunnerClient {
  /// The acting seat's view as this device has it (a spectator's rebuilt).
  Map<String, Object?> get seatViewOrSpectators {
    final t = turn;
    return t == null ? view! : blackjackSeatViewFrom(view!, t.seat)!;
  }
}
