import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/gomoku/app/gomoku_grading.dart';
import 'package:pokerfection/src/games/gomoku/gomoku.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;

import 'positions.dart';

GomokuGame _game(String moves, [GomokuRules rules = GomokuRules.freestyle]) =>
    GomokuGame.fromMoves(rules, GomokuGame.parseMoves(moves));

void main() {
  const coach = GomokuCoach(budget: CoachBudget.quick);

  test('the engine\'s grades map one to one onto the app\'s', () {
    expect([for (final g in MoveGrade.values) gomokuDecision(g)], DecisionGrade.values);
  });

  test('every analysed move gets the engine\'s own grade', () {
    for (final (rules, moves) in sampleGames) {
      final words = moves.split(' ');
      for (final cut in [4, words.length ~/ 2, words.length - 2]) {
        final game = _game(words.take(cut).join(' '), rules);
        final analysis = coach.analyze(game.viewFor(game.toMove));
        for (final move in analysis.moves) {
          final mark = gomokuMark(analysis, move.move.notation)!;
          expect(mark.grade, gomokuDecision(analysis.grade(move.move)));
          expect(mark.best, analysis.best!.move.notation);
          expect(mark.played, move.move.notation);
          expect(mark.reasons, [for (final r in move.reasons) r.name]);
          expect(mark.loss, greaterThanOrEqualTo(0));
          expect(gomokuScale.gradeFor(mark.loss), mark.grade, reason: 'the loss shown reads as the grade');
          expect(mark.score, inInclusiveRange(0, 100));
        }
      }
    }
  });

  test('the best move: Best, nothing lost, a full score', () {
    final game = _game(fourThree);
    final analysis = coach.analyze(game.viewFor(Stone.black));
    final mark = gomokuMark(analysis, 'i8')!;
    expect(mark.grade, DecisionGrade.best);
    expect(mark.loss, 0);
    expect(mark.score, 100);
    expect(mark.proof, 'win:3');
  });

  test('giving up a forced win says so, and is at least an Inaccuracy', () {
    final game = _game(fourThree);
    final analysis = coach.analyze(game.viewFor(Stone.black), include: GomokuMove.parse('c13'));
    final mark = gomokuMark(analysis, 'c13')!;
    expect(mark.proof, 'missedWin:3');
    expect(mark.grade.index, greaterThanOrEqualTo(DecisionGrade.inaccuracy.index));
    expect(mark.loss, greaterThan(0));
    expect(mark.reasons.first, 'missesForcedWin');
  });

  test('in a lost position, holding out less long is not Best: it neither reads "0%" nor scores 100', () {
    // Black to move. White has a four d10-g10 (closed at c10: only h10
    // makes five) and an open three l3-l5, so blocking at h10 loses in 2
    // and anything else loses at once. Both win chances are 0.
    final game = _game('c10 d10 a15 e10 c13 f10 e15 g10 a11 l3 o1 l4 o14 l5');
    final analysis = coach.analyze(game.viewFor(Stone.black), include: GomokuMove.parse('a5'));
    expect(analysis.of(GomokuMove.parse('h10'))!.losesIn, 2);
    expect(analysis.of(GomokuMove.parse('a5'))!.losesIn, 1);

    final mark = gomokuMark(analysis, 'a5')!;
    expect(mark.grade, DecisionGrade.good, reason: 'the engine: one move sooner is Good');
    expect(mark.loss, greaterThan(0.02), reason: 'inside Good\'s band, not "Good 0%"');
    expect(gomokuScale.gradeFor(mark.loss), DecisionGrade.good);
    expect(mark.score, lessThan(100), reason: 'not a perfect move in the session average');
    expect(mark.best, 'h10');
  });

  test('leaving a four on the board: a Blunder that scores nothing, and the proof says the loss', () {
    final game = _game(mustBlock);
    final analysis = coach.analyze(game.viewFor(Stone.black), include: GomokuMove.parse('k3'));
    final mark = gomokuMark(analysis, 'k3')!;
    expect(mark.grade, DecisionGrade.blunder);
    expect(mark.score, 0);
    expect(mark.proof, 'allowsLoss:1');
    expect(mark.best, 'h10');
  });

  test('a move the coach did not analyse is not guessed: the kit asks again with it included', () {
    final game = _game('h8');
    final analysis = coach.analyze(game.viewFor(Stone.white));
    expect(analysis.of(GomokuMove.parse('a15')), isNull);
    expect(gomokuMark(analysis, 'a15'), isNull);
    expect(gomokuMark(analysis, 'not a move'), isNull);
    final again = coach.analyze(game.viewFor(Stone.white), include: GomokuMove.parse('a15'));
    final mark = gomokuMark(again, 'a15')!;
    expect(mark.grade.index, greaterThan(DecisionGrade.good.index), reason: 'far from the stones');
  });

  test('the score falls with the loss: 37 at 10%', () {
    expect(gomokuScale.scoreFor(0), 100);
    expect(gomokuScale.scoreFor(0.1), 37);
    expect(gomokuScale.gradeFor(0.02), DecisionGrade.best);
    expect(gomokuScale.gradeFor(0.31), DecisionGrade.blunder);
  });
}
