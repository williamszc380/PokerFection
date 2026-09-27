import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/cards.dart';
import 'package:pokerfection/src/engine/hand_evaluator.dart';

HandValue v(String cards) => evaluateHand(parseCards(cards));

void main() {
  test('parses and prints cards', () {
    expect(PlayingCard.parse('As').toString(), 'As');
    expect(PlayingCard.parse('td').toString(), 'Td');
    expect(PlayingCard.parse('Td').rankLabel, '10');
    expect(PlayingCard.parse('Kh').isRed, isTrue);
    expect(PlayingCard.parse('Kc').isRed, isFalse);
    expect(() => PlayingCard.parse('Xx'), throwsFormatException);
  });

  test('names every category', () {
    expect(v('As Ks Qs Js Ts').describe(), 'Royal Flush');
    expect(v('5h 4h 3h 2h Ah Kc Kd').describe(), 'Straight Flush, Five high');
    expect(v('9c 9d 9h 9s Kd 2c 3c').describe(), 'Four of a Kind, Nines');
    expect(v('Kc Kd Ks 7h 7d 2c 3c').describe(), 'Full House, Kings full of Sevens');
    expect(v('Ac Jc 8c 4c 2c Kd Qd').describe(), 'Flush, Ace high');
    expect(v('Tc 9d 8h 7s 6c 2d 2h').describe(), 'Straight, Ten high');
    expect(v('Ac 2d 3h 4s 5c Kd Kh').describe(), 'Straight, Five high');
    expect(v('Qc Qd Qh 7s 4c 2d 9h').describe(), 'Three of a Kind, Queens');
    expect(v('Kc Kd 7h 7s 4c 2d 9h').describe(), 'Two Pair, Kings and Sevens');
    expect(v('Jc Jd 7h 5s 4c 2d 9h').describe(), 'Pair of Jacks');
    expect(v('Ac Jd 7h 5s 4c 2d 9h').describe(), 'Ace High');
  });

  test('categories rank in the right order', () {
    final ascending = [
      v('Ac Jd 7h 5s 4c 2d 9h'), // high card
      v('Jc Jd 7h 5s 4c 2d 9h'), // pair
      v('Kc Kd 7h 7s 4c 2d 9h'), // two pair
      v('Qc Qd Qh 7s 4c 2d 9h'), // trips
      v('Ac 2d 3h 4s 5c Kd Kh'), // straight
      v('Ac Jc 8c 4c 2c Kd Qd'), // flush
      v('Kc Kd Ks 7h 7d 2c 3c'), // full house
      v('9c 9d 9h 9s Kd 2c 3c'), // quads
      v('5h 4h 3h 2h Ah Kc Kd'), // straight flush
    ];
    for (var i = 1; i < ascending.length; i++) {
      expect(ascending[i] > ascending[i - 1], isTrue, reason: '${ascending[i]} vs ${ascending[i - 1]}');
    }
  });

  test('full house takes the best trips and the best pair', () {
    expect(v('Kc Kd Ks 7h 7d 7c Ac').describe(), 'Full House, Kings full of Sevens');
    expect(v('5c 5d 5s Qh Qd 9c 9d').describe(), 'Full House, Fives full of Queens');
  });

  test('kickers break ties', () {
    expect(v('Ac Ad Kh 7s 4c 3d 2h') > v('Ac Ad Qh Js Tc 3d 2h'), isTrue);
    // With three pairs, the best two count and the third pair can be the kicker.
    expect(v('Kc Kd 7h 7s 5c 5d 2h') > v('Kc Kd 7h 7s 4c 3d 2h'), isTrue);
    expect(v('Ah 9h 7h 5h 3h 2h Kd') == v('Ah 9h 7h 5h 3h Kd Qs'), isTrue);
  });

  test('the wheel is the lowest straight', () {
    expect(v('6c 5d 4h 3s 2c') > v('5c 4d 3h 2s Ac'), isTrue);
    expect(v('Ac Kd Qh Js Tc') > v('Kc Qd Jh Ts 9c'), isTrue);
  });

  test('players who both play the board tie', () {
    const board = 'Ac Kd Qh Js Tc';
    expect(v('$board 2c 3d') == v('$board 4h 5s'), isTrue);
  });
}
