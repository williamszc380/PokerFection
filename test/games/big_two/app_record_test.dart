// The game record: rules, the deal and the moves as plain JSON, read back
// and replayed exactly.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_rules_codec.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/game_keys.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/seats.dart';

import 'helpers.dart';

List<SeatSpec> seatsFor(int players) => [
  const SeatSpec(human: true, name: 'Player'),
  for (var i = 1; i < players; i++) SeatSpec(human: false, level: KitLevel.hard, name: kitBotNames[i - 1]),
];

/// A whole deal played by Easy bots, as a record, and the engine's own game.
(GameRecord, BigTwoState) playedOut(BigTwoRules rules, int seed) {
  var record = BigTwoRecord.deal(rules: rules, seats: seatsFor(rules.players), seed: seed);
  final game = BigTwoState.deal(rules, seed: seed);
  var i = 0;
  while (!game.isOver) {
    final seat = game.toMove;
    final play = BigTwoBot(BotLevel.easy, seed: i++).chooseMove(game.viewFor(seat));
    game.apply(play);
    record = record.withMove(bigTwoMoveText(seat, play));
  }
  return (record, game);
}

void main() {
  group('rules', () {
    test('every preset at every player count reads back equal, and is recognised as that preset', () {
      for (final preset in BigTwoPreset.values) {
        for (final players in [4, 3, 2]) {
          for (final cards in BigTwoRulesCodec.cardsEachFor(players)) {
            final rules = BigTwoRules.preset(preset, players: players, cardsEach: cards);
            final json = jsonDecode(jsonEncode(BigTwoRulesCodec.encode(rules)));
            expect(BigTwoRulesCodec.decode(json), rules, reason: '$preset $players×$cards');
            expect(BigTwoRulesCodec.presetOf(rules), preset);
          }
        }
      }
    });

    test('the codec is the engine\'s own JSON', () {
      final rules = BigTwoRules.taiwan(players: 3).copyWith(passLockout: true);
      expect(BigTwoRulesCodec.encode(rules), rules.toJson());
    });

    test('changing any switch away from a preset makes the rules Custom', () {
      final rules = BigTwoRules.hongKong().copyWith(bombs: true);
      expect(BigTwoRulesCodec.presetOf(rules), isNull);
      expect(BigTwoRulesCodec.presetOf(BigTwoRules.standard().copyWith(straights: StraightRule.twoHigh)), isNull);
    });

    test('broken rules throw a FormatException', () {
      expect(() => BigTwoRulesCodec.decode(null), throwsFormatException);
      expect(() => BigTwoRulesCodec.decode({'players': 4}), throwsFormatException);
      expect(() => BigTwoRulesCodec.decode({...BigTwoRules.standard().toJson(), 'players': 7}), throwsFormatException);
    });

    test("changing the players deals that count's default: 13 each for 4, 17 for 3 and for 2", () {
      final two = BigTwoRulesCodec.withPlayers(BigTwoRules.standard(), 2);
      expect((two.players, two.cardsEach), (2, 17));
      expect(BigTwoRulesCodec.withPlayers(two.copyWith(cardsEach: 21), 3).cardsEach, 17);
      expect(BigTwoRulesCodec.withPlayers(two, 4).cardsEach, 13);
    });
  });

  group('moves', () {
    final rules = BigTwoRules.standard();

    test('a play is "<seat>:<cards>", lowest card first, and a pass "<seat>:pass"', () {
      expect(bigTwoMoveText(2, play(rules, '7h 7c')), '2:7c 7h');
      expect(bigTwoMoveText(0, play(rules, '3d 4c 5h 6s 7d')), '0:3d 4c 5h 6s 7d');
      expect(bigTwoMoveText(1, Play.pass), '1:pass');
    });

    test('a move reads back as the same play, whichever order its cards were written in', () {
      for (final text in ['2:7c 7h', '0:Ts', '3:pass', '1:3d 4c 5h 6s 7d']) {
        final (:seat, :play) = bigTwoParseMove(rules, text);
        expect(bigTwoMoveText(seat, play), text);
      }
      expect(bigTwoParseMove(rules, '2:7h 7c').play, play(rules, '7c 7h'));
    });

    test('text that is not a move, or cards that make no combination, throw', () {
      for (final bad in ['', 'pass', '4:3d', '-1:3d', 'x:3d', '0:3d 4d', '0:3x', '0:3d 3d']) {
        expect(() => bigTwoParseMove(rules, bad), throwsFormatException, reason: bad);
      }
    });

    test('a move\'s seat and cards can be read without the rules', () {
      expect(bigTwoMoveSeat('2:7c 7h'), 2);
      expect(bigTwoMoveCards('2:7c 7h'), parseCards('7c 7h'));
      expect(bigTwoMoveCards('1:pass'), isEmpty);
    });
  });

  group('records', () {
    test('a new deal\'s record holds the rules, the seats and every hand as dealt', () {
      final rules = BigTwoRules.standard();
      final record = BigTwoRecord.deal(rules: rules, seats: seatsFor(4), seed: 5, extra: {'sort': 'suit'});
      expect(record.game, GameKeys.bigTwo);
      expect(record.version, bigTwoRecordVersion);
      expect(record.seed, 5);
      expect(record.moves, isEmpty);
      expect(record.extra, {'sort': 'suit'});
      final game = BigTwoState.deal(rules, seed: 5);
      expect(record.deal['hands'], [for (var s = 0; s < 4; s++) game.handOf(s).map((c) => c.short).join(' ')]);
      expect(record.deal.containsKey('extra'), isFalse);
    });

    test('three players: the face-up card is kept apart, and goes back to the same seat on replay', () {
      final rules = BigTwoRules.standard(players: 3);
      for (final seed in [1, 2, 3, 4, 5]) {
        final record = BigTwoRecord.deal(rules: rules, seats: seatsFor(3), seed: seed);
        final hands = [for (final h in record.deal['hands']! as List) parseCards(h as String)];
        expect([for (final h in hands) h.length], [17, 17, 17]);
        expect(record.deal['extra'], isA<String>());
        final game = BigTwoState.deal(rules, seed: seed);
        final replayed = BigTwoRecord.replay(record);
        expect(replayed.extraCode, game.extraCode);
        expect(replayed.extraSeat, game.extraSeat);
        expect([for (var s = 0; s < 3; s++) replayed.handOf(s)], [for (var s = 0; s < 3; s++) game.handOf(s)]);
        expect(replayed.toMove, game.toMove);
      }
    });

    test('whole deals replay to the engine\'s own game, under every preset and player count', () {
      for (final preset in BigTwoPreset.values) {
        for (final players in [4, 3, 2]) {
          final rules = BigTwoRules.preset(preset, players: players);
          for (final seed in [7, 8]) {
            final (record, game) = playedOut(rules, seed);
            final back = GameRecord.fromJson(
              jsonDecode(jsonEncode(record.toJson())),
              game: GameKeys.bigTwo,
              version: bigTwoRecordVersion,
            )!;
            expect(back.moves, record.moves);
            final replayed = BigTwoRecord.replay(back);
            expect(replayed.isOver, isTrue, reason: '$preset $players');
            expect(replayed.result.scores, game.result.scores);
            expect([for (final t in replayed.history) bigTwoMoveText(t.seat, t.play)], record.moves);
            expect(BigTwoRecord.validate(back), isTrue);
          }
        }
      }
    });

    test('cut short, a record replays to the position before that move', () {
      final (record, _) = playedOut(BigTwoRules.standard(), 9);
      final before = BigTwoRecord.replay(record.upTo(10));
      expect(before.history, hasLength(10));
      expect(before.toMove, bigTwoMoveSeat(record.moves[10]));
      final fromJob = BigTwoRecord.replayJson(record.jobJson(upTo: 10));
      expect(fromJob.handOf(fromJob.toMove), before.handOf(before.toMove));
    });

    test('the result names the winner and each seat\'s points and cards left', () {
      final (_, game) = playedOut(BigTwoRules.standard(), 4);
      final result = BigTwoRecord.resultOf(game);
      expect(result['winners'], [game.winner]);
      expect(result['scores'], game.result.scores);
      expect(result['cardsLeft'], game.result.cardsLeft);
      expect(jsonDecode(jsonEncode(result)), result, reason: 'plain JSON');
    });

    test('a broken record does not validate: a move out of turn, an illegal move, a bad deal, a bot at seat 0', () {
      final rules = BigTwoRules.standard();
      final record = BigTwoRecord.deal(rules: rules, seats: seatsFor(4), seed: 3);
      final starter = BigTwoRecord.replay(record).toMove;
      final other = (starter + 1) % 4;
      expect(BigTwoRecord.validate(record.withMove('$other:pass')), isFalse, reason: 'not their turn');
      expect(BigTwoRecord.validate(record.withMove('$starter:pass')), isFalse, reason: 'the leader cannot pass');
      expect(BigTwoRecord.validate(record.withMove('$starter:2s')), isFalse, reason: 'the first play must hold the 3♦');
      final badDeal = GameRecord(
        game: GameKeys.bigTwo,
        version: bigTwoRecordVersion,
        seed: 1,
        rules: rules.toJson(),
        seats: seatsFor(4),
        deal: const {
          'hands': ['3d', '3d', '4c', '5c'],
        },
      );
      expect(BigTwoRecord.validate(badDeal), isFalse, reason: 'a card dealt twice');
      final botFirst = GameRecord.fromJson(
        {
          ...record.toJson(),
          'seats': [for (final s in seatsFor(4).reversed) s.toJson()],
        },
        game: GameKeys.bigTwo,
        version: bigTwoRecordVersion,
      )!;
      expect(BigTwoRecord.validate(botFirst), isFalse, reason: 'the player sits at seat 0');
    });
  });
}
