// The Big Two controller: deals against bots through the kit's jobs,
// grades in Training, saves the record after every move, and keeps the
// screen's toggles from deal to deal and game to game.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;
import 'package:pokerfection/src/kit/game_keys.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/hand_order.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_table.dart' show BigTwoTableFacts;
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/fakes.dart';
import 'big_two_test_util.dart' show seededGame;

/// A store that remembers every record it was asked to save.
class RecordingStore extends LastGames {
  final saved = <GameRecord>[];

  @override
  void save(GameRecord record) {
    saved.add(record);
    super.save(record);
  }
}

/// The controller with its sounds kept in a list.
class TestBigTwo extends BigTwoController {
  TestBigTwo({required super.setup, required super.jobs, LastGames? lastGames})
    : super(lastGames: lastGames ?? LastGames(), speed: () => PlaybackSpeed.instant);

  final sounds = <SoundEffect>[];

  @override
  void playSound(SoundEffect effect) => sounds.add(effect);
}

BigTwoSetup setupOf({
  BigTwoRules? rules,
  bool training = true,
  KitLevel level = KitLevel.easy,
  Map<String, Object?> toggles = const {},
}) => BigTwoSetup(rules: rules ?? BigTwoRules.standard(), level: level, training: training, toggles: toggles);

/// Whether the player has more than one legal move (else there is no
/// coach answer and no grade).
bool hasChoice(BigTwoController game) => game.state.legalMoves().length > 1;

/// The player's move: the coach's pick when there is one, else the first legal move.
String pickFor(BigTwoController game) => game.coach?.pick ?? bigTwoMoveText(0, game.state.legalMoves().first);

/// Plays the deal to its end, the player choosing with [choose].
Future<void> playDeal(BigTwoController game, {String Function(BigTwoController game) choose = pickFor}) async {
  for (var guard = 0; guard < 400 && !game.isOver; guard++) {
    await settle();
    if (game.myTurn) game.humanMove(choose(game));
  }
  await settle();
  expect(game.isOver, isTrue, reason: 'the deal ends');
}

void main() {
  test('a whole deal against three bots ends, with the result in the record and Next deal offered', () async {
    final game = TestBigTwo(setup: setupOf(), jobs: Jobs.inline());
    await game.newGame();
    await playDeal(game);
    final result = game.state.result;
    expect(game.winners, [result.winner]);
    expect(game.record.result!['scores'], result.scores);
    expect(game.between, isTrue, reason: 'card games deal again');
    expect(game.net, result.scores[0]);
    final replayed = BigTwoRecord.replay(game.record);
    expect(replayed.isOver, isTrue, reason: 'the record replays to the same end');
    expect(replayed.result.scores, result.scores);
    expect(game.sounds.first, SoundEffect.deal);
    expect(game.sounds, containsAll([SoundEffect.cardsDown, SoundEffect.pass]));
    expect(game.sounds.last, game.winners.single == 0 ? SoundEffect.win : SoundEffect.lose);
    game.dispose();
  });

  test('every seat plays: three players and two players deal and finish too', () async {
    for (final players in [3, 2]) {
      final game = TestBigTwo(
        setup: setupOf(rules: BigTwoRules.standard(players: players)),
        jobs: Jobs.inline(),
      );
      await game.newGame();
      expect(game.record.seats, hasLength(players));
      await playDeal(game);
      expect({for (final m in game.record.moves) bigTwoMoveSeat(m)}, hasLength(players), reason: '$players players');
      game.dispose();
    }
  });

  test('in Training every choice the player makes is graded, and only theirs', () async {
    final game = TestBigTwo(setup: setupOf(), jobs: Jobs.inline());
    await game.newGame();
    await playDeal(game);
    final record = game.record;
    for (final (i, move) in record.moves.indexed) {
      final mine = bigTwoMoveSeat(move) == 0;
      final choice = BigTwoRecord.replay(record.upTo(i)).legalMoves().length > 1;
      expect(record.marks[i] != null, mine && choice, reason: 'move $i ($move)');
    }
    expect(record.marks.whereType<Object>(), isNotEmpty);
    expect(
      record.marks.nonNulls.every((m) => m.grade == DecisionGrade.best),
      isTrue,
      reason: 'the player followed the coach every time',
    );
    expect(game.averageScore, 100);
    game.dispose();
  });

  test('a move away from the coach\'s pick is graded against it', () async {
    final game = TestBigTwo(setup: setupOf(), jobs: Jobs.inline());
    await game.newGame();
    // Play the coach's worst-rated move each time.
    await playDeal(game, choose: (g) => g.coach?.lines.last.move ?? pickFor(g));
    final marks = game.record.marks.nonNulls.toList();
    expect(marks, isNotEmpty);
    expect(marks.any((m) => m.grade != DecisionGrade.best), isTrue);
    for (final m in marks) {
      expect(m.best, isNot(isEmpty));
    }
    game.dispose();
  });

  test('a move with no choice (the only legal one, such as a forced pass) is not graded, and asks no coach', () async {
    final backend = ManualBackend(kitJobs);
    final game = TestBigTwo(setup: setupOf(), jobs: Jobs.using(backend));
    final forced = <int>{};
    // Seen as each turn begins (a forced pass plays itself soon after).
    game.addListener(() {
      if (!game.myTurn || hasChoice(game)) return;
      expect(game.coachJobs, isEmpty, reason: 'move ${game.record.moves.length}: nothing to ask the coach');
      expect(game.coach, isNull);
      forced.add(game.record.moves.length);
    });
    await game.newGame();
    for (var guard = 0; guard < 600 && !game.isOver; guard++) {
      await settle();
      for (final job in backend.running) {
        backend.answer(job);
      }
      await settle();
      if (!game.myTurn) continue;
      if (game.coach != null || !hasChoice(game)) game.humanMove(pickFor(game));
    }
    expect(game.isOver, isTrue);
    expect(forced, isNotEmpty, reason: 'this deal has forced passes');
    for (final i in forced) {
      expect(game.record.marks[i], isNull, reason: 'forced move $i');
    }
    expect(game.record.marks.nonNulls, isNotEmpty, reason: 'the real choices are graded');
    game.dispose();
  });

  test("a pass the player can't avoid plays itself, saying Can't beat meanwhile, as in Fight the Landlord; "
      'a card never plays itself', () async {
    var forcedPasses = 0, lone = 0;
    for (var seed = 1; seed < 40 && (forcedPasses == 0 || lone == 0); seed++) {
      final played = <int, String>{};
      final game = TestBigTwo(setup: setupOf(training: false), jobs: Jobs.inline());
      game.addListener(() {
        if (!game.myTurn) return;
        if (game.forcedMove(0) case final move?) {
          expect(game.cantBeat, isTrue, reason: 'the headline says so while it waits to play itself');
          played[game.record.moves.length] = move;
        }
      });
      await game.newGame();
      for (var guard = 0; guard < 600 && !game.isOver; guard++) {
        await settle();
        if (!game.myTurn) continue;
        final legal = game.state.legalMoves();
        if (legal.length == 1 && legal.single.isPass) continue; // the kit plays it
        if (legal.length == 1) {
          // The only move, a card: it waits for the player.
          lone++;
          final at = game.record.moves.length;
          await settle();
          expect(game.record.moves.length, at, reason: 'a card is never played without a click');
          expect(game.forcedMove(0), isNull);
        }
        game.humanMove(bigTwoMoveText(0, legal.first));
      }
      expect(game.isOver, isTrue);
      for (final MapEntry(key: i, value: move) in played.entries) {
        expect(move, bigTwoMoveText(0, Play.pass));
        expect(game.record.moves[i], move, reason: 'played by itself');
      }
      forcedPasses += played.length;
      game.dispose();
    }
    expect(forcedPasses, greaterThan(0), reason: 'some deal left the player only Pass');
    expect(lone, greaterThan(0), reason: 'some deal left the player one card to lead');
  });

  test('three players: the face-up card is visible in the seat that took it until it is played', () async {
    var bots = 0, player = 0;
    for (var seed = 1; seed < 30 && (bots == 0 || player == 0); seed++) {
      final game = seededGame(rules: BigTwoRules.standard(players: 3), seed: seed, training: false);
      await game.newGame();
      final state = game.state;
      final card = game.state.rules.cardOf(state.extraCode);
      if (state.extraSeat == 0) {
        player++;
        expect(game.visibleInHand, contains(card), reason: 'seed $seed: the player holds it, marked in their fan');
      } else {
        bots++;
        expect(game.visibleInHand, isNot(contains(card)));
        expect(state.visibleIn(state.extraSeat), contains(card), reason: 'seed $seed');
        for (var guard = 0; guard < 400 && !game.isOver && game.state.visibleIn(state.extraSeat).contains(card); guard++) {
          await settle();
          if (game.myTurn) game.humanMove(pickFor(game));
        }
        if (!game.isOver) {
          expect(game.state.history.any((t) => t.play.cards.contains(card)), isTrue,
              reason: 'seed $seed: it leaves the visible cards only when played');
        }
      }
      game.dispose();
      await settle();
    }
    expect(bots, isPositive, reason: "a deal where a bot took it");
    expect(player, isPositive, reason: "a deal where the player took it");
  });

  test('a four-player deal shows the 3 of diamonds in its holder\'s seat until the first play', () async {
    var bots = 0, player = 0;
    for (var seed = 1; seed < 30 && (bots == 0 || player == 0); seed++) {
      final game = seededGame(seed: seed, training: false);
      await game.newGame();
      final three = Card.parse('3d');
      final holder = game.state.startSeat;
      expect(game.state.visibleIn(holder), [three], reason: 'seed $seed');
      for (var seat = 0; seat < 4; seat++) {
        if (seat != holder) expect(game.state.visibleIn(seat), isEmpty);
      }
      if (holder == 0) {
        player++;
        expect(game.visibleInHand, {three});
      } else {
        bots++;
        expect(game.visibleInHand, isEmpty);
      }
      for (var guard = 0; guard < 400 && !game.isOver && game.state.history.isEmpty; guard++) {
        await settle();
        if (game.myTurn) game.humanMove(pickFor(game));
      }
      expect(game.state.visibleCards, isEmpty, reason: 'seed $seed: the first play had to hold it');
      expect(game.visibleInHand, isEmpty);
      game.dispose();
      await settle();
    }
    expect(bots, isPositive);
    expect(player, isPositive);
  });

  test('Free Play gives no grades and starts no coach jobs', () async {
    final backend = ManualBackend(kitJobs);
    final game = TestBigTwo(setup: setupOf(training: false), jobs: Jobs.using(backend));
    await game.newGame();
    for (var guard = 0; guard < 400 && !game.isOver; guard++) {
      await settle();
      expect(game.coachJobs, isEmpty);
      if (backend.on(JobLane.bot) case final job?) backend.answer(job);
      if (game.myTurn) game.humanMove(pickFor(game));
    }
    expect(game.isOver, isTrue);
    expect(game.record.marks.nonNulls, isEmpty);
    expect(backend.started.where((j) => j.name == 'big_two.coach'), isEmpty);
    expect(game.coach, isNull);
    game.dispose();
  });

  test('New game and Next deal cancel the jobs still running', () async {
    final backend = ManualBackend(kitJobs);
    final game = TestBigTwo(setup: setupOf(), jobs: Jobs.using(backend));
    await game.newGame();
    await settle();
    // A bot's job, or the coach's for the player (unless the deal ended at
    // once on a dealt dragon, or the player's only move is the 3 alone).
    if (!game.isOver && (game.seatToAct != 0 || hasChoice(game))) {
      expect(backend.running, isNotEmpty, reason: 'a bot or the coach is at work at once');
    }
    final before = [...backend.running];
    await game.newGame();
    await settle();
    expect(before.every((j) => j.token.isCancelled), isTrue, reason: 'New game');

    // Play a deal to the end with real answers, then leave a job running into Next deal.
    for (var guard = 0; guard < 600 && !game.isOver; guard++) {
      await settle();
      for (final job in backend.running) {
        backend.answer(job);
      }
      if (game.myTurn && (game.coach != null || !hasChoice(game))) game.humanMove(pickFor(game));
    }
    expect(game.between, isTrue);
    await game.nextRound();
    await settle();
    final running = [...backend.running];
    // A bot's job, or the coach's for the player (unless the deal ended at
    // once on a dealt dragon, or the player's only move is the 3 alone).
    if (!game.isOver && (game.seatToAct != 0 || hasChoice(game))) expect(running, isNotEmpty);
    expect(game.record.moves, isEmpty, reason: 'a fresh deal');
    // A New game now cancels whatever the new deal started.
    await game.newGame();
    expect(running.every((j) => j.token.isCancelled), isTrue, reason: 'New game after Next deal');
    game.dispose();
  });

  test('the record is saved when the deal starts and after every move', () async {
    final store = RecordingStore();
    final game = TestBigTwo(setup: setupOf(training: false), jobs: Jobs.inline(), lastGames: store);
    await game.newGame();
    expect(store.saved.first.moves, isEmpty);
    await playDeal(game);
    final lengths = {for (final r in store.saved) r.moves.length};
    expect(lengths, {
      for (var n = 0; n <= game.record.moves.length; n++) n,
    }, reason: 'a save for every number of moves');
    expect(store.saved.last.result, isNotNull, reason: 'the finished deal is saved with its result');
    await store.flush();
    final loaded = await store.load(GameKeys.bigTwo, version: bigTwoRecordVersion, validate: BigTwoRecord.validate);
    expect(loaded!.moves, game.record.moves);
    game.dispose();
  });

  test(
    'the sort, Card counter and the coach chip survive Next deal and New game, and come back from the record',
    () async {
      final store = LastGames();
      final game = TestBigTwo(setup: setupOf(training: false), jobs: Jobs.inline(), lastGames: store);
      await game.newGame();
      game
        ..sortTap()
        ..reorder(0, 1)
        ..counterOn = true
        ..coachVisible = false;
      expect(game.sortOrder, HandOrder.own);
      await playDeal(game);
      await game.nextRound();
      // The player's own order was for the last hand: a new deal is sorted
      // again, by the sort last chosen.
      expect((game.sortOrder, game.counterOn, game.coachVisible), (HandOrder.suit, true, false), reason: 'Next deal');
      expect(game.record.extra['order'], isNull);
      await game.newGame();
      expect((game.sortOrder, game.counterOn, game.coachVisible), (HandOrder.suit, true, false), reason: 'New game');
      expect(game.record.extra['mode'], 'free');
      game.dispose();
      await store.flush();

      final last = await store.load(GameKeys.bigTwo, version: bigTwoRecordVersion);
      final setup = BigTwoSetup.from(last);
      expect(setup.training, isFalse);
      final next = TestBigTwo(setup: setup, jobs: Jobs.inline());
      await next.newGame();
      expect(
        (next.sortOrder, next.counterOn, next.coachVisible),
        (HandOrder.suit, true, false),
        reason: 'a new screen',
      );
      next.dispose();
    },
  );

  test('the setup is read back from a record: rules, levels, custom seats and mode', () async {
    final rules = BigTwoRules.taiwan(players: 3).copyWith(passLockout: true);
    const custom = [KitLevel.hard, KitLevel.easy];
    final game = TestBigTwo(
      setup: BigTwoSetup(rules: rules, level: KitLevel.medium, seatLevels: custom, training: false),
      jobs: Jobs.inline(),
    );
    await game.newGame();
    expect([for (final s in game.record.seats) s.level], [null, KitLevel.hard, KitLevel.easy]);
    expect([for (final s in game.record.seats) s.name], ['Player', 'Ana', 'Ben']);
    final back = BigTwoSetup.from(game.record);
    expect(back.rules, rules);
    expect(back.seatLevels, custom);
    expect(back.level, KitLevel.medium);
    expect(back.training, isFalse);
    expect(
      BigTwoSetup.from(null).rules,
      BigTwoRules.standard(players: 2),
      reason: 'no record: the standard game for 2',
    );
    game.dispose();
  });

  group('the player\'s controls', () {
    late TestBigTwo game;

    setUp(() async {
      game = TestBigTwo(setup: setupOf(training: false), jobs: Jobs.inline());
      await game.newGame();
      // On to a turn of the player's with something to play (passing
      // when there is nothing).
      for (var guard = 0; guard < 200; guard++) {
        await settle();
        if (!game.myTurn) continue;
        if (game.state.legalMoves().any((p) => !p.isPass)) break;
        game.passTurn();
      }
    });

    tearDown(() => game.dispose());

    test('Play lights up only for picked cards that make a legal move; Clear empties the pick', () {
      expect(game.myTurn, isTrue);
      expect(game.canPlay, isFalse, reason: 'nothing picked');
      expect(game.canClear, isFalse);
      final legal = game.state.legalMoves().firstWhere((p) => !p.isPass);
      for (final card in legal.cards) {
        game.toggle(card);
      }
      expect(game.selectedMove, bigTwoMoveText(0, legal));
      expect(game.canPlay, isTrue);
      expect(game.canClear, isTrue);
      // One card more makes no legal move.
      final extra = game.hand.firstWhere((c) => !legal.cards.contains(c));
      game.toggle(extra);
      expect(game.canPlay, game.state.legalMoves().any((p) => game.rules.classify([...legal.cards, extra]) == p));
      game.clearSelection();
      expect(game.selected, isEmpty);
      expect(game.canPlay, isFalse);
    });

    test('playing the pick moves and empties it; a coach row picks its cards', () {
      final legal = game.state.legalMoves().firstWhere((p) => !p.isPass);
      game.selectMove(bigTwoMoveText(0, legal));
      expect(game.selected, legal.cards.toSet());
      game.playSelected();
      expect(game.record.moves.last, bigTwoMoveText(0, legal));
      expect(game.selected, isEmpty);
      expect(game.sounds.last, SoundEffect.cardsDown);
    });

    test('Sort orders the hand by rank, or by suit as the rules order suits', () {
      final byRank = game.hand;
      expect(game.sortOrder, HandOrder.rank);
      expect(byRank, game.state.handOf(0), reason: 'lowest first');
      game.sortTap();
      expect(game.sortOrder, HandOrder.suit);
      final bySuit = game.hand;
      expect(bySuit.toSet(), byRank.toSet());
      final strengths = [for (final c in bySuit) game.rules.suitStrength(c.suit)];
      expect(strengths, [...strengths]..sort());
      game.sortTap();
      expect(game.sortOrder, HandOrder.rank, reason: 'and back');
      expect(game.hand, byRank, reason: 'and back');
    });

    test("a dragged card takes its new place, and the hand is the player's own order; Sort sorts it again", () {
      final sorted = game.hand;
      game.reorder(0, 3);
      expect(game.hand, [sorted[1], sorted[2], sorted[3], sorted[0], ...sorted.skip(4)]);
      expect(game.sortOrder, HandOrder.own, reason: 'the button now reads Sort');
      expect(game.record.extra['order'], [for (final c in game.hand) c.short], reason: 'saved in the record');
      game.reorder(game.hand.length - 1, 0);
      expect(game.hand.first, sorted.last);
      game.sortTap();
      expect(game.sortOrder, HandOrder.rank, reason: 'back to the sort last chosen');
      expect(game.hand, sorted, reason: 'back to the sort last chosen');
      expect(game.record.extra['order'], isNull);
    });

    test('a pick stays picked while its card moves', () {
      final card = game.hand.first;
      game.toggle(card);
      game.reorder(0, 2);
      expect(game.hand[2], card);
      expect(game.selected, {card});
    });

    test("played cards leave the player's order; the rest keep their places", () {
      // The hand reversed: the player's own order.
      for (var i = 0; i < game.hand.length - 1; i++) {
        game.reorder(game.hand.length - 1, i);
      }
      final own = game.hand;
      expect(own, game.state.handOf(0).reversed.toList());
      final legal = game.state.legalMoves().firstWhere((p) => !p.isPass);
      game.selectMove(bigTwoMoveText(0, legal));
      game.playSelected();
      expect(game.hand, [
        for (final c in own)
          if (!legal.cards.contains(c)) c,
      ]);
      expect(game.sortOrder, HandOrder.own);
    });

    test('the review lays out a card played before the first drag where it lay in the sorted hand', () {
      final dealt = game.hand;
      // A play that keeps the last card, the one dragged below (the deal is
      // random: the first legal play may hold it).
      final legal = game.state.legalMoves().where((p) => !p.isPass && !p.cards.contains(dealt.last)).firstOrNull;
      if (legal == null) return markTestSkipped('every play this deal holds the top card');
      game.selectMove(bigTwoMoveText(0, legal));
      game.playSelected();
      game.reorder(game.hand.length - 1, 0);
      final live = game.hand;
      expect(live.toSet(), dealt.toSet().difference(legal.cards.toSet()), reason: 'the live hand has no played card');
      // The review's first step: the hand as dealt, in the order the deal ended with.
      final first = arrangedHand(
        game.rules,
        BigTwoRecord.replay(game.record.upTo(0)).handOf(0),
        arrangementOf(game.record.extra),
      );
      expect(first, [
        dealt.last,
        for (final c in dealt.take(dealt.length - 1)) c,
      ], reason: 'every card where it lay; only the one dragged has moved');
    });

    test('a hovered coach move is kept for the hand to light, and cleared by a move', () {
      final legal = game.state.legalMoves().firstWhere((p) => !p.isPass);
      game.preview = bigTwoMoveText(0, legal);
      expect(game.preview, bigTwoMoveText(0, legal));
      game.selectMove(bigTwoMoveText(0, legal));
      game.playSelected();
      expect(game.preview, isNull);
    });
  });
}
