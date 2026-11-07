// Big Two bot matches and coach timing.
//
// Plays one bot (the "hero", Hard by default) against the others at a lower
// level over many deals, rotating the hero through every seat, and prints
// the hero's win rate and average points per deal (penalty scoring, so 0 is
// break-even), with the time each level takes per decision. Every deal is
// seeded, so a run can be repeated exactly.
//
//   dart run tool/games/big_two_match.dart --hero hard --field easy --deals 200
//   dart run tool/games/big_two_match.dart --hero hard --field medium --deals 200
//   dart run tool/games/big_two_match.dart --coach-timing 50
//
// Options:
//   --hero easy|medium|hard     the bot being measured (default hard)
//   --field easy|medium|hard    the other seats (default easy)
//   --deals N                   deals to play (default 100)
//   --preset standard|hongKong|taiwan|pusoyDos
//   --players 2|3|4             (default 4)
//   --cards 13|17|21            cards each with two players (default 17)
//   --playouts N                the hero's play-out budget when it is Hard
//                               (default the coach's standard budget)
//   --field-playouts N          the field's budget, Medium-style (plain play-outs)
//   --no-exact                  turn off exact endgames in the hero's play-outs
//   --flat                      rate moves by plain play-outs, without the tree
//   --inference N               weigh N guessed deals by the opponents' moves
//   --hero-noise X, --field-noise X
//                               randomness of the play-out policy (default 0.3)
//   --coach-timing N            instead of a match, time the coach's default
//                               budget on N decisions taken from Easy games
//   --seed N                    first deal's seed (default 1)
//   --fingerprint               print a checksum of seeded deals, bot games and
//                               coach answers; it must be the same natively and
//                               in JavaScript (see below)
//
// JavaScript: the tool imports no dart:io, so it also runs under Node to
// measure the web build's speed:
//   dart compile js -O2 tool/games/big_two_match.dart -o build/b2.js
//   node -e "globalThis.self=globalThis;globalThis.dartMainRunner=(m)=>m(process.argv.slice(1));require('./build/b2.js')" -- --coach-timing 50
// WebAssembly: `dart compile wasm -O2 ... -o build/b2.wasm`, then in Node
// `const app = await (await import('./build/b2.mjs')).compile(readFileSync('build/b2.wasm'));
// (await app.instantiate({})).invokeMain('--coach-timing', '50');`
//
// ignore_for_file: avoid_print
import 'dart:math' as math;

import 'package:pokerfection/src/games/big_two/big_two.dart';

void main(List<String> args) {
  String opt(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final preset = BigTwoPreset.values.byName(opt('preset', 'standard'));
  final players = int.parse(opt('players', '4'));
  final rules = BigTwoRules.preset(preset, players: players, cardsEach: int.tryParse(opt('cards', '')));
  final seed = int.parse(opt('seed', '1'));
  final timing = int.parse(opt('coach-timing', '0'));
  if (args.contains('--fingerprint')) {
    fingerprint(rules);
    return;
  }
  final playouts = int.tryParse(opt('playouts', ''));
  final exact = !args.contains('--no-exact');
  final tree = !args.contains('--flat');
  final inference = int.tryParse(opt('inference', ''));
  final budget = playouts == null && exact && tree && inference == null
      ? null
      : CoachBudget(
          playouts: playouts ?? CoachBudget.standard.playouts,
          exactEndgame: exact,
          tree: tree,
          inferencePool: inference ?? CoachBudget.standard.inferencePool,
        );
  final heroNoise = double.tryParse(opt('hero-noise', ''));
  heroPolicy = heroNoise == null ? null : HeuristicPolicy(noise: heroNoise);
  final fieldNoise = double.tryParse(opt('field-noise', ''));
  fieldPolicy = fieldNoise == null ? null : HeuristicPolicy(noise: fieldNoise);
  final fieldPlayouts = int.tryParse(opt('field-playouts', ''));
  final fieldBudget =
      fieldPlayouts == null
          ? null
          : CoachBudget(playouts: fieldPlayouts, exactEndgame: false, proofNodes: 4000, tree: false, inferencePool: 0);
  if (timing > 0) {
    coachTiming(rules, timing, seed, budget ?? CoachBudget.standard);
    return;
  }
  final hero = BotLevel.values.byName(opt('hero', 'hard'));
  final field = BotLevel.values.byName(opt('field', 'easy'));
  final deals = int.parse(opt('deals', '100'));
  match(rules, hero, field, deals, seed, budget, fieldBudget);
}

HeuristicPolicy? heroPolicy, fieldPolicy;

void match(BigTwoRules rules, BotLevel hero, BotLevel field, int deals, int seed, CoachBudget? budget,
    CoachBudget? fieldBudget) {
  final n = rules.players;
  print('Big Two: ${hero.name} vs ${n - 1} x ${field.name}, $deals deals, ${rules.players} players, '
      'straights ${rules.straights.name}${budget == null ? '' : ', hero ${budget.playouts} play-outs'}'
      '${budget != null && !budget.exactEndgame ? ' (no exact endgames)' : ''}'
      '${fieldBudget == null ? '' : ', field ${fieldBudget.playouts} play-outs'}');
  var wins = 0, points = 0, pointsSq = 0.0;
  final times = <BotLevel, List<int>>{for (final l in BotLevel.values) l: <int>[]};
  final watch = Stopwatch()..start();
  for (var d = 0; d < deals; d++) {
    final heroSeat = d % n;
    final state = BigTwoState.deal(rules, seed: seed + d);
    final bots = [
      for (var s = 0; s < n; s++)
        BigTwoBot(s == heroSeat ? hero : field,
            seed: (seed + d) * 31 + s,
            budget: s == heroSeat ? (hero == BotLevel.easy ? null : budget) : fieldBudget,
            playoutPolicy: s == heroSeat ? heroPolicy : fieldPolicy),
    ];
    while (!state.isOver) {
      final seat = state.toMove;
      final view = state.viewFor(seat);
      final t = Stopwatch()..start();
      final move = bots[seat].chooseMove(view);
      if (view.legalMoves().length > 1) times[bots[seat].level]!.add(t.elapsedMicroseconds);
      state.apply(move);
    }
    final r = state.result;
    if (r.winner == heroSeat) wins++;
    points += r.scores[heroSeat];
    pointsSq += r.scores[heroSeat] * r.scores[heroSeat].toDouble();
    if ((d + 1) % math.max(1, deals ~/ 10) == 0) {
      print('  after ${d + 1}: win ${(100 * wins / (d + 1)).toStringAsFixed(1)}%, '
          'points ${(points / (d + 1)).toStringAsFixed(2)}/deal  (${watch.elapsed.inSeconds} s)');
    }
  }
  final mean = points / deals;
  final sd = math.sqrt(math.max(0, pointsSq / deals - mean * mean));
  final p = wins / deals;
  print('Result: ${hero.name} won ${(100 * p).toStringAsFixed(1)}% '
      '(± ${(196 * math.sqrt(p * (1 - p) / deals)).toStringAsFixed(1)}, break-even ${(100 / n).toStringAsFixed(1)}%), '
      'average ${mean.toStringAsFixed(2)} points/deal (± ${(1.96 * sd / math.sqrt(deals)).toStringAsFixed(2)})');
  for (final e in times.entries) {
    if (e.value.isEmpty) continue;
    final v = e.value..sort();
    final avg = v.reduce((a, b) => a + b) / v.length;
    print('  ${e.key.name}: ${v.length} decisions, mean ${(avg / 1000).toStringAsFixed(2)} ms, '
        'median ${(v[v.length ~/ 2] / 1000).toStringAsFixed(2)} ms, max ${(v.last / 1000).toStringAsFixed(1)} ms');
  }
}

/// Times the coach on decisions from Easy-bot games: the first decision of
/// each deal plus a few later ones, so leads and follows are both covered.
void coachTiming(BigTwoRules rules, int decisions, int seed, CoachBudget budget) {
  final coach = BigTwoCoach(budget: budget);
  final easy = [for (var s = 0; s < rules.players; s++) BigTwoBot(BotLevel.easy, seed: s)];
  final times = <int>[];
  var cands = 0, maxCands = 0;
  var d = 0;
  // Warm up the JIT (no effect on compiled builds).
  coach.analyze(BigTwoState.deal(rules, seed: 999).viewFor(BigTwoState.deal(rules, seed: 999).toMove));
  while (times.length < decisions) {
    final state = BigTwoState.deal(rules, seed: seed + d++);
    var turn = 0;
    while (!state.isOver && times.length < decisions) {
      final view = state.viewFor(state.toMove);
      final legal = view.legalMoves();
      if (legal.length > 1 && turn % 7 == 0) {
        final t = Stopwatch()..start();
        final a = coach.analyze(view, seed: turn);
        times.add(t.elapsedMicroseconds);
        cands += a.candidates.length;
        maxCands = math.max(maxCands, a.candidates.length);
      }
      state.apply(easy[state.toMove].chooseMove(view));
      turn++;
    }
  }
  times.sort();
  final avg = times.reduce((a, b) => a + b) / times.length;
  print('Coach, ${budget.playouts} play-outs: ${times.length} decisions, mean ${(avg / 1000).toStringAsFixed(1)} ms, '
      'median ${(times[times.length ~/ 2] / 1000).toStringAsFixed(1)} ms, '
      '95th ${(times[(times.length * 0.95).floor().clamp(0, times.length - 1)] / 1000).toStringAsFixed(1)} ms, '
      'max ${(times.last / 1000).toStringAsFixed(1)} ms; candidates mean ${(cands / times.length).toStringAsFixed(1)}, '
      'max $maxCands');
}

/// A checksum over seeded deals, Easy-bot games and coach answers (flat and
/// tree, with and without inference). Equal checksums natively and in
/// JavaScript show the engine is deterministic across platforms.
void fingerprint(BigTwoRules rules) {
  var h = 17;
  void mix(Object o) {
    for (final unit in o.toString().codeUnits) {
      h = (h * 31 + unit) % 1000000007;
    }
  }

  final rng = GameRandom(12345);
  for (var i = 0; i < 5; i++) {
    mix(rng.nextUint32());
  }
  for (var d = 0; d < 20; d++) {
    final s = BigTwoState.deal(rules, seed: d);
    final bots = [for (var i = 0; i < rules.players; i++) BigTwoBot(BotLevel.easy, seed: d + i)];
    var turn = 0;
    while (!s.isOver) {
      final v = s.viewFor(s.toMove);
      if (d < 4 && turn % 9 == 4 && v.legalMoves().length > 1) {
        for (final budget in const [
          CoachBudget(playouts: 400, tree: false, inferencePool: 0),
          CoachBudget(playouts: 400, inferencePool: 100),
        ]) {
          final a = BigTwoCoach(budget: budget).analyze(v, seed: d * 100 + turn);
          for (final c in a.candidates) {
            mix('${c.play} ${c.expectedPoints.toStringAsFixed(6)} ${c.winChance.toStringAsFixed(6)} ${c.samples}');
          }
        }
      }
      s.apply(bots[s.toMove].chooseMove(v));
      turn++;
    }
    mix(s.result.scores);
  }
  print('Fingerprint (${rules.players} players, ${rules.straights.name}): $h');
}
