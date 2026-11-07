import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/cards.dart';
import 'package:pokerfection/src/games/doudizhu/play_gen.dart';
import 'package:pokerfection/src/games/doudizhu/plays.dart';
import 'package:pokerfection/src/games/doudizhu/rules.dart';

List<int> hand(String text) => countsOfRanks(parseRanks(text));
Play play(String text) => classifyPlay(parseRanks(text)).single;
Set<String> texts(Iterable<Play> plays) => {for (final p in plays) ranksText(p.ranks)};

/// Every play in [counts], found the slow way: try every sub-multiset.
Set<Play> bruteForce(List<int> counts, DdzRules rules) {
  final out = <Play>{};
  final pick = List<int>.filled(Rank.count, 0);
  void go(int r) {
    if (r == Rank.count) {
      final ranks = [
        for (var x = 0; x < Rank.count; x++)
          for (var i = 0; i < pick[x]; i++) x,
      ];
      out.addAll(classifyPlay(ranks, rules));
      return;
    }
    for (var n = 0; n <= counts[r]; n++) {
      pick[r] = n;
      go(r + 1);
    }
    pick[r] = 0;
  }

  go(0);
  return out;
}

void main() {
  group('leads', () {
    test('a small hand lists every play exactly once', () {
      final leads = leadPlays(hand('3334'));
      expect(texts(leads), {'3', '4', '33', '333', '3334'});
      expect(leads.toSet(), hasLength(leads.length), reason: 'no duplicates');
    });

    test('match a brute-force search over every subset, for random hands', () {
      final random = Random(7);
      for (var trial = 0; trial < 40; trial++) {
        final deck = shuffledDeck(random);
        final size = trial < 20 ? 17 : 20;
        final counts = countsOfIds(deck.take(size));
        for (final rules in [DdzRules.standard, DdzRules.beginner, const DdzRules(rocketAsKickers: true)]) {
          final generated = leadPlays(counts, rules);
          expect(generated.toSet(), hasLength(generated.length), reason: 'duplicates in ${countsText(counts)}');
          expect(generated.toSet(), bruteForce(counts, rules), reason: countsText(counts));
        }
      }
    });

    test('match brute force on airplane-heavy hands', () {
      for (final h in ['33344455566677789TJQ', '3334445556667778889T', '333444555666BR22', '3333444455556666']) {
        final counts = hand(h);
        expect(leadPlays(counts).toSet(), bruteForce(counts, DdzRules.standard), reason: h);
      }
    });
  });

  group('answers to a play', () {
    test('a solo is beaten by higher solos, bombs and the rocket', () {
      final answers = beatingPlays(hand('3 9 2 BR 5555'), play('8'));
      expect(texts(answers), {'9', '2', 'B', 'R', '5555', 'BR'});
    });

    test('pairs, trios and trios with kickers must match the kind', () {
      expect(texts(beatingPlays(hand('3399QQQ'), play('88'))), {'99', 'QQ'});
      expect(texts(beatingPlays(hand('99QQQ4'), play('8885'))), {'4QQQ', '9QQQ'});
      expect(texts(beatingPlays(hand('99QQQ44'), play('88855'))), {'44QQQ', '99QQQ'});
    });

    test('a straight is answered only by a higher straight of the same length', () {
      final answers = beatingPlays(hand('456789T'), play('34567'));
      expect(texts(answers), {'45678', '56789', '6789T'});
    });

    test('consecutive pairs of the same length', () {
      expect(texts(beatingPlays(hand('44556677'), play('334455'))), {'445566', '556677'});
    });

    test('airplanes with solo wings: every wing choice, never a trio rank', () {
      final answers = beatingPlays(hand('4445556799'), play('33344456'));
      expect(texts(answers), {'44455567', '44455569', '44455579', '44455599'});
    });

    test('airplanes with pair wings', () {
      expect(texts(beatingPlays(hand('444555 66 77 88'), play('3334448899'))),
          {'4445556677', '4445556688', '4445557788'});
    });

    test('four with two solos and two pairs', () {
      expect(texts(beatingPlays(hand('KKKK3455'), play('QQQQ67'))), {'34KKKK', '35KKKK', '45KKKK', 'KKKK'},
          reason: 'the two solos must be of different ranks');
      expect(texts(beatingPlays(hand('KKKK 33 55'), play('QQQQ6677'))), {'3355KKKK', 'KKKK'});
    });

    test('a bomb is answered only by a higher bomb or the rocket', () {
      expect(texts(beatingPlays(hand('3333 6666 BR 2'), play('5555'))), {'6666', 'BR'});
    });

    test('nothing beats the rocket', () {
      expect(beatingPlays(hand('2222 AAAA'), play('BR')), isEmpty);
    });

    test('canBeat agrees with the list of answers', () {
      final random = Random(3);
      final targets = ['3', 'A', '22', '3335', '34567', '334455', '33344456', '5555', 'BR', '666689'];
      for (var trial = 0; trial < 50; trial++) {
        final counts = countsOfIds(shuffledDeck(random).take(17));
        for (final t in targets) {
          expect(canBeat(counts, play(t)), beatingPlays(counts, play(t)).isNotEmpty,
              reason: '${countsText(counts)} vs $t');
        }
      }
    });

    test('every answer really beats the play, and none is missed', () {
      final random = Random(11);
      for (var trial = 0; trial < 30; trial++) {
        final counts = countsOfIds(shuffledDeck(random).take(20));
        final all = bruteForce(counts, DdzRules.standard);
        for (final t in ['7', 'QQ', '8889', '45678', '33344456', '3334445566', '7777', '666689']) {
          final target = play(t);
          expect(beatingPlays(counts, target).toSet(), {for (final p in all) if (p.beats(target)) p},
              reason: '${countsText(counts)} vs $t');
        }
      }
    });
  });
}
