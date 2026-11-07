import '../../../games/doudizhu/app/doudizhu_range.dart';
import '../../kit/l10n/game_strings.dart';
import '../../kit/range_sheet.dart';
import 'l10n/doudizhu_strings.dart';

/// How an opponent's range names Fight the Landlord's ranks and
/// combinations: ranks as the cards show them ('T' is "10", the jokers
/// short: "LJ" / "BJ", 小 / 大), kinds by the players' words ("Pairs",
/// "Pair straights", 王炸), each combination as its cards ("3 4 5 6 7",
/// "LJ BJ"), and the kinds explained under "?".
RangeLook landlordRangeLook(LandlordStrings s) => RangeLook(
  rankLabel: (code) => switch (code) {
    'SJ' => s.jokerShort(big: false),
    'BJ' => s.jokerShort(big: true),
    'T' => '10',
    _ => code,
  },
  comboLabel: s.rangeKind,
  comboText: (combo) => ddzRangeComboText(s, combo),
  terms: [for (final kind in ddzRangeKinds) GameTerm(s.rangeKind(kind), s.rangeKindInfo(kind))],
);

/// A combination of a range (the engine's rank letters: "556677", the
/// rocket "BR") as its cards, each rank's cards together and the ranks
/// apart: "55 66 77", "3 4 5 6 7", "LJ BJ". A 10's cards keep a thin space
/// ("10 10"), so they don't read as "1010".
String ddzRangeComboText(LandlordStrings s, String combo) {
  String label(String ch) => switch (ch) {
    'T' => '10',
    'B' => s.jokerShort(big: false),
    'R' => s.jokerShort(big: true),
    _ => ch,
  };
  final groups = <List<String>>[];
  for (final ch in combo.split('')) {
    if (groups.isNotEmpty && groups.last.first == ch) {
      groups.last.add(ch);
    } else {
      groups.add([ch]);
    }
  }
  return [
    for (final g in groups) g.map(label).join(label(g.first).length > 1 ? '\u2009' : ''),
  ].join(' ');
}
