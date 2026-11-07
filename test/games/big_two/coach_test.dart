// The endgame solver, the coach, the hand plan, card counting and the bots.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/big_two/inference.dart';

import 'helpers.dart';

void main() {
  final standard = BigTwoRules.standard();
  const fast = CoachBudget(playouts: 400);

  group('endgame solver', () {
    test('leading the unbeatable 2♠ first, then the last card, is a forced win', () {
      final s = dealOf(standard, ['3d 2s', '4c 5c', '6c 7c', '8c 9c'], leader: 0);
      final solver = EndgameSolver();
      expect(solver.solvePerfect(s, 0), SolveOutcome.win);
      expect(solver.bestMove(s), play(standard, '2s'));
    });

    test('a hand the others can stop is not a forced win', () {
      final s = dealOf(standard, ['3d 4d', '5c', '6c 7c', '8c 9c'], leader: 0);
      expect(EndgameSolver().solvePerfect(s, 0), SolveOutcome.loss,
          reason: 'any single led lets seat 1 out with the 5♣ or better');
    });

    test('against opponents who could hold any unseen card, a proof holds whatever they have', () {
      final s = dealOf(standard, ['3d 2s', '4c 5c', '6c 7c', '8c 9c'], leader: 0);
      final shared = EndgameSolver.sharedState(s, 0);
      expect(EndgameSolver().solveShared(shared, 0), SolveOutcome.win);
      final bombs = dealOf(BigTwoRules.taiwan(), ['3c 2s', '4c 4d 4h 4s 5c', '6c 7c 8c 9c Tc', 'Jc Qc'], leader: 0);
      expect(EndgameSolver().solveShared(EndgameSolver.sharedState(bombs, 0), 0), SolveOutcome.loss,
          reason: 'with bombs, five unseen cards could beat the 2♠');
    });
  });

  group('coach', () {
    test('going out is the best move, a sure win, with the reason "goes out"', () {
      final s = dealOf(standard, ['3d 3s', '4c 5c 6h', '6c 7c 8h', '8c 9c Th'], leader: 0);
      final a = const BigTwoCoach(budget: fast).analyze(s.viewFor(0));
      expect(a.best.play, play(standard, '3d 3s'));
      expect(a.best.sureWin, isTrue);
      expect(a.best.winChance, 1.0);
      expect(a.best.reasons, contains(CoachReason.goesOut));
      expect(a.best.expectedPoints, 27,
          reason: 'three losers with 3 cards each; none has played a card, so each pays triple: 9');
    });

    test('"you can\'t be beaten": lead the 2♠, then your last card', () {
      final s = dealOf(standard, ['3d 2s', '4c', '6c 7c Qh', '8c 9c Jh'], leader: 0);
      final a = const BigTwoCoach(budget: fast).analyze(s.viewFor(0));
      expect(a.best.play, play(standard, '2s'));
      expect(a.best.sureWin, isTrue);
      expect(a.best.reasons, containsAll([CoachReason.sureWin, CoachReason.cantBeBeaten, CoachReason.usesTwo]));
      final low = a.candidates.firstWhere((c) => c.play == play(standard, '3d'));
      expect(low.sureWin, isFalse);
      expect(low.winChance, lessThan(0.5), reason: 'the next player can go out over the 3♦');
      expect(low.pointsLost, greaterThan(0));
    });

    test('rates every legal move, best first, and the same seed gives the same answer', () {
      final s = BigTwoState.deal(standard, seed: 21);
      final v = s.viewFor(s.toMove);
      final a = const BigTwoCoach(budget: fast).analyze(v, seed: 4);
      final b = const BigTwoCoach(budget: fast).analyze(v, seed: 4);
      expect(a.candidates.map((c) => c.play).toSet(), v.legalMoves().toSet());
      expect([for (final c in a.candidates) c.expectedPoints], [for (final c in b.candidates) c.expectedPoints]);
      expect(a.best.pointsLost, 0);
      expect(a.plan.count, greaterThan(0));
      expect(const BigTwoCoach(budget: fast).analyze(v, topN: 2).candidates, hasLength(2));
    });

    test('reasons: passing to keep a 2, shedding the lowest card, breaking a pair', () {
      final s = dealOf(standard, ['3d 4d 9c 9h 2s Kd', '5c 6c Qh', '6h 7c 8h', '8c 9s Th'], leader: 1);
      s.apply(legalMove(s, '5c'));
      s.apply(legalMove(s, 'pass'));
      s.apply(legalMove(s, 'pass'));
      final b = const BigTwoCoach(budget: fast).analyze(s.viewFor(0));
      final pass = b.candidates.firstWhere((c) => c.play.isPass);
      expect(pass.reasons, contains(CoachReason.keepsTwo));
      final two = b.candidates.firstWhere((c) => c.play == play(standard, '2s'));
      expect(two.reasons, contains(CoachReason.usesTwo));
      final nine = b.candidates.firstWhere((c) => c.play == play(standard, '9h'));
      expect(nine.reasons, contains(CoachReason.breaksPair));
    });

    test('the next player on one card: a low single is flagged, a pair blocks', () {
      final s = dealOf(standard, ['3d 3s 7h 9s', 'Kd', '4c 5c', '6c 8c'], leader: 0);
      final a = const BigTwoCoach(budget: fast).analyze(s.viewFor(0));
      final low = a.candidates.firstWhere((c) => c.play == play(standard, '7h'));
      expect(low.reasons, contains(CoachReason.lastCardDanger));
      final pair = a.candidates.firstWhere((c) => c.play == play(standard, '3d 3s'));
      expect(pair.reasons, contains(CoachReason.blocksLastCard));
    });

    test('the light budget (plain play-outs, as the Medium bot uses) also rates every move', () {
      final s = BigTwoState.deal(standard, seed: 22);
      final v = s.viewFor(s.toMove);
      final a = const BigTwoCoach(budget: CoachBudget.quick).analyze(v);
      expect(a.candidates.map((c) => c.play).toSet(), v.legalMoves().toSet());
      expect(a.playouts, greaterThanOrEqualTo(CoachBudget.quick.playouts));
    });

    test('spectators: the same analysis with every hand known', () {
      final s = BigTwoState.deal(standard, seed: 23);
      final a = const BigTwoCoach(budget: fast).analyzeAllKnown(s);
      expect(a.candidates.map((c) => c.play).toSet(), s.legalMoves().toSet());
    });

    test('a time cap stops the search early but still answers', () {
      final s = BigTwoState.deal(standard, seed: 24);
      final a = const BigTwoCoach(budget: CoachBudget(playouts: 1000000, maxMillis: 50)).analyze(s.viewFor(s.toMove));
      expect(a.playouts, lessThan(1000000));
      expect(a.best.samples, greaterThan(0));
    });

    test('refuses to analyze when it is not the viewer\'s turn', () {
      final s = BigTwoState.deal(standard, seed: 1);
      expect(() => const BigTwoCoach(budget: fast).analyze(s.viewFor((s.toMove + 1) % 4)), throwsStateError);
    });
  });

  group("reading the opponents' moves", () {
    test('the real deal explains moves made by the heuristic player perfectly; most guesses less so', () {
      final s = BigTwoState.deal(standard, seed: 31);
      final rng = GameRandom(4);
      for (var t = 0; t < 16 && !s.isOver; t++) {
        s.apply(const HeuristicPolicy().choose(s, rng));
      }
      final v = s.viewFor(s.toMove);
      const model = InferenceModel();
      final truth = [for (var i = 0; i < 4; i++) s.handCodesOf(i)];
      expect(model.weight(v, truth), 1.0);
      final sampler = DealSampler(v);
      final guesses = [for (var i = 0; i < 100; i++) model.weight(v, sampler.sample(rng))];
      expect(guesses.reduce((a, b) => a + b) / guesses.length, lessThan(0.9));
      expect(guesses.every((w) => w > 0 && w <= 1), isTrue);
    });

    test('a weighted pool picks heavier guesses more often', () {
      final s = BigTwoState.deal(standard, seed: 32);
      final rng = GameRandom(5);
      for (var t = 0; t < 12 && !s.isOver; t++) {
        s.apply(const HeuristicPolicy().choose(s, rng));
      }
      final v = s.viewFor(s.toMove);
      final sampler = DealSampler(v);
      final pool = WeightedDeals(v, () => sampler.sample(rng), const InferenceModel(), 200);
      expect(pool.deals, hasLength(200));
      expect(pool.effectiveSize, inInclusiveRange(1, 200));
      expect(pool.deals, contains(pool.pick(rng)));
    });
  });

  test('lnInt matches the natural log without platform-dependent rounding', () {
    for (final n in [1, 2, 3, 10, 999, 65535, 70000]) {
      expect(lnInt(n), closeTo(math.log(n), 1e-12));
    }
  });

  group('hand plan', () {
    test('splits a hand into the fewest plays', () {
      final plan = planHand(standard, parseCards('3d 4c 5h 6s 7d 9c 9h 9s Kd Kh 2s 2h Ac'));
      expect(plan.count, 4);
      expect(labels(plan.plays), ['3d 4c 5h 6s 7d', '9c 9h 9s Kd Kh', 'Ac', '2h 2s']);
    });

    test('uses the rules\' straights: A-2-3-4-5 counts in the standard game', () {
      final plan = planHand(standard, parseCards('Ad 2c 3h 4s 5d'));
      expect(plan.count, 1);
      final twoHigh = standard.copyWith(straights: StraightRule.twoHigh);
      expect(planHand(twoHigh, parseCards('Ad 2c 3h 4s 5d')).count, 5);
    });

    test('handles 17-card hands (three players)', () {
      final s = BigTwoState.deal(BigTwoRules.standard(players: 3), seed: 4);
      final plan = planHand(s.rules, s.handOf(0));
      expect(plan.plays.expand((p) => p.cards).toSet(), s.handOf(0).toSet(), reason: 'every card is used once');
      expect(plan.count, lessThan(s.countOf(0)));
    });

    test('marks plays no unseen cards can beat', () {
      final s = dealOf(standard, ['3d 2s', '4c 5c Kh', '6c 7c Qh', '8c 9c Jh'], leader: 0);
      final plan = planHand(standard, s.handOf(0), view: s.viewFor(0));
      expect(plan.count, 2);
      expect(plan.unbeatable, [false, true]);
      expect(plan.controls, 1);
    });
  });

  group('card counting', () {
    test('tracks the 2s and aces still out and whether your top card is the boss', () {
      final s = BigTwoState.deal(standard, seed: 8);
      final v = s.viewFor(0);
      final count = CardCounter.of(v);
      final myTwos = v.hand.where((c) => c.rank == Ranks.two).length;
      expect(count.twosOut, hasLength(4 - myTwos));
      expect(count.out, hasLength(39));
      expect(count.cardsLeft, [13, 13, 13, 13]);
      expect(count.myTopSingleWins, v.hand.contains(Card.parse('2s')));
    });
  });

  group('visible cards (the starting card until played, the face-up card)', () {
    /// A three-player endgame: the player (seat 0) holds A♣ 2♥ and leads;
    /// seat 1 holds one card; seat 2 took the face-up 2♠ and holds two more.
    /// Every other card is out of play, so the only single that beats the
    /// 2♥ is the 2♠, and everyone saw where it went.
    BigTwoState endgame() {
      final three = BigTwoRules.standard(players: 3);
      final s = dealOf(three, ['Ac 2h', 'Kd', '5c 9h'], extra: '2s', leader: 0);
      final inPlay = {for (final c in parseCards('Ac 2h Kd 5c 9h 2s')) three.codeOf(c)};
      for (var c = 0; c < 52; c++) {
        if (!inPlay.contains(c)) s.playedMasks[c >> 2] |= 1 << (c & 3);
      }
      return s;
    }

    test('the proof keeps a visible card with its holder only', () {
      final s = endgame();
      final twoS = s.rules.codeOf(Card.parse('2s'));
      expect(s.visibleCards, [(code: twoS, seat: 2)]);
      final shared = EndgameSolver.sharedState(s, 0);
      bool holds(int seat) => shared.handMasks[seat * 13 + (twoS >> 2)] & (1 << (twoS & 3)) != 0;
      expect(holds(2), isTrue, reason: 'its holder may play it');
      expect(holds(1), isFalse, reason: 'nobody else can hold it');
    });

    test('leading the 2♥ is a proven win only because the 2♠ is known to be with seat 2', () {
      final s = endgame();
      final lead = play(s.rules, '2h');
      // Seat 1 can't beat the 2♥ with its one card; seat 2 can only take the
      // trick with the 2♠ and then lead a single, which the A♣ beats.
      final shared = EndgameSolver.sharedState(s, 0)..applyTrusted(lead);
      expect(EndgameSolver().solveShared(shared, 0), SolveOutcome.win);
      // Were the 2♠ anyone's, seat 1 could go out with it.
      final blind = EndgameSolver.sharedState(s, 0);
      final twoS = s.rules.codeOf(Card.parse('2s'));
      blind.handMasks[13 + (twoS >> 2)] |= 1 << (twoS & 3);
      blind.applyTrusted(lead);
      expect(EndgameSolver().solveShared(blind, 0), SolveOutcome.loss);
      final a = const BigTwoCoach(budget: fast).analyze(s.viewFor(0));
      expect(a.candidates.firstWhere((c) => c.play == lead).sureWin, isTrue);
      expect(a.best.sureWin, isTrue);
    });

    test('an opponent whose every card is visible holds exactly those in the proof', () {
      final r = standard.copyWith(mustPlayStartCard: false);
      final s = dealOf(r, ['3d 9s Kh', '4d 6d', '4c 7c 2s', '8c 8h Ah']);
      playMoves(s, ['Kh', 'pass', 'pass', 'pass', '9s']);
      // Seat 0 holds only the 3♦ now, which everyone saw dealt.
      expect(s.visibleCards, [(code: 0, seat: 0)]);
      final shared = EndgameSolver.sharedState(s, 1);
      expect([for (var r = 0; r < 13; r++) shared.handMasks[r]], [1, ...List.filled(12, 0)]);
    });

    test("the coach's weighted guesses never move a visible card", () {
      // "Must play the starting card" off: the leader opens without the 3♦
      // and keeps it, so the guesses come from a history of plays.
      final r = standard.copyWith(mustPlayStartCard: false);
      var checked = 0;
      for (var seed = 0; seed < 12; seed++) {
        final s = BigTwoState.deal(r, seed: seed);
        if (s.isOver) continue;
        final lead = s.legalMoves().where((m) => !m.containsCode(s.startCode)).firstOrNull;
        if (lead == null) continue;
        s.apply(lead);
        final viewer = (s.startSeat + 1) % 4;
        final view = s.viewFor(viewer);
        expect(view.visibleCards, [(code: s.startCode, seat: s.startSeat)]);
        final sampler = DealSampler(view);
        final rng = GameRandom(seed);
        final pool = WeightedDeals(view, () => sampler.sample(rng), const InferenceModel(), 200);
        for (final hands in pool.deals) {
          for (var seat = 0; seat < 4; seat++) {
            expect(hands[seat].contains(s.startCode), seat == s.startSeat, reason: 'seed $seed seat $seat');
          }
        }
        for (var i = 0; i < 100; i++) {
          expect(pool.pick(rng)[s.startSeat], contains(s.startCode));
        }
        checked++;
      }
      expect(checked, greaterThan(5));
    });

    test('card counting leaves out the cards a two-player deal never dealt', () {
      final two = BigTwoRules.standard(players: 2, cardsEach: 13);
      final s = dealOf(two, ['9h 9c Th Tc Jh Jc Qh Qc Kh Kc Ah Ac 8c', '5s 6s 7s 8s 9s Ts Js Qs Ks As 2s 2h 2c']);
      final counter = CardCounter.of(s.viewFor(0));
      expect(counter.out.first, two.codeOf(Card.parse('5s')), reason: 'the 5♠ is the lowest card dealt');
      expect(counter.out, contains(two.codeOf(Card.parse('5s'))), reason: 'seen, but still in seat 1\'s hand');
    });
  });

  group('bots', () {
    for (final rules in [
      BigTwoRules.standard(),
      BigTwoRules.hongKong(),
      BigTwoRules.taiwan(),
      BigTwoRules.pusoyDos(),
      BigTwoRules.standard(players: 3),
      BigTwoRules.standard(players: 2, cardsEach: 13),
      BigTwoRules.standard().copyWith(passLockout: true, lastCardRule: true),
    ]) {
      test('Easy bots finish deals with legal moves: ${rules.players} players, ${rules.straights.name}, '
          'lockout ${rules.passLockout}', () {
        for (var seed = 0; seed < 25; seed++) {
          final s = BigTwoState.deal(rules, seed: seed);
          final bots = [for (var i = 0; i < rules.players; i++) BigTwoBot(BotLevel.easy, seed: seed + i)];
          var turns = 0;
          while (!s.isOver) {
            s.apply(bots[s.toMove].chooseMove(s.viewFor(s.toMove)));
            expect(++turns, lessThan(500));
          }
        }
      });
    }

    test('Medium and Hard play a whole deal legally', () {
      final s = BigTwoState.deal(standard, seed: 12);
      final bots = [
        BigTwoBot(BotLevel.hard, seed: 1, budget: const CoachBudget(playouts: 200)),
        BigTwoBot(BotLevel.medium, seed: 2),
        BigTwoBot(BotLevel.easy, seed: 3),
        BigTwoBot(BotLevel.medium, seed: 4),
      ];
      while (!s.isOver) {
        s.apply(bots[s.toMove].chooseMove(s.viewFor(s.toMove)));
      }
      expect(s.result.scores.reduce((a, b) => a + b), 0);
    });

    test('a seeded bot repeats its choices', () {
      final s = BigTwoState.deal(standard, seed: 13);
      final v = s.viewFor(s.toMove);
      expect(BigTwoBot(BotLevel.medium, seed: 5).chooseMove(v), BigTwoBot(BotLevel.medium, seed: 5).chooseMove(v));
      expect(BigTwoBot(BotLevel.easy, seed: 5).chooseMove(v), BigTwoBot(BotLevel.easy, seed: 5).chooseMove(v));
    });
  });
}
