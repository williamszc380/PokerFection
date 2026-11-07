import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_record.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/kit/game_keys.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/seats.dart';

import 'positions.dart';

void main() {
  group('a new game', () {
    test('seats are colours: the player in the colour chosen, the bot at its level in the other', () {
      final asBlack = GomokuRecord.start(const GomokuOptions(level: KitLevel.hard), seed: 5);
      expect(asBlack.game, GameKeys.gomoku);
      expect(asBlack.version, gomokuRecordVersion);
      expect([for (final s in asBlack.seats) s.human], [true, false]);
      expect(asBlack.seats[1].level, KitLevel.hard);
      expect(asBlack.seats[0].name, 'Player', reason: "the user's seat is 'Player', never 'You'");
      expect(asBlack.seats[1].name, 'Ana');
      expect(asBlack.deal, isEmpty, reason: 'nothing is dealt in Gomoku');

      final asWhite = GomokuRecord.start(const GomokuOptions(color: GomokuColorChoice.white), seed: 5);
      expect([for (final s in asWhite.seats) s.human], [false, true]);
      expect(GomokuRecord.colorOf(0), Stone.black);
      expect(GomokuRecord.seatOf(Stone.white), 1);
    });

    test('Random is settled by the game seed: the same seed, the same colour, and both colours happen', () {
      const random = GomokuOptions(color: GomokuColorChoice.random);
      final colors = <Stone>{};
      for (var seed = 0; seed < 40; seed++) {
        final color = GomokuRecord.playerColor(GomokuColorChoice.random, seed);
        expect(GomokuRecord.playerColor(GomokuColorChoice.random, seed), color);
        final record = GomokuRecord.start(random, seed: seed);
        expect(record.seats[GomokuRecord.seatOf(color)].human, isTrue);
        colors.add(color);
      }
      expect(colors, {Stone.black, Stone.white});
    });

    test('keeps the rules as the engine writes them, and the mode and colour choice in extra', () {
      const options = GomokuOptions(rules: GomokuRules.renju, color: GomokuColorChoice.random, training: false);
      final record = GomokuRecord.start(options, seed: 1);
      expect(record.rules, GomokuRules.renju.toJson());
      expect(record.extra, {'mode': 'free', 'color': 'random'});
      expect(GomokuOptions.fromRecord(record), options.copyWith(level: KitLevel.medium));
    });
  });

  group('the codec', () {
    test('a record survives JSON exactly, moves and passes included', () {
      for (final (rules, moves) in [...sampleGames, (GomokuRules.renju, stuckRenju)]) {
        final record = GomokuRecord.start(GomokuOptions(rules: rules), seed: 9, moves: moves.split(' '));
        final copy = GomokuRecord.fromJson(jsonDecode(jsonEncode(record.toJson())))!;
        expect(copy.toJson(), record.toJson());
      }
    });

    test('replays to the game the engine plays, and matches the engine\'s own JSON', () {
      for (final (rules, moves) in sampleGames) {
        final engine = GomokuGame.fromMoves(rules, GomokuGame.parseMoves(moves));
        final record = GomokuRecord.start(GomokuOptions(rules: rules), seed: 2, moves: moves.split(' '));
        final replayed = GomokuRecord.replay(record);
        expect(replayed.toJson(), engine.toJson());
        expect(replayed.result?.winner, engine.result?.winner);
        expect({'rules': record.rules, 'moves': record.moves.join(' ')}, engine.toJson());
      }
    });

    test('a Renju game where Black had to pass replays with its pass', () {
      final record = GomokuRecord.start(
        const GomokuOptions(rules: GomokuRules.renju),
        seed: 1,
        moves: [...stuckRenju.split(' '), 'pass'],
      );
      final game = GomokuRecord.replay(record);
      expect(game.moves.last, GomokuMove.pass);
      expect(game.toMove, Stone.white);
    });

    test('a broken record, an illegal game, another game or another version is ignored', () {
      final good = GomokuRecord.start(const GomokuOptions(), seed: 1, moves: ['h8', 'h9']).toJson();
      expect(GomokuRecord.fromJson(good), isNotNull);
      expect(
        GomokuRecord.fromJson({
          ...good,
          'moves': ['h8', 'h8'],
        }),
        isNull,
        reason: 'a point played twice',
      );
      expect(
        GomokuRecord.fromJson({
          ...good,
          'moves': ['z99'],
        }),
        isNull,
        reason: 'not a point',
      );
      expect(
        GomokuRecord.fromJson({
          ...good,
          'rules': {'size': 13, 'win': 'freestyle'},
        }),
        isNull,
      );
      expect(GomokuRecord.fromJson({...good, 'version': 2}), isNull);
      expect(GomokuRecord.fromJson({...good, 'game': GameKeys.bigTwo}), isNull);
      expect(GomokuRecord.fromJson({...good, 'seats': <Object?>[]}), isNull);
      expect(GomokuRecord.fromJson('h8 h9'), isNull);
      expect(GomokuRecord.fromJson(null), isNull);
      // Renju: a forbidden point for Black isn't a legal game either.
      final renju = GomokuGame.fromMoves(GomokuRules.renju, GomokuGame.parseMoves(stuckRenju));
      final forbidden = renju.forbiddenMoves().first.notation;
      final bad = GomokuRecord.start(
        const GomokuOptions(rules: GomokuRules.renju),
        seed: 1,
        moves: [...stuckRenju.split(' '), forbidden],
      );
      expect(GomokuRecord.validate(bad), isFalse);
    });

    test('the setup reads its choices back from a record, and the defaults from an odd one', () {
      const options = GomokuOptions(
        rules: GomokuRules.standard19,
        color: GomokuColorChoice.white,
        level: KitLevel.easy,
        training: false,
      );
      expect(GomokuOptions.fromRecord(GomokuRecord.start(options, seed: 3)), options);
      final odd = GameRecord(
        game: GameKeys.gomoku,
        version: 1,
        seed: 0,
        rules: const {'size': 7},
        extra: const {'color': 'red'},
      );
      expect(GomokuOptions.fromRecord(odd), const GomokuOptions());
    });
  });
}
