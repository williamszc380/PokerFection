import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';

/// The landlord's opening lead of a dealt game: 20 cards, and usually far
/// more legal leads than the coach rates.
DdzGame openingLead(int seed) {
  final g = DdzGame.deal(random: Random(seed), firstBidder: 0);
  g.act(const DdzBid(3));
  return g;
}

const small = DdzBudget(rollouts: 200, maxCandidates: 8);

void main() {
  group('include: a move the coach must rate', () {
    test('a lead the quick sort leaves out is rated when included, and nothing else changes', () {
      final g = openingLead(4);
      final view = g.viewFor(0);
      final plain = const DdzCoach(budget: small).analyze(view, random: Random(1));
      expect(view.legalMoves.length, greaterThan(small.maxCandidates));
      final left = view.legalMoves.firstWhere((m) => plain.candidateFor(m) == null);

      final asked = const DdzCoach(budget: small).analyze(view, random: Random(1), include: left);
      expect(asked.candidateFor(left), isNotNull, reason: 'rated now');
      expect(asked.lossOf(left), isNotNull, reason: 'so it can be graded');
      expect(asked.candidates, hasLength(small.maxCandidates + 1), reason: 'added to the usual candidates');
      for (final c in plain.candidates) {
        expect(asked.candidateFor(c.move), isNotNull, reason: '${c.move} is still rated');
      }
    });

    test('a move already rated is not added twice', () {
      final g = openingLead(4);
      final view = g.viewFor(0);
      final plain = const DdzCoach(budget: small).analyze(view, random: Random(1));
      final asked = const DdzCoach(budget: small).analyze(view, random: Random(1), include: plain.best.move);
      expect(asked.candidates, hasLength(plain.candidates.length));
      expect({for (final c in asked.candidates) c.move.encode()}, hasLength(asked.candidates.length));
    });

    test('passing can be included when following, as any play', () {
      final g = openingLead(9);
      g.act(g.legalMoves().firstWhere((m) => m is DdzPlay && m.play.type == PlayType.solo));
      final view = g.viewFor(1);
      final asked = const DdzCoach(budget: small).analyze(view, random: Random(2), include: const DdzPass());
      expect(asked.candidateFor(const DdzPass()), isNotNull);
    });

    test('in the auction every bid is rated anyway', () {
      final g = DdzGame.deal(random: Random(5), firstBidder: 0);
      final view = g.viewFor(0);
      final a = const DdzCoach(budget: small).analyze(view, random: Random(1), include: const DdzBid(2));
      expect(a.candidates, hasLength(view.legalMoves.length));
    });

    test('a move that is not legal is refused', () {
      final g = openingLead(4);
      expect(
        () => const DdzCoach(budget: small).analyze(g.viewFor(0), random: Random(1), include: const DdzPass()),
        throwsArgumentError,
        reason: 'the landlord leads: passing is not allowed',
      );
    });
  });
}
