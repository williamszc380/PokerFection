// ignore_for_file: avoid_print

// Blackjack bot matches, house edges and coach timing.
//
// Bots play against the dealer over many rounds (every seat at the same
// level, each its own bet of 1), and the tool prints the average result
// per round in bets next to the exact house edge of the bot's strategy
// (fresh shoe every round, no insurance), so you can see Hard lose about
// the house edge and Easy lose much more. Every round is seeded.
//
//   dart run tool/games/blackjack_match.dart --rounds 1000000
//   dart run tool/games/blackjack_match.dart --level easy --preset singleDeck
//   dart run tool/games/blackjack_match.dart --edges
//   dart run tool/games/blackjack_match.dart --coach-timing 300
//
// Options:
//   --level easy|medium|hard|all   (default all)
//   --rounds N                     rounds per level (default 200000)
//   --seats N                      seats at the table, 1-7 (default 3)
//   --preset standard|vegasStrip|downtown|atlanticCity|european|singleDeck
//   --csm                          continuous shuffler instead of a cut card
//   --seed N                       (default 1)
//   --edges                        house edges of the presets and of the
//                                  Wizard of Odds rule sets the tests use
//   --coach-timing N               time the coach (both modes) on N
//                                  decisions from Hard-bot play
//   --chart                        print the preset's basic strategy chart
import 'dart:math' as math;

import 'package:pokerfection/src/games/blackjack/blackjack.dart';

void main(List<String> args) {
  String opt(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  var rules = BlackjackRules.preset(BlackjackPreset.values.byName(opt('preset', 'standard')));
  if (args.contains('--csm')) rules = rules.copyWith(continuousShuffle: true);
  final seed = int.parse(opt('seed', '1'));
  if (args.contains('--edges')) {
    edges();
    return;
  }
  if (args.contains('--chart')) {
    final sw = Stopwatch()..start();
    final chart = BasicStrategyChart.forRules(rules);
    print('$rules  (built in ${sw.elapsedMilliseconds} ms)');
    print(chart.toText());
    print(chart.houseEdge);
    return;
  }
  final timing = int.parse(opt('coach-timing', '0'));
  if (timing > 0) {
    coachTiming(rules, timing, seed);
    return;
  }
  final rounds = int.parse(opt('rounds', '200000'));
  final seats = int.parse(opt('seats', '3'));
  final level = opt('level', 'all');
  final levels = level == 'all' ? BotLevel.values : [BotLevel.values.byName(level)];
  print(
    'Blackjack: $rules, $seats seats, $rounds rounds per level, '
    '${rules.continuousShuffle ? 'continuous shuffler' : 'cut at ${(rules.penetration * 100).round()}%'}',
  );
  for (final l in levels) {
    match(rules, l, rounds, seats, seed);
  }
}

void match(BlackjackRules rules, BotLevel level, int rounds, int seats, int seed) {
  final bot = BlackjackBot(level);
  final table = BlackjackTable(rules, seed: seed);
  final watch = Stopwatch()..start();
  final exact = level == BotLevel.hard
      ? BasicStrategyChart.forRules(rules).basicStrategyEdge()
      : houseEdgeFollowing(rules, bot.policyFor(rules));
  final edgeMs = watch.elapsedMilliseconds;
  watch.reset();
  var sum = 0.0, sumSq = 0.0, insurance = 0.0;
  var hands = 0;
  for (var r = 0; r < rounds; r++) {
    final round = table.deal(List.filled(seats, 1));
    while (!round.isOver) {
      final t = round.turn!;
      round.apply(bot.chooseAction(round.viewFor(t.seat)));
    }
    for (var s = 0; s < seats; s++) {
      final res = round.result(s);
      sum += res.net;
      sumSq += res.net * res.net;
      insurance += res.insuranceNet;
      hands++;
    }
  }
  final mean = sum / hands;
  final sd = math.sqrt(sumSq / hands - mean * mean);
  final se = sd / math.sqrt(hands);
  print(
    '  ${level.name.padRight(6)}: result ${(mean * 100).toStringAsFixed(3)}% per bet '
    '± ${(1.96 * se * 100).toStringAsFixed(3)}% (95%), exact house edge of its strategy '
    '${(exact * 100).toStringAsFixed(3)}% (fresh shoe, no insurance; insurance result '
    '${(insurance / hands * 100).toStringAsFixed(3)}%)  '
    '[${watch.elapsedMilliseconds} ms play, $edgeMs ms exact edge]',
  );
}

/// House edges: our optimal and basic-strategy numbers next to Wizard of
/// Odds' calculator (https://wizardofodds.com/games/blackjack/calculator/,
/// "optimal results" and "basic strategy with continuous shuffler").
void edges() {
  final cases = <String, (BlackjackRules, double, double)>{
    '6D S17 DAS (Standard)': (const BlackjackRules(), 0.403115, 0.406215),
    '6D H17 DAS': (const BlackjackRules(dealerHitsSoft17: true), 0.615626, 0.618726),
    '6D H17 DAS LS': (const BlackjackRules(dealerHitsSoft17: true, surrender: Surrender.late), 0.527409, 0.530509),
    '8D S17 DAS LS (Atlantic City)': (const BlackjackRules(decks: 8, surrender: Surrender.late), 0.355143, 0.357043),
    '2D H17 DAS (Downtown)': (const BlackjackRules(decks: 2, dealerHitsSoft17: true), 0.379879, 0.393879),
    '1D H17 no DAS (Single deck)': (
      const BlackjackRules(decks: 1, dealerHitsSoft17: true, doubleAfterSplit: false),
      0.151762,
      0.190462,
    ),
    '6D S17 DAS no hole card': (const BlackjackRules(holeCard: false), 0.514166, 0.517266),
  };
  print('Rule set                          optimal (WoO)          basic strategy (WoO CSM)   time');
  for (final e in cases.entries) {
    final sw = Stopwatch()..start();
    final chart = BasicStrategyChart.forRules(e.value.$1);
    final h = chart.houseEdge;
    print(
      '${e.key.padRight(33)} ${(h.optimal * 100).toStringAsFixed(4)}% (${e.value.$2.toStringAsFixed(4)}%)   '
      '${(h.basicStrategy * 100).toStringAsFixed(4)}% (${e.value.$3.toStringAsFixed(4)}%)   ${sw.elapsedMilliseconds} ms',
    );
  }
  print('\nPresets:');
  for (final p in BlackjackPreset.values) {
    final r = BlackjackRules.preset(p);
    final h = BasicStrategyChart.forRules(r).houseEdge;
    print('  ${p.name.padRight(13)} $h   ($r)');
  }
}

/// Times the coach on [n] decisions taken from Hard-bot play deep into
/// shoes (both knowledge modes each time), and lists the slowest spots.
/// Use a few thousand decisions: the slow tail (small pairs against a 2
/// or an ace, where both modes value resplits) is rare, so a few hundred
/// decisions understate it several times over.
void coachTiming(BlackjackRules rules, int n, int seed) {
  final coach = const BlackjackCoach();
  final watch = Stopwatch()..start();
  BasicStrategyChart.forRules(rules);
  print('chart for $rules: ${watch.elapsedMilliseconds} ms (once per rule set)');
  final table = BlackjackTable(rules, seed: seed);
  final bot = BlackjackBot(BotLevel.hard);
  final times = <int>[];
  final spots = <(int, String)>[];
  var differs = 0;
  while (times.length < n) {
    final round = table.deal([1, 1, 1]);
    while (!round.isOver) {
      final t = round.turn!;
      final v = round.viewFor(t.seat);
      final a = coach.analyze(v);
      times.add(a.elapsedMicros);
      spots.add((
        a.elapsedMicros,
        '${v.seats[t.seat].hands[t.hand].cards.join(' ')} v ${v.dealerUpcard} (${v.phase.name}'
            '${v.unseenSeen != v.unseenFresh && !v.seenMayRunOut ? ', both modes solved' : ''})',
      ));
      if (a.differs) differs++;
      round.apply(bot.chooseAction(v));
    }
  }
  times.sort();
  final avg = times.reduce((a, b) => a + b) / times.length;
  String ms(int micros) => (micros / 1000).toStringAsFixed(2);
  print(
    'coach (FRESH + SEEN) on ${times.length} decisions: average ${(avg / 1000).toStringAsFixed(2)} ms, '
    'median ${ms(times[times.length ~/ 2])} ms, '
    '99th percentile ${ms(times[(times.length * 0.99).floor()])} ms, '
    '99.9th percentile ${ms(times[(times.length * 0.999).floor()])} ms, '
    'max ${ms(times.last)} ms; SEEN changed the play in $differs',
  );
  spots.sort((a, b) => b.$1.compareTo(a.$1));
  print('slowest: ${[for (final s in spots.take(5)) '${s.$2} ${ms(s.$1)} ms'].join('; ')}');
}
