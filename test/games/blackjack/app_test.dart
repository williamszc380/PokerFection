// The glue between the engine and the app: a shoe as a game record that
// replays exactly, the background jobs that answer from such records, and
// the coach list and grades the kit shows.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_analysis_codec.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_examples.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_grading.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_jobs.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/job_registry.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';

/// A shoe played by the Hard bot (with [chart]) for [rounds] rounds, as a
/// record.
GameRecord botShoe(BasicStrategyChart chart, {int seed = 7, int rounds = 20}) {
  var record = newBlackjackRecord(rules: chart.rules, seed: seed, playerName: 'Player', dealerName: 'Dealer');
  final play = BlackjackPlay(chart.rules, shoeSeed: seed);
  final bot = BlackjackBot(BotLevel.hard, chart: chart);
  while (!play.shoeOver && play.rounds <= rounds) {
    if (play.betweenRounds && play.rounds == rounds) break;
    final move = play.betweenRounds ? dealMove : handMove(play.handToPlay!, bot.chooseAction(play.view()));
    play.apply(move);
    record = record.withMove(move);
  }
  return record;
}

/// Runs [job] on [input] the way every platform does: JSON request in,
/// JSON reply out.
Object? viaRequest(GameJob<Object?, Object?> job, Object? input) {
  final reply = jsonDecode(runJobRequest(encodeRequest(1, job, input, platform: JobPlatform.test), kitJobs)) as Map;
  if (reply['err'] != null) fail('${job.name} failed: ${reply['err']}');
  return job.decodeOutput(reply['out']);
}

/// The coach's result for [view] in [hand], as the job builds it.
BlackjackCoachResult resultFor(BlackjackView view, BasicStrategyChart chart) => BlackjackCoachResult(
  hand: view.turn!.hand,
  evenMoney: view.offersEvenMoney,
  analysis: const BlackjackCoach().analyze(view, chart: chart),
);

/// A play whose shoe starts with [top] (dealing order: player, upcard,
/// player, hole card, then draws), its first round dealt.
BlackjackPlay stackedPlay(BlackjackRules rules, String top) {
  final play = BlackjackPlay(rules, shoeSeed: 3);
  play.table.shoe.stack([for (final t in top.split(' ')) Card.parse(t)]);
  play.apply(dealMove);
  return play;
}

void main() {
  final charts = exampleCharts;
  final standard = charts.first;

  group('moves', () {
    test('a hand move is the hand number and a letter, and reads back', () {
      for (final action in BlackjackAction.values) {
        final move = handMove(2, action);
        expect(move, '2:${actionLetters[action]}');
        expect(parseHandMove(move), (hand: 2, action: action));
      }
      expect(handMove(0, BlackjackAction.split), '0:P');
      expect(handMove(0, BlackjackAction.surrender), '0:R');
      expect(handMove(0, BlackjackAction.keepPlaying), '0:K');
    });

    test('anything else is not a hand move', () {
      for (final move in ['d', '', '0', ':H', '0:X', 'a:H', '-1:H', '0:HH']) {
        expect(parseHandMove(move), isNull, reason: move);
      }
    });

    test('between rounds the only move is the deal; in a round, the legal decisions', () {
      final play = BlackjackPlay(const BlackjackRules(), shoeSeed: 1);
      expect(play.legalMoves(), [dealMove]);
      expect(play.handToPlay, isNull);
      final stacked = stackedPlay(const BlackjackRules(), 'Ts 9h 6d 7c');
      expect(stacked.legalMoves(), ['0:S', '0:H', '0:D']);
      expect(stacked.handToPlay, 0);
      expect(() => stacked.apply(dealMove), throwsStateError, reason: 'a round is being played');
      expect(() => stacked.apply('1:H'), throwsStateError, reason: 'there is no hand 1');
      expect(() => stacked.apply('0:P'), throwsStateError, reason: '16 is not a pair');
    });

    test('splitting gives hand 1, played after hand 0', () {
      final play = stackedPlay(const BlackjackRules(), '8s 6h 8d 9c Ts Tc');
      play.apply('0:P');
      expect(play.round!.seats[0].hands, hasLength(2));
      expect(play.handToPlay, 0);
      play.apply('0:S');
      expect(play.handToPlay, 1);
      expect(play.legalMoves(), contains('1:S'));
    });
  });

  group('the record', () {
    test('a played shoe replays to the same cards and winnings', () {
      final record = botShoe(standard);
      final play = BlackjackPlay.replay(record);
      expect(play.rounds, 20);
      final again = BlackjackPlay.replay(GameRecord.fromJson(record.toJson(), game: 'blackjack', version: 1)!);
      expect(again.net, play.net);
      expect(again.roundNets, play.roundNets);
      expect(again.round!.dealerCards, play.round!.dealerCards);
    });

    test('the record keeps the rules and the shoe\'s seed, and the dealer as a seat', () {
      final rules = BlackjackRules.preset(BlackjackPreset.european);
      final record = newBlackjackRecord(
        rules: rules,
        seed: 42,
        playerName: 'Player',
        dealerName: 'Dealer',
        extra: {'coachMode': 'seen'},
      );
      expect(record.game, 'blackjack');
      expect(record.version, blackjackRecordVersion);
      expect(BlackjackRules.fromJson(record.rules), rules);
      expect(record.deal, {'shoeSeed': 42});
      expect(record.seats.map((s) => s.human), [true, false]);
      expect(record.seats[dealerSeat].name, 'Dealer');
      expect(record.extra['coachMode'], 'seen');
    });

    test('a broken record is ignored or refused, never played', () {
      final good = botShoe(standard, rounds: 2).toJson();
      expect(GameRecord.fromJson({...good, 'version': 2}, game: 'blackjack', version: 1), isNull);
      expect(GameRecord.fromJson({...good, 'game': 'gomoku'}, game: 'blackjack', version: 1), isNull);
      final badMove = GameRecord.fromJson(
        {
          ...good,
          'moves': ['d', '0:Q'],
        },
        game: 'blackjack',
        version: 1,
      )!;
      expect(() => BlackjackPlay.replay(badMove), throwsStateError);
      final badRules = GameRecord.fromJson(
        {
          ...good,
          'rules': {'decks': 'six'},
        },
        game: 'blackjack',
        version: 1,
      )!;
      expect(() => BlackjackPlay.replay(badRules), throwsFormatException);
      // The check a saved shoe passes before it is used.
      expect(blackjackReplays(botShoe(standard, rounds: 2)), isTrue);
      expect(blackjackReplays(badMove), isFalse);
      expect(blackjackReplays(badRules), isFalse);
    });

    test('a move is known to answer an even-money offer from the shoe up to it, and only then', () {
      var evenMoney = 0, insurance = 0;
      for (var seed = 1; seed <= 40 && (evenMoney < 2 || insurance < 2); seed++) {
        final shoe = botShoe(standard, seed: seed, rounds: 1000);
        final play = BlackjackPlay(standard.rules, shoeSeed: seed);
        for (var i = 0; i < shoe.moves.length; i++) {
          final round = play.round;
          final offer = round != null && round.phase == RoundPhase.insurance;
          final expected = offer && play.view().offersEvenMoney;
          expect(evenMoneyAtMove(shoe, i), expected, reason: 'seed $seed, move $i');
          if (expected) evenMoney++;
          if (offer && !expected) insurance++;
          play.apply(shoe.moves[i]);
        }
      }
      expect(evenMoney, greaterThan(0), reason: 'an even-money offer was met');
      expect(insurance, greaterThan(0), reason: 'a plain insurance offer was met');
    });

    test('the shoe ends when the cut card is out, after the round', () {
      final record = botShoe(charts[3], rounds: 1000); // a single deck, cut at 60%
      final play = BlackjackPlay.replay(record);
      expect(play.shoeOver, isTrue);
      expect(play.table.shoe.needsShuffle, isTrue);
      expect(play.legalMoves(), isEmpty);
      expect(() => play.apply(dealMove), throwsStateError);
      expect(play.roundNets, hasLength(play.rounds), reason: 'every round was booked');
    });

    test('with a continuous shuffler a shoe is $continuousShuffleRounds rounds', () {
      final chart = BasicStrategyChart.fromJson({
        ...standard.toJson(),
        'rules': const BlackjackRules(continuousShuffle: true).toJson(),
      });
      final play = BlackjackPlay.replay(botShoe(chart, rounds: 1000));
      expect(play.rounds, continuousShuffleRounds);
      expect(play.shoeOver, isTrue);
    });

    test('a blackjack ends the round at the deal, and is booked', () {
      final play = stackedPlay(const BlackjackRules(), 'As 9h Kd 7c');
      expect(play.betweenRounds, isTrue);
      expect(play.net, 1.5);
      expect(play.legalMoves(), [dealMove]);
    });
  });

  group('the jobs', () {
    test('blackjack.chart gives the engine\'s chart for exactly the rules asked', () {
      const rules = BlackjackRules(penetration: 0.6);
      final chart = viaRequest(const BlackjackChartJob(), rules)! as BasicStrategyChart;
      expect(chart.rules, rules);
      expect(chart.toText(), BasicStrategyChart.forRules(rules).toText());
    });

    test('the ready-made example charts are the ones the engine builds', () {
      for (final chart in charts) {
        expect(chart.toText(), BasicStrategyChart.forRules(chart.rules).toText(), reason: '${chart.rules}');
        expect(chart.optimalEdge, BasicStrategyChart.forRules(chart.rules).optimalEdge);
      }
    });

    test('the coach job answers the decision the record stops at, from that seat\'s view only', () {
      final record = botShoe(standard, rounds: 6);
      for (var i = 0; i < record.moves.length; i++) {
        final play = BlackjackPlay.replay(record.upTo(i));
        if (play.betweenRounds) continue;
        final result =
            viaRequest(const BlackjackCoachJob(), BlackjackDecisionInput(position: record.upTo(i), chart: standard))!
                as BlackjackCoachResult;
        final direct = const BlackjackCoach().analyze(play.view(), chart: standard);
        expect(result.hand, play.handToPlay);
        expect(result.analysis.bestFresh, direct.bestFresh);
        expect(result.analysis.chartAction, direct.chartAction);
        expect([for (final a in result.analysis.actions) a.evFresh], [for (final a in direct.actions) a.evFresh]);
        expect(result.analysis.elapsedMicros, 0, reason: 'no timing in a job\'s output');
      }
    });

    test('a decision that isn\'t there fails the job, it doesn\'t guess', () {
      final record = botShoe(standard, rounds: 1);
      final reply = jsonDecode(
        runJobRequest(
          encodeRequest(
            1,
            const BlackjackCoachJob(),
            BlackjackDecisionInput(position: record),
            platform: JobPlatform.test,
          ),
          kitJobs,
        ),
      ) as Map;
      expect(reply['err'], contains('no decision'));
    });

    test('the bot job plays the Hard bot\'s move as a hand move', () {
      final record = botShoe(standard, rounds: 3);
      final play = BlackjackPlay.replay(record.upTo(1));
      final move = viaRequest(
        const BlackjackBotJob(),
        BlackjackDecisionInput(position: record.upTo(1), chart: standard, level: BotLevel.hard),
      );
      expect(move, record.moves[1]);
      expect(play.legalMoves(), contains(move));
    });

    test('the same input gives the same output, and examples cover the offers', () {
      final inputs = const BlackjackCoachJob().checkInputs();
      expect(inputs.length, greaterThanOrEqualTo(25));
      final phases = <RoundPhase>{};
      for (final input in inputs) {
        final request = encodeRequest(1, const BlackjackCoachJob(), input, platform: JobPlatform.test);
        final a = jsonDecode(runJobRequest(request, kitJobs)) as Map;
        final b = jsonDecode(runJobRequest(request, kitJobs)) as Map;
        expect(jsonEncode(roundNumbers(a['out'])), jsonEncode(roundNumbers(b['out'])));
        phases.add(BlackjackCoachResult.fromJson(a['out']).analysis.phase);
      }
      expect(phases, containsAll([RoundPhase.playing, RoundPhase.insurance, RoundPhase.earlySurrender]));
      expect(const BlackjackCoachJob().examples(), hasLength(3));
      expect(const BlackjackChartJob().examples(), isEmpty, reason: 'a chart takes far more than 50 ms');
    });

    test('numbers are compared as whole billionths, alike on every platform', () {
      expect(
        roundNumbers({
          'a': [0.1234567891234, 1.0, 1],
          'b': 'x',
        }),
        {
          'a': [123456789, 1000000000, 1000000000],
          'b': 'x',
        },
      );
    });
  });

  group('the analysis codec', () {
    test('an analysis survives the trip without its time, reasons as codes', () {
      final view = stackedPlay(const BlackjackRules(), 'Ts 9h 6d 7c').view();
      final a = const BlackjackCoach().analyze(view, chart: standard);
      final back = analysisFromJson(jsonDecode(jsonEncode(analysisToJson(a))));
      expect(back.bestFresh, a.bestFresh);
      expect(back.bestSeen, a.bestSeen);
      expect(back.chartAction, a.chartAction);
      expect(back.count.running, a.count.running);
      expect(back.count.unseenCards, a.count.unseenCards);
      expect([for (final x in back.actions) x.action], [for (final x in a.actions) x.action]);
      expect([for (final x in back.actions) x.lostSeen], [for (final x in a.actions) x.lostSeen]);
      expect(analysisToJson(a).containsKey('elapsedMicros'), isFalse);
    });

    test('a reason code reads back, with four decimals for its fractions', () {
      const r = CoachReason(
        ReasonKind.countDeviation,
        total: 16,
        soft: false,
        upcard: tenIndex,
        trueCount: 2.123456,
        action: BlackjackAction.stand,
        basicAction: BlackjackAction.hit,
      );
      final code = reasonCode(r);
      expect(code, 'countDeviation|16|0|9|-1|2.1235|stand|hit|');
      final back = parseReasonCode(code);
      expect(back.kind, r.kind);
      expect(back.trueCount, 2.1235);
      expect(back.action, BlackjackAction.stand);
      expect(back.basicAction, BlackjackAction.hit);
      expect(back.chance, isNull);
      expect(tryParseReasonCode('nonsense'), isNull);
    });
  });

  group('the coach list and grades', () {
    test('with a fresh shoe: every legal action in bets, best first, the chart\'s play tagged', () {
      final view = stackedPlay(const BlackjackRules(), 'Ts 9h 6d 7c').view(); // 16 vs 9
      final answer = blackjackAnswer(resultFor(view, standard), CoachMode.fresh);
      expect(answer.unit, ValueUnit.bets);
      expect(answer.lines.map((l) => l.move).toSet(), {'0:H', '0:S', '0:D'});
      expect(answer.lines.first.move, '0:H');
      expect(answer.pick, '0:H', reason: 'the chart hits 16 against a 9');
      expect(answer.lines.every((l) => l.tag == null), isTrue, reason: 'no Count tag with a fresh shoe');
      for (var i = 1; i < answer.lines.length; i++) {
        expect(answer.lines[i - 1].value, greaterThanOrEqualTo(answer.lines[i].value));
      }
      final hit = gradeBlackjack(answer, '0:H', CoachMode.fresh)!;
      expect(hit.grade, DecisionGrade.best);
      expect(hit.score, 100);
      final stand = gradeBlackjack(answer, '0:S', CoachMode.fresh)!;
      expect(stand.grade, isNot(DecisionGrade.best));
      expect(stand.best, '0:H');
      expect(stand.bestTag, isNull, reason: 'with a fresh shoe the best move is the chart\'s');
      expect(stand.loss, closeTo(answer.lineFor('0:H')!.value - answer.lineFor('0:S')!.value, 1e-12));
      expect(gradeBlackjack(answer, '0:P', CoachMode.fresh), isNull, reason: 'not a legal move: not graded');
      expect(gradeBlackjack(answer, '1:H', CoachMode.fresh), isNull, reason: 'another hand');
    });

    test('when the exact cards beat the chart, both are Best and the exact play says why', () {
      // A three-card 16 (T 2 4) against a 10: the chart hits, the exact
      // composition stands.
      final play = stackedPlay(const BlackjackRules(), 'Ts Th 2d 9c 4s');
      play.apply('0:H');
      final view = play.view();
      final result = resultFor(view, standard);
      final a = result.analysis;
      expect(a.chartAction, BlackjackAction.hit);
      expect(a.bestFresh, BlackjackAction.stand);
      final answer = blackjackAnswer(result, CoachMode.fresh);
      expect(answer.pick, '0:H');
      expect(answer.alsoBest, {'0:S'});
      expect(answer.lineFor('0:S')!.reasons.first, startsWith('exactCardsPlay|'));
      expect(gradeBlackjack(answer, '0:H', CoachMode.fresh)!.grade, DecisionGrade.best);
      expect(gradeBlackjack(answer, '0:S', CoachMode.fresh)!.grade, DecisionGrade.best);
    });

    test('with the cards seen, the count\'s play is tagged "count", graded against, and named so in the feedback', () {
      // One deck. The first round uses up twelve small cards (the player
      // hits 2 3 2 2 3 3 4 to 19, the dealer draws 4 4 4 to 17), so the rest
      // of the deck is rich in tens; then 16 against a ten: the chart hits,
      // the count stands.
      const rules = BlackjackRules(decks: 1);
      final chart = BasicStrategyChart.forRules(rules);
      final play = BlackjackPlay(rules, shoeSeed: 1);
      play.table.shoe.stack([
        for (final t in '2c 2d 3c 3d 2h 2s 3h 3s 4c 4d 4h 4s Ts Th 6h 9c'.split(' ')) Card.parse(t),
      ]);
      play.apply(dealMove);
      for (var i = 0; i < 5; i++) {
        play.apply('0:H');
      }
      play.apply('0:S');
      play.apply(dealMove);
      final result = resultFor(play.view(), chart);
      final a = result.analysis;
      expect(
        (a.chartAction, a.bestFresh, a.bestSeen),
        (BlackjackAction.hit, BlackjackAction.hit, BlackjackAction.stand),
      );
      final answer = blackjackAnswer(result, CoachMode.seen);
      expect(answer.lines.first.move, '0:S', reason: 'ranked by the values with the cards seen');
      expect(answer.lineFor('0:S')!.tag, 'count');
      expect(answer.lineFor('0:S')!.reasons.first, startsWith('countDeviation|'));
      expect(answer.lineFor('0:H')!.tag, isNull);
      expect(answer.pick, '0:H', reason: 'the chart\'s play is still tagged Basic strategy');
      expect(gradeBlackjack(answer, '0:S', CoachMode.seen)!.grade, DecisionGrade.best);
      final chartMark = gradeBlackjack(answer, '0:H', CoachMode.seen)!;
      expect(chartMark.loss, greaterThan(0), reason: 'graded against the count\'s play');
      expect(chartMark.best, '0:S');
      expect(chartMark.bestTag, 'count', reason: 'the feedback reads "Count: Stand", not "Basic strategy: Stand"');
      // The same decision with a fresh shoe: the chart's hit is Best.
      final fresh = blackjackAnswer(result, CoachMode.fresh);
      expect(fresh.lines.every((l) => l.tag == null), isTrue);
      expect(gradeBlackjack(fresh, '0:H', CoachMode.fresh)!.grade, DecisionGrade.best);
      expect(
        gradeBlackjack(fresh, '0:S', CoachMode.fresh)!.bestTag,
        isNull,
        reason: 'the chart\'s play: the pick label',
      );
    });

    test('insurance: the chart never insures; even money is reported for a blackjack', () {
      final play = stackedPlay(const BlackjackRules(), 'As Ah Kd 7c'); // a blackjack against an ace
      final view = play.view();
      expect(view.phase, RoundPhase.insurance);
      final result = resultFor(view, standard);
      expect(result.evenMoney, isTrue);
      final answer = blackjackAnswer(result, CoachMode.fresh);
      expect(answer.pick, '0:N');
      expect(answer.lines.map((l) => l.move).toSet(), {'0:I', '0:N'});
      expect(gradeBlackjack(answer, '0:I', CoachMode.fresh)!.grade, isNot(DecisionGrade.blunder));
    });

    test('the coach mode is read from a record by name, Fresh shoe otherwise', () {
      expect(CoachMode.byName('seen'), CoachMode.seen);
      expect(CoachMode.byName('fresh'), CoachMode.fresh);
      expect(CoachMode.byName(null), CoachMode.fresh);
      expect(CoachMode.byName('x'), CoachMode.fresh);
    });
  });
}
