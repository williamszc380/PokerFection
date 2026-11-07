import 'package:flutter/widgets.dart';

import '../../../../app/app_settings.dart';
import '../../../../games/gomoku/gomoku.dart';
import '../../../kit/l10n/game_strings.dart';
import 'gomoku_strings_en.dart';
import 'gomoku_strings_es.dart';
import 'gomoku_strings_zh.dart';

/// Gomoku's glossary entries, in the order the glossary lists them.
enum GomokuTerm {
  bestMove,
  provenWin,
  five,
  openFour,
  four,
  openThree,
  brokenThree,
  fourThree,
  doubleThree,
  doubleFour,
  vcf,
  overline,
  forbiddenMove,
  freestyle,
  standard,
  renju,
  firstMove,
}

/// The figures of the Threats guide, in order.
enum GomokuFigure {
  five,
  openFour,
  four,
  openThree,
  brokenThree,
  fourThree,
  doubleThree,
  doubleFour,
  vcf,
  forbiddenThree,
  forbiddenFour,
  forbiddenOverline,
}

/// Gomoku's own words in English, Spanish and Chinese: the panel, the
/// coach's reasons, the setup, the guides, the glossary and the rules. The
/// kit reads it through [GameStrings]. Enums become text through
/// exhaustive switches, so a new reason or term stops compilation until all
/// three languages have it.
abstract class GomokuStrings implements GameStrings {
  const GomokuStrings();

  static GomokuStrings forLanguage(AppLanguage language) => switch (language) {
    AppLanguage.english => const GomokuStringsEn(),
    AppLanguage.spanish => const GomokuStringsEs(),
    AppLanguage.chinese => const GomokuStringsZh(),
  };

  static GomokuStrings of(BuildContext context) => forLanguage(AppSettings.of(context).language);

  // ---- the table and the panel ----

  /// The player's own seat, beside its stone colour and as the setup's
  /// colour row: "Player" (as Hold'em's S.you), never "You".
  String get you;

  /// A side: "Black", "White".
  String color(Stone stone);

  /// Puts the aimed stone down (touch: aim, then this or a second tap).
  String get place;

  /// Renju: Black's only move when every free point is forbidden.
  String get pass;

  /// A move as the panel shows it: "h8", or the word for a pass.
  String moveName(String notation) => notation == 'pass' ? pass : notation;

  /// A proven result: "Wins in 3", "Loses in 2".
  String winsIn(int moves);
  String losesIn(int moves);

  /// A coach reason, in a few words.
  String reason(MoveReason reason);

  // ---- the setup ----

  String get rule;
  String get board;
  String get random;
  String ruleName(WinRule rule);
  String boardSize(int size) => '$size×$size';

  // ---- the guides ----

  /// The learning guide's name.
  String get threats;
  String figureTitle(GomokuFigure figure);
  String figureCaption(GomokuFigure figure);

  // ---- the glossary ----

  String term(GomokuTerm term);
  String definition(GomokuTerm term);
  GameTerm entry(GomokuTerm t) => GameTerm(term(t), definition(t));

  @override
  List<GameTerm> get glossary => [for (final t in GomokuTerm.values) entry(t)];

  @override
  String? tagLabel(String tag) => null;

  @override
  List<String> samples() => [
    pickLabel,
    you,
    for (final stone in Stone.values) color(stone),
    place,
    pass,
    moveName('pass'),
    winsIn(3),
    losesIn(2),
    for (final r in MoveReason.values) reason(r),
    rule,
    board,
    random,
    for (final w in WinRule.values) ruleName(w),
    threats,
    for (final f in GomokuFigure.values) ...[figureTitle(f), figureCaption(f)],
    for (final t in GomokuTerm.values) ...[term(t), definition(t)],
    for (final (title, body) in rulesSections) ...[title, body],
  ];
}
