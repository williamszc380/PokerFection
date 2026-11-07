// The coach: every legal action valued in both knowledge modes, the best
// action, reasons for the app's one-line explanations, and grades.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';

import 'helpers.dart';

const coach = BlackjackCoach();

/// A one-deck table where the first round (seven seats) used up 18 small
/// cards, so the rest of the deck is rich in tens; then [secondRound] is
/// dealt to one seat.
BlackjackRound afterLowCards(String secondRound, {BlackjackRules rules = const BlackjackRules(decks: 1)}) {
  final shoe = Shoe.forRules(rules, seed: 1)
    ..stack(cards('2c 2d 2h 2s 3c 3d 3h 3s 4c 4d 4h 4s 5c 5d 5h 5s 6c 6d $secondRound'));
  final first = BlackjackRound.deal(rules, shoe, List.filled(7, 1));
  while (!first.isOver) {
    first.apply(BlackjackAction.stand);
  }
  expect(first.dealerCards, cards('3s 5s 6c 6d'), reason: 'the setup round went as planned');
  return BlackjackRound.deal(rules, shoe, [1]);
}

void main() {
  group('the best play', () {
    final cases = <(String, String, BlackjackAction, ReasonKind)>[
      ('11 vs 6: double', '5s 6h 6d Tc', BlackjackAction.double, ReasonKind.doubleStrong),
      ('12 vs 4: stand, the dealer busts often', '7s 4h 5d 9c', BlackjackAction.stand, ReasonKind.dealerBustsOften),
      ('16 vs 7: hit, the dealer usually makes 17', 'Ts 7h 6d 9c', BlackjackAction.hit, ReasonKind.dealerStrong),
      ('never split tens', 'Ts 6h Kd 9c', BlackjackAction.stand, ReasonKind.standMadeHand),
      ('always split eights', '8s Th 8d 9c', BlackjackAction.split, ReasonKind.splitEights),
      ('always split aces', 'As 9h Ad 7c', BlackjackAction.split, ReasonKind.splitAces),
      ('soft 18 vs 4: double', 'As 4h 7d 9c', BlackjackAction.double, ReasonKind.doubleSoft),
      ('soft 15 vs 9: hit, it can\'t bust', 'As 9h 4d 7c', BlackjackAction.hit, ReasonKind.softCantBust),
    ];
    for (final (name, deal, best, reason) in cases) {
      test(name, () {
        final r = stacked(const BlackjackRules(), deal);
        final a = coach.analyze(r.viewFor(0));
        expect(a.bestFresh, best);
        expect(a.chartAction, best, reason: 'FRESH agrees with the basic strategy chart');
        expect(a.reasons.map((x) => x.kind), contains(reason));
        expect(a.actions.first.action, best, reason: 'actions are sorted best first');
        expect(a.actions.first.lostFresh, 0);
        expect(a.actions.map((x) => x.action).toSet(), r.legalActions().toSet());
      });
    }

    test('splitting tens is explained as a mistake', () {
      final a = coach.analyze(stacked(const BlackjackRules(), 'Ts 6h Kd 9c').viewFor(0));
      expect(a.of(BlackjackAction.split).reasons.map((r) => r.kind), contains(ReasonKind.neverSplitTens));
      expect(coach.grade(BlackjackAction.split, a).grade, MoveGrade.blunder);
    });

    test('a hit on a stiff hand reports the chance of busting', () {
      final a = coach.analyze(stacked(const BlackjackRules(), 'Ts 7h 6d 9c').viewFor(0));
      final bust = a.of(BlackjackAction.hit).reasons.firstWhere((r) => r.kind == ReasonKind.bustRisk);
      // 16: any 6 or more busts. Unseen: 6 decks minus T, 7, 6.
      expect(bust.chance, closeTo((23 + 23 + 24 + 24 + 95) / 309, 1e-12));
    });

    test('the exact cards can beat the chart: a three-card 16 (4-4-8) stands against a 10', () {
      final r = stacked(const BlackjackRules(), '4s Kh 4d 9c 8c')..apply(BlackjackAction.hit);
      final a = coach.analyze(r.viewFor(0));
      expect(a.chartAction, BlackjackAction.hit);
      expect(a.bestFresh, BlackjackAction.stand);
      expect(a.reasons.map((x) => x.kind), contains(ReasonKind.exactCardsPlay));
    });

    test('the same view always gets the same answer', () {
      final v = stacked(const BlackjackRules(), '8s 6h 8d 9c').viewFor(0);
      final a = coach.analyze(v), b = coach.analyze(v);
      expect([for (final x in a.actions) x.evSeen], [for (final x in b.actions) x.evSeen]);
    });
  });

  group('knowledge modes', () {
    test('a fresh shoe: FRESH and SEEN agree', () {
      final a = coach.analyze(stacked(const BlackjackRules(), 'Ts 6h 6d 9c').viewFor(0));
      expect(a.differs, isFalse);
      for (final x in a.actions) {
        expect(x.evSeen, x.evFresh);
      }
    });

    test('after many small cards, SEEN stands on 16 against a 10 while FRESH (basic strategy) hits', () {
      final r = afterLowCards('Ts Kh 6h 9c');
      final v = r.viewFor(0);
      expect(v.count.running, 18 - 2 + 1, reason: '18 small cards, then a ten, a king and a 6 this round');
      final a = coach.analyze(v);
      expect(a.bestFresh, BlackjackAction.hit);
      expect(a.bestSeen, BlackjackAction.stand);
      expect(a.differs, isTrue);
      final dev = a.reasons.firstWhere((x) => x.kind == ReasonKind.countDeviation);
      expect(dev.action, BlackjackAction.stand);
      expect(dev.basicAction, BlackjackAction.hit);
      expect(dev.trueCount, greaterThan(20), reason: 'running 17 with 31 cards (0.6 decks) unseen');
    });

    test('insurance only pays when the count is high', () {
      final fresh = coach.analyze(stacked(const BlackjackRules(decks: 1), 'Ts As 9s 7c').viewFor(0));
      expect(fresh.phase, RoundPhase.insurance);
      expect(fresh.bestFresh, BlackjackAction.noInsurance);
      expect(fresh.chartAction, BlackjackAction.noInsurance);
      expect(fresh.of(BlackjackAction.insurance).reasons.single.kind, ReasonKind.insuranceBad);
      expect(coach.grade(BlackjackAction.insurance, fresh).grade, MoveGrade.mistake);

      final rich = coach.analyze(afterLowCards('Ts As 9s Kc').viewFor(0));
      expect(rich.bestFresh, BlackjackAction.noInsurance);
      expect(rich.bestSeen, BlackjackAction.insurance, reason: '15 of the 31 unseen cards are tens');
      expect(
        rich.of(BlackjackAction.insurance).evSeen - rich.of(BlackjackAction.noInsurance).evSeen,
        closeTo(0.5 * (3 * 15 / 31 - 1), 1e-12),
      );
      expect(rich.of(BlackjackAction.insurance).reasons.single.kind, ReasonKind.insuranceGood);
    });

    test('even money: taking it is worth exactly 1 bet', () {
      final a = coach.analyze(stacked(const BlackjackRules(), 'As Ad Kh 7c').viewFor(0));
      expect(a.of(BlackjackAction.insurance).evFresh, closeTo(1, 1e-12));
      expect(a.of(BlackjackAction.noInsurance).evFresh, closeTo(1.5 * (1 - 95 / 309), 1e-12));
      expect(a.bestFresh, BlackjackAction.noInsurance, reason: 'declining is worth more than 1 without a count');
    });
  });

  group('reasons agree with the numbers', () {
    // A reason that says "do X" must be about a play that is at least Good
    // (gives up under 0.01 bets) and, when attached to another action,
    // better than that action. A reason that says "don't do X" must not be
    // about the best play. And every play that gives up 0.01 or more says
    // why, so the app never shows advice its own numbers contradict.
    BlackjackAction? advises(ReasonKind k) => switch (k) {
      ReasonKind.standMadeHand || ReasonKind.dealerBustsOften || ReasonKind.softStand => BlackjackAction.stand,
      ReasonKind.cantBust ||
      ReasonKind.softCantBust ||
      ReasonKind.dealerStrong ||
      ReasonKind.dealerBustsLess => BlackjackAction.hit,
      ReasonKind.doubleStrong || ReasonKind.doubleSoft => BlackjackAction.double,
      ReasonKind.splitAces || ReasonKind.splitEights || ReasonKind.splitVsWeak => BlackjackAction.split,
      ReasonKind.surrenderSaves => BlackjackAction.surrender,
      _ => null,
    };
    BlackjackAction? discourages(ReasonKind k, BlackjackAction a) => switch (k) {
      ReasonKind.neverSplitTens || ReasonKind.neverSplitFives => BlackjackAction.split,
      ReasonKind.tooRisky || ReasonKind.noSplitVsStrong || ReasonKind.betterPlay => a,
      _ => null,
    };

    const suits = 'shdc';
    String card(int rank, int suit) => '${rankName(rank)}${suits[suit]}';

    final ruleSets = {
      'Standard': const BlackjackRules(insurance: false),
      'single deck H17 late surrender': const BlackjackRules(
        decks: 1,
        dealerHitsSoft17: true,
        doubleAfterSplit: false,
        surrender: Surrender.late,
        insurance: false,
      ),
      'European (no hole card)': BlackjackRules.preset(BlackjackPreset.european).copyWith(insurance: false),
    };
    for (final MapEntry(key: name, value: rules) in ruleSets.entries) {
      test('every first decision, every upcard: $name', () {
        var checked = 0;
        for (var up = 0; up < rankCount; up++) {
          // A hole card that can't make blackjack, so play goes on.
          final hole = up == aceIndex || up == tenIndex ? 4 : 3;
          for (var c1 = 0; c1 < rankCount; c1++) {
            for (var c2 = c1; c2 < rankCount; c2++) {
              if (c1 == aceIndex && c2 == tenIndex) continue; // blackjack: no decision
              final deal = '${card(c1, 0)} ${card(up, 1)} ${card(c2, 2)}${rules.holeCard ? ' ${card(hole, 3)}' : ''}';
              final a = coach.analyze(stacked(rules, deal).viewFor(0));
              final lost = {for (final x in a.actions) x.action: x.lostFresh};
              for (final x in a.actions) {
                var explained = false;
                for (final r in x.reasons) {
                  final adv = advises(r.kind);
                  if (adv != null) {
                    expect(lost[adv], lessThan(0.01), reason: '$deal ${x.action.name}: ${x.reasons}');
                    if (adv != x.action) {
                      expect(lost[adv], lessThan(lost[x.action]!), reason: '$deal ${x.action.name}: ${x.reasons}');
                      explained = true;
                    }
                  }
                  final dis = discourages(r.kind, x.action);
                  if (dis != null && lost[dis] != null) {
                    expect(lost[dis], greaterThan(0.001), reason: '$deal ${x.action.name}: ${x.reasons}');
                    if (dis == x.action) explained = true;
                  }
                  if (r.kind == ReasonKind.betterPlay) expect(r.action, a.bestFresh);
                }
                if (x.lostFresh >= 0.01) expect(explained, isTrue, reason: '$deal ${x.action.name}: ${x.reasons}');
                checked++;
              }
            }
          }
        }
        expect(checked, greaterThan(1000));
      });
    }

    test('12 against a 2 or 3: hit, those upcards bust less often than you\'d think', () {
      for (final deal in ['7s 2h 5d 9c', '7s 3h 5d 9c']) {
        final a = coach.analyze(stacked(const BlackjackRules(), deal).viewFor(0));
        expect(a.bestFresh, BlackjackAction.hit, reason: deal);
        expect(a.reasons.map((r) => r.kind), contains(ReasonKind.dealerBustsLess), reason: deal);
        expect(a.of(BlackjackAction.stand).reasons.map((r) => r.kind), [ReasonKind.dealerBustsLess], reason: deal);
      }
    });

    test('a play that loses with no rule of thumb against it names the better play', () {
      // Soft 13 against a 2: doubling gives up about 0.11 bets; the 2 is
      // not a strong upcard, so "too risky" would be the wrong words.
      final a = coach.analyze(stacked(const BlackjackRules(insurance: false), 'As 2h 2d 9c').viewFor(0));
      final why = a.of(BlackjackAction.double).reasons.single;
      expect(why.kind, ReasonKind.betterPlay);
      expect(why.action, BlackjackAction.hit);
    });
  });

  group('the end of a shoe', () {
    test('SEEN uses the cards seen since the shuffle while they are sure to last the round', () {
      final v = afterLowCards('Ts Kh 6h 9c').viewFor(0);
      expect(v.seenMayRunOut, isFalse, reason: '30 unseen cards, one hand and the dealer');
      expect(stacked(const BlackjackRules(), 'Ts 6h 6d 9c').viewFor(0).seenMayRunOut, isFalse);
    });

    test('a six-deck shoe just before its cut card still lasts seven seats', () {
      const rules = BlackjackRules();
      final shoe = Shoe.forRules(rules, seed: 5)..startRound();
      for (var i = 0; i < shoe.cutCard - 1; i++) {
        shoe.draw();
      }
      final r = BlackjackRound.deal(rules, shoe, List.filled(7, 1));
      for (var s = 0; s < 7; s++) {
        expect(r.viewFor(s).seenMayRunOut, isFalse, reason: 'seat $s, ${shoe.cardsLeft} cards left');
      }
    });

    test('when the cards might run out, SEEN is the reshuffled discards: FRESH', () {
      // One deck: 40 cards dealt before the round and 4 in it, so 8 are
      // left, every one of them an ace, 2 or 3.
      const rules = BlackjackRules(decks: 1, penetration: 0.9);
      final small = cards('Ac Ad Ah As 2c 2d 2h 3c');
      final deal = cards('4s 2s 5d 7c'); // 9 against a 2
      final rest = [...Card.deck]..removeWhere((c) => small.contains(c) || deal.contains(c));
      final shoe = Shoe.forRules(rules, seed: 1)..stack([...rest, ...deal, ...small]);
      shoe.startRound();
      for (var i = 0; i < rest.length; i++) {
        shoe.draw();
      }
      final v = BlackjackRound.deal(rules, shoe, [1]).viewFor(0);
      expect(v.unseenSeen.total, 9, reason: 'eight small cards and the hole card');
      expect(v.seenMayRunOut, isTrue, reason: 'the 9 could draw A A A A 2 2 2 3 and the dealer still needs cards');
      final a = coach.analyze(v);
      expect(a.differs, isFalse);
      for (final x in a.actions) {
        expect(x.evSeen, x.evFresh);
      }
    });
  });

  group('early surrender', () {
    test('16 against an ace: surrender before the peek', () {
      final r = stacked(const BlackjackRules(surrender: Surrender.early), 'Ts As 6s 7c');
      final a = coach.analyze(r.viewFor(0));
      expect(a.phase, RoundPhase.earlySurrender);
      expect(a.of(BlackjackAction.surrender).evFresh, -0.5);
      expect(a.bestFresh, BlackjackAction.surrender);
      expect(a.chartAction, BlackjackAction.surrender);
      expect(a.of(BlackjackAction.keepPlaying).evFresh, lessThan(-0.5));
    });
  });

  group('grades', () {
    test('the lines between grades are in bets', () {
      expect(BlackjackCoach.gradeFor(0), MoveGrade.best);
      expect(BlackjackCoach.gradeFor(0.0009), MoveGrade.best);
      expect(BlackjackCoach.gradeFor(0.005), MoveGrade.good);
      expect(BlackjackCoach.gradeFor(0.02), MoveGrade.inaccuracy);
      expect(BlackjackCoach.gradeFor(0.05), MoveGrade.mistake);
      expect(BlackjackCoach.gradeFor(0.2), MoveGrade.blunder);
    });

    test('typical errors land where a teacher would put them', () {
      MoveGrade graded(String deal, BlackjackAction played, {BlackjackRules rules = const BlackjackRules()}) =>
          coach.grade(played, coach.analyze(stacked(rules, deal).viewFor(0))).grade;
      expect(graded('5s 6h 6d Tc', BlackjackAction.hit), MoveGrade.blunder, reason: 'not doubling 11 vs 6');
      expect(graded('5s 6h 6d Tc', BlackjackAction.stand), MoveGrade.blunder, reason: 'standing on 11');
      expect(graded('Ts Th 6d 9c', BlackjackAction.stand), MoveGrade.good, reason: '16 vs 10: a close call');
      expect(graded('7s 4h 5d 9c', BlackjackAction.hit), MoveGrade.good, reason: 'hitting 12 vs 4: close');
      expect(graded('7s 3h 5d 9c', BlackjackAction.stand), MoveGrade.inaccuracy, reason: 'standing on 12 vs 3');
      expect(graded('9s 2h 4d 9c', BlackjackAction.hit), MoveGrade.inaccuracy, reason: 'hitting 13 vs 2');
      expect(graded('Ts 7h 6d 9c', BlackjackAction.stand), MoveGrade.mistake, reason: 'standing on 16 vs 7');
    });

    test('grading against SEEN judges a counter\'s play', () {
      final a = coach.analyze(afterLowCards('Ts Kh 6h 9c').viewFor(0));
      expect(coach.grade(BlackjackAction.stand, a, mode: KnowledgeMode.seen).grade, MoveGrade.best);
      expect(coach.grade(BlackjackAction.stand, a).grade, isNot(MoveGrade.best));
    });
  });
}
