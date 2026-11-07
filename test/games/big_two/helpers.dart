import 'package:pokerfection/src/games/big_two/big_two.dart';

/// The play made by [cards] (short notation such as `3d 3s`) under [rules].
/// Fails the test if they don't form a combination.
Play play(BigTwoRules rules, String cards) {
  final p = rules.classify(parseCards(cards));
  if (p == null) throw ArgumentError('Not a combination: $cards');
  return p;
}

/// Whether [cards] form any combination under [rules].
bool isCombination(BigTwoRules rules, String cards) => rules.classify(parseCards(cards)) != null;

/// A deal with hands given by text, one string per seat.
BigTwoState dealOf(BigTwoRules rules, List<String> hands, {String? extra, int? leader}) => BigTwoState.fromHands(
      rules,
      [for (final h in hands) parseCards(h)],
      extra: extra == null ? null : Card.parse(extra),
      leader: leader,
    );

/// The legal move matching [cards] (or a pass for `pass`), failing if there
/// is none.
Play legalMove(BigTwoState s, String cards) {
  if (cards == 'pass') {
    if (!s.legalMoves().contains(Play.pass)) throw StateError('Passing is not legal here');
    return Play.pass;
  }
  final want = play(s.rules, cards);
  return s.legalMoves().firstWhere((m) => m == want, orElse: () => throw StateError('Not legal: $cards'));
}

/// Plays a series of moves ("3d", "pass", "4s 4h", ...) in turn order.
void playMoves(BigTwoState s, List<String> moves) {
  for (final m in moves) {
    s.apply(legalMove(s, m));
  }
}

/// Short labels of plays, for readable expectations.
List<String> labels(Iterable<Play> plays) => [for (final p in plays) p.cards.map((c) => c.short).join(' ')];
