// Bot-vs-bot Gomoku matches, with colors alternating, and per-move timing.
//
//   dart run tool/games/gomoku_match.dart --a hard --b easy --games 20
//   dart run tool/games/gomoku_match.dart --a hard --b medium --games 20 --rule standard
//   dart run tool/games/gomoku_match.dart --coach 40      (coach timing only)
//
// Options: --a/--b easy|medium|hard, --games N, --rule freestyle|standard|
// renju, --size 15|19, --seed N (openings and bot randomness), --opening N
// (random stones near the center before the bots take over, so the games
// differ), --time MS (each bot's cap per move), --coach N (time the coach
// on N positions from Medium self-play, under --rule and --size), --show
// (print each final board), --log (print every move with how it was chosen
// and its score), --only N (play just game N of the series, with the same
// opening).
import 'dart:io';
import 'dart:math';

import 'package:pokerfection/src/games/gomoku/gomoku.dart';

void main(List<String> args) {
  String? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final rules = GomokuRules(
    size: int.parse(option('--size') ?? '15'),
    winRule: WinRule.values.byName(option('--rule') ?? 'freestyle'),
  );
  final seed = int.parse(option('--seed') ?? '1');
  final cap = option('--time') == null ? null : Duration(milliseconds: int.parse(option('--time')!));
  final coachPositions = option('--coach');
  if (coachPositions != null) {
    _coachTiming(rules, int.parse(coachPositions), seed);
    return;
  }
  final a = BotLevel.values.byName(option('--a') ?? 'hard');
  final b = BotLevel.values.byName(option('--b') ?? 'easy');
  final games = int.parse(option('--games') ?? '10');
  final opening = int.parse(option('--opening') ?? '2');
  final show = args.contains('--show');
  final log = args.contains('--log');
  final only = option('--only') == null ? null : int.parse(option('--only')!);

  stdout.writeln('${rules.label}: ${a.name} (A) vs ${b.name} (B), $games games, colors alternate');
  final rng = Random(seed);
  final wins = {'A': 0, 'B': 0, 'draw': 0};
  final asBlack = {'A': 0, 'B': 0};
  final times = {'A': <int>[], 'B': <int>[]};
  final hows = {'A': <String, int>{}, 'B': <String, int>{}};
  var totalMoves = 0;
  for (var g = 0; g < games; g++) {
    final aIsBlack = g.isEven;
    final bots = {
      'A': GomokuBot(a, seed: seed * 1000 + g, maxTime: cap),
      'B': GomokuBot(b, seed: seed * 1000 + g + 500, maxTime: cap),
    };
    var game = _opening(rules, opening, rng);
    if (only != null && g + 1 != only) continue;
    while (!game.isOver) {
      final blackToMove = game.toMove == Stone.black;
      final who = blackToMove == aIsBlack ? 'A' : 'B';
      final bot = bots[who]!;
      final sw = Stopwatch()..start();
      final move = bot.chooseMove(game.viewFor(game.toMove));
      times[who]!.add(sw.elapsedMicroseconds);
      final how = bot.lastStats?.how ?? '?';
      if (log) {
        final s = bot.lastStats;
        stdout.writeln('  ${game.moves.length + 1}. $who ${move.notation} ${s?.how} score ${s?.score} depth ${s?.depth} nodes ${s?.nodes}');
      }
      hows[who]![how] = (hows[who]![how] ?? 0) + 1;
      game = game.play(move);
    }
    totalMoves += game.moves.length;
    final result = game.result!;
    String winner;
    if (result.isDraw) {
      winner = 'draw';
    } else {
      winner = (result.winner == Stone.black) == aIsBlack ? 'A' : 'B';
      if (result.winner == Stone.black) asBlack[winner] = asBlack[winner]! + 1;
    }
    wins[winner] = wins[winner]! + 1;
    stdout.writeln('game ${g + 1}: A ${aIsBlack ? 'Black' : 'White'}, ${game.moves.length} moves, '
        'winner ${winner == 'draw' ? 'draw' : '$winner (${result.winner!.name})'}');
    if (show) stdout.writeln(_picture(game));
  }
  String pct(int n) => '${(100 * n / games).toStringAsFixed(0)}%';
  stdout.writeln('\nA (${a.name}) won ${wins['A']} (${pct(wins['A']!)}), ${asBlack['A']} of them as Black');
  stdout.writeln('B (${b.name}) won ${wins['B']} (${pct(wins['B']!)}), ${asBlack['B']} of them as Black');
  stdout.writeln('draws ${wins['draw']}; average game ${(totalMoves / games).toStringAsFixed(1)} moves');
  for (final who in ['A', 'B']) {
    final t = times[who]!..sort();
    if (t.isEmpty) continue;
    final avg = t.reduce((x, y) => x + y) / t.length / 1000;
    stdout.writeln('$who (${who == 'A' ? a.name : b.name}) per move: average ${avg.toStringAsFixed(1)} ms, '
        'median ${(t[t.length ~/ 2] / 1000).toStringAsFixed(1)} ms, 95th ${(t[(t.length * 0.95).floor()] / 1000).toStringAsFixed(1)} ms, '
        'max ${(t.last / 1000).toStringAsFixed(1)} ms; how: ${hows[who]}');
  }
}

// A few random stones near the center (Black's first on it), so that
// deterministic bots play different games.
GomokuGame _opening(GomokuRules rules, int stones, Random rng) {
  final c = rules.size ~/ 2;
  var game = GomokuGame(rules).play(GomokuMove(c, c));
  while (game.moves.length < 1 + stones) {
    final m = GomokuMove(c + rng.nextInt(5) - 2, c + rng.nextInt(5) - 2);
    if (game.isLegal(m)) game = game.play(m);
  }
  return game;
}

void _coachTiming(GomokuRules rules, int positions, int seed) {
  const coach = GomokuCoach();
  final rng = Random(seed);
  final times = <int>[];
  var proven = 0;
  var done = 0;
  while (done < positions) {
    var game = _opening(rules, 2, rng);
    final bot = GomokuBot(BotLevel.medium, seed: rng.nextInt(1000));
    while (!game.isOver && done < positions) {
      final sw = Stopwatch()..start();
      final analysis = coach.analyze(game.viewFor(game.toMove));
      times.add(sw.elapsedMicroseconds);
      if (analysis.best?.isProvenWin ?? false) proven++;
      done++;
      game = game.play(bot.chooseMove(game.viewFor(game.toMove)));
    }
  }
  times.sort();
  final avg = times.reduce((x, y) => x + y) / times.length / 1000;
  stdout.writeln('coach on $positions positions: average ${avg.toStringAsFixed(0)} ms, '
      'median ${(times[times.length ~/ 2] / 1000).toStringAsFixed(0)} ms, '
      '95th ${(times[(times.length * 0.95).floor()] / 1000).toStringAsFixed(0)} ms, max ${(times.last / 1000).toStringAsFixed(0)} ms; '
      '$proven with a proven win');
}

String _picture(GomokuGame game) {
  final n = game.rules.size;
  final rows = <String>[];
  for (var y = n - 1; y >= 0; y--) {
    final row = StringBuffer('${(y + 1).toString().padLeft(2)} ');
    for (var x = 0; x < n; x++) {
      final s = game.stoneAt(x, y);
      row.write(s == null ? '. ' : (s == Stone.black ? 'X ' : 'O '));
    }
    rows.add(row.toString());
  }
  rows.add('   ${[for (var x = 0; x < n; x++) String.fromCharCode(97 + x)].join(' ')}');
  return rows.join('\n');
}
