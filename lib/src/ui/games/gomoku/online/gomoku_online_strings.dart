import 'package:flutter/widgets.dart';

import '../../../../app/app_settings.dart';
import '../../../../games/gomoku/online/gomoku_view_codec.dart';
import '../../../kit/l10n/game_strings.dart';

/// The few words Gomoku needs in a room beyond the solo game's
/// (GomokuStrings): the host's rule for who plays Black, and its "?".
abstract class GomokuOnlineStrings {
  const GomokuOnlineStrings();

  static GomokuOnlineStrings forLanguage(AppLanguage language) => switch (language) {
    AppLanguage.english => const _En(),
    AppLanguage.spanish => const _Es(),
    AppLanguage.chinese => const _Zh(),
  };

  static GomokuOnlineStrings of(BuildContext context) => forLanguage(AppSettings.of(context).language);

  /// The rules form's row: who plays Black.
  String get black;

  /// Each way of picking Black, as a choice.
  String blackRule(GomokuBlackRule rule);

  /// The row's "?": what each choice does.
  GameTerm get blackHelp;

  /// Every string, for the language checks.
  List<String> samples() => [
    black,
    for (final r in GomokuBlackRule.values) blackRule(r),
    blackHelp.term,
    blackHelp.definition,
  ];
}

class _En extends GomokuOnlineStrings {
  const _En();

  @override
  String get black => 'Black';

  @override
  String blackRule(GomokuBlackRule rule) => switch (rule) {
    GomokuBlackRule.turns => 'Take turns',
    GomokuBlackRule.random => 'Random',
    GomokuBlackRule.loser => 'Loser',
  };

  @override
  GameTerm get blackHelp => const GameTerm(
    'Who plays Black',
    'Black moves first, a big edge. Take turns: the players swap colours every game. Random: drawn each game. '
        'Loser: whoever lost the last game plays Black (after a draw, colours swap).',
  );
}

class _Es extends GomokuOnlineStrings {
  const _Es();

  @override
  String get black => 'Negras';

  @override
  String blackRule(GomokuBlackRule rule) => switch (rule) {
    GomokuBlackRule.turns => 'Por turnos',
    GomokuBlackRule.random => 'Al azar',
    GomokuBlackRule.loser => 'Perdedor',
  };

  @override
  GameTerm get blackHelp => const GameTerm(
    'Quién juega con negras',
    'Las negras mueven primero, una gran ventaja. Por turnos: los jugadores cambian de color en cada partida. '
        'Al azar: se sortea en cada partida. Perdedor: quien perdió la última partida juega con negras (tras un '
        'empate, se cambian los colores).',
  );
}

class _Zh extends GomokuOnlineStrings {
  const _Zh();

  @override
  String get black => '执黑';

  @override
  String blackRule(GomokuBlackRule rule) => switch (rule) {
    GomokuBlackRule.turns => '轮流',
    GomokuBlackRule.random => '随机',
    GomokuBlackRule.loser => '输家',
  };

  @override
  GameTerm get blackHelp => const GameTerm('谁执黑', '黑棋先下，优势很大。轮流：每局双方交换颜色。随机：每局随机决定。输家：上一局输的一方执黑（平局后交换颜色）。');
}
