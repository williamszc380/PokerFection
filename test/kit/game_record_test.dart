import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/grading.dart';
import 'package:pokerfection/src/kit/seats.dart';

void main() {
  const mark = MoveMark(grade: DecisionGrade.mistake, loss: 0.12, score: 30, played: 'h9', best: 'h8');
  final record = GameRecord(
    game: 'gomoku',
    version: 1,
    seed: 77,
    rules: {'rule': 'standard', 'size': 15},
    seats: const [SeatSpec(human: true, name: 'You'), SeatSpec(human: false, level: KitLevel.hard, name: 'Ana')],
    played: DateTime.utc(2026, 10, 18, 9),
  ).withMove('h8').withMove('h9').withMark(1, mark).withExtra('coach', false);

  test('moves and marks grow together; a mark belongs to its move', () {
    expect(record.moves, ['h8', 'h9']);
    expect(record.marks, [null, mark]);
    expect(record.extra, {'coach': false});
  });

  test('a record goes to JSON and back unchanged', () {
    final back = GameRecord.fromJson(jsonDecode(jsonEncode(record.toJson())), game: 'gomoku', version: 1)!;
    expect(back.toJson(), record.toJson());
    expect(back.seats, record.seats);
    expect(back.marks[1], mark);
    expect(back.played.isAtSameMomentAs(record.played), isTrue);
  });

  test('a job gets the game up to a move: no marks, result or extra', () {
    final json = record.withResult({'winner': 0}).jobJson(upTo: 1);
    expect(json.keys, unorderedEquals(['game', 'version', 'seed', 'rules', 'seats', 'deal', 'moves']));
    expect(json['moves'], ['h8']);
    final replayed = GameRecord.fromJson(jsonDecode(jsonEncode(json)), game: 'gomoku', version: 1)!;
    expect(replayed.moves, ['h8']);
    expect(replayed.marks, [null]);
  });

  test('upTo cuts the moves and marks, and the result unless it is the whole game', () {
    final over = record.withResult({'winner': 1});
    expect(over.upTo(1).moves, ['h8']);
    expect(over.upTo(1).result, isNull);
    expect(over.upTo(2).result, {'winner': 1});
    expect(over.upTo(0).marks, isEmpty);
  });

  test('a broken record, another game or another version reads as null', () {
    final json = record.toJson();
    expect(GameRecord.fromJson(json, game: 'big_two', version: 1), isNull);
    expect(GameRecord.fromJson(json, game: 'gomoku', version: 2), isNull);
    expect(GameRecord.fromJson({...json, 'moves': 'h8 h9'}, game: 'gomoku', version: 1), isNull);
    expect(GameRecord.fromJson({...json, 'marks': [null]}, game: 'gomoku', version: 1), isNull);
    expect(GameRecord.fromJson({...json, 'seats': [{'human': 'yes'}]}, game: 'gomoku', version: 1), isNull);
    expect(GameRecord.fromJson('{}', game: 'gomoku', version: 1), isNull);
    expect(GameRecord.fromJson(null, game: 'gomoku', version: 1), isNull);
  });
}
