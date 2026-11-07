// The middle of Fight the Landlord's table and the cards on their way to
// it: every turn of the deal goes on one messy pile (the latest on top, the
// one to beat), a tap opens the deal's history, plays fly in from the hand
// or a bot's seat, and the kitty flies to the landlord. The hand fans out
// under the table, never under the panel.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_cards.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_table.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/kit/card_flights.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/table_pile.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'helpers.dart';
import 'states.dart';

final english = LandlordStrings.forLanguage(AppLanguage.english);

/// A Free Play game whose speed the test sets as it goes ([speed]).
class _Timed {
  _Timed(int seed) {
    GameSounds.output = (_) {};
    controller = LandlordController(
      jobs: Jobs.inline(),
      lastGames: LastGames(),
      choice: const LandlordChoice(training: false, levels: [KitLevel.easy, KitLevel.easy]),
      speed: () => speed,
      random: Random(seed),
    );
  }

  late final LandlordController controller;
  var speed = PlaybackSpeed.instant;
}

bool _decision(LandlordController c) =>
    !c.isOver && c.seatToAct == LandlordController.you && c.forcedMove(LandlordController.you) == null;

/// A Free Play game at Instant stopped at the player's first decision where
/// [want] holds (playing like an Easy bot until then), trying seeds.
Future<_Timed> _timedGameAt(WidgetTester tester, bool Function(LandlordController c) want, {int seed = 1}) async {
  for (var s = seed; s < seed + 60; s++) {
    final t = _Timed(s);
    final c = t.controller..newGame();
    for (var guard = 0; guard < 150 && !c.isOver; guard++) {
      await pumpUntil(tester, () => c.isOver || _decision(c));
      if (c.isOver) break;
      if (want(c)) return t;
      c.humanMove(easyMove(c));
    }
    c.dispose();
  }
  throw StateError('no deal got there');
}

/// Pumps frames for [time] (a flight starts on the frame after it is
/// launched, so one long pump would not move it).
Future<void> frames(WidgetTester tester, Duration time) async {
  for (var t = Duration.zero; t < time; t += const Duration(milliseconds: 20)) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Pumps on real-looking time until the player's next decision (or the end).
Future<void> untilDecision(WidgetTester tester, LandlordController c) async {
  for (var i = 0; i < 2000 && !(c.isOver || _decision(c)); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(loadShotFonts);

  test('the pile takes one turn per action: bids as words, plays in reading order with their kind, '
      'a new trick at each lead after two passes', () async {
    final c = testController(seed: 5);
    await c.newGame();
    await playDeal(c);
    final game = c.game;
    final plays = ddzPilePlays(game, english);
    expect(plays, hasLength(game.history.length), reason: 'turn i of the deal is pile play i');
    var trick = 0, passes = 0, played = false;
    for (final (i, a) in game.history.indexed) {
      final turn = plays[i];
      expect(turn.seat, a.seat);
      switch (a.move) {
        case DdzPlay(:final play):
          if (played && passes == 2) trick++;
          played = true;
          passes = 0;
          expect(turn.cards, [for (final id in ddzPlayOrder(a.cardIds, play)) ddzFace(id)]);
          expect(turn.label, english.kind(play.type));
        case DdzPass():
          passes++;
          expect(turn.pass, isTrue);
          expect(turn.hasCards, isFalse);
        default:
          expect(turn.hasCards, isFalse, reason: 'a bid is words');
          expect(turn.label, isNotEmpty);
          expect(turn.heading, english.bidding, reason: 'the bids are not a trick');
      }
      expect(turn.trick, trick, reason: 'turn $i');
    }
    expect(trick, greaterThan(0), reason: 'a whole deal has more than one trick');
    c.dispose();
  });

  testWidgets('one pile in the middle: the plays lie messily, the latest on top; a tap opens every turn', (
    tester,
  ) async {
    final c = await finishedGame(tester, seed: 5);
    await showGame(tester, c, const Size(1280, 800), AppLanguage.english);
    final pile = find.byKey(const ValueKey('table pile'));
    expect(pile, findsOneWidget);
    final onTable = [
      for (final (i, turn) in ddzPilePlays(c.game, english).indexed)
        if (turn.hasCards) i,
    ];
    final shown = onTable.sublist(max(0, onTable.length - 6));
    // Each play lies at its own spot, so the ones under the latest show.
    final spots = {for (final i in shown) tester.getRect(find.byKey(ValueKey('pile play $i'))).center};
    expect(spots, hasLength(shown.length));
    // The latest is drawn last (on top).
    final positioned = tester
        .widgetList<Positioned>(find.descendant(of: pile, matching: find.byType(Positioned)))
        .where((p) => p.key is ValueKey<String> && (p.key! as ValueKey<String>).value.startsWith('pile play'))
        .toList();
    expect(positioned.last.key, ValueKey('pile play ${onTable.last}'));

    await tester.tap(find.byKey(const ValueKey('pile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pile history')), findsOneWidget);
    // The newest turn is in sight, named; the player is "Player".
    final last = c.game.history.length - 1;
    expect(find.byKey(ValueKey('history $last')), findsOneWidget);
    expect(find.text('Player'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('close history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pile history')), findsNothing);
    await closeGame(tester, c);
  });

  testWidgets('the history lists the auction too, and every turn from the first', (tester) async {
    final c = await gameAt(tester, DdzPhase.playing, training: false, seed: 3);
    await showGame(tester, c, const Size(1280, 800), AppLanguage.english);
    final turns = ddzPilePlays(c.game, english);
    // Before the first card too (the player leads): the middle opens it.
    await tester.tap(find.byKey(const ValueKey('pile')));
    await tester.pumpAndSettle();
    final bid = turns.indexWhere((t) => !t.hasCards && !t.pass);
    final scrollable = find.descendant(of: find.byKey(const ValueKey('pile history')), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.byKey(ValueKey('history $bid')), -40, scrollable: scrollable);
    expect(find.text(turns[bid].label!), findsWidgets);
    // The bids go under "Bidding", never under "Trick 1".
    final history = find.byKey(const ValueKey('pile history'));
    expect(find.descendant(of: history, matching: find.text(english.bidding)), findsOneWidget);
    final first = turns.indexWhere((t) => t.hasCards);
    if (first >= 0) {
      await tester.scrollUntilVisible(find.byKey(ValueKey('history $first')), 40, scrollable: scrollable);
      final trick1 = KitStrings.forLanguage(AppLanguage.english).trick(1);
      expect(find.descendant(of: history, matching: find.text(trick1)), findsOneWidget);
    }
    await closeGame(tester, c);
  });

  testWidgets('a play flies from the hand to its place on the pile, which stays empty until it lands', (tester) async {
    final t = await _timedGameAt(tester, (c) => c.game.phase == DdzPhase.playing && c.game.isLead);
    final c = t.controller;
    t.speed = PlaybackSpeed.normal;
    await showGame(tester, c, const Size(1280, 800), AppLanguage.english);
    final card = ddzSorted(c.game.hands[0]).last;
    c.toggle(card);
    await tester.pump();
    final from = tester.getCenter(find.byKey(ValueKey('${ddzFace(card)}#1')));
    c.playSelection();
    final index = c.game.history.length - 1;
    await tester.pump();
    final flying = find.byKey(CardFlights.flyingKey(TablePile.flightTag(index, 0)));
    expect(flying, findsOneWidget, reason: 'in the air');
    final start = tester.getCenter(flying);
    expect((start - from).distance, lessThan(30), reason: 'it leaves from the hand');
    await frames(tester, const Duration(milliseconds: 200));
    final landing = tester.getCenter(find.byKey(ValueKey('pile play $index')));
    expect((tester.getCenter(flying) - landing).distance, lessThan((start - landing).distance), reason: 'on its way');
    await frames(tester, const Duration(milliseconds: 300));
    expect(flying, findsNothing, reason: 'landed');
    await closeGame(tester, c);
  });

  testWidgets('a bot\'s play flies from its seat; at Instant nothing flies', (tester) async {
    final t = await _timedGameAt(tester, (c) => c.game.phase == DdzPhase.playing);
    final c = t.controller;
    t.speed = PlaybackSpeed.normal;
    await showGame(tester, c, const Size(1280, 800), AppLanguage.english);
    c.humanMove(easyMove(c));
    await tester.pump();
    // Wait for a bot's play (it may pass first).
    int? index;
    for (var i = 0; i < 200 && index == null && !c.isOver; i++) {
      final before = c.game.history.length;
      await tester.pump(const Duration(milliseconds: 50));
      final after = c.game.history;
      if (after.length > before && after.last.seat != 0 && after.last.move is DdzPlay) index = after.length - 1;
      if (_decision(c)) c.humanMove(easyMove(c));
    }
    expect(index, isNotNull, reason: 'a bot played');
    await tester.pump();
    final flying = find.byKey(CardFlights.flyingKey(TablePile.flightTag(index!, 0)));
    expect(flying, findsOneWidget);
    final seat = tester.getCenter(find.byKey(ValueKey('seat ${c.game.history[index].seat}')));
    expect((tester.getCenter(flying) - seat).distance, lessThan(60), reason: 'it grows out of the seat');
    await frames(tester, const Duration(milliseconds: 600));
    expect(flying, findsNothing);

    // Instant: the next plays just appear.
    t.speed = PlaybackSpeed.instant;
    await untilDecision(tester, c);
    if (!c.isOver) {
      c.humanMove(easyMove(c));
      await tester.pump();
      expect(
        find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key! as ValueKey).value}'.startsWith('(flying')),
        findsNothing,
      );
      expect(c.flights.flying, isFalse);
    }
    await closeGame(tester, c);
  });

  testWidgets('bidding 3 takes the kitty: its cards fly into the player\'s hand', (tester) async {
    final t = await _timedGameAt(
      tester,
      (c) => c.game.phase == DdzPhase.bidding && c.game.legalMoves().contains(const DdzBid(3)),
    );
    final c = t.controller;
    t.speed = PlaybackSpeed.normal;
    await showGame(tester, c, const Size(1280, 800), AppLanguage.english);
    c.humanMove(yours(const DdzBid(3)));
    expect(c.game.landlord, 0);
    await tester.pump();
    for (final id in c.game.kitty) {
      expect(find.byKey(CardFlights.flyingKey(HandFan.flightTag(ddzFace(id)))), findsOneWidget, reason: '$id');
    }
    await frames(tester, const Duration(milliseconds: 600));
    expect(c.flights.flying, isFalse);
    expect(
      find.descendant(of: find.byKey(const ValueKey('hand')), matching: find.byType(GameCardView)),
      findsNWidgets(20),
    );
    await closeGame(tester, c);
  });

  testWidgets('a bot that becomes the landlord gets the kitty flown to its seat', (tester) async {
    for (var seed = 1; seed < 60; seed++) {
      final t = _Timed(seed)..speed = PlaybackSpeed.normal;
      final c = t.controller..newGame();
      await showGame(tester, c, const Size(1280, 800), AppLanguage.english);
      // The player never bids.
      for (var i = 0; i < 400 && c.game.landlord == null && !c.isOver; i++) {
        if (_decision(c) && c.game.phase == DdzPhase.bidding) c.humanMove(yours(const DdzBid(0)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      final lord = c.game.landlord;
      if (lord != null && lord != 0) {
        await tester.pump();
        final launched = find.byKey(CardFlights.flyingKey(LandlordTable.lordCardTag(lord, 0))).evaluate().isNotEmpty;
        expect(launched, isTrue, reason: 'seed $seed: the kitty on its way to seat $lord');
        await closeGame(tester, c);
        return;
      }
      await closeGame(tester, c);
    }
    fail('no bot became the landlord');
  });

  testWidgets('20 cards fan out under the table on a sideways phone, clear of the panel', (tester) async {
    final t = await _timedGameAt(
      tester,
      (c) => c.game.phase == DdzPhase.playing && c.game.landlord == 0 && c.game.isLead,
    );
    final c = t.controller;
    expect(c.game.hands[0], hasLength(20));
    await showGame(tester, c, const Size(568, 320), AppLanguage.english);
    expect(tester.takeException(), isNull);
    final area = tester.getRect(find.byKey(const ValueKey('hand area')));
    final panelLeft = tester.getRect(find.byKey(const ValueKey('pass'))).left;
    expect(area.right, lessThanOrEqualTo(panelLeft), reason: 'never under the panel');
    final fan = tester.widget<HandFan>(find.byKey(const ValueKey('hand')));
    expect(fan.fanned, isTrue);
    final cards = find.descendant(of: find.byKey(const ValueKey('hand')), matching: find.byType(GameCardView));
    expect(cards, findsNWidgets(20));
    for (final card in cards.evaluate()) {
      final center = tester.getCenter(find.byWidget(card.widget));
      expect(center.dx, inInclusiveRange(area.left, area.right));
    }
    final ends = [tester.getCenter(cards.first), tester.getCenter(cards.last)];
    expect(ends[1].dx - ends[0].dx, greaterThan(area.width * 0.6), reason: 'spread across the table\'s width');
    await closeGame(tester, c);
  });
}
