import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_jobs.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/game_keys.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/seats.dart';

const seats = [
  SeatSpec(human: true, name: 'Player'),
  SeatSpec(human: false, level: KitLevel.hard, name: 'Ana'),
  SeatSpec(human: false, level: KitLevel.medium, name: 'Ben'),
];

/// Saves and loads [record] the way LastGames does (through JSON text).
GameRecord? throughDisk(GameRecord record) => ddzRecordFromJson(jsonDecode(jsonEncode(record.toJson())));

void main() {
  group('move text', () {
    test('a play names the seat, the engine\'s move and the exact cards', () {
      final pair = DdzPlay(classifyPlay(parseRanks('77')).single);
      expect(ddzMoveText(2, pair, [20, 23]), '2:xpair:77|20,23');
      final read = ddzParseMove('2:xpair:77|20,23');
      expect(read.seat, 2);
      expect(read.move, pair);
      expect(read.cardIds, [20, 23]);
    });

    test('bids, calls, robs and passes carry no cards', () {
      expect(ddzMoveText(0, const DdzBid(3)), '0:b3');
      expect(ddzMoveText(1, const DdzCall(true)), '1:c1');
      expect(ddzMoveText(2, const DdzRob(false)), '2:r0');
      expect(ddzMoveText(1, const DdzPass(), [5]), '1:p');
      expect(ddzParseMove('1:p').cardIds, isNull);
    });

    test('the key leaves out the cards: any two 7s are the same move to the coach', () {
      expect(ddzMoveKey('2:xpair:77|20,23'), '2:xpair:77');
      expect(ddzMoveKey('2:xpair:77|21,22'), '2:xpair:77');
      expect(ddzMoveKey('0:b2'), '0:b2');
    });

    test('text that is not a move is refused', () {
      for (final bad in ['', 'xpair:77', '3:p', 'a:b1', '0:b9', '0:xpair:78', '0:xpair:77|a,b']) {
        expect(() => ddzParseMove(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('a deal\'s record', () {
    test('a new record holds the rules, the cards as dealt and no moves', () {
      final record = ddzNewRecord(seed: 42, rules: DdzRules.app, seats: seats, firstBidder: 1);
      expect(record.game, GameKeys.doudizhu);
      expect(record.version, ddzRecordVersion);
      expect(record.rules, DdzRules.app.toJson());
      expect(record.deal.keys, containsAll(['hands', 'kitty', 'firstBidder']));
      expect(record.deal.keys, isNot(contains('moves')));
      expect(record.moves, isEmpty);
      final game = ddzReplay(record);
      expect(game.firstBidder, 1);
      expect([for (final h in game.hands) h.length], [17, 17, 17]);
      expect(game.kitty, hasLength(3));
    });

    test('the same seed deals the same cards', () {
      final a = ddzNewRecord(seed: 7, rules: DdzRules.standard, seats: seats, firstBidder: 0);
      final b = ddzNewRecord(seed: 7, rules: DdzRules.standard, seats: seats, firstBidder: 0);
      expect(jsonEncode(a.deal), jsonEncode(b.deal));
    });

    test('a whole deal survives saving and loading, and replays to the same end', () {
      for (final seed in [1, 2, 3]) {
        final record = ddzSampleGame(seed);
        final loaded = throughDisk(record)!;
        expect(jsonEncode(loaded.toJson()), jsonEncode(record.toJson()));
        final game = ddzReplay(loaded);
        expect(game.phase, DdzPhase.finished);
        expect(game.history, hasLength(record.moves.length));
      }
    });

    test('in the engine\'s own JSON it is exactly what the engine writes for the same deal', () {
      final record = ddzSampleGame(5);
      final game = ddzReplay(record);
      expect(jsonEncode(ddzEngineJson(record)), jsonEncode(game.toJson()));
      // And the engine reads it back to the same game.
      expect(jsonEncode(DdzGame.fromJson(ddzEngineJson(record)).toJson()), jsonEncode(game.toJson()));
    });

    test('the cards the player picked are the cards replayed (suits included)', () {
      var record = ddzNewRecord(seed: 11, rules: DdzRules.standard, seats: seats, firstBidder: 0);
      final game = ddzReplay(record);
      record = record.withMove(ddzMoveTextFor(game, const DdzBid(3)));
      game.act(const DdzBid(3));
      // Lead the highest-suited card of the lowest rank, not the engine's default.
      final low = game.hands[0].first;
      final sameRank = game.hands[0].where((id) => rankOfId(id) == rankOfId(low)).toList();
      final picked = sameRank.last;
      final solo = DdzPlay(classifyPlay([rankOfId(picked)]).single);
      record = record.withMove(ddzMoveTextFor(game, solo, [picked]));
      final replayed = ddzReplay(record);
      expect(replayed.history.last.cardIds, [picked]);
      expect(replayed.hands[0], isNot(contains(picked)));
    });

    test('a position is the record cut at a move: the job sees the game up to it', () {
      final record = ddzSampleGame(2);
      final cut = record.upTo(10);
      final game = ddzReplay(cut);
      final whole = ddzReplay(record, upTo: 10);
      expect(jsonEncode(game.toJson()), jsonEncode(whole.toJson()));
      expect(ddzReplay(ddzRecordFromJson(record.jobJson(upTo: 10))!).history, hasLength(10));
    });

    test('call and rob deals replay too', () {
      final record = ddzSampleGame(3, rules: DdzRules.app);
      expect(ddzRulesOf(record), DdzRules.app);
      expect(ddzReplay(record).phase, DdzPhase.finished);
      expect(record.moves.first, matches(RegExp(r'^\d:c[01]$')));
    });
  });

  group('broken records are ignored, never trusted', () {
    test('another version or another game is not read', () {
      final json = ddzSampleGame(1).toJson();
      expect(ddzRecordFromJson({...json, 'version': ddzRecordVersion + 1}), isNull);
      expect(ddzRecordFromJson({...json, 'game': GameKeys.bigTwo}), isNull);
      expect(ddzRecordFromJson('not a record'), isNull);
    });

    test('a move out of turn, an illegal move or cards the seat does not hold fail the replay', () {
      final record = ddzSampleGame(1);
      final first = ddzParseMove(record.moves.first);
      final otherSeat = '${(first.seat + 1) % 3}:${first.move.encode()}';
      final broken = [
        record.copyWith(moves: [otherSeat, ...record.moves.skip(1)]),
        record.copyWith(moves: [...record.moves.take(record.moves.length - 1), '0:b3']),
        record.copyWith(moves: [for (final m in record.moves) m.contains('|') ? '${ddzMoveKey(m)}|53' : m]),
      ];
      for (final b in broken) {
        expect(ddzReplays(b), isFalse);
        expect(() => ddzReplay(b), throwsA(anything));
      }
      expect(ddzReplays(record), isTrue);
    });
  });

  group('the face-up card in a record', () {
    test('with no first bidder given, one card of the 51 dealt to the hands is face up and its holder opens', () {
      final openers = <int>{};
      for (var seed = 0; seed < 60; seed++) {
        final record = ddzNewRecord(seed: seed, rules: DdzRules.standard, seats: seats);
        final first = record.deal['firstBidder']! as int;
        final up = record.deal['faceUp']! as int;
        expect((record.deal['hands']! as List)[first] as List, contains(up));
        expect(record.deal['kitty']! as List, isNot(contains(up)));
        final game = ddzReplay(record);
        expect((game.faceUp, game.toAct), (up, first));
        openers.add(first);
      }
      expect(openers, {0, 1, 2});
    });

    test('a first bidder given still opens, with one of its own cards face up', () {
      final record = ddzNewRecord(seed: 42, rules: DdzRules.app, seats: seats, firstBidder: 1);
      final game = ddzReplay(record);
      expect(game.firstBidder, 1);
      expect(game.hands[1], contains(game.faceUp));
    });

    test('a record saved before the face-up card replays, with none', () {
      final record = ddzSampleGame(1);
      final old = GameRecord(
        game: record.game,
        version: record.version,
        seed: record.seed,
        rules: record.rules,
        seats: record.seats,
        deal: {...record.deal}..remove('faceUp'),
        moves: record.moves,
      );
      final game = ddzReplay(old);
      expect(game.faceUp, isNull);
      expect(game.phase, DdzPhase.finished);
    });
  });
}
