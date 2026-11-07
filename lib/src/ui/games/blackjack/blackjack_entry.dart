import 'package:flutter/material.dart';

import '../../../l10n/strings.dart';
import '../../games.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../widgets/game_emblems.dart';
import 'blackjack_guides.dart';
import 'blackjack_review.dart';
import 'blackjack_setup.dart';
import 'l10n/blackjack_strings.dart';

/// Blackjack on Home and in its menu (see GameInfo): Play opens the setup
/// (which then gives way to the game), Last game the review of the most
/// recent shoe, greyed out until one is saved (asked again whenever the
/// menu is back on top), and Guides the rules and the basic strategy
/// chart.
final blackjackGame = GameInfo(
  id: GameId.blackjack,
  name: (s) => s.blackjack,
  emblem: (size) => BlackjackEmblem(size: size),
  menu: [
    GameMenuButton(icon: Icons.play_arrow, label: (c) => S.of(c).play, open: (_) => const BlackjackSetup()),
    GameMenuButton(
      icon: Icons.history,
      label: (c) => KitStrings.of(c).lastGame,
      open: (_) => const BlackjackReview(),
      enabled: (c) async => await loadLastShoe(KitScope.of(c).lastGames) != null,
    ),
    GameMenuButton(
      icon: Icons.menu_book_outlined,
      label: (c) => S.of(c).guides,
      choices: [
        GameMenuButton(icon: Icons.rule, label: (c) => S.of(c).rules, open: (_) => const BlackjackRulesGuide()),
        GameMenuButton(
          icon: Icons.grid_view,
          label: (c) => BlackjackStrings.of(c).pickLabel,
          open: (_) => const BlackjackStrategyGuide(),
        ),
      ],
    ),
  ],
);
