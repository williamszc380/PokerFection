import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/bot.dart';
import 'package:pokerfection/src/games/doudizhu/cards.dart';
import 'package:pokerfection/src/games/doudizhu/coach.dart';
import 'package:pokerfection/src/games/doudizhu/game.dart';
import 'package:pokerfection/src/games/doudizhu/hand_plan.dart';
import 'package:pokerfection/src/games/doudizhu/plays.dart';
import 'package:pokerfection/src/games/doudizhu/policy.dart';
import 'package:pokerfection/src/games/doudizhu/rules.dart';
import 'package:pokerfection/src/games/doudizhu/sampler.dart';
import 'package:pokerfection/src/games/doudizhu/sim.dart';
import 'package:pokerfection/src/games/doudizhu/solver.dart';

List<int> hand(String text) => countsOfRanks(parseRanks(text));
Play play(String text) => classifyPlay(parseRanks(text)).single;
DdzMove move(String text) => DdzPlay(play(text));
const policy = HeuristicPolicy();

/// The policy's choice for [seat], with hand sizes taken from the texts.
/// Unseen cards are everything outside [mine] unless given.
Play? choose({
  required String mine,
  int seat = 0,
  int landlord = 0,
  List<int>? sizes,
  String? current,
  int currentPlayer = -1,
  String? unseen,
}) {
  final h = hand(mine);
  final u = unseen != null
      ? hand(unseen)
      : [for (var r = 0; r < Rank.count; r++) deckCountOf(r) - h[r]];
  return policy.choose(DdzSituation(
    seat: seat,
    landlord: landlord,
    hand: h,
    handSizes: sizes ?? [for (var s = 0; s < 3; s++) s == seat ? parseRanks(mine).length : 17],
    current: current == null ? null : play(current),
    currentPlayer: currentPlayer,
    unseen: u,
  ));
}

void main() {
  group('hand plan', () {
    test('finds the straight and lets the trio carry the lowest solo', () {
      final plan = planHand(hand('34567 999 3 K'));
      expect(plan.plays.map((p) => p.toString()), containsAll(['34567', '999+3', 'K']));
      expect(plan.turns, 3);
    });

    test('keeps bombs and the rocket whole', () {
      final plan = planHand(hand('5555 BR 3'));
      expect(plan.plays.map((p) => p.type), containsAll([PlayType.bomb, PlayType.rocket, PlayType.solo]));
    });

    test('airplanes carry wings', () {
      final plan = planHand(hand('333444 7 9'));
      expect(plan.plays.single.type, PlayType.airplaneSolos);
    });

    test('fewer, higher groups score better', () {
      expect(handScore(hand('34567')), greaterThan(handScore(hand('3 5 7 9 J'))));
      expect(handScore(hand('22')), greaterThan(handScore(hand('33'))));
    });
  });

  group('rule-of-thumb player', () {
    test('goes out when the whole hand is one play', () {
      expect(choose(mine: '334455')?.toString(), '334455');
      expect(choose(mine: '999K', current: '8883', currentPlayer: 1, sizes: [4, 10, 10])?.toString(), '999+K');
    });

    test('a peasant lets the partner\'s play win the trick', () {
      expect(choose(mine: '3 9 K 22', seat: 1, landlord: 0, current: '8', currentPlayer: 2), isNull);
    });

    test('a peasant still beats the landlord\'s play', () {
      expect(choose(mine: '3 9 K 22', seat: 1, landlord: 0, current: '8', currentPlayer: 0), isNotNull);
    });

    test('leads the smallest solo when the partner has one card left', () {
      final p = choose(mine: '55 99 KK 3', seat: 1, landlord: 0, sizes: [10, 7, 1]);
      expect(p?.toString(), '3');
      final q = choose(mine: '55 99 KK', seat: 1, landlord: 0, sizes: [10, 6, 1]);
      expect(q?.toString(), '5', reason: 'breaks a pair to lead its smallest card');
    });

    test('does not lead a small solo the landlord could follow with a last card', () {
      final p = choose(mine: '3 77 9', seat: 1, landlord: 0, sizes: [1, 4, 10]);
      expect(p?.type, isNot(PlayType.solo));
    });

    test('against a last card, answers a solo with its highest card', () {
      final p = choose(mine: '4 9 K A', seat: 1, landlord: 0, sizes: [1, 4, 10], current: '3', currentPlayer: 0);
      expect(p?.toString(), 'A');
    });

    test('keeps a bomb rather than spending it early', () {
      final p = choose(mine: '3 6 7 9 J 5555', current: 'K', currentPlayer: 1, sizes: [10, 15, 15]);
      expect(p, isNull);
    });

    test('bombs when an opponent is about to go out', () {
      final p = choose(mine: '3 6 7 9 J 4444', current: 'K', currentPlayer: 1, sizes: [10, 1, 15]);
      expect(p?.type, PlayType.bomb);
    });

    test('cashes safe plays first when that wins', () {
      final p = choose(mine: '2 3', sizes: [2, 5, 5], unseen: '4567889TTJQ');
      expect(p?.toString(), '2', reason: 'nobody can beat the 2, then the 3 goes out');
    });

    test('bidding strength grows with jokers, 2s and bombs', () {
      expect(policy.bidFor(hand('BR 2222 AAA KKQ 345 67')), 3);
      expect(policy.bidFor(hand('3 4 5 7 8 9 J Q 33 44 66 88 T')), 0);
    });
  });

  group('guessing hidden cards', () {
    DdzGame afterKitty() {
      final g = DdzGame.deal(random: Random(9), firstBidder: 0);
      g.act(const DdzBid(3));
      return g;
    }

    test('every guess fits the hand sizes and never uses the viewer\'s cards', () {
      final g = afterKitty();
      g.act(g.legalMoves().last);
      final view = g.viewFor(1);
      final sampler = DdzSampler(view);
      final rnd = Random(1);
      for (var i = 0; i < 50; i++) {
        final hands = sampler.deal(rnd);
        for (var s = 0; s < 3; s++) {
          expect(hands[s].reduce((a, b) => a + b), view.handSizes[s]);
        }
        expect(hands[1], view.counts);
        final total = [for (var r = 0; r < Rank.count; r++) hands[0][r] + hands[1][r] + hands[2][r]];
        for (var r = 0; r < Rank.count; r++) {
          expect(total[r] + sampler.count.played[r], deckCountOf(r));
        }
      }
    });

    test('the shown kitty cards the landlord still holds are always given to the landlord', () {
      final g = afterKitty();
      final kitty = countsOfIds(g.kitty);
      final sampler = DdzSampler(g.viewFor(2));
      final rnd = Random(2);
      for (var i = 0; i < 30; i++) {
        final lord = sampler.deal(rnd)[0];
        for (var r = 0; r < Rank.count; r++) {
          expect(lord[r], greaterThanOrEqualTo(kitty[r]));
        }
      }
    });

    test('during the auction the kitty is guessed too', () {
      final g = DdzGame.deal(random: Random(4), firstBidder: 0);
      final hands = DdzSampler(g.viewFor(0)).deal(Random(1));
      expect(hands[3].reduce((a, b) => a + b), 3);
    });

    test('guesses that explain the other players\' moves weigh more', () {
      // The landlord leads a K and seat 1 passes. Seen from seat 2, a guess
      // where seat 1 holds an ace (which the rule-of-thumb player would
      // have played) explains the pass worse than one where it doesn't.
      final g = DdzGame.fromRanks(
        hands: ['K 3 5 7 9 J 2 2 B', '4 4 5 5 6 6 7 7 8', 'A A Q Q T T 9 8 R'],
        kitty: '',
        landlord: 0,
      );
      g.act(move('K'));
      g.act(const DdzPass());
      final view = g.viewFor(2);
      final count = view.cardCount;
      final lordGuess = hand('3579J22B');
      final noAce = dealWeight(view, count, [lordGuess, hand('445566778'), view.counts], policy, 0.3);
      final withAce = dealWeight(view, count, [lordGuess, hand('44556677A'), view.counts], policy, 0.3);
      expect(withAce, closeTo(noAce * 0.3, 1e-9));
      expect(dealWeight(view, count, [lordGuess, hand('44556677A'), view.counts], policy, 1), 1,
          reason: 'mismatch 1 turns the inference off');
    });
  });

  group('exact endgames', () {
    test('a landlord with two unbeatable cards wins', () {
      final sim = DdzSim(rules: DdzRules.standard, hands: [hand('2 R'), hand('3 4 5'), hand('6 7 8')], landlord: 0, toAct: 0, stake: 1);
      expect(DdzEndgameSolver().landlordWins(sim), isTrue);
    });

    test('the peasants win together when the partner can go out', () {
      // Landlord to lead with two low solos; peasant 1 holds a 2, peasant 2
      // a single card: whatever the landlord leads, a peasant wins.
      final sim = DdzSim(rules: DdzRules.standard, hands: [hand('3 4'), hand('2 5'), hand('6')], landlord: 0, toAct: 0, stake: 1);
      expect(DdzEndgameSolver().landlordWins(sim), isFalse);
    });

    test('a pair the peasants cannot match, then the last card, wins for the landlord', () {
      final sim = DdzSim(rules: DdzRules.standard, hands: [hand('KK 3'), hand('A 4'), hand('2 5')], landlord: 0, toAct: 0, stake: 1);
      expect(DdzEndgameSolver().landlordWins(sim), isTrue, reason: 'KK, two passes, then the 3 goes out');
    });

    test('the solver agrees with a play-out of the forced line', () {
      // The landlord must lead into a peasant who goes out.
      final sim = DdzSim(rules: DdzRules.standard, hands: [hand('346'), hand('2'), hand('5 6')], landlord: 0, toAct: 0, stake: 1);
      expect(DdzEndgameSolver().landlordWins(sim), isFalse,
          reason: 'every lead is a solo, and the 2 beats it and goes out');
    });
  });

  group('landlord wins without seeing the split', () {
    test('the rocket and a last card win however the peasants\' cards are split', () {
      final sim = DdzSim(rules: DdzRules.standard, hands: [hand('BR 3'), hand('4 5'), hand('6 7')], landlord: 0, toAct: 0, stake: 1);
      expect(DdzBlindLandlordCheck().landlordWins(sim), isTrue);
    });

    test('a win that needs the split is no blind win', () {
      // The landlord's J J K wins on the real deal (lead J-J, then the K),
      // but if either peasant held A-A, J-J would lose.
      final g = DdzGame.fromCards(hands: [<int>[], [35, 46], [2, 44]], kitty: [29, 32, 33, 41], landlord: 0);
      g.act(move('T'));
      g.act(const DdzPass());
      g.act(const DdzPass());
      final sim = DdzSim.fromGame(g);
      expect(DdzEndgameSolver().landlordWins(sim), isTrue, reason: 'seeing every card, he wins');
      expect(DdzBlindLandlordCheck().landlordWins(sim), isFalse);
    });

    test('a blind win is a win on every split, and a loss on the real deal is never a blind win', () {
      // Random small endgames, the landlord to lead: whenever the check
      // says he wins blind, he must also win, seeing every card, on each
      // way the peasants' cards could be split.
      final rnd = Random(11);
      var blindWins = 0, blindLosses = 0;
      for (var trial = 0; trial < 300; trial++) {
        final deck = shuffledDeck(rnd);
        final l = 2 + rnd.nextInt(3), a = 1 + rnd.nextInt(3), b = 1 + rnd.nextInt(3);
        List<int> counts(List<int> ids) => countsOfIds(ids);
        final lord = counts(deck.sublist(0, l)), pool = counts(deck.sublist(l, l + a + b));
        final sim = DdzSim(
            rules: DdzRules.standard,
            hands: [lord, counts(deck.sublist(l, l + a)), counts(deck.sublist(l + a, l + a + b))],
            landlord: 0,
            toAct: 0,
            stake: 1);
        final blind = DdzBlindLandlordCheck().landlordWins(sim);
        if (blind == null) continue;
        if (!blind) {
          blindLosses++;
          continue;
        }
        blindWins++;
        expect(DdzEndgameSolver().landlordWins(sim), isTrue);
        // Every split of the pool with the same hand sizes.
        void each(int r, List<int> pick, int left) {
          if (r == Rank.count) {
            if (left > 0) return;
            final other = [for (var k = 0; k < Rank.count; k++) pool[k] - pick[k]];
            final alt = DdzSim(
                rules: DdzRules.standard, hands: [List<int>.of(lord), List<int>.of(pick), other], landlord: 0, toAct: 0, stake: 1);
            expect(DdzEndgameSolver().landlordWins(alt), isTrue, reason: '$alt');
            return;
          }
          for (var n = 0; n <= pool[r] && n <= left; n++) {
            pick[r] = n;
            each(r + 1, pick, left - n);
          }
          pick[r] = 0;
        }

        each(0, List<int>.filled(Rank.count, 0), a);
      }
      expect(blindWins, greaterThan(20), reason: 'the property is tested on real blind wins');
      expect(blindLosses, greaterThan(20));
    });
  });

  group('coach', () {
    test('rates going out as a certain win', () {
      final g = DdzGame.fromRanks(hands: ['334455 9', '6 7 8 T', 'J Q K A'], kitty: '', landlord: 0);
      g.act(move('9'));
      g.act(const DdzPass());
      g.act(const DdzPass());
      final a = const DdzCoach().analyze(g.viewFor(0), random: Random(1));
      expect(a.best.move, move('334455'));
      expect(a.best.winChance, 1);
      expect(a.best.reasons, contains(DdzReason.goesOut));
    });

    test('a known endgame is proven: the landlord holds only shown kitty cards', () {
      // The landlord's last card is the shown kitty ace, so seat 1 knows
      // every hand: seat 2's 2 can take the trick, but the landlord's ace
      // then beats whatever seat 2 leads.
      final g = DdzGame.fromRanks(hands: ['3 4 5 6 7', '8 9 T', 'J Q 2'], kitty: 'A K', landlord: 0);
      g.act(move('34567'));
      g.act(const DdzPass());
      g.act(const DdzPass());
      g.act(move('K'));
      final a = const DdzCoach().analyze(g.viewFor(1), random: Random(1));
      expect(a.candidates.every((c) => c.proven), isTrue,
          reason: 'a landlord with one card needs no hidden information: he plays it when he can');
      expect(a.best.winChance, 0);
    });

    test('a peasant\'s loss is not "proven" when the landlord cannot see how to win', () {
      // The landlord holds only shown kitty cards (J J K after leading the
      // 10), so seat 2 knows every hand. After two passes the landlord must
      // lead J-J (no peasant has a pair) and then the K. But he sees only
      // the peasants' four cards J A 3 A together: if one peasant held A-A,
      // leading J-J would lose. He cannot know, so the pass is no certain
      // loss for seat 2.
      final g = DdzGame.fromCards(hands: [<int>[], [35, 46], [2, 44]], kitty: [29, 32, 33, 41], landlord: 0);
      g.act(move('T'));
      g.act(const DdzPass());
      final a = const DdzCoach().analyze(g.viewFor(2), random: Random(1));
      final pass = a.candidateFor(const DdzPass())!;
      expect(pass.winChance, 0, reason: 'a landlord who saw every card would win');
      expect(pass.proven, isFalse, reason: '$pass');
    });

    test('a peasant\'s win in a known endgame is proven', () {
      // The landlord holds only the shown kitty A K, so seat 1 knows every
      // hand; its 2 beats the 3 and goes out.
      final g = DdzGame.fromRanks(hands: ['', '2', '9 T'], kitty: 'A K 3', landlord: 0);
      g.act(move('3'));
      final a = const DdzCoach().analyze(g.viewFor(1), random: Random(1));
      expect(a.best.winChance, 1);
      expect(a.best.proven, isTrue);
    });

    test('the coach\'s best move is one that survived sequential halving', () {
      // Replays Easy-bot deals and checks every 4th decision: the best
      // move must have had at least as many play-outs as any other, and
      // the list must go finalists first, then moves dropped later before
      // moves dropped earlier.
      for (var seed = 0; seed < 3; seed++) {
        final g = DdzGame.deal(random: Random(seed), firstBidder: 0);
        final bots = [for (var s = 0; s < 3; s++) DdzBot(DdzLevel.easy, random: Random(seed * 3 + s))];
        var steps = 0;
        while (g.phase == DdzPhase.bidding || g.phase == DdzPhase.playing) {
          final v = g.viewFor(g.toAct);
          if (g.phase == DdzPhase.playing && v.legalMoves.length >= 3 && steps % 4 == 0) {
            final a = const DdzCoach().analyze(v, random: Random(seed));
            if (!a.best.proven) {
              final most = a.candidates.map((c) => c.samples).reduce(max);
              expect(a.best.samples, most, reason: 'seed $seed: best ${a.best}');
              for (var i = 1; i < a.candidates.length; i++) {
                expect(a.candidates[i].samples, lessThanOrEqualTo(a.candidates[i - 1].samples));
              }
              for (final c in a.candidates) {
                expect(a.lossOf(c.move), greaterThanOrEqualTo(0));
              }
            }
          }
          steps++;
          g.act(bots[g.toAct].chooseMove(v));
        }
      }
    });

    test('breaking the rocket is not "keeps your bomb"', () {
      final s = DdzSituation(
        seat: 1, landlord: 0, hand: hand('BR 3 4 5'), handSizes: [15, 5, 17],
        current: play('2'), currentPlayer: 0,
        unseen: [for (var r = 0; r < Rank.count; r++) deckCountOf(r) - hand('BR345')[r] - (r == Rank.two ? 1 : 0)],
      );
      final reasons = const DdzCoach().reasonsFor(s, play('B'));
      expect(reasons, isNot(contains(DdzReason.keepsBomb)));
      expect(reasons, contains(DdzReason.breaksBomb));
    });

    test('a trio taken out of a bomb is not "keeps your bomb"', () {
      final s = DdzSituation(
        seat: 1, landlord: 0, hand: hand('5555 3 9'), handSizes: [15, 6, 17],
        current: null, currentPlayer: -1,
        unseen: [for (var r = 0; r < Rank.count; r++) deckCountOf(r) - hand('555539')[r]],
      );
      final reasons = const DdzCoach().reasonsFor(s, play('5553'));
      expect(reasons, isNot(contains(DdzReason.keepsBomb)));
      expect(reasons, contains(DdzReason.breaksBomb));
    });

    test('a play that leaves the bomb whole does keep it', () {
      final s = DdzSituation(
        seat: 1, landlord: 0, hand: hand('5555 3 9'), handSizes: [15, 6, 17],
        current: null, currentPlayer: -1,
        unseen: [for (var r = 0; r < Rank.count; r++) deckCountOf(r) - hand('555539')[r]],
      );
      final reasons = const DdzCoach().reasonsFor(s, play('3'));
      expect(reasons, contains(DdzReason.keepsBomb));
      expect(reasons, isNot(contains(DdzReason.breaksBomb)));
    });

    test('a peasant is told to let the partner\'s play win', () {
      final g = DdzGame.fromRanks(
        hands: ['3 4 5 6 7 9 J', 'Q K 2 8 8', 'A 9 T T'],
        kitty: '',
        landlord: 0,
      );
      g.act(move('3'));
      g.act(const DdzPass());
      g.act(move('A'));
      // Landlord can't beat the A without a 2 or joker; it passes.
      g.act(const DdzPass());
      final a = const DdzCoach().analyze(g.viewFor(1), random: Random(3));
      final pass = a.candidateFor(const DdzPass())!;
      expect(pass.reasons, contains(DdzReason.partnerWinning));
      expect(a.candidates.length, a.legalMoveCount);
    });

    test('the same seed gives the same analysis', () {
      final g = DdzGame.deal(random: Random(21), firstBidder: 0);
      g.act(const DdzBid(3));
      const coach = DdzCoach(budget: DdzBudget(rollouts: 300));
      final a = coach.analyze(g.viewFor(0), random: Random(5));
      final b = coach.analyze(g.viewFor(0), random: Random(5));
      expect([for (final c in a.candidates) '${c.move} ${c.winChance}'], [for (final c in b.candidates) '${c.move} ${c.winChance}']);
    });

    test('rates every move of a small decision and ranks them best first', () {
      final g = DdzGame.deal(random: Random(8), firstBidder: 0);
      g.act(const DdzBid(3));
      g.act(g.legalMoves().first);
      final view = g.viewFor(1);
      final a = const DdzCoach(budget: DdzBudget(rollouts: 400)).analyze(view, random: Random(1));
      expect(a.candidates, hasLength(min(view.legalMoves.length, const DdzBudget().maxCandidates)));
      // Moves that survived more halving rounds (more play-outs) come
      // first; moves judged on the same play-outs are ranked by value.
      for (var i = 1; i < a.candidates.length; i++) {
        final (prev, next) = (a.candidates[i - 1], a.candidates[i]);
        expect(prev.samples, greaterThanOrEqualTo(next.samples));
        if (prev.samples == next.samples) expect(prev.winChance, greaterThanOrEqualTo(next.winChance));
      }
      expect(a.lossOf(a.best.move), 0);
    });

    test('bidding advice: a monster hand should bid 3, a weak one pass', () {
      DdzGame withHand(String text) {
        final mine = idsForRanks(parseRanks(text));
        final rest = [for (var id = 0; id < 54; id++) if (!mine.contains(id)) id]..shuffle(Random(1));
        return DdzGame.fromCards(hands: [mine, rest.sublist(0, 17), rest.sublist(17, 34)], kitty: rest.sublist(34));
      }

      final strong = const DdzCoach().analyze(withHand('BR 2222 AAA KK 345 678').viewFor(0), random: Random(1));
      expect(strong.best.move, const DdzBid(3));
      expect(strong.best.reasons, containsAll([DdzReason.strongHand, DdzReason.holdsRocket, DdzReason.holdsBomb]));
      final weak = const DdzCoach().analyze(withHand('3 3 4 6 6 7 9 9 T J Q 4 8 K 5 T 7').viewFor(0), random: Random(1));
      expect(weak.best.move, const DdzBid(0));
    });
  });

  group('bots', () {
    test('every level plays legal moves to the end of a deal, with the auction', () {
      for (final level in DdzLevel.values) {
        // Call and rob, with every deal played (the house rule), so each
        // level finishes a deal.
        const rules = DdzRules(bidding: BiddingStyle.callRob, allPass: AllPassRule.firstBidderLandlord);
        final g = DdzGame.deal(random: Random(level.index + 30), rules: rules, firstBidder: 0);
        final budget = const DdzBudget(rollouts: 120, maxCandidates: 6);
        final bots = [for (var s = 0; s < 3; s++) DdzBot(level, random: Random(s), budget: budget)];
        playOut(g, bots);
        expect(g.phase, DdzPhase.finished);
        expect(g.result!.points.reduce((a, b) => a + b), 0, reason: 'zero-sum');
      }
    });

    test('a seeded game repeats exactly', () {
      List<String> run() {
        final g = DdzGame.deal(random: Random(77), firstBidder: 0);
        final budget = const DdzBudget(rollouts: 150, maxCandidates: 6);
        final bots = [for (var s = 0; s < 3; s++) DdzBot(DdzLevel.medium, random: Random(s), budget: budget)];
        playOut(g, bots);
        return [for (final a in g.history) a.toString()];
      }

      expect(run(), run());
    });
  });

  group('the cards everyone has seen (the face-up card, the shown kitty) stay with their holder', () {
    /// Positions of random deals (the auction and the play, the kitty shown
    /// or hidden), each with every seat's visible cards as the game has them.
    List<DdzGame> positions() {
      final random = Random(31);
      final out = <DdzGame>[];
      for (var deal = 0; deal < 30; deal++) {
        final rules = DdzRules.standard.copyWith(kittyShown: deal % 3 != 2);
        final g = DdzGame.deal(rules: rules, random: random);
        final stop = random.nextInt(30);
        for (var i = 0; i < stop && (g.phase == DdzPhase.bidding || g.phase == DdzPhase.playing); i++) {
          final legal = g.legalMoves();
          g.act(legal[random.nextInt(legal.length)]);
        }
        if (g.phase == DdzPhase.bidding || g.phase == DdzPhase.playing) out.add(g);
      }
      return out;
    }

    /// Checks one guess of [view]'s hidden cards against [game]: every
    /// other seat holds at least its visible cards (by rank: the guesses
    /// deal ranks), and the places add up to what the viewer can't see.
    void expectFits(DdzGame game, int viewer, List<List<int>> hands, String reason) {
      final count = game.viewFor(viewer).cardCount;
      for (var s = 0; s < 3; s++) {
        if (s == viewer) continue;
        final known = countsOfIds(game.visibleIn(s));
        for (var r = 0; r < Rank.count; r++) {
          expect(hands[s][r], greaterThanOrEqualTo(known[r]), reason: '$reason: seat $s, ${Rank.label(r)}');
        }
      }
      for (var r = 0; r < Rank.count; r++) {
        final placed = [for (var s = 0; s < hands.length; s++) if (s != viewer) hands[s][r]].fold(0, (a, b) => a + b);
        expect(placed, count.unseen[r], reason: '$reason: every unseen ${Rank.label(r)} placed once');
      }
    }

    test('no guess ever puts a visible card anywhere but its holder: in the auction (never the kitty) and in play',
        () {
      var guesses = 0, auction = 0, withKitty = 0;
      for (final g in positions()) {
        for (var viewer = 0; viewer < 3; viewer++) {
          final others = [for (var s = 0; s < 3; s++) if (s != viewer) ...g.visibleIn(s)];
          if (others.isEmpty) continue;
          final sampler = DdzSampler(g.viewFor(viewer));
          final rnd = Random(guesses);
          for (var i = 0; i < 40; i++) {
            final hands = sampler.deal(rnd);
            expectFits(g, viewer, hands, '${g.phase} viewer $viewer');
            if (g.phase == DdzPhase.bidding) {
              expect(hands, hasLength(4), reason: 'the kitty is guessed too');
              final up = g.faceUp!;
              final unknown = sampler.count.unknown[rankOfId(up)];
              expect(hands[3][rankOfId(up)], lessThanOrEqualTo(unknown), reason: 'the face-up card is not in it');
            }
            guesses++;
          }
          if (g.phase == DdzPhase.bidding) auction++;
          if (g.landlord != null && g.rules.kittyShown) withKitty++;
        }
      }
      expect(guesses, greaterThanOrEqualTo(2000));
      expect(auction, greaterThan(0));
      expect(withKitty, greaterThan(0));
    });

    test("the coach's weighed guesses (DealPool) keep them with their holder too", () {
      var checked = 0;
      for (final g in positions()) {
        if (g.phase != DdzPhase.playing) continue;
        final viewer = g.toAct;
        final sampler = DdzSampler(g.viewFor(viewer));
        final pool = DealPool(sampler, Random(checked), size: 60, policy: policy);
        final rnd = Random(7);
        for (var i = 0; i < 30; i++) {
          expectFits(g, viewer, pool.draw(rnd), 'pool, viewer $viewer');
        }
        checked++;
      }
      expect(checked, greaterThan(3));
    });

    test("a peasant's guesses keep a shown kitty card by id, after the landlord played another of its rank", () {
      const sevenClubs = 4 * 4, sevenDiamonds = 4 * 4 + 1;
      final g = DdzGame.fromCards(
        hands: [
          [sevenClubs, 0, 1],
          [8, 9, 10],
          [12, 13, 14],
        ],
        kitty: [sevenDiamonds, 52, 53],
        landlord: 0,
      );
      g.act(DdzPlay(Play.decode('solo:7')), cardIds: [sevenClubs]);
      final sampler = DdzSampler(g.viewFor(1));
      final rnd = Random(3);
      for (var i = 0; i < 200; i++) {
        final lord = sampler.deal(rnd)[0];
        expect(lord[rankOfId(sevenDiamonds)], 1, reason: 'the 7♦ went into the hand for all to see');
        expect(lord[Rank.littleJoker] + lord[Rank.bigJoker], 2);
      }
    });

    test('the blind landlord check leaves out the splits that put the face-up card on the wrong peasant', () {
      // The landlord leads from 6 7 9; the peasants hold 3 (seat 1, the
      // face-up card) and 7 8 (seat 2). Knowing the 3 is seat 1's, he wins:
      // a 6, the 9 over seat 2's answer, then the 7. Not knowing, a split
      // where seat 1 holds the 8 could beat him.
      final sim = DdzSim(rules: DdzRules.standard, hands: [hand('679'), hand('3'), hand('78')], landlord: 0, toAct: 0, stake: 1);
      expect(DdzEndgameSolver().landlordWins(sim.copy()), isTrue, reason: 'seeing every card, he wins');
      expect(DdzBlindLandlordCheck().landlordWins(sim.copy()), isFalse);
      final known = [List<int>.filled(Rank.count, 0), hand('3'), List<int>.filled(Rank.count, 0)];
      expect(DdzBlindLandlordCheck().landlordWins(sim.copy(), known: known), isTrue);
    });

    test("the coach solves a known endgame with the face-up card in its partner's hand", () {
      // Seat 0 (a peasant) follows the landlord's 6; the landlord holds
      // only the shown kitty, so every hidden card is known: the coach
      // solves each move exactly, and its proof check is told that the K
      // dealt face up is seat 1's.
      final g = DdzGame.fromCards(
        hands: [
          [0, 8, 24],
          [4, 20, 40],
          <int>[],
        ],
        kitty: [12, 16, 44],
        firstBidder: 1,
        faceUp: 40,
        landlord: 2,
      );
      g.act(DdzPlay(Play.decode('solo:6')), cardIds: [12]);
      final view = g.viewFor(0);
      expect(view.visibleIn(1), [40]);
      expect(DdzSampler(view).isUnique, isTrue);
      final a = const DdzCoach(budget: DdzBudget(rollouts: 60)).analyze(view, random: Random(1));
      expect(a.candidates, hasLength(view.legalMoves.length));
    });
  });
}
