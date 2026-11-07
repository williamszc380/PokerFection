import 'package:flutter/material.dart';

import '../../../l10n/strings.dart';
import '../../games.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../widgets/game_emblems.dart';
import 'gomoku_guides.dart';
import 'gomoku_review.dart';
import 'gomoku_setup.dart';
import 'l10n/gomoku_strings.dart';

/// Gomoku on Home and in its menu (see GameInfo): Play opens the setup
/// (which then becomes the game), Last game the review of the most recent
/// game, greyed out until one is saved (asked again whenever a screen
/// opened from the menu closes), and Guides the rules and the threats
/// (the shapes that win: fours, open threes, four-threes...).
final gomokuGame = GameInfo(
  id: GameId.gomoku,
  name: (s) => s.gomoku,
  emblem: (size) => GomokuEmblem(size: size),
  menu: [
    GameMenuButton(icon: Icons.play_arrow, label: (c) => S.of(c).play, open: (_) => const GomokuSetup()),
    GameMenuButton(
      icon: Icons.history,
      label: (c) => KitStrings.of(c).lastGame,
      open: (_) => const GomokuReview(),
      enabled: (c) async => await loadLastGomoku(KitScope.of(c).lastGames) != null,
    ),
    GameMenuButton(
      icon: Icons.menu_book_outlined,
      label: (c) => S.of(c).guides,
      choices: [
        GameMenuButton(icon: Icons.rule, label: (c) => S.of(c).rules, open: (_) => const GomokuRulesGuide()),
        GameMenuButton(
          icon: Icons.grid_on,
          label: (c) => GomokuStrings.of(c).threats,
          open: (_) => const GomokuThreatsGuide(),
        ),
      ],
    ),
  ],
);
