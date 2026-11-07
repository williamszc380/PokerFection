import 'package:flutter/material.dart';

import '../../../games/blackjack/app/blackjack_grading.dart';
import '../../../games/blackjack/app/blackjack_record.dart';
import '../../../games/blackjack/blackjack.dart';
import '../../../kit/game_keys.dart';
import '../../../l10n/strings.dart';
import '../../kit/help.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../kit/setup_kit.dart';
import 'blackjack_controller.dart';
import 'blackjack_screen.dart';
import 'l10n/blackjack_strings.dart';

/// The table's rules before a game: a preset (Custom by itself once a
/// switch matches none), each rule, then the coach's assumption (Fresh shoe
/// or Cards seen) and the mode. Filled in from the last game. One player
/// betting 1 a round, so there are no Players or Bet rows. Rules that can't
/// apply with the others are greyed out: penetration and Cards seen with a
/// continuous shuffler, resplitting aces when a pair splits only once, the
/// coach in Free Play. Start replaces the page with the game, so Back
/// from the game goes straight to the menu.
class BlackjackSetup extends StatefulWidget {
  const BlackjackSetup({super.key});

  /// The decks a table can use.
  static const deckChoices = [1, 2, 6, 8];

  /// The penetrations offered (share of the shoe dealt before the shuffle).
  static const penetrationChoices = [0.6, 0.65, 0.75, 0.85];

  /// The payouts offered.
  static const payoutChoices = [BlackjackPayout.threeToTwo, BlackjackPayout.sixToFive];

  @override
  State<BlackjackSetup> createState() => _BlackjackSetupState();
}

class _BlackjackSetupState extends State<BlackjackSetup> {
  var _settings = const BlackjackSettings();
  var _touched = false;

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  /// The last game's choices, unless the player has already changed one.
  Future<void> _loadLast() async {
    final record = await KitScope.of(context).lastGames.load(
      GameKeys.blackjack,
      version: blackjackRecordVersion,
      // A shoe that doesn't replay (broken, or from an older engine) is ignored.
      validate: blackjackReplays,
    );
    if (record == null || !mounted || _touched) return;
    try {
      final settings = BlackjackSettings.fromRecord(record);
      setState(() => _settings = settings);
    } on Object {
      // A record we can't read keeps the defaults.
    }
  }

  void _set({BlackjackRules? rules, bool? training, CoachMode? coachMode}) => setState(() {
    _touched = true;
    _settings = _settings.copyWith(rules: rules, training: training, coachMode: coachMode);
  });

  void _start() {
    var settings = _settings;
    // Nothing to count with a continuous shuffler: the coach assumes a fresh shoe.
    if (settings.rules.continuousShuffle && settings.coachMode == CoachMode.seen) {
      settings = settings.copyWith(coachMode: CoachMode.fresh);
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => BlackjackScreen(settings: settings)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final k = KitStrings.of(context);
    final b = BlackjackStrings.of(context);
    final rules = _settings.rules;
    Widget help(List<BlackjackTerm> terms) =>
        TermsHelpButton(title: b.term(terms.first), terms: [for (final t in terms) b.entry(t)], all: b.glossary);
    final csm = rules.continuousShuffle;
    final rows = blackjackRuleRows(context, rules, onChanged: (r) => _set(rules: r));
    return SetupPage(
      title: s.blackjack,
      onStart: _start,
      // The shoe and the dealer on the left; the player's options, the
      // coach and the mode on the right: on a PC both columns fit without
      // scrolling.
      left: rows.left,
      right: [
        ...rows.right,
        SetupSection(
          label: k.coach,
          help: help([BlackjackTerm.freshShoe, BlackjackTerm.cardsSeen, BlackjackTerm.basicStrategy]),
          child: ChoiceRow<CoachMode>(
            values: CoachMode.values,
            selected: csm ? CoachMode.fresh : _settings.coachMode,
            label: b.coachMode,
            enabled: (m) => _settings.training && (m == CoachMode.fresh || !csm),
            onChanged: (m) => _set(coachMode: m),
          ),
        ),
        ModeRow(
          training: _settings.training,
          onChanged: (t) => _set(training: t),
        ),
      ],
    );
  }
}

/// The table's rules as rows, the shoe and the dealer ([left]) and the
/// player's options ([right]): a preset (Custom by itself once a switch
/// matches none), then each rule with its "?". Rules that can't apply with
/// the others are greyed out (penetration with a continuous shuffler,
/// resplitting aces when a pair splits only once, what a dealer blackjack
/// takes at a hole card table), and every row is greyed out unless
/// [enabled]. The setup shows them in two columns; a room's Rules part
/// (BlackjackOnlineUi.rulesForm) in one, greyed out for all but the host.
({List<Widget> left, List<Widget> right}) blackjackRuleRows(
  BuildContext context,
  BlackjackRules rules, {
  required ValueChanged<BlackjackRules> onChanged,
  bool enabled = true,
}) {
  final b = BlackjackStrings.of(context);
  Widget help(List<BlackjackTerm> terms) =>
      TermsHelpButton(title: b.term(terms.first), terms: [for (final t in terms) b.entry(t)], all: b.glossary);
  BlackjackPreset? preset;
  for (final p in BlackjackPreset.values) {
    if (BlackjackRules.preset(p) == rules) preset = p;
  }
  final csm = rules.continuousShuffle;
  bool all(Object? _) => enabled;
  return (
    left: [
      if (enabled)
        PresetRow<BlackjackPreset>(
          label: b.presetLabel,
          presets: BlackjackPreset.values,
          selected: preset,
          name: b.preset,
          onChanged: (p) => onChanged(BlackjackRules.preset(p)),
        )
      else
        // The kit's PresetRow, every segment greyed out.
        SetupSection(
          label: b.presetLabel,
          child: ChoiceRow<BlackjackPreset?>(
            values: [...BlackjackPreset.values, null],
            selected: preset,
            label: (p) => p == null ? KitStrings.of(context).custom : b.preset(p),
            enabled: all,
            onChanged: (_) {},
          ),
        ),
      SetupSection(
        label: b.decks,
        help: help([BlackjackTerm.shoe]),
        child: ChoiceRow<int>(
          values: BlackjackSetup.deckChoices,
          selected: rules.decks,
          label: (d) => '$d',
          enabled: all,
          onChanged: (d) => onChanged(rules.copyWith(decks: d)),
        ),
      ),
      SetupSection(
        label: b.blackjackPays,
        help: help([BlackjackTerm.blackjack]),
        child: ChoiceRow<BlackjackPayout>(
          values: BlackjackSetup.payoutChoices,
          selected: rules.payout,
          label: (p) => p == BlackjackPayout.threeToTwo ? '3:2' : '6:5',
          enabled: all,
          onChanged: (p) => onChanged(rules.copyWith(payout: p)),
        ),
      ),
      const SizedBox(height: 10),
      SwitchRow(
        label: b.dealerHitsSoft17,
        value: rules.dealerHitsSoft17,
        enabled: enabled,
        help: help([BlackjackTerm.soft17]),
        onChanged: (v) => onChanged(rules.copyWith(dealerHitsSoft17: v)),
      ),
      SwitchRow(
        label: b.continuousShuffle,
        value: csm,
        enabled: enabled,
        help: help([BlackjackTerm.continuousShuffle]),
        onChanged: (v) => onChanged(rules.copyWith(continuousShuffle: v)),
      ),
      SetupSection(
        label: b.penetration,
        help: help([BlackjackTerm.penetration]),
        child: ChoiceRow<double>(
          values: BlackjackSetup.penetrationChoices,
          selected: rules.penetration,
          label: (p) => '${(p * 100).round()}%',
          enabled: (_) => enabled && !csm,
          onChanged: (p) => onChanged(rules.copyWith(penetration: p)),
        ),
      ),
    ],
    right: [
      SetupSection(
        label: b.doubleLabel,
        help: help([BlackjackTerm.double]),
        child: ChoiceRow<DoubleRule>(
          values: DoubleRule.values,
          selected: rules.doubling,
          label: b.doubleRule,
          enabled: all,
          onChanged: (r) => onChanged(rules.copyWith(doubling: r)),
        ),
      ),
      SetupSection(
        label: b.surrenderLabel,
        help: help([BlackjackTerm.surrender]),
        child: ChoiceRow<Surrender>(
          values: Surrender.values,
          selected: rules.surrender,
          label: b.surrenderRule,
          enabled: all,
          onChanged: (r) => onChanged(rules.copyWith(surrender: r)),
        ),
      ),
      const SizedBox(height: 10),
      SwitchRow(
        label: b.doubleAfterSplit,
        value: rules.doubleAfterSplit,
        enabled: enabled && rules.canSplit,
        help: help([BlackjackTerm.doubleAfterSplit]),
        onChanged: (v) => onChanged(rules.copyWith(doubleAfterSplit: v)),
      ),
      SwitchRow(
        label: b.resplitAces,
        value: rules.resplitAces,
        // Split once only (2 hands): there is no second split.
        enabled: enabled && rules.maxHands >= 3,
        help: help([BlackjackTerm.resplitAces]),
        onChanged: (v) => onChanged(rules.copyWith(resplitAces: v)),
      ),
      SwitchRow(
        label: b.holeCard,
        value: rules.holeCard,
        enabled: enabled,
        help: help([BlackjackTerm.holeCard]),
        onChanged: (v) => onChanged(rules.copyWith(holeCard: v)),
      ),
      SetupSection(
        label: b.noHoleCardLossLabel,
        help: help([BlackjackTerm.noHoleCardLoss]),
        child: ChoiceRow<NoHoleCardLoss>(
          key: const ValueKey('no hole card loss'),
          values: NoHoleCardLoss.values,
          selected: rules.noHoleCardLoss,
          label: b.noHoleCardLoss,
          // With a hole card the dealer's blackjack is found before
          // anyone doubles or splits: the rule never comes up.
          enabled: (_) => enabled && !rules.holeCard,
          onChanged: (r) => onChanged(rules.copyWith(noHoleCardLoss: r)),
        ),
      ),
    ],
  );
}
