// The coach list's words agree with its own numbers and tags: a reason
// never tells the player the opposite of the row it sits on, and a reason
// that names "the chart's" play names the play the chart (and the "Basic
// strategy" tag) really gives.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_analysis_codec.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_grading.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/kit/coach_answer.dart';

/// Every decision of [shoes] shoes of [rules], each played by the chart,
/// with the coach's result there.
Iterable<BlackjackCoachResult> decisions(BlackjackRules rules, {int shoes = 40}) =>
    spots(rules, shoes: shoes).map((s) => s.result);

/// Every decision of [shoes] shoes of [rules] as the player saw it, with
/// the coach's result there.
Iterable<({BlackjackView view, BlackjackCoachResult result})> spots(BlackjackRules rules, {int shoes = 40}) sync* {
  final chart = BasicStrategyChart.forRules(rules);
  for (var seed = 0; seed < shoes; seed++) {
    final play = BlackjackPlay(rules, shoeSeed: seed);
    while (!play.shoeOver) {
      if (play.betweenRounds) {
        play.apply(dealMove);
        continue;
      }
      final view = play.view();
      final result = BlackjackCoachResult(
        hand: view.turn!.hand,
        evenMoney: view.offersEvenMoney,
        analysis: const BlackjackCoach().analyze(view, chart: chart),
      );
      yield (view: view, result: result);
      play.apply(blackjackAnswer(result, CoachMode.fresh).pick);
    }
  }
}

List<CoachReason> reasonsOf(CoachLine line) => [for (final code in line.reasons) parseReasonCode(code)];

/// The share of tens in [cards].
double tensIn(Composition cards) => cards[tenIndex] / cards.total;

void main() {
  final single = BlackjackRules.preset(BlackjackPreset.singleDeck);

  test('Fresh shoe: the insurance rows never say "insurance pays" while No insurance is the best play', () {
    final contradictions = <String>[];
    for (final result in decisions(single)) {
      if (result.analysis.phase != RoundPhase.insurance) continue;
      final answer = blackjackAnswer(result, CoachMode.fresh);
      final best = answer.lines.first; // best first, in Fresh shoe values
      for (final line in answer.lines) {
        for (final r in reasonsOf(line)) {
          final saysInsure = r.kind == ReasonKind.insuranceGood;
          final saysDont = r.kind == ReasonKind.insuranceBad;
          final bestInsures = best.move.endsWith(':I');
          if ((saysInsure && !bestInsures) || (saysDont && bestInsures)) {
            contradictions.add(
              '${line.move} "${r.kind.name} ${r.chance}" while the best is ${best.move} '
              '(${[for (final l in answer.lines) '${l.move} ${l.value.toStringAsFixed(4)}'].join(', ')})',
            );
          }
        }
      }
    }
    expect(contradictions, isEmpty);
  });

  test('Cards seen: a count reason\'s "(chart: X)" is the chart\'s play, the row tagged Basic strategy', () {
    final wrong = <String>[];
    for (final result in decisions(single)) {
      final a = result.analysis;
      final answer = blackjackAnswer(result, CoachMode.seen);
      for (final line in answer.lines) {
        for (final r in reasonsOf(line)) {
          if (r.kind != ReasonKind.countDeviation) continue;
          final picked = parseHandMove(answer.pick)!.action;
          if (r.basicAction != picked) {
            wrong.add(
              '${line.move}: "chart: ${r.basicAction!.name}" but the chart plays ${picked.name} '
              '(fresh best ${a.bestFresh.name}, seen best ${a.bestSeen.name})',
            );
          }
        }
      }
    }
    expect(wrong, isEmpty);
  });

  for (final (name, rules) in [('single deck', single), ('6 decks', const BlackjackRules())]) {
    test('$name: the insurance rows give the tens of the shoe the mode assumes, as its values do', () {
      var offers = 0;
      for (final (:view, :result) in spots(rules, shoes: 60)) {
        if (result.analysis.phase != RoundPhase.insurance) continue;
        offers++;
        for (final (mode, cards) in [
          (CoachMode.fresh, view.unseenFresh),
          if (!view.seenMayRunOut) (CoachMode.seen, view.unseenSeen),
        ]) {
          for (final line in blackjackAnswer(result, mode).lines) {
            final r = reasonsOf(line)
                .singleWhere((r) => r.kind == ReasonKind.insuranceGood || r.kind == ReasonKind.insuranceBad);
            // The reason code keeps four decimals.
            expect(r.chance, closeTo(tensIn(cards), 1e-4), reason: '${mode.name} ${line.move}');
          }
        }
      }
      expect(offers, greaterThan(10), reason: 'enough insurance offers to mean something');
    });
  }

  test('Fresh shoe: insurance never "pays", since a full shoe is never a third tens after an ace', () {
    for (final result in decisions(single, shoes: 60)) {
      if (result.analysis.phase != RoundPhase.insurance) continue;
      for (final line in blackjackAnswer(result, CoachMode.fresh).lines) {
        expect(reasonsOf(line).map((r) => r.kind), isNot(contains(ReasonKind.insuranceGood)));
      }
    }
  });

  test('Cards seen: when the count\'s play is the chart\'s, no count reason says otherwise', () {
    var agreeing = 0;
    for (final result in decisions(single)) {
      final a = result.analysis;
      final answer = blackjackAnswer(result, CoachMode.seen);
      if (handMove(result.hand, a.bestSeen) != answer.pick) continue;
      agreeing++;
      for (final line in answer.lines) {
        expect(reasonsOf(line).map((r) => r.kind), isNot(contains(ReasonKind.countDeviation)), reason: line.move);
        expect(line.tag, isNull);
      }
    }
    expect(agreeing, greaterThan(100));
  });
}
