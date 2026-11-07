import 'package:flutter/material.dart';

import '../../../l10n/strings.dart';
import '../../games.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../widgets/game_emblems.dart';
import 'doudizhu_guides.dart';
import 'doudizhu_review.dart';
import 'doudizhu_setup.dart';
import 'l10n/doudizhu_strings.dart';

/// Fight the Landlord on Home and in its menu (see GameInfo): Play opens
/// the setup (which then becomes the game), Last game the review of the
/// most recent deal, greyed out until one is saved (asked again whenever a
/// screen opened from the menu closes), and Guides the rules and the
/// combinations.
final doudizhuGame = GameInfo(
  id: GameId.fightTheLandlord,
  name: (s) => s.fightTheLandlord,
  emblem: (size) => LandlordEmblem(size: size),
  menu: [
    GameMenuButton(icon: Icons.play_arrow, label: (c) => S.of(c).play, open: (_) => const LandlordSetup()),
    GameMenuButton(
      icon: Icons.history,
      label: (c) => KitStrings.of(c).lastGame,
      open: (_) => const LandlordReview(),
      enabled: (c) async => await loadLastDeal(KitScope.of(c).lastGames) != null,
    ),
    GameMenuButton(
      icon: Icons.menu_book_outlined,
      label: (c) => S.of(c).guides,
      choices: [
        GameMenuButton(icon: Icons.rule, label: (c) => S.of(c).rules, open: (_) => const LandlordRulesGuide()),
        GameMenuButton(
          icon: Icons.style,
          label: (c) => LandlordStrings.of(c).combinations,
          open: (_) => const LandlordCombinationsGuide(),
        ),
      ],
    ),
  ],
);
