import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/drills.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/game/table_session.dart';
import 'package:pokerfection/src/gto/gto_solutions.dart';
import 'package:pokerfection/src/gto/preflop/preflop_equity.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';
import 'package:pokerfection/src/ui/table_controller.dart';

/// Solves synchronously, with few iterations, so tests stay fast.
GtoSolutions _solutions() => GtoSolutions(
      iterations: 30,
      postflopIterations: 5,
      inBackground: false,
      loadEquity: () async =>
          PreflopEquity.fromBytes(ByteData.sublistView(File('assets/preflop_equity.bin').readAsBytesSync())),
    );

void main() {
  test('drills: the cooldown grows when played right and starts over when wrong; the most overdue (Blunders first) '
      'come first; when full, the best learned go; they survive the trip to the file', () {
    final t0 = DateTime(2026, 1, 1);
    DrillSpot spot(String hand, {DecisionGrade grade = DecisionGrade.mistake, int stack = 10000, DateTime? saved}) =>
        DrillSpot(
          names: const ['You', 'Alice'],
          styles: const [null, BotStyle.gto],
          stacks: [stack, 10000],
          button: 0,
          cards: [parseCards(hand), parseCards('2c 3d')],
          moves: const [],
          grade: grade,
          evLoss: 1,
          saved: saved ?? t0,
        );
    expect([for (var step = 0; step < 7; step++) drillCooldown(step).inMinutes], [
      10,
      60,
      24 * 60,
      3 * 24 * 60,
      7 * 24 * 60,
      (17.5 * 24 * 60).round(),
      (43.75 * 24 * 60).round(),
    ]);

    final list = DrillList();
    final ak = spot('As Kd');
    expect(list.add(ak), isTrue);
    expect(list.due(t0), isEmpty, reason: 'first review in 10 min');
    var now = t0.add(const Duration(minutes: 10));
    expect(list.due(now), [ak]);
    expect(list.review(ak, right: true, now: now), const Duration(hours: 1));
    now = now.add(const Duration(hours: 1));
    expect(list.review(ak, right: true, now: now), const Duration(days: 1));
    expect(list.review(ak, right: false, now: now), const Duration(minutes: 10));
    expect(list.review(ak, right: null, now: now), const Duration(minutes: 10), reason: 'not graded: the same again');
    // The same mistake again (another AKo, same table and moves) starts that spot over.
    list.review(ak, right: true, now: now);
    expect(list.add(spot('Ah Kc', saved: now)), isFalse);
    expect(list.spots.single.step, 0);

    // Most overdue first; due the same minute, Blunders first.
    final second = DrillList([
      spot('Qs Jd', saved: t0.add(const Duration(minutes: 1))),
      spot('7s 7d', saved: t0.add(const Duration(seconds: 20))),
      spot('As Ad', grade: DecisionGrade.blunder, saved: t0.add(const Duration(seconds: 30))),
    ]);
    expect([for (final s in second.due(t0.add(const Duration(hours: 1)))) s.handName], ['AA', '77', 'QJo']);
    expect(second.nextDue(t0), t0.add(const Duration(minutes: 10, seconds: 20)));

    // Full: the spot with the longest cooldown makes room.
    final full = DrillList([for (var i = 0; i < DrillList.capacity; i++) spot('As Kd', stack: 5000 + i)]);
    final learned = full.spots[7];
    full.review(learned, right: true, now: t0);
    full.add(spot('As Kd', stack: 4000));
    expect(full.spots, hasLength(DrillList.capacity));
    expect(full.spots, isNot(contains(learned)));

    final copy = DrillSpot.fromJson(ak.toJson())!;
    expect([copy.key, copy.step, copy.due, copy.grade], [ak.key, ak.step, ak.due, ak.grade]);
    expect(DrillSpot.fromJson({...ak.toJson(), 'cards': ['AsKd', 'AsQd']}), isNull, reason: 'a card twice');
  });

  test('a saved mistake is dealt again exactly, up to its decision, with the same GTO answer, and graded', () async {
    var now = DateTime(2026, 1, 1);
    final drills = Drills(clock: () => now);
    final table = TableController(
      TableConfig.quick(playerCount: 3, stackBb: 20, guessGto: true),
      speed: PlaybackSpeed.instant,
      random: Random(3),
      solutions: _solutions(),
      drills: drills,
    );
    final saved = <({bool again, Duration wait})>[];
    table.savedToDrills.listen(saved.add);
    // Folds whenever it may (with a good hand, a mistake), until one is saved.
    for (var hand = 0; hand < 40 && drills.isEmpty; hand++) {
      await table.startNextHand();
      while (!table.handOver) {
        // GTO's answer comes behind the table: wait for it, to play graded.
        await table.caughtUp();
        final menu = table.heroMenu!;
        final fold = menu.indexWhere((a) => a.kind == SpotActionKind.fold && a.available);
        final choice = fold >= 0 ? fold : menu.indexWhere((a) => a.kind == SpotActionKind.check);
        if (table.heroSpot == null) {
          await table.heroAct(menu[choice].action);
        } else {
          await table.playGraded(choice);
          if (table.heroScore != null) await table.continueHand();
        }
      }
    }
    expect(drills.spots, isNotEmpty, reason: 'no mistake in 40 hands');
    final spot = drills.spots.first;
    final record = table.session.history
        .expand((h) => h.decisions)
        .firstWhere((d) => d.score.grade.index >= DecisionGrade.mistake.index);
    expect(saved.first, (again: false, wait: const Duration(minutes: 10)));
    expect(drills.dueCount, 0);
    table.dispose();

    // 10 minutes later it is due: the same hand at the same decision, solved again from scratch.
    now = now.add(const Duration(minutes: 10));
    final drill = DrillController(drills, speed: PlaybackSpeed.instant, random: Random(4), solutions: _solutions());
    await drill.startNextHand();
    await drill.caughtUp();
    expect(drill.spot, same(spot));
    final hand = drill.session.hand!;
    expect([for (var seat = 0; seat < hand.playerCount; seat++) hand.holeCards(seat)], spot.cards);
    expect(hand.board, spot.board);
    expect(hand.buttonSeat, spot.button);
    expect(hand.toAct, TableSession.heroSeat);
    final answer = drill.heroSpot!;
    expect(answer.handName, record.spot.handName);
    expect(answer.frequencies, record.spot.frequencies);

    // GTO's favourite play is right: back in 1 h.
    final best = [for (var i = 0; i < answer.actions.length; i++) i]
        .reduce((a, b) => answer.frequencies[a] >= answer.frequencies[b] ? a : b);
    await drill.playGraded(best);
    expect(drill.outcome, (wait: const Duration(hours: 1), right: true));
    expect(spot.due, now.add(const Duration(hours: 1)));
    expect(drills.dueCount, 0);
    // Nothing else is due: a random hand comes next, and the hand isn't played on.
    expect(hand.toAct, TableSession.heroSeat);
    await drill.continueHand();
    expect(drill.spot, isNull);
    drill.dispose();
  });
}
