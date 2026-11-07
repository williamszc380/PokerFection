/// Fight the Landlord's visible cards in a room: the card dealt face up,
/// which decided who bids first, and the kitty in the landlord's hand once
/// taken (when the rules show it). Every seat and every spectator sees them
/// face up in their holder's seat with the kit's eye, a hidden bot's too;
/// the player's own carries the eye in the fan. The online jobs (the bots
/// the host's device plays, a spectator's coach) see them as the engine's
/// own view does, and never guess them anywhere but their holder.
///
/// Screenshots with `--dart-define=SHOTS=<folder>` (see test/kit/shots.dart):
/// the guest seeing a bot's face-up card, the label under the mouse, the
/// guest's own face-up card, a spectator with the host's switch off, and a
/// bot landlord holding the shown kitty, at a sideways phone, a browser, a
/// PC and an upright phone, in every language. Without it the test still
/// lays every screen out and checks that nothing overflows.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_online_jobs.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_runner.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_view_codec.dart';
import 'package:pokerfection/src/games/doudizhu/sampler.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_cards.dart';
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

Finder _backs(int seat) => find.byKey(ValueKey('backs $seat'));
final _hand = find.byKey(const ValueKey('hand'));

/// The faces drawn with the eye under [of].
List<CardFace?> _marked(WidgetTester tester, Finder of) => [
  for (final card in tester.widgetList<GameCardView>(find.descendant(of: of, matching: find.byType(GameCardView))))
    if (card.visibleToAll && card.faceUp) card.face,
];

/// The marked card drawn in display seat [seat]'s backs.
Finder _markedIn(int seat) => find.descendant(
  of: _backs(seat),
  matching: find.byWidgetPredicate((w) => w is GameCardView && w.visibleToAll && w.faceUp),
);

/// Plays [r]'s seat to act like a room member: legal random moves.
String _pick(DdzGame game, Random random) {
  final legal = game.legalMoves();
  final move = legal[random.nextInt(legal.length)];
  return ddzOnlineMoveText(game.toAct, move, move is DdzPlay ? _cardsFor(game.hands[game.toAct], move.play) : const []);
}

void main() {
  setUpAll(loadShotFonts);

  group('the online jobs', () {
    test("a seat's job view sees the visible cards and the card counter as the engine's own view does, and its "
        'guesses never move them; the bot job plays from it', () {
      final runner = DoudizhuRunner(DdzRules.standard, Random(5));
      final random = Random(9);
      var checked = 0;
      for (var round = 1; round <= 8; round++) {
        runner.startRound(round, [false, true, true]);
        while (!runner.roundOver) {
          final seat = runner.seatToAct!;
          final json = jsonDecode(jsonEncode(runner.seatView(seat))) as Map<String, Object?>;
          final view = ddzOnlineJobView(json), real = runner.game.viewFor(seat);
          expect(view.faceUp, real.faceUp);
          for (var s = 0; s < 3; s++) {
            expect(view.visibleIn(s), real.visibleIn(s), reason: 'round $round, seat $seat sees seat $s');
          }
          expect(view.cardCount.knownInHand, real.cardCount.knownInHand);
          if (checked % 5 == 0) {
            final sampler = DdzSampler(view);
            for (var i = 0; i < 20; i++) {
              final hands = sampler.deal(random);
              for (var s = 0; s < 3; s++) {
                if (s == seat) continue;
                final known = countsOfIds(runner.game.visibleIn(s));
                for (var r = 0; r < Rank.count; r++) {
                  expect(hands[s][r], greaterThanOrEqualTo(known[r]), reason: 'seat $s holds its visible cards');
                }
              }
            }
          }
          if (checked % 40 == 0) {
            final move = const DdzOnlineBotJob().run(
              DdzOnlineBotInput(view: json, level: 'easy', seed: checked),
              JobContext(platform: JobPlatform.test),
            );
            expect(runner.check(seat, move), isNull, reason: 'the bot job\'s move is legal');
          }
          checked++;
          runner.act(seat, _pick(runner.game, random));
        }
      }
      expect(checked, greaterThan(300));
    });
  });

  testWidgets("in a room: a bot's face-up card shows face up with the eye for a guest and a spectator (the host's "
      "switch off), the label under the mouse; the guest's own carries the eye in the fan; a bot landlord's shown "
      'kitty too; nothing overflows anywhere (screenshots)', (tester) async {
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
    own.send(ChooseGame(game: 'doudizhu', setup: {'seats': 3, 'turnLimit': 0, 'rules': doudizhuOnline!.defaultRules}));
    await server.wait(tester, const Duration(seconds: 1));
    own.send(const TakeSeat(0));
    benClient.send(const TakeSeat(1));
    own.send(const AddBot(style: 'easy'));
    await server.until(tester, () => own.room!.taken == 3, 'seated');
    own.send(const StartGame());
    await server.until(tester, () => ann.runner?.state != null && cy.runner?.state != null, 'the deal');
    final benSeat = ben.runner!.you!, annSeat = ann.runner!.you!;
    final botSeat = 3 - benSeat - annSeat;

    /// The deal as the spectators have it (the bot's hand stand-ins).
    DdzGame watched() => DdzWireView.read(cy.runner!.view!).replay()!;

    /// Plays on (the people decline in the auction and play their smallest
    /// play) until [done] holds for the spectators' deal.
    Future<void> playUntil(bool Function(DdzGame game) done, String what) async {
      for (var guard = 0; guard < 4000; guard++) {
        final view = cy.runner?.view;
        final game = view == null ? null : DdzWireView.read(view).replay();
        if (game != null && done(game)) return;
        _autoPlay(ann.runner);
        _autoPlay(ben.runner);
        await server.wait(tester);
      }
      fail('never: $what');
    }

    bool auction(DdzGame g) => g.phase == DdzPhase.bidding;

    /// [rooms]'s table at every size in every language, [check]ed after
    /// each layout; the label shown first when [hover] gives the card to
    /// point at.
    Future<void> everywhere(
      RoomService rooms,
      String name,
      void Function(String tag) check, {
      Finder Function()? hover,
    }) async {
      for (final language in AppLanguage.values) {
        rooms.settings.update((s) => s.language = language);
        await _pumpApp(tester, rooms);
        for (final size in _sizes) {
          final tag = shotTag(size, language);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          await _pumps(tester);
          rooms.watch();
          await _pumps(tester);
          expect(tester.takeException(), isNull, reason: '$name $tag');
          check(tag);
          await _shot(tester, '${name}_$tag');
          if (hover != null) {
            final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
            await mouse.addPointer(location: tester.getCenter(hover()));
            await _pumps(tester);
            expect(find.text(KitStrings.forLanguage(language).visibleToAll), findsOneWidget, reason: '$name $tag');
            await _shot(tester, '${name}_hover_$tag');
            await mouse.removePointer();
            await _pumps(tester);
          }
        }
      }
      rooms.settings.update((s) => s.language = AppLanguage.english);
    }

    // The bot dealt the face-up card, in the auction.
    await playUntil((g) => auction(g) && g.firstBidder == botSeat, "the bot's face-up card");
    final up = watched().faceUp!;
    // For Ben the table turns so he sits at the bottom.
    final botForBen = (botSeat - benSeat) % 3;
    await everywhere(ben, 'online_guest_bot_faceup', (tag) {
      expect(_marked(tester, _backs(botForBen)), [ddzFace(up)], reason: tag);
      expect(_marked(tester, _hand), isEmpty);
    }, hover: () => _markedIn(botForBen));
    // The spectator, the host's switch off: the bot's hand is backs, but
    // the face-up card shows.
    await everywhere(cy, 'online_spectator_bot_faceup', (tag) {
      expect(_marked(tester, _backs(botSeat)), [ddzFace(up)], reason: tag);
    });

    // Ben dealt it: the eye in his own fan.
    await playUntil((g) => auction(g) && g.firstBidder == benSeat, "Ben's face-up card");
    final his = watched().faceUp!;
    await everywhere(ben, 'online_guest_own_faceup', (tag) {
      expect(_marked(tester, _hand), [ddzFace(his)], reason: tag);
      for (final seat in [1, 2]) {
        expect(_marked(tester, _backs(seat)), isEmpty);
      }
    });

    // The bot the landlord holding the face-up card and the shown kitty.
    await playUntil(
      (g) => g.landlord == botSeat && g.visibleIn(botSeat).length >= 3 && g.phase == DdzPhase.playing,
      'a bot landlord',
    );
    final held = watched().visibleIn(botSeat);
    await everywhere(cy, 'online_spectator_landlord_kitty', (tag) {
      expect(_marked(tester, _backs(botSeat)), unorderedEquals([for (final id in held) ddzFace(id)]), reason: tag);
    });

    for (final r in [ann, ben, cy]) {
      unawaited(r.leave());
    }
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await server.wait(tester, const Duration(seconds: 6));
  });
}
