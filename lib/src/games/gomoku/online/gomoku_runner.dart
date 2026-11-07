/// Gomoku in a room (see online_games.dart): two seats, Black and White, a
/// round is one game, and nothing is hidden. Pure Dart: it imports only the
/// engine and its view codec, so the room runs it on a host's device, in a
/// browser or in bin/server.dart alike.
///
/// Nothing is dealt, so no Random is drawn from, except to pick Black when
/// the host's rules say Random (from the room's secure Random, never a
/// seed). Every view is the whole game: the rules, Black's seat and the
/// moves (see gomoku_view_codec.dart).
library;

import 'dart:math';

import '../../../online/games/game_runner.dart';
import '../game.dart';
import '../rules.dart';
import 'gomoku_view_codec.dart';

/// Gomoku's online support. Nullable as online_games.dart expects of every
/// game's (a game without one yet is null there).
// ignore: unnecessary_nullable_for_final_variable_declarations
final OnlineGame? gomokuOnline = GomokuOnline();

/// Gomoku's rules, seats and bots in a room.
class GomokuOnline implements OnlineGame {
  /// The game's key (GameKeys.gomoku; the runner imports no kit files).
  @override
  String get key => 'gomoku';

  @override
  int get gv => gomokuOnlineGv;

  @override
  Map<String, Object?> get defaultRules => const GomokuOnlineRules().toJson();

  @override
  Map<String, Object?> readRules(Object? json) => GomokuOnlineRules.fromJson(json).toJson();

  /// Always two: Black and White, both taken for a game to start.
  @override
  SeatRange seatsFor(Map<String, Object?> rules) => const SeatRange(2, 2);

  @override
  List<String> get botLevels => const ['easy', 'medium', 'hard'];

  /// Time to look at the five in a row before the board clears.
  @override
  Duration get betweenRounds => const Duration(seconds: 5);
  @override
  Duration get maxBetweenRounds => const Duration(seconds: 15);

  @override
  GameRunner newRunner(OnlineSetup setup, Random random) =>
      GomokuRunner(GomokuOnlineRules.fromJson(setup.rules), random);
}

/// The games of Gomoku played at one room's table, Start to End game: one
/// game per round, Black moving as the rules say.
class GomokuRunner implements GameRunner {
  GomokuRunner(this.rules, this._random);

  final GomokuOnlineRules rules;
  final Random _random;

  GomokuGame? _game;
  int _black = 0;

  /// The winner of the game before (null: none yet, or a draw).
  int? _lastWinner;
  int _round = 0;

  /// The game being played (or the last one).
  GomokuGame get game => _game ?? GomokuGame(rules.rules);

  /// The hand seat playing Black this game.
  int get black => _black;

  int _seatOf(Stone color) => color == Stone.black ? _black : 1 - _black;

  @override
  void startRound(int round, List<bool> isBot) {
    if (isBot.length != 2) throw ArgumentError('Gomoku has two seats, not ${isBot.length}');
    final previous = _round == 0 ? null : _black;
    _black = switch (rules.black) {
      GomokuBlackRule.turns => (round - 1) % 2,
      GomokuBlackRule.random => _random.nextInt(2),
      // The loser of the last game; after a draw Black changes seats.
      GomokuBlackRule.loser => switch ((previous, _lastWinner)) {
        (null, _) => 0,
        (_, final int winner) => 1 - winner,
        (final int seat, null) => 1 - seat,
      },
    };
    _round = round;
    _game = GomokuGame(rules.rules);
  }

  @override
  bool get roundOver => game.isOver;

  @override
  int? get seatToAct => _game == null || game.isOver ? null : _seatOf(game.toMove);

  @override
  bool get redealt => false;

  static final _notation = RegExp(r'^(pass|[a-s][1-9][0-9]?)$');

  @override
  String? check(int seat, String move) {
    final game = _game;
    if (game == null) return 'no game yet';
    if (game.isOver) return 'the game is over';
    if (seat != seatToAct) return 'not their turn';
    // Only the notation the views use ("h8", "pass"): nothing else is read.
    if (!_notation.hasMatch(move)) return 'not a point';
    final point = GomokuMove.parse(move);
    if (game.isLegal(point)) return null;
    if (point.isPass) return 'a pass only when every point is forbidden';
    if (!point.isOn(game.rules.size)) return 'off the board';
    if (game.stoneAt(point.x, point.y) != null) return 'taken';
    return 'forbidden';
  }

  @override
  void act(int seat, String move) {
    if (check(seat, move) case final reason?) throw ArgumentError(reason);
    _game = game.play(GomokuMove.parse(move));
    if (game.result case final result?) {
      _lastWinner = result.winner == null ? null : _seatOf(result.winner!);
    }
  }

  /// No who-goes-first step: the colours are known before the game.
  @override
  int get openingMs => 0;

  /// The free point nearest the last stone (or the centre) that the side to
  /// move may take, looking ring by ring: legal, and no search at all.
  @override
  String autoMove(int seat, {bool absent = false}) {
    final game = this.game;
    if (game.mustPass) return GomokuMove.pass.notation;
    final size = game.rules.size;
    final last = game.moves.lastWhere((m) => !m.isPass, orElse: () => GomokuMove(size ~/ 2, size ~/ 2));
    for (var r = 0; r < size; r++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (max(dx.abs(), dy.abs()) != r) continue;
          final point = GomokuMove(last.x + dx, last.y + dy);
          if (game.isLegal(point)) return point.notation;
        }
      }
    }
    return game.legalMoves().first.notation;
  }

  /// A stone is put down: a moment to see it.
  @override
  int playbackMs(String move) => 350;

  @override
  Map<String, Object?> seatView(int seat) => {...gomokuPublicView(rules.rules, _black, game), 'you': seat};

  /// Everyone sees the whole board: the bots hide nothing either.
  @override
  Map<String, Object?> spectatorView({required bool seesBots}) => gomokuPublicView(rules.rules, _black, game);

  /// `{"winner": seat}`, or `{"draw": true}` for a full board.
  @override
  Map<String, Object?> roundResult() => switch (game.result?.winner) {
    final Stone stone => {'winner': _seatOf(stone)},
    null => {'draw': true},
  };

  /// A win is one point (the seats' score is their wins).
  @override
  List<num> get roundScores => [
    for (var seat = 0; seat < 2; seat++)
      if (game.result?.winner case final Stone stone when _seatOf(stone) == seat) 1 else 0,
  ];
}
