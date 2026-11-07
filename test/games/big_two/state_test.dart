// The flow of a deal: dealing, the first play, passing and new leads, the
// optional rules, the end and the score. Rule quotes are from Pagat
// (https://www.pagat.com/climbing/bigtwo.html) unless noted.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';

import 'helpers.dart';

void main() {
  final standard = BigTwoRules.standard();

  group('dealing', () {
    test('four players get 13 cards each and the holder of the 3♦ leads', () {
      final s = BigTwoState.deal(standard, seed: 7);
      expect([for (var i = 0; i < 4; i++) s.countOf(i)], [13, 13, 13, 13]);
      final all = {for (var i = 0; i < 4; i++) ...s.handOf(i)};
      expect(all, hasLength(52));
      expect(s.handOf(s.toMove), contains(Card.parse('3d')));
      expect(s.firstPlay, isTrue);
    });

    test('the same seed gives the same deal, a different seed a different one', () {
      final a = BigTwoState.deal(standard, seed: 42);
      final b = BigTwoState.deal(standard, seed: 42);
      final c = BigTwoState.deal(standard, seed: 43);
      for (var i = 0; i < 4; i++) {
        expect(a.handOf(i), b.handOf(i));
      }
      expect(a.handOf(0), isNot(c.handOf(0)));
    });

    test('Taiwan and Pusoy Dos start with the 3♣, the lowest card under their suit order', () {
      for (final rules in [BigTwoRules.taiwan(), BigTwoRules.pusoyDos()]) {
        final s = BigTwoState.deal(rules, seed: 3);
        expect(s.handOf(s.toMove), contains(Card.parse('3c')));
        expect(s.legalMoves().every((m) => m.cards.contains(Card.parse('3c'))), isTrue);
      }
    });

    test('three players: 17 each, and the face-up last card goes to the holder of the 3♦', () {
      final rules = BigTwoRules.standard(players: 3);
      for (var seed = 0; seed < 30; seed++) {
        final s = BigTwoState.deal(rules, seed: seed);
        final counts = [for (var i = 0; i < 3; i++) s.countOf(i)]..sort();
        expect(counts, [17, 17, 18]);
        expect(s.countOf(s.extraSeat), 18);
        expect(s.handOf(s.extraSeat), contains(Card.parse('3d')));
        expect(s.toMove, s.extraSeat);
      }
    });

    test('three players: if the face-up card is the 3♦ itself, the 3♣ holder takes it', () {
      final rules = BigTwoRules.standard(players: 3);
      final deck = [for (final c in fullDeck) if (c != Card.parse('3d')) c];
      final hands = [deck.sublist(0, 17), deck.sublist(17, 34), deck.sublist(34, 51)];
      final holder3c = hands.indexWhere((h) => h.contains(Card.parse('3c')));
      final s = BigTwoState.fromHands(rules, hands, extra: Card.parse('3d'));
      expect(s.extraSeat, holder3c);
      expect(s.handOf(holder3c), containsAll([Card.parse('3d'), Card.parse('3c')]));
      expect(s.toMove, holder3c);
    });

    test('two players: 13, 17 or 21 cards each, the rest unused, and the lowest card dealt starts', () {
      for (final each in [13, 17, 21]) {
        final rules = BigTwoRules.standard(players: 2, cardsEach: each);
        final s = BigTwoState.deal(rules, seed: each);
        expect([s.countOf(0), s.countOf(1)], [each, each]);
        final lowest = [...s.handCodesOf(0), ...s.handCodesOf(1)].reduce((a, b) => a < b ? a : b);
        expect(s.startCode, lowest);
        expect(s.legalMoves().every((m) => m.containsCode(lowest)), isTrue);
      }
      expect(() => BigTwoRules.standard(players: 2, cardsEach: 15), throwsArgumentError);
      expect(() => BigTwoRules(players: 5), throwsArgumentError);
    });
  });

  group('the first play', () {
    test('must include the 3♦: "either by itself or as part of a legal combination"', () {
      final s = dealOf(standard, [
        '3d 3s 4c 5h 6s 7d 9c 9h 9s Kd Kh 2s Ac',
        '3c 4d 5d 6d 7c 8c 8d Tc Jc Qc Kc Ad 2d',
        '3h 4h 5c 6c 7h 8h 9d Td Jd Qd Ks Ah 2h',
        '4s 5s 6h 7s 8s Th Ts Jh Js Qh Qs As 2c',
      ]);
      expect(s.toMove, 0);
      final moves = s.legalMoves();
      expect(moves, isNotEmpty);
      expect(moves.every((m) => m.cards.contains(Card.parse('3d'))), isTrue);
      expect(labels(moves), containsAll(['3d', '3d 3s', '3d 4c 5h 6s 7d']));
      expect(moves, isNot(contains(Play.pass)), reason: 'the leader cannot pass');
      expect(() => s.apply(play(standard, '4c')), throwsStateError);
    });

    test('with the rule off the holder of the 3♦ still leads, but may lead anything', () {
      final rules = standard.copyWith(mustPlayStartCard: false);
      final s = BigTwoState.deal(rules, seed: 11);
      expect(s.handOf(s.toMove), contains(Card.parse('3d')));
      expect(s.legalMoves().any((m) => !m.cards.contains(Card.parse('3d'))), isTrue);
    });

    test('a chosen leader (for "winner starts the next deal") may lead anything', () {
      final s = BigTwoState.deal(standard, seed: 5, leader: 2);
      expect(s.toMove, 2);
      expect(s.firstPlay, isFalse);
      expect(s.legalMoves().length, greaterThan(1));
    });
  });

  group('passing and new leads', () {
    BigTwoState small({BigTwoRules? rules}) => dealOf(rules ?? standard, [
          '3d 6d 9d',
          '4d 7d Td',
          '5d 8d Jd',
          '3c 6c 9c',
        ], leader: 0);

    test('passing never locks you out in the standard game; after three passes the last player leads', () {
      final s = small();
      playMoves(s, ['3d', '4d', 'pass', 'pass']);
      expect(s.toMove, 0);
      expect(s.legalMoves(), contains(Play.pass));
      expect(s.legalMoves().any((m) => m.cards.first == Card.parse('6d')), isTrue,
          reason: 'seat 0 passed nothing yet and may still beat the 4♦');
      playMoves(s, ['pass']);
      expect(s.toMove, 1);
      expect(s.current, isNull, reason: '"all but one of the players pass in succession": seat 1 leads');
      expect(s.legalMoves(), isNot(contains(Play.pass)));
    });

    test('a player who passed may play on a later turn of the same trick', () {
      final s = small();
      playMoves(s, ['3d', 'pass', '5d', '6c', '9d']);
      expect(s.toMove, 1);
      expect(s.legalMoves().any((m) => !m.isPass), isTrue);
      playMoves(s, ['Td']);
      expect(s.current, play(standard, 'Td'));
    });

    test('pass lock-out: "A player who has passed is not allowed to play cards in subsequent turns of the same trick"', () {
      final s = small(rules: standard.copyWith(passLockout: true));
      playMoves(s, ['3d', 'pass', '5d', '6c', '9d']);
      expect(s.toMove, 1);
      expect(s.legalMoves(), [Play.pass], reason: 'seat 1 passed earlier in this trick');
      playMoves(s, ['pass', 'pass', '9c', 'pass', 'pass']);
      expect(s.toMove, 2);
      expect(s.legalMoves(), [Play.pass], reason: 'seat 2 passed earlier, though its J♦ would beat the 9♣');
      playMoves(s, ['pass']);
      expect(s.toMove, 3, reason: 'everyone else passed: the 9♣ wins the trick');
      expect(s.current, isNull);
      expect(s.lockedMask, 0, reason: 'a new trick unlocks everyone');
    });
  });

  group('the last-card rule', () {
    final rules = standard.copyWith(lastCardRule: true);

    test('before a player with one card, a single you play must be your highest', () {
      final s = dealOf(rules, ['3d 6d 9s', 'Kd', '4c 5c', '7c 8c'], leader: 0);
      expect(labels(s.legalMoves().where((m) => m.size == 1)), ['9s']);
      s.apply(legalMove(s, '9s'));
      expect(s.history.last.forcedHighest, isTrue);
    });

    test('a multi-card play is still allowed, and following you may pass', () {
      final s = dealOf(rules, ['3d 3s 9s', 'Kd', '4c 5c', '7c 8c'], leader: 0);
      expect(labels(s.legalMoves()), containsAll(['3d 3s', '9s']));
      expect(labels(s.legalMoves()), isNot(contains('3d')));
    });

    test('playing the forced highest single tells everyone you hold nothing higher', () {
      final s = dealOf(rules, ['3d 6d 9s', 'Kd', '4c 5c', '7c 8c'], leader: 0);
      s.apply(legalMove(s, '9s'));
      final view = s.viewFor(2);
      expect(view.bounds[0], rules.codeOf(Card.parse('9s')));
      expect(CardCounter.of(view).capOf(0), Card.parse('9s'));
    });

    test('off by default', () {
      final s = dealOf(standard, ['3d 6d 9s', 'Kd', '4c 5c', '7c 8c'], leader: 0);
      expect(labels(s.legalMoves()), containsAll(['3d', '6d', '9s']));
    });
  });

  group('the end of the deal', () {
    test('the first player to empty their hand wins at once', () {
      final rules = BigTwoRules.standard(players: 2, cardsEach: 13);
      final s = dealOf(rules, [
        '3d 4d 5d 6d 7d 8c 8h 8s 9c 9h 2s 2h 2c',
        '3c 4c 5c 6c 7c 3h 4h 5h 6h 7h Ts Js Qs',
      ]);
      playMoves(s, ['3d 4d 5d 6d 7d', 'pass', '8c 8h 8s 9c 9h', 'pass']);
      expect(s.isOver, isFalse);
      playMoves(s, ['2c 2h 2s']);
      expect(s.isOver, isTrue);
      expect(s.winner, 0);
      expect(s.legalMoves(), isEmpty);
      final r = s.result;
      expect(r.cardsLeft, [0, 13]);
      expect(r.penalties, [0, 39], reason: '"three points per card (i.e. 39 points) if you have all 13"');
      expect(r.scores, [39, -39]);
    });

    test('the result is not available before the end', () {
      expect(() => BigTwoState.deal(standard, seed: 1).result, throwsStateError);
    });

    test('a dragon (one card of every rank) wins outright in Hong Kong, not in the standard game', () {
      final hands = [
        '3d 4d 5d 6d 7d 8d 9d Td Jd Qd Kd Ad 2d',
        '3c 4c 5c 6c 7c 8c 9c Tc Jc Qc Kc Ac 2c',
        '3h 4h 5h 6h 7h 8h 9h Th Jh Qh Kh Ah 2h',
        '3s 4s 5s 6s 7s 8s 9s Ts Js Qs Ks As 2s',
      ];
      final hk = dealOf(BigTwoRules.hongKong(), hands);
      expect(hk.isOver, isTrue);
      expect(hk.winner, 0, reason: 'everyone has a dragon here; the first in turn order from the leader wins');
      expect(hk.result.dragon, isTrue);
      expect(dealOf(standard, hands).isOver, isFalse);
    });

    test('a dragon is a dealt 13-card hand: bigger hands that cover every rank are not one', () {
      // Pagat: "a player who is dealt a dragon, which is one card of each
      // rank ... immediately wins". With 17 or 21 cards most hands cover
      // every rank, which would end many deals before any play.
      final two = BigTwoRules.hongKong(players: 2, cardsEach: 17);
      final big = dealOf(two, [
        '3d 4d 5d 6d 7d 8d 9d Td Jd Qd Kd Ad 2d 3c 4c 5c 6c',
        '3h 4h 5h 6h 7h 8h 9h Th Jh Qh Kh Ah 2h 3s 4s 5s 6s',
      ]);
      expect(big.isOver, isFalse);
      for (final r in [
        BigTwoRules.hongKong(players: 3),
        BigTwoRules.hongKong(players: 2, cardsEach: 21),
        BigTwoRules.hongKong(players: 2, cardsEach: 17),
      ]) {
        var dragons = 0;
        for (var seed = 0; seed < 1000; seed++) {
          if (BigTwoState.deal(r, seed: seed).dragonWin) dragons++;
        }
        expect(dragons, 0, reason: '${r.players} players with ${r.cardsEach} cards each');
      }
      final small = dealOf(BigTwoRules.hongKong(players: 2, cardsEach: 13), [
        '3d 4c 5d 6d 7d 8d 9d Td Jd Qd Kd Ad 2d',
        '3c 4d 5c 6c 7c 8c 9c Tc Jc Qc Kc Ac 2c',
      ]);
      expect(small.winner, 0, reason: 'two players with 13 cards each can be dealt a dragon');
    });

    test('Taiwan: a dragon does not win before play (Chinese Wikipedia makes it a playable cut, not built yet)', () {
      final hands = [
        '3d 4d 5d 6d 7d 8d 9d Td Jd Qd Kd Ad 2d',
        '3c 4c 5c 6c 7c 8c 9c Tc Jc Qc Kc Ac 2c',
        '3h 4h 5h 6h 7h 8h 9h Th Jh Qh Kh Ah 2h',
        '3s 4s 5s 6s 7s 8s 9s Ts Js Qs Ks As 2s',
      ];
      expect(BigTwoRules.taiwan().dragonWins, isFalse);
      expect(dealOf(BigTwoRules.taiwan(), hands).isOver, isFalse);
    });
  });

  group('Hong Kong: no going out with a lone 2♠', () {
    // Pagat, Hong Kong: "The deal cannot be won by playing a single ♠2 as
    // your last card."
    final hk = BigTwoRules.hongKong();

    test('on in the Hong Kong preset only', () {
      expect(hk.noTopSingleFinish, isTrue);
      expect(standard.noTopSingleFinish, isFalse);
      expect(BigTwoRules.taiwan().noTopSingleFinish, isFalse);
    });

    test('a lone 2♠ cannot be your last card, but may be played before that', () {
      final s = dealOf(hk, ['3d 9h', '2s', '4c 4h', '5c 5h'], leader: 0);
      playMoves(s, ['9h']);
      expect(s.legalMoves(), [Play.pass], reason: "the 2♠ is seat 1's last card");
      final early = dealOf(hk, ['3d 9h', '2s 6c', '4c 4h', '5c 5h'], leader: 0);
      playMoves(early, ['9h']);
      expect(labels(early.legalMoves().where((m) => !m.isPass)), ['2s']);
      final other = dealOf(hk, ['3d 9h', '2h', '4c 4h', '5c 5h'], leader: 0);
      playMoves(other, ['9h', '2h']);
      expect(other.winner, 1, reason: 'any other 2 may finish');
      final std = dealOf(standard, ['3d 9h', '2s', '4c 4h', '5c 5h'], leader: 0);
      playMoves(std, ['9h', '2s']);
      expect(std.winner, 1, reason: 'the standard game has no such rule');
    });

    test('a player left on lead with only the 2♠ passes the lead on', () {
      final s = dealOf(hk, ['3d 2s', '4c 4h', '5c 5h', '6c 6h'], leader: 0);
      playMoves(s, ['3d', 'pass', 'pass', 'pass']);
      expect(s.toMove, 0);
      expect(s.current, isNull);
      expect(s.legalMoves(), [Play.pass], reason: 'leading, but the only card cannot be played');
      s.apply(Play.pass);
      expect(s.toMove, 1);
      expect(s.current, isNull, reason: 'the next player leads anything');
      expect(s.legalMoves(), isNot(contains(Play.pass)));
      playMoves(s, ['4c 4h']);
      expect(s.winner, 1);
    });

    test('bots and the coach handle the stuck player through whole deals', () {
      final lone = hk.classify(parseCards('2s'));
      for (var seed = 0; seed < 40; seed++) {
        final s = BigTwoState.deal(hk, seed: seed);
        final bots = [for (var i = 0; i < 4; i++) BigTwoBot(BotLevel.easy, seed: seed + i)];
        while (!s.isOver) {
          s.apply(bots[s.toMove].chooseMove(s.viewFor(s.toMove)));
        }
        expect(s.winningPlay, isNot(equals(lone)));
      }
      final s = dealOf(hk, ['3d 2s', '4c 4h 7d', '5c 5h 8d', '6c 6h 9d'], leader: 0);
      playMoves(s, ['3d', 'pass', 'pass', 'pass']);
      final a = const BigTwoCoach(budget: CoachBudget.quick).analyze(s.viewFor(0));
      expect(a.best.play, Play.pass);
      expect(BigTwoBot(BotLevel.hard, seed: 1).chooseMove(s.viewFor(0)), Play.pass);
    });
  });

  group('scoring', () {
    test('Pagat penalties: 1 per card up to 9, 2 per card for 10 to 12, 3 per card for all 13', () {
      int pen(int left) => penaltyFor(standard, BigTwoState.deal(standard, seed: 1).handMasks, 3, left, 13);
      expect([for (final n in [1, 5, 9, 10, 12, 13]) pen(n)], [1, 5, 9, 20, 24, 39]);
    });

    test('optional doubling for each 2 left, and for a four of a kind or straight flush left', () {
      final twos = standard.copyWith(doubleTwosLeft: true);
      final s = dealOf(twos, ['3d', '2s 2h 4c', '5c 6c 7c 8c 9c Tc', '3s 3h 3c Kd'], leader: 0);
      expect(penaltyFor(twos, s.handMasks, 1, 3, 13), 3 * 4, reason: 'two 2s: doubled twice');
      final bombs = standard.copyWith(doubleBombLeft: true);
      final b = dealOf(bombs, ['3d', '9d 9c 9h 9s 4c', '5c 6c 7c 8c Tc', '4d 5d 6d 7d 8d'], leader: 0);
      expect(penaltyFor(bombs, b.handMasks, 1, 5, 13), 10);
      expect(penaltyFor(bombs, b.handMasks, 2, 5, 13), 5);
      expect(penaltyFor(bombs, b.handMasks, 3, 5, 13), 10, reason: 'a straight flush');
    });

    test('Pusoy Dos: the winner scores 1, doubled for each 2 in the winning play', () {
      final rules = BigTwoRules.pusoyDos();
      final s = dealOf(rules, ['2c 2s', '4c', '5c', '6c'], leader: 0);
      playMoves(s, ['2c 2s']);
      expect(s.result.scores, [4, 0, 0, 0]);
      final t = dealOf(rules, ['3c', '4c', '5c', '6c'], leader: 0);
      playMoves(t, ['3c']);
      expect(t.result.scores, [1, 0, 0, 0]);
    });

    test('penalty scores add up to zero: the winner collects what the others pay', () {
      for (var seed = 0; seed < 20; seed++) {
        final s = BigTwoState.deal(standard, seed: seed);
        final bots = [for (var i = 0; i < 4; i++) BigTwoBot(BotLevel.easy, seed: seed * 4 + i)];
        while (!s.isOver) {
          s.apply(bots[s.toMove].chooseMove(s.viewFor(s.toMove)));
        }
        expect(s.result.scores.reduce((a, b) => a + b), 0);
        expect(s.result.scores[s.winner], greaterThan(0));
      }
    });
  });

  group('views', () {
    test('a view holds only its own hand plus public facts', () {
      final s = BigTwoState.deal(standard, seed: 9);
      final leader = s.toMove;
      final v = s.viewFor((leader + 1) % 4);
      expect(v.hand, s.handOf((leader + 1) % 4));
      expect(v.counts, [13, 13, 13, 13]);
      expect(v.startCode, s.startCode, reason: 'all 52 cards are dealt, so everyone knows the 3♦ starts');
      expect(v.legalMoves(), isEmpty, reason: 'not on turn');
      expect(v.knownOtherCards, [s.startCode], reason: 'the leader shows the 3♦ until it is played');
      expect(v.unknownCodes(), hasLength(38));
      expect(s.viewFor(leader).legalMoves(), s.legalMoves());
    });

    test('a view survives a trip through plain data (for web workers)', () {
      final rules = BigTwoRules.taiwan(players: 3).copyWith(lastCardRule: true);
      final s = BigTwoState.deal(rules, seed: 14);
      final bots = [for (var i = 0; i < 3; i++) BigTwoBot(BotLevel.easy, seed: i)];
      for (var t = 0; t < 9; t++) {
        s.apply(bots[s.toMove].chooseMove(s.viewFor(s.toMove)));
      }
      final v = s.viewFor(s.toMove);
      final back = BigTwoView.fromJson(jsonDecode(jsonEncode(v.toJson())) as Map<String, Object?>);
      expect(back.rules, rules);
      expect(back.hand, v.hand);
      expect(back.counts, v.counts);
      expect(back.current, v.current);
      expect([for (final t in back.history) t.play], [for (final t in v.history) t.play]);
      expect(back.legalMoves(), v.legalMoves());
      expect(back.unknownCodes(), v.unknownCodes());
      expect(back.toJson(), v.toJson());
    });

    test('a view keeps the starting card\'s holder through plain data, and an old one without it shows none', () {
      final s = BigTwoState.deal(standard, seed: 9);
      final v = s.viewFor((s.toMove + 1) % 4);
      final json = jsonDecode(jsonEncode(v.toJson())) as Map<String, Object?>;
      final back = BigTwoView.fromJson(json);
      expect(back.startSeat, s.startSeat);
      expect(back.visibleCards, v.visibleCards);
      expect(BigTwoView.fromJson({...json}..remove('startSeat')).visibleCards, isEmpty);
    });

    test('a guessed state keeps the starting card\'s holder, so it shows the same visible cards as the view', () {
      for (final rules in [standard, BigTwoRules.standard(players: 3), BigTwoRules.standard(players: 2)]) {
        for (var seed = 0; seed < 10; seed++) {
          final s = BigTwoState.deal(rules, seed: seed);
          for (var seat = 0; seat < rules.players; seat++) {
            final v = s.viewFor(seat);
            final guess = DealSampler(v).sampleState(GameRandom(seed));
            expect(guess.startSeat, s.startSeat);
            expect(guess.visibleCards, v.visibleCards);
            expect(guess.copy().visibleCards, v.visibleCards);
          }
        }
      }
    });

    group('visible cards: the starting card until it is played, and the face-up card', () {
      test('four players: the 3♦ (the 3♣ under Taiwan and Pusoy Dos) in the leader\'s seat until the first play', () {
        for (final preset in BigTwoPreset.values) {
          final rules = BigTwoRules.preset(preset);
          final lowest = Card.parse(preset == BigTwoPreset.taiwan || preset == BigTwoPreset.pusoyDos ? '3c' : '3d');
          for (var seed = 0; seed < 5; seed++) {
            final s = BigTwoState.deal(rules, seed: seed);
            if (s.isOver) continue; // a dealt dragon
            expect(s.visibleCards, [(code: rules.codeOf(lowest), seat: s.toMove)], reason: '$preset seed $seed');
            for (var seat = 0; seat < 4; seat++) {
              expect(s.viewFor(seat).visibleCards, s.visibleCards);
            }
            s.apply(s.legalMoves().first);
            expect(s.visibleCards, isEmpty, reason: 'played, it is no longer in a hand');
            expect(s.viewFor(0).visibleCards, isEmpty);
          }
        }
      });

      test('three players: the starting card and the face-up card, one entry when they are the same card', () {
        final rules = BigTwoRules.standard(players: 3);
        var same = 0, apart = 0;
        for (var seed = 0; seed < 200 && (same == 0 || apart == 0); seed++) {
          final s = BigTwoState.deal(rules, seed: seed);
          if (s.extraCode == s.startCode) {
            same++;
            expect(s.visibleCards, [(code: s.startCode, seat: s.startSeat)]);
          } else {
            apart++;
            expect(s.visibleCards, [(code: s.startCode, seat: s.startSeat), (code: s.extraCode, seat: s.extraSeat)]);
          }
          expect(s.extraSeat, s.startSeat, reason: 'the holder of the lowest card takes the face-up card');
        }
        expect(same, greaterThan(0));
        expect(apart, greaterThan(0));
      });

      test('with "must play the starting card" off, it stays visible in the leader\'s hand until played', () {
        final r = standard.copyWith(mustPlayStartCard: false);
        final s = dealOf(r, ['3d 9s Kh 5c', '4d 6d', '4c 7c 2s', '8c 8h Ah']);
        final three = (code: r.codeOf(Card.parse('3d')), seat: 0);
        playMoves(s, ['Kh']);
        expect(s.visibleCards, [three]);
        expect(s.viewFor(2).visibleCards, [three]);
        playMoves(s, ['pass', 'pass', 'pass']);
        expect(s.visibleCards, [three], reason: 'still in the leader\'s hand');
        playMoves(s, ['3d']);
        expect(s.visibleCards, isEmpty);
        expect(s.viewFor(1).visibleCards, isEmpty);
      });
    });

    group('the starting card is public from the deal, unless a seat was chosen to lead', () {
      // Two players, 13 cards each, 26 unused: which low cards were dealt
      // at all is hidden until the lowest card dealt is found.
      final two = BigTwoRules.standard(players: 2, cardsEach: 13);
      const mine = '5s 6s 7s 8s 9s Ts Js Qs Ks As 2s 2h 2c';
      const oppA = '3d 4d 5d 6d 7d 8d 9d Td Jd Qd Kd Ad 2d';
      const oppB = '9h 9c Th Tc Jh Jc Qh Qc Kh Kc Ah Ac 8c';

      test('with a chosen leader, nobody is told the lowest card dealt, and no card is visible but the face-up one', () {
        final a = dealOf(two, [mine, oppA], leader: 0);
        final b = dealOf(two, [mine, oppB], leader: 0);
        expect(a.viewFor(0).startCode, -1);
        expect(a.viewFor(1).startCode, -1, reason: 'holding the 3♦ is no news, but holding the lowest card dealt is');
        expect(a.viewFor(0).toJson(), b.viewFor(0).toJson(), reason: 'same hand and history, same view');
        expect(a.visibleCards, isEmpty);
        expect(a.viewFor(1).visibleCards, isEmpty);
        final three = BigTwoState.deal(BigTwoRules.standard(players: 3), seed: 2, leader: 1);
        expect(three.visibleCards, [(code: three.extraCode, seat: three.extraSeat)]);
        expect(three.viewFor(0).startSeat, -1);
      });

      test('a guess may then deal the opponent any low card', () {
        final v = dealOf(two, [mine, oppB], leader: 0).viewFor(0);
        expect(DealSampler(v).pool, containsAll([two.codeOf(Card.parse('3d')), two.codeOf(Card.parse('4d'))]));
      });

      test('with two players the lowest card dealt is public from the deal, and so is its holder', () {
        // Found by naming low cards upward until someone holds one.
        final s = dealOf(two, [oppB, mine]);
        final five = two.codeOf(Card.parse('5s'));
        for (final seat in [0, 1]) {
          expect(s.viewFor(seat).startCode, five);
          expect(s.viewFor(seat).startSeat, 1);
          expect(s.viewFor(seat).visibleCards, [(code: five, seat: 1)]);
        }
        expect(s.viewFor(0).knownOtherCards, [five]);
        expect(s.viewFor(0).opponentCodes.first, five, reason: 'nothing below the lowest card dealt was dealt');
        playMoves(s, ['5s']);
        expect(s.viewFor(0).visibleCards, isEmpty);
        expect(s.viewFor(0).startCode, five, reason: 'still the lowest card dealt');
      });

      test('with "must play the starting card" off, it stays visible in the leader\'s hand until played', () {
        final r = two.copyWith(mustPlayStartCard: false);
        final s = dealOf(r, [oppA, mine]);
        final three = r.codeOf(Card.parse('3d'));
        playMoves(s, ['Kd']);
        expect(s.viewFor(1).startCode, three);
        expect(s.viewFor(1).visibleCards, [(code: three, seat: 0)]);
        s.apply(Play.pass);
        playMoves(s, ['3d']);
        expect(s.viewFor(1).visibleCards, isEmpty, reason: 'played, it is no longer in a hand');
      });

      test('three and four players: every card is dealt, so the starting card is always public', () {
        for (final r in [BigTwoRules.standard(), BigTwoRules.standard(players: 3)]) {
          final s = BigTwoState.deal(r, seed: 3, leader: 1);
          for (var seat = 0; seat < r.players; seat++) {
            expect(s.viewFor(seat).startCode, 0);
          }
        }
      });

      test('a guess for a seat not on turn gives the leader the starting card', () {
        final s = BigTwoState.deal(standard, seed: 9);
        final v = s.viewFor((s.toMove + 1) % 4);
        final rng = GameRandom(4);
        for (var i = 0; i < 50; i++) {
          final guess = DealSampler(v).sampleState(rng);
          expect(guess.handCodesOf(s.toMove), contains(0));
          expect(guess.legalMoves(), isNotEmpty);
        }
      });
    });

    test('views update with every play', () {
      final s = BigTwoState.deal(standard, seed: 9);
      final first = s.legalMoves().firstWhere((m) => m.size == 1);
      s.apply(first);
      final v = s.viewFor(s.toMove);
      expect(v.current, first);
      expect(v.isPlayed(first.codes.first), isTrue);
      expect(v.history.single.play, first);
      expect(v.unknownCodes(), hasLength(38));
    });
  });
}
