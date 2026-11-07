import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/cards.dart';
import 'package:pokerfection/src/games/doudizhu/plays.dart';
import 'package:pokerfection/src/games/doudizhu/rules.dart';

/// The single reading of [text], failing when there isn't exactly one.
Play one(String text, [DdzRules rules = DdzRules.standard]) {
  final plays = classifyPlay(parseRanks(text), rules);
  expect(plays, hasLength(1), reason: '"$text" should be exactly one play, got $plays');
  return plays.single;
}

void none(String text, [DdzRules rules = DdzRules.standard]) =>
    expect(classifyPlay(parseRanks(text), rules), isEmpty, reason: '"$text" is not a play');

void main() {
  group('ranks', () {
    test('run 3 4 5 ... K A 2, little joker, big joker', () {
      expect(parseRanks('3TA2BR'), [Rank.three, Rank.ten, Rank.ace, Rank.two, Rank.littleJoker, Rank.bigJoker]);
      expect(rankOfId(0), Rank.three);
      expect(rankOfId(51), Rank.two);
      expect(rankOfId(52), Rank.littleJoker);
      expect(rankOfId(53), Rank.bigJoker);
      expect(fullDeckCounts().reduce((a, b) => a + b), 54);
    });
  });

  group('every combination is recognised', () {
    test('solo, pair, trio', () {
      expect(one('7').type, PlayType.solo);
      expect(one('R').type, PlayType.solo);
      expect(one('22').type, PlayType.pair);
      expect(one('QQQ').type, PlayType.trio);
    });

    test('the two jokers are the rocket, not a pair', () {
      expect(one('BR').type, PlayType.rocket);
    });

    test('trio with a solo and with a pair', () {
      final ts = one('6668');
      expect(ts.type, PlayType.trioSolo);
      expect(ts.rank, parseRanks('6').single);
      expect(ts.kickers, parseRanks('8'));
      expect(one('QQQ66').type, PlayType.trioPair);
      expect(one('333R').type, PlayType.trioSolo, reason: 'a joker may be the attached solo');
    });

    test('a trio cannot carry a pair of jokers (that is the rocket)', () {
      none('333BR');
    });

    test('straights: five or more in a row from 3 to A, no 2s or jokers', () {
      final s = one('34567');
      expect((s.type, s.rank, s.length), (PlayType.straight, Rank.three, 5));
      expect(one('3456789TJQKA').length, 12);
      none('3456');
      none('TJQKA2');
      none('JQKA2');
      none('34568');
    });

    test('consecutive pairs: three or more pairs in a row', () {
      expect(one('334455').type, PlayType.pairStraight);
      expect(one('QQKKAA').length, 3);
      none('3344');
      none('KKAA22');
    });

    test('airplane: two or more consecutive trios', () {
      final a = one('333444');
      expect((a.type, a.length), (PlayType.airplane, 2));
      none('KKKAAA222');
      none('333555');
    });

    test('airplane with solo wings, which may form a pair but not match a trio', () {
      final a = one('77788836');
      expect((a.type, a.rank, a.length), (PlayType.airplaneSolos, parseRanks('7').single, 2));
      expect(a.kickers, parseRanks('36'));
      expect(one('44455599').type, PlayType.airplaneSolos, reason: 'Pagat: "may form a pair (4-4-4-5-5-5-9-9)"');
      none('33334445');
      none('333444BR');
      expect(one('333444BR', const DdzRules(rocketAsKickers: true)).type, PlayType.airplaneSolos);
      expect(one('333444555678').type, PlayType.airplaneSolos);
    });

    test('airplane with pair wings: different pairs, none matching a trio', () {
      final a = one('3334445566');
      expect((a.type, a.length), (PlayType.airplanePairs, 2));
      expect(a.kickers, parseRanks('5566'));
      none('3334445555');
      none('33344466BR');
    });

    test('three trios with three solos', () {
      final a = one('333444555789');
      expect((a.type, a.length), (PlayType.airplaneSolos, 3));
    });

    test('four trios in a row are a plain airplane, not three trios with wings', () {
      final plays = classifyPlay(parseRanks('333444555666'));
      expect(plays.map((p) => (p.type, p.length)), [(PlayType.airplane, 4)]);
    });

    test('five trios with five solos fill twenty cards', () {
      final a = one('33344455566677789TJQ');
      expect((a.type, a.length, a.size), (PlayType.airplaneSolos, 5, 20));
    });

    test('four with two solos of different ranks, and with two pairs', () {
      expect(one('666689').type, PlayType.fourTwoSolos);
      expect(one('66668899').type, PlayType.fourTwoPairs);
      expect(one('66662B').type, PlayType.fourTwoSolos, reason: 'twos and a joker can be attached');
      none('666688');
      none('6666BR');
      none('66668888');
    });

    test('four with two is switched off by the beginner rules', () {
      none('666689', DdzRules.beginner);
      none('66668899', DdzRules.beginner);
    });

    test('bomb', () {
      expect(one('2222').type, PlayType.bomb);
    });

    test('random cards are not a play', () {
      none('37');
      none('3355');
      none('3R');
      none('');
    });
  });

  group('comparing plays', () {
    Play p(String t) => one(t);

    test('same kind and length with a higher main rank wins', () {
      expect(p('8').beats(p('7')), isTrue);
      expect(p('7').beats(p('8')), isFalse);
      expect(p('7').beats(p('7')), isFalse);
      expect(p('2').beats(p('A')), isTrue);
      expect(p('B').beats(p('2')), isTrue);
      expect(p('R').beats(p('B')), isTrue);
      expect(p('4443').beats(p('3335')), isTrue, reason: 'only the trio counts, not the kicker');
      expect(p('45678').beats(p('34567')), isTrue);
      expect(p('456789').beats(p('34567')), isFalse, reason: 'straights must be the same length');
      expect(p('44455567').beats(p('33344489')), isTrue);
    });

    test('different kinds never beat each other', () {
      expect(p('88').beats(p('7')), isFalse);
      expect(p('888').beats(p('77')), isFalse);
      expect(p('8889').beats(p('777')), isFalse);
    });

    test('a bomb beats any non-bomb, a higher bomb beats a lower one', () {
      expect(p('3333').beats(p('2')), isTrue);
      expect(p('3333').beats(p('3456789TJQKA')), isTrue);
      expect(p('3333').beats(p('AAAA34')), isTrue, reason: 'four with two is not a bomb');
      expect(p('4444').beats(p('3333')), isTrue);
      expect(p('3333').beats(p('4444')), isFalse);
      expect(p('7').beats(p('3333')), isFalse);
    });

    test('four with two is not a bomb', () {
      expect(p('KKKK34').beats(p('QQQQ56')), isTrue);
      expect(p('KKKK34').beats(p('5')), isFalse);
      expect(p('3333').beats(p('KKKK34')), isTrue);
    });

    test('the rocket beats everything, even the highest bomb', () {
      expect(p('BR').beats(p('2222')), isTrue);
      expect(p('2222').beats(p('BR')), isFalse);
      expect(p('BR').beats(p('R')), isTrue);
    });
  });

  group('reading the cards a player selected', () {
    test('picks the reading that beats the play on the table', () {
      expect(readPlay(parseRanks('4446'), one('3335'))?.type, PlayType.trioSolo);
      expect(readPlay(parseRanks('4446'), one('5556')), isNull);
      expect(readPlay(parseRanks('5555'), one('3')), isNotNull);
    });

    test('encode and decode round trip', () {
      for (final t in ['3', '22', 'BR', '33344456', '666689', '3334445566', '3456789']) {
        final play = one(t);
        expect(Play.decode(play.encode()), play);
      }
    });
  });
}
