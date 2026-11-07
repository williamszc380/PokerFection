// Combinations and how they compare, under each preset. Rule quotes are
// from Pagat (https://www.pagat.com/climbing/bigtwo.html) unless noted.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/big_two/plays.dart' show masksOf;

import 'helpers.dart';

void main() {
  final standard = BigTwoRules.standard();
  final hongKong = BigTwoRules.hongKong();
  final taiwan = BigTwoRules.taiwan();
  final pusoy = BigTwoRules.pusoyDos();

  bool beats(BigTwoRules r, String a, String b) => r.beats(play(r, a), play(r, b));

  group('cards', () {
    test('parse short notation, with T or 10 for the ten', () {
      expect(Card.parse('3d').label, '3♦');
      expect(Card.parse('Ts'), Card.parse('10s'));
      expect(Card.parse('2h').rank, Ranks.two);
      expect(Card.parse('Ac').rank, Ranks.ace);
      expect(() => Card.parse('1x'), throwsFormatException);
      expect(parseCards('3d 4c 2s').map((c) => c.short), ['3d', '4c', '2s']);
    });

    test('ranks run 3 (low) to 2 (high): "2-A-K-Q-J-10-9-8-7-6-5-4-3"', () {
      expect(beats(standard, '2d', 'As'), isTrue);
      expect(beats(standard, 'Ad', 'Ks'), isTrue);
      expect(beats(standard, '4d', '3s'), isTrue);
      expect(beats(standard, '3s', '4d'), isFalse);
    });
  });

  group('singles and suit order', () {
    test('standard: spades > hearts > clubs > diamonds', () {
      expect(beats(standard, '3c', '3d'), isTrue);
      expect(beats(standard, '3h', '3c'), isTrue);
      expect(beats(standard, '3s', '3h'), isTrue);
      expect(beats(standard, '3d', '3s'), isFalse);
      expect(standard.codeOf(Card.parse('3d')), 0, reason: '3♦ is the lowest card');
      expect(standard.codeOf(Card.parse('2s')), 51, reason: '2♠ is the highest card');
    });

    test('Taiwan swaps clubs and diamonds: spades > hearts > diamonds > clubs', () {
      expect(beats(taiwan, '3d', '3c'), isTrue);
      expect(beats(taiwan, '3c', '3d'), isFalse);
      expect(taiwan.codeOf(Card.parse('3c')), 0);
    });

    test('Pusoy Dos: diamonds > hearts > spades > clubs', () {
      expect(beats(pusoy, '2d', '2h'), isTrue);
      expect(beats(pusoy, '2h', '2s'), isTrue);
      expect(beats(pusoy, '2s', '2c'), isTrue);
      expect(pusoy.codeOf(Card.parse('2d')), 51);
      expect(pusoy.codeOf(Card.parse('3c')), 0);
    });

    test('a play needs the same number of cards to beat it', () {
      expect(beats(standard, '4d 4c', '3s'), isFalse);
      expect(beats(standard, '2s', '3d 3c'), isFalse);
      expect(beats(standard, '9d 9c 9h', '3d 3c'), isFalse);
    });
  });

  group('pairs and triples', () {
    test('pairs compare by rank, then by the higher suit in each pair', () {
      expect(beats(standard, '8d 8c', '7h 7s'), isTrue);
      expect(beats(standard, '7d 7s', '7c 7h'), isTrue, reason: '"the one containing the highest suit is better"');
      expect(beats(standard, '7c 7h', '7d 7s'), isFalse);
    });

    test('triples compare by rank', () {
      expect(beats(standard, '4d 4c 4h', '3c 3h 3s'), isTrue);
      expect(beats(standard, '2d 2c 2h', 'Ac Ah As'), isTrue);
    });

    test('two different ranks are not a pair, four of a kind alone is not a play', () {
      expect(isCombination(standard, '3d 4d'), isFalse);
      expect(isCombination(standard, '3d 3c 3h 3s'), isFalse, reason: '"four equal cards by themselves are not a playable combination"');
      expect(isCombination(standard, '3d 3c 4h 4s'), isFalse, reason: 'no two-pair play in Pagat\'s game');
    });
  });

  group('five-card hands', () {
    test('kinds rank straight < flush < full house < four of a kind < straight flush', () {
      const straight = '9d Tc Jh Qs Ks';
      const flush = '3h 5h 7h 9h Jh';
      const full = '4d 4c 4h 5d 5c';
      const quads = '6d 6c 6h 6s 3c';
      const straightFlush = '3d 4d 5d 6d 7d';
      final order = [straight, flush, full, quads, straightFlush];
      expect([for (final h in order) play(standard, h).kind],
          [PlayKind.straight, PlayKind.flush, PlayKind.fullHouse, PlayKind.fourOfAKind, PlayKind.straightFlush]);
      for (var i = 0; i < order.length; i++) {
        for (var j = 0; j < order.length; j++) {
          expect(beats(standard, order[i], order[j]), i > j, reason: '${order[i]} vs ${order[j]}');
        }
      }
    });

    test('full houses compare by the triple, four of a kind by the four', () {
      expect(beats(standard, '5d 5c 5h 3d 3c', '4d 4c 4h 2d 2c'), isTrue, reason: 'the pair does not matter');
      expect(beats(standard, '4d 4c 4h 3d 3c', '5d 5c 5h 3h 3s'), isFalse);
      expect(beats(standard, '4d 4c 4h 4s 5d', '3c 3h 3s 3d 2s'), isTrue, reason: 'the fifth card does not matter');
    });

    group('Pagat straights (standard)', () {
      test('A-2-3-4-5 is the lowest, then 2-3-4-5-6, then 3-4-5-6-7 ... up to 10-J-Q-K-A', () {
        expect(beats(standard, '2d 3c 4h 5s 6d', 'Ad 2c 3h 4s 5d'), isTrue);
        expect(beats(standard, '3d 4c 5h 6s 7d', '2s 3s 4s 5s 6h'), isTrue);
        expect(beats(standard, 'Td Jc Qh Ks Ad', '9s Ts Js Qs Kh'), isTrue);
      });

      test('the ace is "not in the middle": J-Q-K-A-2, Q-K-A-2-3 and K-A-2-3-4 are not straights', () {
        expect(isCombination(standard, 'Jd Qc Kh As 2d'), isFalse);
        expect(isCombination(standard, 'Qd Kc Ah 2s 3d'), isFalse);
        expect(isCombination(standard, 'Kd Ac 2h 3s 4d'), isFalse);
      });

      test('ties: "the suit of the top card determines which is higher"', () {
        expect(beats(standard, '3d 4d 5d 6d 7s', '3c 4c 5c 6c 7h'), isTrue);
        expect(beats(standard, 'As 2s 3s 4s 5c', 'Ad 2d 3d 4d 5h'), isFalse,
            reason: 'in 5-4-3-2-A the top card is the 5');
        expect(beats(standard, 'Ad 2d 3d 4c 5h', 'As 2s 3s 4s 5c'), isTrue);
      });

      test('straight flushes: rank first, then suit', () {
        expect(beats(standard, '4c 5c 6c 7c 8c', '3s 4s 5s 6s 7s'), isTrue);
        expect(beats(standard, '3s 4s 5s 6s 7s', '3h 4h 5h 6h 7h'), isTrue);
        expect(play(standard, 'Ts Js Qs Ks As').kind, PlayKind.straightFlush,
            reason: 'the royal flush in spades is the best hand');
      });
    });

    test('flushes, standard: "A flush in a higher suit beats a flush in a lower suit, irrespective of the ranks"', () {
      expect(beats(standard, '3s 4s 6s 7s 9s', '9h Jh Kh Ah 2h'), isTrue);
      expect(beats(standard, '3s 4s 6s 7s Js', '5s 8s 9s Ts Qs'), isFalse);
      expect(beats(standard, '5s 8s 9s Ts Ks', '3s 4s 6s 7s Js'), isTrue, reason: 'same suit: the higher top card');
    });

    test('flushes, Pusoy Dos: suit first, with diamonds the highest suit', () {
      expect(beats(pusoy, '3d 5d 6d 8d 9d', '3h 5h 6h 8h Ah'), isTrue);
      expect(beats(pusoy, '3s 5s 6s 8s 2s', '4c 6c 7c 9c Jc'), isTrue);
      expect(beats(pusoy, '3c 4c 5c 6c 7c', '3d 4d 5d 6d 7d'), isFalse,
          reason: 'straight flushes of the same ranks: the suit decides');
    });

    test('flushes, Hong Kong: "compared according to the rank of the highest card"', () {
      expect(beats(hongKong, '3d 5d 6d 8d Ad', '3s 4s 6s 7s Ks'), isTrue);
      expect(beats(hongKong, '3s 4s 6s 7s As', '3d 5d 6d 8d Ad'), isTrue, reason: 'equal top cards: suit decides');
    });

    test('flushes, all ranks (poker style): compare every card from the top before the suit', () {
      final r = standard.copyWith(flushOrder: FlushOrder.allRanks);
      expect(beats(r, '4d 5d 7d 9d Kd', '3s 5s 7s 9s Ks'), isTrue);
      expect(beats(r, '3s 5s 7s 9s Ks', '3h 5h 7h 9h Kh'), isTrue);
      expect(beats(r, '3s 5s 7s 9s Ks', '4d 5d 7d 9d Kd'), isFalse);
    });

    group('Hong Kong straights', () {
      test('"The highest ... is A2345, then 23456, TJQKA, 9TJQK, and so on down to 34567 (lowest)"', () {
        expect(beats(hongKong, 'Ad 2c 3h 4s 5d', '2d 3c 4h 5s 6d'), isTrue);
        expect(beats(hongKong, '2d 3c 4h 5s 6d', 'Td Jc Qh Ks Ad'), isTrue);
        expect(beats(hongKong, 'Td Jc Qh Ks Ad', '9d Tc Jh Qs Kd'), isTrue);
        expect(beats(hongKong, '4d 5c 6h 7s 8d', '3s 4s 5s 6s 7h'), isTrue);
      });

      test('"JQKA2 is not a valid straight or straight flush"', () {
        expect(isCombination(hongKong, 'Jd Qc Kh As 2d'), isFalse);
        expect(play(hongKong, 'Jd Qd Kd Ad 2d').kind, PlayKind.flush);
      });

      test('ties between A-2-3-4-5 straights go to the suit of the 2', () {
        expect(beats(hongKong, 'Ad 2s 3d 4d 5c', 'As 2h 3s 4s 5h'), isTrue);
      });
    });

    test('Taiwan straights: 2-3-4-5-6 highest, A-2-3-4-5 lowest', () {
      expect(beats(taiwan, '2d 3c 4h 5s 6d', 'Td Jc Qh Ks Ad'), isTrue);
      expect(beats(taiwan, '3d 4c 5h 6s 7d', 'Ad 2c 3h 4s 5d'), isTrue);
    });

    test('two-high straights: J-Q-K-A-2 is the top straight, A-2-3-4-5 is not a straight', () {
      final r = standard.copyWith(straights: StraightRule.twoHigh);
      expect(beats(r, 'Jd Qc Kh As 2d', 'Td Jc Qh Ks Ad'), isTrue);
      expect(isCombination(r, 'Ad 2c 3h 4s 5d'), isFalse);
      expect(isCombination(r, '2d 3c 4h 5s 6d'), isFalse);
    });

    test('a custom straight order allows exactly the runs listed', () {
      final r = standard.copyWith(straights: const StraightRule([0, 1, 9]));
      expect(isCombination(r, 'Qd Kc Ah 2s 3d'), isTrue, reason: 'Q-K-A-2-3 starts at rank 9');
      expect(beats(r, 'Qd Kc Ah 2s 3d', '4d 5c 6h 7s 8d'), isTrue);
      expect(isCombination(r, '5d 6c 7h 8s 9d'), isFalse);
    });
  });

  group('bombs (honour hands)', () {
    test('off in the standard game: four of a kind cannot beat a single', () {
      expect(beats(standard, '3d 3c 3h 3s 4d', '2s'), isFalse);
    });

    test('Taiwan: four of a kind and straight flushes beat any single, pair or triple', () {
      expect(beats(taiwan, '3d 3c 3h 3s 4d', '2s'), isTrue);
      expect(beats(taiwan, '3d 3c 3h 3s 4d', '2h 2s'), isTrue);
      expect(beats(taiwan, '4c 5c 6c 7c 8c', '2d 2h 2s'), isTrue);
      expect(beats(taiwan, '4c 5c 6c 7c 8c', '3d 3c 3h 3s 4d'), isTrue, reason: 'a straight flush beats four of a kind');
      expect(beats(taiwan, '3d 3c 3h 3s 4d', '4c 5c 6c 7c 8c'), isFalse);
      expect(beats(taiwan, '9d 9c 9h 9s 4d', '3d 3c 3h 3s 4h'), isTrue, reason: 'higher four of a kind');
    });

    test('Taiwan: a five-card reply must be the kind led, unless it is a bomb', () {
      expect(beats(taiwan, '3h 5h 7h 9h Jh', '3d 4c 5h 6s 7d'), isFalse, reason: 'flush on a straight');
      expect(beats(taiwan, '4d 4c 4h 5d 5c', '3h 5h 7h 9h Jh'), isFalse, reason: 'full house on a flush');
      expect(beats(taiwan, '4d 5c 6h 7s 8d', '3d 4c 5h 6s 7d'), isTrue, reason: 'higher straight');
      expect(beats(taiwan, '6d 6c 6h 6s 3h', '3d 4c 5h 6s 7d'), isTrue,
          reason: 'four of a kind is a bomb');
    });
  });

  group('move generation', () {
    final presets = {'standard': standard, 'Hong Kong': hongKong, 'Taiwan': taiwan, 'Pusoy Dos': pusoy};

    // Every subset of 1, 2, 3 or 5 cards, classified one by one. Each play
    // maps to its ordering key as well: Play equality ignores the key, so
    // comparing keys is what catches a generator that orders a play
    // differently from classifyCodes (which rebuilds plays from history and
    // JSON), where beats() would then give two answers for the same cards.
    Map<String, int> bruteForce(BigTwoRules r, List<int> hand, Play? current) {
      final out = <String, int>{};
      void rec(int start, List<int> pick) {
        if (pick.length == 1 || pick.length == 2 || pick.length == 3 || pick.length == 5) {
          final p = r.classifyCodes(pick);
          if (p != null && r.beats(p, current)) out[keyed(p)] = p.key;
        }
        if (pick.length == 5) return;
        for (var i = start; i < hand.length; i++) {
          rec(i + 1, [...pick, hand[i]]);
        }
      }

      rec(0, []);
      return out;
    }

    for (final entry in presets.entries) {
      test('${entry.key}: every lead and every reply to each kind matches a brute-force search', () {
        final r = entry.value;
        final rng = GameRandom(entry.key.hashCode & 0xffff);
        for (var trial = 0; trial < 12; trial++) {
          final deck = List<int>.generate(52, (i) => i);
          rng.shuffle(deck);
          // Every hand size a deal can have: 13, 17 and 21 cards.
          final size = const [13, 17, 21][trial % 3];
          final hand = deck.sublist(0, size)..sort();
          final masks = masksOf(hand);
          final leads = r.playsFrom(masks, 0, null);
          expect(keysOf(leads), bruteForce(r, hand, null),
              reason: 'leads from ${hand.map(r.cardOf).map((c) => c.short)}');
          expect(leads.length, leads.toSet().length, reason: 'no duplicates');
          // Replies: to a sample of plays made from the other cards.
          final others = deck.sublist(size, size + 20)..sort();
          final targets = r.playsFrom(masksOf(others), 0, null);
          for (var k = 0; k < targets.length; k += (targets.length ~/ 25) + 1) {
            final t = targets[k];
            expect(keysOf(r.playsFrom(masks, 0, t)), bruteForce(r, hand, t), reason: 'replies to $t');
          }
        }
      });
    }

    test('replies to each kind: only bigger plays of the same size', () {
      final hand = masksOf([for (final c in parseCards('3d 3c 5h 7s 7d 8c 9h Ts Jd Qd 2s 2h Kd')) standard.codeOf(c)]);
      expect(labels(standard.playsFrom(hand, 0, play(standard, 'Qs'))), ['Kd', '2h', '2s']);
      expect(labels(standard.playsFrom(hand, 0, play(standard, '7c 7h'))), ['7d 7s', '2h 2s'],
          reason: 'the pair with the spade beats the pair of the same rank with the heart');
      expect(standard.playsFrom(hand, 0, play(standard, '4d 4c 4h')), isEmpty);
      expect(labels(standard.playsFrom(hand, 0, play(standard, '4d 5c 6h 7s 8d'))),
          containsAll(['7d 8c 9h Ts Jd', '7s 8c 9h Ts Jd']));
      expect(labels(standard.playsFrom(hand, 0, play(standard, '4d 5c 6h 7s 8d'))), isNot(contains('5h 7d 8c 9h Ts')),
          reason: 'not a run');
    });

    test('maxSize limits the plays (used for opponents with few cards)', () {
      final hand = masksOf([for (final c in parseCards('3d 3c 3h 4s 5d 6c 7h')) standard.codeOf(c)]);
      final plays = standard.playsFrom(hand, 0, null, maxSize: 2);
      expect(plays.every((p) => p.size <= 2), isTrue);
      expect(plays.where((p) => p.size == 2), hasLength(3));
    });
  });
}

/// A play's identity (kind and cards) as text, for maps keyed by play.
String keyed(Play p) => '${p.kind.name} ${p.codes.join(',')}';

/// Each play's ordering key, by identity.
Map<String, int> keysOf(Iterable<Play> plays) => {for (final p in plays) keyed(p): p.key};
