// ignore_for_file: avoid_print

// Fight the Landlord bot matches and coach timing.
//
//   dart run tool/games/ddz_match.dart [--games 200] [--seed 1] [--only hard-lord,easy-lord,hard-hard,medium,bidding,coach]
//
// Matches skip the auction (seat 0 is landlord at stake 1) so each side's
// strength shows on its own; every deal is also played by Easy vs Easy as
// the baseline, so the luck of the cards cancels out:
// - hard-lord:  Hard landlord vs Easy peasants
// - easy-lord:  Easy landlord vs Hard peasants
// - hard-hard:  Hard vs Hard (team play)
// - medium:     Medium landlord vs Easy peasants, Easy landlord vs Medium peasants
// - bidding:    full deals with the auction, Hard in seat 0 vs two Easy bots
// - coach:      the coach's time for one decision at its default budget
import 'dart:math';

import 'package:pokerfection/src/games/doudizhu/bot.dart';
import 'package:pokerfection/src/games/doudizhu/coach.dart';
import 'package:pokerfection/src/games/doudizhu/game.dart';

int games = 200;
int seed = 1;
DdzBudget hardBudget = DdzBudget.hard;

void main(List<String> args) {
  var only = <String>{'hard-lord', 'easy-lord', 'hard-hard', 'medium', 'bidding', 'coach'};
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--games':
        games = int.parse(args[++i]);
      case '--seed':
        seed = int.parse(args[++i]);
      case '--only':
        only = args[++i].split(',').toSet();
      case '--rollouts':
        hardBudget = hardBudget.copyWith(rollouts: int.parse(args[++i]));
      case '--candidates':
        hardBudget = hardBudget.copyWith(maxCandidates: int.parse(args[++i]));
      case '--exact':
        hardBudget = hardBudget.copyWith(exactCards: int.parse(args[++i]));
      case '--mismatch':
        hardBudget = hardBudget.copyWith(mismatch: double.parse(args[++i]));
    }
  }
  print('Fight the Landlord: $games deals per match, seed $seed, Hard: ${hardBudget.rollouts} rollouts, '
      '${hardBudget.maxCandidates} candidates, exact below ${hardBudget.exactCards} cards, mismatch ${hardBudget.mismatch}');
  if (only.contains('hard-lord')) match('Hard landlord vs Easy peasants', DdzLevel.hard, DdzLevel.easy);
  if (only.contains('easy-lord')) match('Easy landlord vs Hard peasants', DdzLevel.easy, DdzLevel.hard);
  if (only.contains('medium')) {
    match('Medium landlord vs Easy peasants', DdzLevel.medium, DdzLevel.easy);
    match('Easy landlord vs Medium peasants', DdzLevel.easy, DdzLevel.medium);
  }
  if (only.contains('hard-hard')) match('Hard vs Hard', DdzLevel.hard, DdzLevel.hard);
  if (only.contains('bidding')) bidding();
  if (only.contains('coach')) coachTiming();
}

final times = <DdzLevel, List<int>>{};

DdzGame deal(int i) => DdzGame.deal(random: Random(seed * 100003 + i));

DdzGame playRoles(int i, DdzLevel lord, DdzLevel peasants) {
  final d = deal(i);
  final g = DdzGame.fromCards(hands: d.hands, kitty: d.kitty, landlord: 0, stake: 1);
  DdzBot bot(DdzLevel level, int r) =>
      DdzBot(level, random: Random(r), budget: level == DdzLevel.hard ? hardBudget : null);
  final bots = [bot(lord, i * 3 + 1), bot(peasants, i * 3 + 2), bot(peasants, i * 3 + 3)];
  return playOut(g, bots, onMove: (game, move, took) {
    final seat = game.history.last.seat;
    (times[bots[seat].level] ??= []).add(took.inMicroseconds);
  });
}

void match(String name, DdzLevel lord, DdzLevel peasants) {
  times.clear();
  var lordWins = 0, baseWins = 0, lordPoints = 0, basePoints = 0;
  final watch = Stopwatch()..start();
  for (var i = 0; i < games; i++) {
    final r = playRoles(i, lord, peasants).result!;
    if (r.landlordWon) lordWins++;
    lordPoints += r.points[0];
    if (lord != DdzLevel.easy || peasants != DdzLevel.easy) {
      final b = playRoles(i, DdzLevel.easy, DdzLevel.easy).result!;
      if (b.landlordWon) baseWins++;
      basePoints += b.points[0];
    }
  }
  final pct = (100 * lordWins / games).toStringAsFixed(1);
  final base = (100 * baseWins / games).toStringAsFixed(1);
  final se = (100 * sqrt(0.25 / games)).toStringAsFixed(1);
  print('\n$name: landlord wins $pct% (Easy vs Easy on the same deals: $base%, ±$se% one s.e.)');
  print('  landlord points per deal ${(lordPoints / games).toStringAsFixed(2)} (baseline ${(basePoints / games).toStringAsFixed(2)})');
  for (final e in times.entries) {
    if (e.key == DdzLevel.easy && (lord != DdzLevel.easy || peasants != DdzLevel.easy)) {
      // includes the baseline games
    }
    final t = [...e.value]..sort();
    final avg = t.reduce((a, b) => a + b) / t.length / 1000;
    print('  ${e.key.name} move time: avg ${avg.toStringAsFixed(2)} ms, p95 ${(t[(t.length * 0.95).floor()] / 1000).toStringAsFixed(1)} ms, max ${(t.last / 1000).toStringAsFixed(1)} ms over ${t.length} moves');
  }
  print('  ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
}

void bidding() {
  var wins = 0, points = 0, lordCount = 0, thrown = 0;
  for (var i = 0; i < games; i++) {
    final g = DdzGame.deal(random: Random(seed * 7919 + i), firstBidder: i % 3);
    final bots = [
      DdzBot(DdzLevel.hard, random: Random(i), budget: hardBudget),
      DdzBot(DdzLevel.easy, random: Random(i + 1)),
      DdzBot(DdzLevel.easy, random: Random(i + 2)),
    ];
    playOut(g, bots);
    if (g.phase == DdzPhase.thrownIn) {
      thrown++;
      continue;
    }
    final r = g.result!;
    if (r.wonBy(0)) wins++;
    if (r.landlord == 0) lordCount++;
    points += r.points[0];
  }
  final played = games - thrown;
  print('\nFull deals with the auction, Hard (seat 0) vs two Easy bots: Hard wins ${(100 * wins / played).toStringAsFixed(1)}% of $played deals '
      '(landlord in ${(100 * lordCount / played).toStringAsFixed(1)}%), ${(points / played).toStringAsFixed(2)} points per deal; $thrown thrown in');
}

void coachTiming() {
  final ms = <double>[];
  final rnd = Random(seed);
  const coach = DdzCoach();
  var decisions = 0;
  for (var i = 0; decisions < 60; i++) {
    final g = DdzGame.deal(random: Random(seed * 31 + i));
    g.act(const DdzBid(3));
    final easy = DdzBot(DdzLevel.easy, random: rnd);
    // Stop at a random point of the deal and analyze it.
    final stopAt = rnd.nextInt(30);
    var k = 0;
    while (g.phase == DdzPhase.playing) {
      final v = g.viewFor(g.toAct);
      if (k++ == stopAt && v.legalMoves.length > 1) {
        final a = coach.analyze(v, random: Random(i));
        ms.add(a.elapsed.inMicroseconds / 1000);
        decisions++;
        if (decisions <= 3) {
          print('\nexample: seat ${v.seat}${v.isLandlord ? ' (landlord)' : ''}, ${a.legalMoveCount} legal moves, ${a.rollouts} rollouts, ${a.elapsed.inMilliseconds} ms');
          for (final c in a.candidates.take(4)) {
            print('  $c');
          }
        }
        break;
      }
      g.act(easy.chooseMove(v));
    }
  }
  ms.sort();
  final avg = ms.reduce((a, b) => a + b) / ms.length;
  print('\nCoach, default budget (${const DdzBudget().rollouts} rollouts): avg ${avg.toStringAsFixed(1)} ms, median ${ms[ms.length ~/ 2].toStringAsFixed(1)} ms, '
      'max ${ms.last.toStringAsFixed(1)} ms over ${ms.length} decisions');
}
