import 'package:flutter/widgets.dart';

import '../../../app/app_settings.dart';
import '../../../kit/coach_answer.dart';
import '../../../kit/hand_order.dart';
import '../../../kit/seats.dart';
import 'game_strings.dart';
import 'kit_strings_en.dart';
import 'kit_strings_es.dart';
import 'kit_strings_zh.dart';

export '../../../kit/hand_order.dart' show HandOrder;
export '../../../kit/seats.dart' show KitLevel;

/// The kit's glossary entries (opened from the "?" buttons and ☰ Glossary).
enum KitTerm { training, freePlay, coach, grades, score, level, lastGame, showCards, range, playTo }

/// The words every new game shares, in English, Spanish and Chinese. Kept
/// out of the app's `S` so the kit and the games never edit the app's
/// strings; words of `S` that read right are reused (New Game, Rules,
/// Free Play, Start, the grades, "Score 87", "Ana…").
abstract class KitStrings {
  const KitStrings();

  static KitStrings of(BuildContext context) => forLanguage(AppSettings.of(context).language);

  static KitStrings forLanguage(AppLanguage language) => switch (language) {
        AppLanguage.english => const KitStringsEn(),
        AppLanguage.spanish => const KitStringsEs(),
        AppLanguage.chinese => const KitStringsZh(),
      };

  /// The mode with grades ("Training", not poker's "GTO Training").
  String get trainingMode;
  String get lastGame;
  String get thinkLonger;
  String get yourTurn;
  String get youWin;
  String get youLose;
  String get draw;
  String wins(String name);
  String get nextDeal;
  String get deal;
  String get newShoe;
  String get level;
  String kitLevel(KitLevel level);
  String get bots;
  String get custom;
  String get coach;

  /// [pct] as formatValue gives it: "62%".
  String winChance(String pct);

  /// [x] as formatValue gives it: "+1.4".
  String pointsValue(String x);
  String betsValue(String x);
  String net(String x);
  String moveNumber(int n);
  String get allCards;

  /// A turn without a play, in the play history (a game may give its own word).
  String get pass;

  /// A trick's heading in the play history: "Trick 2".
  String trick(int n);

  /// The hand's Sort button: the order the hand is in ("Rank", "Suit"), or,
  /// once the player has moved a card, what a tap does ("Sort").
  String handOrder(HandOrder order);

  /// ☰'s Training option to see the opponents' cards face up.
  String get showCards;

  /// The label on a card everyone at the table can see (Fight the
  /// Landlord's face-up card, Big Two's starting card), shown while the
  /// mouse is over it or on a long press.
  String get visibleToAll;

  /// The range sheet: its title for [name] holding [cards] cards
  /// ("Range · Ana · 7 cards"), what it shows, and its states.
  String rangeTitle(String name, int cards);
  String get rangeRanks;
  String get rangeCombos;
  String get rangeWorking;
  String get rangeFailed;

  /// The sheet stays open but the game has no range to work out any more
  /// (the deal ended behind it): said instead of "Working it out…" for ever.
  String get rangeNone;

  /// Under the sheet: how many possible deals the chances come from.
  String rangeSamples(int n);

  /// The match: the setup's row ("Play to", "No limit", "Scale with
  /// players"), the scoreboard, and the end.
  String get playTo;
  String get noLimit;
  String get scaleWithPlayers;
  String get scores;
  String get total;
  String get newMatch;
  String dealNumber(int n);

  /// The target, on the scoreboard and the status line: "To 100".
  String target(int points);
  String get youWinMatch;
  String winsMatch(String name);

  /// The match ended with [names] sharing the best total (Fight the
  /// Landlord's two peasants score alike): nobody won it alone.
  String matchTie(List<String> names);
  String term(KitTerm term);
  String definition(KitTerm term);

  /// [v] with its unit: "−7%", "+1.4 pts", "−0.03 bets".
  String amount(ValueUnit unit, double v) => switch (unit) {
        ValueUnit.winChance => formatValue(unit, v),
        ValueUnit.points => pointsValue(formatValue(unit, v)),
        ValueUnit.bets => betsValue(formatValue(unit, v)),
      };

  /// A kit glossary entry, as the games' glossaries hold them.
  GameTerm entry(KitTerm term) => GameTerm(this.term(term), definition(term));

  /// Every text, functions called with sample arguments (for the strings test).
  List<String> samples() => [
        trainingMode,
        lastGame,
        thinkLonger,
        yourTurn,
        youWin,
        youLose,
        draw,
        wins('Ana'),
        nextDeal,
        deal,
        newShoe,
        level,
        for (final l in KitLevel.values) kitLevel(l),
        bots,
        custom,
        coach,
        winChance('62%'),
        pointsValue('+1.4'),
        betsValue('−0.03'),
        net('+3.5'),
        moveNumber(12),
        allCards,
        pass,
        trick(2),
        for (final o in HandOrder.values) handOrder(o),
        showCards,
        visibleToAll,
        rangeTitle('Ana', 7),
        rangeRanks,
        rangeCombos,
        rangeWorking,
        rangeFailed,
        rangeNone,
        rangeSamples(400),
        playTo,
        noLimit,
        scaleWithPlayers,
        scores,
        total,
        newMatch,
        dealNumber(3),
        target(100),
        youWinMatch,
        winsMatch('Ana'),
        matchTie(['Ana', 'Ben']),
        for (final t in KitTerm.values) ...[term(t), definition(t)],
      ];
}
