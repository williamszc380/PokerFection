import 'package:flutter/material.dart';

import '../../../l10n/strings.dart';
import '../../games.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../widgets/game_emblems.dart';
import 'big_two_guides.dart';
import 'big_two_review.dart';
import 'big_two_setup.dart';
import 'l10n/big_two_strings.dart';

/// Big Two on Home and in its menu (see GameInfo): Play opens the setup
/// (which starts from the last game's choices and then becomes the game),
/// Last game the review of the most recent deal, greyed out until one is
/// saved (asked again whenever a screen opened from the menu closes), and
/// Guides the rules and the hand ranks (shown for the last game's rules).
final bigTwoGame = GameInfo(
  id: GameId.bigTwo,
  name: (s) => s.bigTwo,
  emblem: (size) => BigTwoEmblem(size: size),
  menu: [
    GameMenuButton(icon: Icons.play_arrow, label: (c) => S.of(c).play, open: (_) => const BigTwoSetupScreen()),
    GameMenuButton(
      icon: Icons.history,
      label: (c) => KitStrings.of(c).lastGame,
      open: (_) => const BigTwoReview(),
      enabled: (c) async => await loadLastBigTwo(KitScope.of(c).lastGames) != null,
    ),
    GameMenuButton(
      icon: Icons.menu_book_outlined,
      label: (c) => S.of(c).guides,
      choices: [
        GameMenuButton(icon: Icons.rule, label: (c) => S.of(c).rules, open: (_) => const BigTwoRulesGuide()),
        GameMenuButton(
          icon: Icons.format_list_numbered,
          label: (c) => BigTwoStrings.of(c).handRanks,
          open: (_) => const BigTwoHandRanksGuide(),
        ),
      ],
    ),
  ],
);
