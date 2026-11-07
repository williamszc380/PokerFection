import 'package:flutter/material.dart';

import '../kit/game_keys.dart';
import '../l10n/strings.dart';
import 'charts_screen.dart';
import 'games/big_two/big_two_entry.dart';
import 'games/blackjack/blackjack_entry.dart';
import 'games/doudizhu/doudizhu_entry.dart';
import 'games/gomoku/gomoku_entry.dart';
import 'hand_rankings_screen.dart';
import 'setup_screen.dart';
import 'widgets/game_emblems.dart';

// Drills are off for now: uncomment to bring them back.
// import '../app/drills.dart';
// import 'drill_screen.dart';

/// The games the app teaches.
enum GameId { holdem, gomoku, bigTwo, fightTheLandlord, blackjack }

/// The key that names a new game everywhere outside the UI: its folders,
/// its jobs, its saved most recent game (see GameKeys). Hold'em came
/// first and keeps its own names, so it has none.
extension GameIdKey on GameId {
  String get key => switch (this) {
        GameId.holdem => throw UnsupportedError("Hold'em has no game key"),
        GameId.gomoku => GameKeys.gomoku,
        GameId.bigTwo => GameKeys.bigTwo,
        GameId.fightTheLandlord => GameKeys.doudizhu,
        GameId.blackjack => GameKeys.blackjack,
      };
}

/// A game on Home: its [name], its [emblem] (drawn at any size), and the
/// buttons of its menu (see GameMenu). A game without a [menu] isn't built
/// yet: Home greys it out and marks it "Soon". Giving it a menu makes it
/// playable.
class GameInfo {
  const GameInfo({required this.id, required this.name, required this.emblem, this.menu});

  final GameId id;
  final String Function(S s) name;
  final Widget Function(double size) emblem;

  /// The game menu's buttons, top to bottom, the first one (Play) stands out.
  final List<GameMenuButton>? menu;

  bool get ready => menu != null;
}

/// A button on a game's menu: it opens a screen ([open]), or a row of
/// [choices] right under it (as Guides does), each opening its own.
class GameMenuButton {
  const GameMenuButton({required this.icon, required this.label, this.open, this.choices = const [], this.enabled});

  final IconData icon;

  /// The button's text, in the app's language: from S, KitStrings or the
  /// game's own strings (which is why it gets the context, not just S).
  final String Function(BuildContext context) label;
  final WidgetBuilder? open;
  final List<GameMenuButton> choices;

  /// Whether the button can be used now, for one that sometimes can't
  /// (Last game, when there is none yet); null: always. The menu asks once
  /// when it opens and again each time the menu is back on top (a game just
  /// played), and greys the button out until the answer is yes.
  final Future<bool> Function(BuildContext context)? enabled;
}

/// Every game, in Home's order. Each new game becomes playable by giving
/// its entry a menu.
final games = <GameInfo>[
  GameInfo(
    id: GameId.holdem,
    name: (s) => s.holdem,
    emblem: (size) => HoldemEmblem(size: size),
    menu: [
      GameMenuButton(
        icon: Icons.play_arrow,
        label: (context) => S.of(context).play,
        open: (_) => const SetupScreen(),
      ),
      // Drills are off for now: uncomment to bring them back. The old main
      // menu (main_menu.dart, removed after commit 2c03cfa) also showed how
      // many spots are due, "Drills (3 due)" (S.drillsDue, kept for this),
      // and woke itself up when one fell due: its label can read
      // Drills.maybeOf(context), but the menu must also rebuild then.
      // GameMenuButton(
      //   icon: Icons.event_repeat,
      //   label: (context) => S.of(context).drills,
      //   open: (context) => DrillScreen(drills: Drills.maybeOf(context)!),
      // ),
      GameMenuButton(
        icon: Icons.menu_book_outlined,
        label: (context) => S.of(context).guides,
        choices: [
          GameMenuButton(
            icon: Icons.format_list_numbered,
            label: (context) => S.of(context).handRankings,
            open: (_) => const HandRankingsScreen(),
          ),
          GameMenuButton(
            icon: Icons.grid_view,
            label: (context) => S.of(context).preflopCharts,
            open: (_) => const ChartsScreen(),
          ),
        ],
      ),
    ],
  ),
  // The new games: each one's entry lives in its own folder
  // (lib/src/ui/games/<key>/<key>_entry.dart), where its menu is added.
  gomokuGame,
  bigTwoGame,
  doudizhuGame,
  blackjackGame,
];
