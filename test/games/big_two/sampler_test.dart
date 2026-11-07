// Guessing hidden hands: every guess must fit what the viewer knows, and
// never put a known card in the wrong place.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';

import 'helpers.dart';

/// Plays [turns] moves of a seeded Easy-bot game.
BigTwoState midGame(BigTwoRules rules, int seed, int turns) {
  final s = BigTwoState.deal(rules, seed: seed);
  final bots = [for (var i = 0; i < rules.players; i++) BigTwoBot(BotLevel.easy, seed: seed + i)];
  for (var t = 0; t < turns && !s.isOver; t++) {
    s.apply(bots[s.toMove].chooseMove(s.viewFor(s.toMove)));
  }
  return s;
}

void checkGuess(BigTwoView v, List<List<int>> hands) {
  expect(hands[v.seat], v.handCodes, reason: 'the viewer keeps their real hand');
  final seen = <int>{};
  for (var s = 0; s < v.players; s++) {
    expect(hands[s], hasLength(v.counts[s]), reason: 'seat $s gets as many cards as it holds');
    for (final c in hands[s]) {
      expect(seen.add(c), isTrue, reason: 'a card dealt twice');
      expect(v.isPlayed(c), isFalse, reason: 'a played card dealt again');
      if (s != v.seat) expect(c < v.bounds[s], isTrue, reason: 'seat $s cannot hold a card above its bound');
    }
  }
  for (final card in v.visibleCards) {
    expect(hands[card.seat], contains(card.code), reason: 'a card everyone has seen stays with its holder');
  }
}

/// Every preset at 2, 3 and 4 players, with "must play the starting card"
/// on and off.
Iterable<BigTwoRules> everyTable() sync* {
  for (final preset in BigTwoPreset.values) {
    for (final players in [2, 3, 4]) {
      for (final must in [true, false]) {
        yield BigTwoRules.preset(preset, players: players).copyWith(mustPlayStartCard: must);
      }
    }
  }
}

void main() {
  test('four players: guesses use exactly the unseen cards, with the right counts', () {
    final s = midGame(BigTwoRules.standard(), 1, 9);
    final v = s.viewFor(s.toMove);
    final sampler = DealSampler(v);
    expect(sampler.pool.toSet(), v.unknownCodes().toSet());
    final rng = GameRandom(5);
    for (var i = 0; i < 300; i++) {
      final hands = sampler.sample(rng);
      checkGuess(v, hands);
      final dealt = {for (var seat = 0; seat < 4; seat++) if (seat != v.seat) ...hands[seat]};
      expect(dealt, v.unknownCodes().toSet(), reason: 'with four players every unseen card is in a hand');
    }
  });

  test('guesses vary, and each unseen card lands with each opponent sometimes', () {
    final s = BigTwoState.deal(BigTwoRules.standard(), seed: 2);
    final v = s.viewFor(s.toMove);
    final sampler = DealSampler(v);
    final rng = GameRandom(1);
    final where = <int, Set<int>>{};
    for (var i = 0; i < 400; i++) {
      final hands = sampler.sample(rng);
      for (var seat = 0; seat < 4; seat++) {
        for (final c in hands[seat]) {
          (where[c] ??= <int>{}).add(seat);
        }
      }
    }
    for (final c in v.unknownCodes()) {
      expect(where[c], hasLength(3));
    }
  });

  test('the same seed gives the same guesses', () {
    final s = midGame(BigTwoRules.standard(), 3, 6);
    final v = s.viewFor(s.toMove);
    final a = DealSampler(v).sample(GameRandom(9));
    final b = DealSampler(v).sample(GameRandom(9));
    expect(a, b);
  });

  test('three players: the face-up card always goes to the player who took it', () {
    final rules = BigTwoRules.standard(players: 3);
    for (var seed = 0; seed < 10; seed++) {
      final s = BigTwoState.deal(rules, seed: seed);
      final viewer = (s.extraSeat + 1) % 3;
      final v = s.viewFor(viewer);
      expect(v.knownOtherCards, contains(s.extraCode));
      expect(v.unknownCodes(), isNot(contains(s.extraCode)));
      final rng = GameRandom(seed);
      for (var i = 0; i < 50; i++) {
        checkGuess(v, DealSampler(v).sample(rng));
      }
    }
  });

  test('two players: unused cards stay out, and nothing below the starting card is dealt', () {
    final rules = BigTwoRules.standard(players: 2, cardsEach: 17);
    final s = midGame(rules, 4, 1);
    final v = s.viewFor(s.toMove);
    expect(v.startCode, s.startCode);
    final rng = GameRandom(2);
    for (var i = 0; i < 200; i++) {
      final hands = DealSampler(v).sample(rng);
      checkGuess(v, hands);
      expect(hands[1 - v.seat].every((c) => c > s.startCode), isTrue);
    }
  });

  test('the last-card rule\'s bound is respected', () {
    final rules = BigTwoRules.standard().copyWith(lastCardRule: true);
    final s = dealOf(rules, ['3d 6d 9s Kh', 'Kd', '4c 5c 2s', '7c 8c Ah'], leader: 0);
    s.apply(legalMove(s, 'Kh'));
    final v = s.viewFor(2);
    expect(v.bounds[0], rules.codeOf(Card.parse('Kh')));
    final rng = GameRandom(3);
    for (var i = 0; i < 300; i++) {
      checkGuess(v, DealSampler(v).sample(rng));
    }
  });

  test('no guess ever puts a visible card anywhere but its holder', () {
    var checked = 0;
    for (final rules in everyTable()) {
      for (var seed = 0; seed < 3; seed++) {
        // At the deal, and after a few plays (the starting card may still
        // be in hand with "must play the starting card" off).
        for (final turns in [0, 1, 4]) {
          final s = midGame(rules, seed, turns);
          if (s.isOver) continue;
          for (var viewer = 0; viewer < rules.players; viewer++) {
            final v = s.viewFor(viewer);
            expect(v.visibleCards, s.visibleCards, reason: 'every seat sees the same visible cards');
            final others = [
              for (final card in v.visibleCards)
                if (card.seat != viewer) card,
            ];
            if (others.isEmpty) continue;
            checked++;
            final sampler = DealSampler(v);
            expect(sampler.pool.toSet().intersection({for (final c in others) c.code}), isEmpty,
                reason: 'the pool holds no visible card');
            final rng = GameRandom(seed * 7 + turns);
            for (var i = 0; i < 500; i++) {
              final hands = sampler.sample(rng);
              for (final card in others) {
                for (var seat = 0; seat < rules.players; seat++) {
                  expect(hands[seat].contains(card.code), seat == card.seat,
                      reason: '${rules.cardOf(card.code)} held by seat ${card.seat}, viewer $viewer');
                }
              }
            }
          }
        }
      }
    }
    expect(checked, greaterThan(50));
  });

  test('with "must play the starting card" off, a lead without it keeps it fixed to the leader', () {
    final rules = BigTwoRules.standard().copyWith(mustPlayStartCard: false);
    final s = dealOf(rules, ['3d 9s Kh 5c', '4d 6d', '4c 7c 2s', '8c 8h Ah']);
    s.apply(legalMove(s, 'Kh'));
    final v = s.viewFor(2);
    expect(v.visibleCards, [(code: rules.codeOf(Card.parse('3d')), seat: 0)]);
    final rng = GameRandom(4);
    for (var i = 0; i < 300; i++) {
      final hands = DealSampler(v).sample(rng);
      checkGuess(v, hands);
      expect(hands[0], contains(rules.codeOf(Card.parse('3d'))));
    }
  });

  test('two players: no guess deals a card below the public starting card, before the first play too', () {
    for (var seed = 0; seed < 20; seed++) {
      final rules = BigTwoRules.standard(players: 2, cardsEach: 13);
      final s = BigTwoState.deal(rules, seed: seed);
      final other = 1 - s.startSeat;
      final v = s.viewFor(other);
      expect(v.startCode, s.startCode, reason: 'public from the deal');
      expect(v.startSeat, s.startSeat);
      final rng = GameRandom(seed);
      for (var i = 0; i < 100; i++) {
        final hands = DealSampler(v).sample(rng);
        checkGuess(v, hands);
        expect(hands[s.startSeat].every((c) => c >= s.startCode), isTrue);
        expect(hands[s.startSeat], contains(s.startCode));
      }
    }
  });

  test('a sampled state plays on from the same public position', () {
    final s = midGame(BigTwoRules.standard(), 6, 10);
    final v = s.viewFor(s.toMove);
    final guess = DealSampler(v).sampleState(GameRandom(1));
    expect(guess.toMove, s.toMove);
    expect(guess.current, s.current);
    expect(guess.handOf(v.seat), s.handOf(v.seat));
    expect(guess.legalMoves(), s.legalMoves());
  });
}
