import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';

import 'helpers.dart';

GomokuMove m(String notation) => GomokuMove.parse(notation);

void main() {
  const coach = GomokuCoach();

  group('a proven win', () {
    // Black's four-three at i8 (see threats_test.dart).
    final position = game('f8 g8 h8 i9 i10', 'e8 a1 a15 o1 o15');

    test('is the best move, marked "wins in 3", with its forcing line', () {
      final analysis = coach.analyze(position.viewFor(Stone.black));
      final best = analysis.best!;
      expect(best.move, m('i8'));
      expect(best.winsIn, 3);
      expect(best.winChance, 1);
      expect(best.reasons, [MoveReason.startsForcedWin, MoveReason.makesFourThree]);
      expect(best.line.first, m('i8'));
      expect(best.line[1], m('j8'));
      expect(analysis.winsIn, 3);
    });

    test('a move that throws it away "misses a forced win", and is at least an inaccuracy', () {
      final analysis = coach.analyze(position.viewFor(Stone.black), include: m('c13'));
      final played = analysis.of(m('c13'))!;
      expect(played.isProvenWin, isFalse);
      expect(played.reasons.first, MoveReason.missesForcedWin);
      expect(analysis.grade(m('c13')).index, greaterThanOrEqualTo(MoveGrade.inaccuracy.index));
      expect(analysis.grade(m('i8')), MoveGrade.best);
    });

    test('a slower proven win is as good as the fastest', () {
      final analysis = coach.analyze(position.viewFor(Stone.black));
      final slower = analysis.moves.where((a) => a.isProvenWin && a.winsIn! > 3);
      expect(slower, isNotEmpty);
      for (final a in slower) {
        expect(a.reasons, isNot(contains(MoveReason.missesForcedWin)));
        expect(analysis.grade(a.move), MoveGrade.best);
      }
    });
  });

  group('grading a move that gives up a proven win', () {
    // The solvers can't prove such a move loses the win, so the grade goes
    // by the estimate: a Blunder only when that drops a lot, or when the
    // opponent then has a proven win.
    GomokuAnalysis analysis(List<MoveAnalysis> others) => GomokuAnalysis(
          toMove: Stone.black,
          moves: [
            MoveAnalysis(
                move: m('i8'), winsIn: 3, winChance: 1, score: 29995, reasons: const [MoveReason.startsForcedWin], line: [m('i8')]),
            ...others,
          ],
          winsIn: 3,
          depth: 6,
          nodes: 1000,
          elapsed: Duration.zero,
        );
    MoveAnalysis gaveUp(String move, double chance, {int? losesIn}) => MoveAnalysis(
          move: m(move),
          winChance: chance,
          losesIn: losesIn,
          score: 0,
          reasons: [MoveReason.missesForcedWin, if (losesIn != null) MoveReason.allowsForcedWin],
          line: [m(move)],
        );

    test('still rated nearly winning: an inaccuracy, not a blunder', () {
      expect(analysis([gaveUp('c13', 0.96)]).grade(m('c13')), MoveGrade.inaccuracy);
    });

    test('rated a lot worse: a mistake or a blunder, by how much', () {
      expect(analysis([gaveUp('c13', 0.8)]).grade(m('c13')), MoveGrade.mistake);
      expect(analysis([gaveUp('c13', 0.5)]).grade(m('c13')), MoveGrade.blunder);
    });

    test('the opponent then has a proven win: a blunder', () {
      expect(analysis([gaveUp('c13', 0, losesIn: 3)]).grade(m('c13')), MoveGrade.blunder);
    });
  });

  group('with an open four on the board', () {
    // Black to move with h8-k8 open at both ends: any move wins next turn.
    final position = game('h8 i8 j8 k8', 'a1 o1 a15 o15');

    test('a quiet move still wins: not "misses a forced win", not a blunder', () {
      final quiet = m('c13');
      final after = position.play(quiet);
      for (final reply in after.legalMoves()) {
        final g = after.play(reply);
        expect(g.legalMoves().any((x) => g.play(x).result?.winner == Stone.black), isTrue);
      }
      final analysis = coach.analyze(position.viewFor(Stone.black), include: quiet);
      expect(analysis.of(quiet)!.winsIn, 2);
      expect(analysis.of(quiet)!.reasons, isNot(contains(MoveReason.missesForcedWin)));
      expect(analysis.grade(quiet), MoveGrade.best);
    });

    test('a move that was not analysed is graded by estimate, not called a blunder', () {
      final analysis = coach.analyze(position.viewFor(Stone.black));
      expect(analysis.of(m('c13')), isNull);
      expect(analysis.grade(m('c13')), isNot(MoveGrade.blunder));
    });
  });

  group("the opponent's four", () {
    // White has d10-g10, closed at c10: h10 is the only block.
    final position = game('c10 h3 j3 l3', 'd10 e10 f10 g10');

    test('must be blocked', () {
      final analysis = coach.analyze(position.viewFor(Stone.black));
      expect(analysis.best!.move, m('h10'));
      expect(analysis.best!.reasons, contains(MoveReason.blocksFour));
    });

    test('ignoring it "loses in 1": a blunder', () {
      final analysis = coach.analyze(position.viewFor(Stone.black), include: m('k3'));
      final played = analysis.of(m('k3'))!;
      expect(played.losesIn, 1);
      expect(played.winChance, 0);
      expect(played.reasons, containsAllInOrder([MoveReason.allowsForcedWin, MoveReason.ignoresFour]));
      expect(coach.grade(position.viewFor(Stone.black), m('k3')), MoveGrade.blunder);
    });
  });

  group("the opponent's open three", () {
    // White's open three e10-g10.
    final position = game('h8 a1 c1', 'e10 f10 g10');

    test('is answered by a block', () {
      final analysis = coach.analyze(position.viewFor(Stone.black));
      expect(['d10', 'h10', 'c10', 'i10'], contains(analysis.best!.move.notation));
      expect(analysis.best!.reasons, contains(MoveReason.blocksOpenThree));
    });

    test('ignoring it is a proven loss', () {
      final analysis = coach.analyze(position.viewFor(Stone.black), include: m('n2'));
      final played = analysis.of(m('n2'))!;
      expect(played.losesIn, 2);
      expect(played.reasons, contains(MoveReason.ignoresOpenThree));
      expect(analysis.grade(m('n2')), MoveGrade.blunder);
    });
  });

  test('a quiet opening has estimates only, and the best move grades as best', () {
    final position = game('h8', '');
    final analysis = coach.analyze(position.viewFor(Stone.white));
    expect(analysis.moves, isNotEmpty);
    expect(analysis.moves.length, lessThanOrEqualTo(const CoachBudget().topN));
    for (final a in analysis.moves) {
      expect(a.isProvenWin || a.isProvenLoss, isFalse);
      expect(a.winChance, inInclusiveRange(0.04, 0.96));
    }
    expect(analysis.grade(analysis.best!.move), MoveGrade.best);
    // Far from the stones is clearly worse.
    expect(coach.grade(position.viewFor(Stone.white), m('a15')).index, greaterThan(MoveGrade.good.index));
  });

  test('moves are ranked: proven wins, then estimates, then proven losses', () {
    final position = game('h8 i9 a1 c1', 'e10 f10 g10 g11');
    final analysis = coach.analyze(position.viewFor(Stone.black), include: m('o8'));
    var phase = 0; // 0 wins, 1 estimates, 2 losses
    for (final a in analysis.moves) {
      final p = a.isProvenWin ? 0 : (a.isProvenLoss ? 2 : 1);
      expect(p, greaterThanOrEqualTo(phase));
      phase = p;
    }
  });

  test('gives the same answer every time, and survives JSON', () {
    final position = game('h8 j6 f6 e5 e7', 'g5 h5 g6 g7');
    final a = coach.analyze(position.viewFor(Stone.white));
    final b = coach.analyze(position.viewFor(Stone.white));
    String strip(GomokuAnalysis x) => (x.toJson()..remove('micros')).toString();
    expect(strip(a), strip(b));
    final copy = GomokuAnalysis.fromJson(a.toJson());
    expect(strip(copy), strip(a));
  });

  // The budget is in positions searched, so the time depends on the
  // machine; on a desktop PC this takes 0.1-0.5 s. The bound is loose so a
  // busy test machine doesn't fail it.
  for (final rules in [GomokuRules.freestyle, GomokuRules.renju, GomokuRules.standard19]) {
    test('answers well within a second at the default budget (${rules.label})', () {
      final position = game('h8 j6 f6 e5 e7 g5', 'h5 g6 g7 h7 i9', rules: rules);
      final clock = Stopwatch()..start();
      coach.analyze(position.viewFor(Stone.white));
      expect(clock.elapsedMilliseconds, lessThan(1500));
    });
  }

  test('a budget with another time cap keeps every node limit', () {
    final capped = CoachBudget.deep.withTime(const Duration(seconds: 2));
    expect(capped.maxTime, const Duration(seconds: 2));
    expect(
      [capped.searchNodes, capped.proofNodes, capped.checkNodes, capped.checkPool, capped.topN],
      [CoachBudget.deep.searchNodes, CoachBudget.deep.proofNodes, CoachBudget.deep.checkNodes,
       CoachBudget.deep.checkPool, CoachBudget.deep.topN],
    );
  });

  test('an analysis sent without its time reads back with none', () {
    final position = game('h8', '');
    final json = coach.analyze(position.viewFor(Stone.white)).toJson()..remove('micros');
    expect(GomokuAnalysis.fromJson(json).elapsed, Duration.zero);
  });

  test('a finished game has nothing to analyse', () {
    final over = game('a1 b1 c1 d1 e1', 'a2 b2 c2 d2');
    expect(coach.analyze(over.viewFor(null)).moves, isEmpty);
  });
}
