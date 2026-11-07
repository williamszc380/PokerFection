/// What every game's own strings class offers the kit (each game has one,
/// `<Prefix>Strings` in `lib/src/ui/games/<key>/l10n/`).
library;

/// One glossary entry: the term, and what it means.
class GameTerm {
  const GameTerm(this.term, this.definition);

  final String term;
  final String definition;
}

abstract interface class GameStrings {
  /// The coach's pick and the coach chip's label: "GTO", "Best move",
  /// "Basic strategy".
  String get pickLabel;

  /// A coach row's tag other than the pick (Blackjack: 'count' → "Count");
  /// null: none.
  String? tagLabel(String tag);

  /// The game's glossary, in order.
  List<GameTerm> get glossary;

  /// The rules as titled sections (Guides > Rules and ☰ Rules).
  List<(String title, String body)> get rulesSections;

  /// Every text of the class, functions called with sample arguments (for
  /// the kit's strings test).
  List<String> samples();
}
