import 'package:flutter/material.dart';

import '../../../games/big_two/app/big_two_match.dart';
import '../../../games/big_two/app/big_two_record.dart';
import '../../../games/big_two/app/big_two_rules_codec.dart';
import '../../../games/big_two/big_two.dart';
import '../../../kit/game_keys.dart';
import '../../../kit/match.dart';
import '../../../kit/seats.dart';
import '../../../l10n/strings.dart';
import '../../kit/help.dart';
import '../../kit/l10n/game_strings.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../kit/match_view.dart';
import '../../kit/setup_kit.dart';
import 'big_two_controller.dart';
import 'big_two_guides.dart' show BigTwoPresetsHelp;
import 'big_two_screen.dart';
import 'l10n/big_two_strings.dart';

/// Big Two's setup: the table (players, cards each, the bots' level or one
/// level per seat, Training or Free Play, the scoring, the match's target)
/// and the rules (a preset, or any mix of the switches: Custom). It starts from the last game's choices.
/// Options the other choices rule out are greyed out, never hidden; every
/// explanation is behind a "?".
class BigTwoSetupScreen extends StatefulWidget {
  const BigTwoSetupScreen({super.key, this.initial, this.onStart});

  /// The choices to start from; null: the last game's (or the defaults).
  final BigTwoSetup? initial;

  /// What Start does; null: replace this screen with the game.
  final void Function(BuildContext context, BigTwoSetup setup)? onStart;

  @override
  State<BigTwoSetupScreen> createState() => _BigTwoSetupScreenState();
}

class _BigTwoSetupScreenState extends State<BigTwoSetupScreen> {
  late BigTwoSetup _setup = widget.initial ?? BigTwoSetup.from(null);
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) _loadLast();
  }

  Future<void> _loadLast() async {
    final last = await KitScope.of(context).lastGames
        .load(GameKeys.bigTwo, version: bigTwoRecordVersion, validate: BigTwoRecord.validate);
    // A choice made while loading wins over the record.
    if (!mounted || _touched || last == null) return;
    setState(() => _setup = BigTwoSetup.from(last));
  }

  BigTwoRules get _rules => _setup.rules;

  void _change({
    BigTwoRules? rules,
    KitLevel? level,
    List<KitLevel>? Function()? seatLevels,
    bool? training,
    MatchTarget? match,
  }) {
    setState(() {
      _touched = true;
      final newRules = rules ?? _setup.rules;
      var custom = seatLevels == null ? _setup.seatLevels : seatLevels();
      // One level per bot: as many as the bots.
      if (custom != null && custom.length != newRules.players - 1) {
        custom = [for (var i = 0; i < newRules.players - 1; i++) i < custom.length ? custom[i] : _setup.level];
      }
      // Another scoring counts other points (penalties, or wins): its own
      // standard target, keeping No limit and the scaling as they were.
      var target = match ?? _setup.match;
      if (newRules.scoring != _setup.rules.scoring && target.points != null) {
        target = target.copyWith(points: () => bigTwoStandardTarget(newRules.scoring).points);
      }
      _setup = BigTwoSetup(
        rules: newRules,
        level: level ?? _setup.level,
        seatLevels: custom,
        training: training ?? _setup.training,
        match: target,
        toggles: _setup.toggles,
      );
    });
  }

  void _start() {
    final start = widget.onStart;
    if (start != null) return start(context, _setup);
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => BigTwoScreen(setup: _setup)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final k = KitStrings.of(context);
    final t = BigTwoStrings.of(context);
    final rules = _rules;
    final rows = BigTwoRuleRows(
      context,
      rules: rules,
      onChanged: (rules) => _change(rules: rules),
    );
    final custom = _setup.seatLevels;
    final match = _setup.match;
    return SetupPage(
      title: s.bigTwo,
      onStart: _start,
      left: [
        SetupSection(
          label: s.players,
          child: ChoiceRow<int>(
            key: const ValueKey('players'),
            values: const [2, 3, 4],
            selected: rules.players,
            label: (n) => '$n',
            onChanged: (n) => _change(rules: BigTwoRulesCodec.withPlayers(rules, n)),
          ),
        ),
        rows.cardsEach(),
        if (custom == null)
          LevelRow(
            value: _setup.level,
            onChanged: (level) => _change(level: level),
          )
        else
          // One line per bot: its name, then its level.
          for (final (i, level) in custom.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 14 : 6),
              child: Row(
                children: [
                  SizedBox(width: 56, child: Text(kitBotNames[i], style: Theme.of(context).textTheme.titleSmall)),
                  Flexible(
                    child: ChoiceRow<KitLevel>(
                      key: ValueKey('seat ${i + 1}'),
                      values: KitLevel.values,
                      selected: level,
                      label: k.kitLevel,
                      onChanged: (l) => _change(seatLevels: () => [...custom]..[i] = l),
                    ),
                  ),
                ],
              ),
            ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SwitchRow(
            key: const ValueKey('customize seats'),
            label: t.customizeSeats,
            value: custom != null,
            onChanged: (on) => _change(seatLevels: () => on ? _setup.levels : null),
          ),
        ),
        ModeRow(
          training: _setup.training,
          onChanged: (training) => _change(training: training),
        ),
        ...rows.scoring(),
      ],
      right: [
        ...rows.ruleSwitches(),
        ...rows.match(match, onChanged: (match) => _change(match: match)),
      ],
    );
  }
}

/// Big Two's rule rows, as the setup lays them out, for the setup and for a
/// room's rules (the online part's rules form): cards each, the scoring and
/// its doublings, the preset and every rule switch, and the match's target.
/// Each "?" explains its rule. With [enabled] off every row is greyed out
/// (a guest sees the host's choices; the "?"s still open).
class BigTwoRuleRows {
  BigTwoRuleRows(this.context, {required this.rules, required this.onChanged, this.enabled = true})
    : t = BigTwoStrings.of(context);

  final BuildContext context;
  final BigTwoRules rules;
  final ValueChanged<BigTwoRules> onChanged;
  final bool enabled;
  final BigTwoStrings t;

  TermsHelpButton _help(String title, List<BigTwoTerm> terms, [List<GameTerm> more = const []]) =>
      TermsHelpButton(title: title, terms: [for (final term in terms) t.entry(term), ...more], all: t.glossary);

  /// A rule switch's "?": what it does, then where each preset stands on it
  /// and its source.
  TermsHelpButton _ruleHelp(String title, BigTwoTerm term, bool Function(BigTwoRules) on, List<BigTwoSource> from) =>
      _help(title, [term], [t.byPresetEntry((r) => t.onOff(on(r)), sources: from)]);

  void _change(BigTwoRules newRules) {
    if (enabled) onChanged(newRules);
  }

  /// Cards each: the deal sizes the player count allows, the rest greyed out.
  Widget cardsEach() => SetupSection(
    label: t.cardsEach,
    child: ChoiceRow<int>(
      key: const ValueKey('cards each'),
      values: const [13, 17, 21],
      selected: rules.cardsEach,
      label: (n) => '$n',
      // The deal sizes the player count allows; the rest greyed out.
      enabled: (n) => enabled && BigTwoRulesCodec.cardsEachFor(rules.players).contains(n),
      onChanged: (n) => _change(rules.copyWith(cardsEach: n)),
    ),
  );

  /// The scoring, then its doublings (greyed out under Pusoy Dos).
  List<Widget> scoring() {
    final penalty = rules.scoring == BigTwoScoring.penalty;
    return [
      SetupSection(
        label: t.scoring,
        help: _help(
          t.scoring,
          const [BigTwoTerm.penalty, BigTwoTerm.pusoyScoring, BigTwoTerm.doubling],
          [t.byPresetEntry((r) => t.scoringName(r.scoring), sources: BigTwoSources.scoring)],
        ),
        child: ChoiceRow<BigTwoScoring>(
          key: const ValueKey('scoring'),
          values: BigTwoScoring.values,
          selected: rules.scoring,
          label: t.scoringName,
          enabled: (_) => enabled,
          onChanged: (scoring) => _change(rules.copyWith(scoring: scoring)),
        ),
      ),
      const SizedBox(height: 4),
      // The doublings belong to penalty scoring: greyed out under Pusoy Dos.
      SwitchRow(
        key: const ValueKey('double twos'),
        label: t.doubleTwosLeft,
        value: rules.doubleTwosLeft,
        enabled: enabled && penalty,
        help: _ruleHelp(t.doubleTwosLeft, BigTwoTerm.doubling, (r) => r.doubleTwosLeft, BigTwoSources.doubling),
        onChanged: (on) => _change(rules.copyWith(doubleTwosLeft: on)),
      ),
      SwitchRow(
        key: const ValueKey('double bombs'),
        label: t.doubleBombLeft,
        value: rules.doubleBombLeft,
        enabled: enabled && penalty,
        help: _ruleHelp(t.doubleBombLeft, BigTwoTerm.doubling, (r) => r.doubleBombLeft, BigTwoSources.doubling),
        onChanged: (on) => _change(rules.copyWith(doubleBombLeft: on)),
      ),
    ];
  }

  /// The preset, the straights, the flushes and every rule switch.
  List<Widget> ruleSwitches() => [
    // Its choices wrap onto a second line when they don't fit (Spanish,
    // a narrow screen): Custom always in sight.
    PresetRow<BigTwoPreset>(
      key: const ValueKey('presets'),
      label: S.of(context).rules,
      presets: BigTwoPreset.values,
      selected: BigTwoRulesCodec.presetOf(rules),
      name: t.preset,
      help: BigTwoPresetsHelp(title: S.of(context).rules),
      enabled: enabled,
      onChanged: (preset) => _change(BigTwoRules.preset(preset, players: rules.players, cardsEach: rules.cardsEach)),
    ),
    SetupSection(
      label: t.straights,
      // Which runs count in each order and how they rank, then each
      // preset's order.
      help: _help(
        t.straights,
        const [BigTwoTerm.straight],
        [
          for (final rule in BigTwoStrings.allStraights) t.straightEntry(rule),
          t.byPresetEntry((r) => t.straightName(r.straights)),
        ],
      ),
      // Long labels ("J-Q-K-A-2"): they wrap rather than scroll sideways.
      child: ChoiceRow<StraightRule>(
        key: const ValueKey('straights'),
        values: BigTwoRulesCodec.straights,
        selected: rules.straights,
        label: t.straightName,
        enabled: (_) => enabled,
        onChanged: (rule) => _change(rules.copyWith(straights: rule)),
      ),
    ),
    SetupSection(
      label: t.flushes,
      help: _help(
        t.flushes,
        const [BigTwoTerm.flush],
        [
          for (final order in FlushOrder.values) t.flushEntry(order),
          t.byPresetEntry((r) => t.flushOrder(r.flushOrder)),
        ],
      ),
      child: ChoiceRow<FlushOrder>(
        key: const ValueKey('flushes'),
        values: FlushOrder.values,
        selected: rules.flushOrder,
        label: t.flushOrder,
        enabled: (_) => enabled,
        onChanged: (order) => _change(rules.copyWith(flushOrder: order)),
      ),
    ),
    const SizedBox(height: 8),
    SwitchRow(
      key: const ValueKey('bombs'),
      enabled: enabled,
      label: t.bombs,
      value: rules.bombs,
      help: _ruleHelp(t.bombs, BigTwoTerm.bomb, (r) => r.bombs, BigTwoSources.bombs),
      onChanged: (on) => _change(rules.copyWith(bombs: on)),
    ),
    SwitchRow(
      key: const ValueKey('same type'),
      enabled: enabled,
      label: t.sameFiveType,
      value: rules.fiveCardSameType,
      help: _ruleHelp(t.sameFiveType, BigTwoTerm.sameType, (r) => r.fiveCardSameType, BigTwoSources.sameType),
      onChanged: (on) => _change(rules.copyWith(fiveCardSameType: on)),
    ),
    SwitchRow(
      key: const ValueKey('lockout'),
      enabled: enabled,
      label: t.passLockout,
      value: rules.passLockout,
      help: _ruleHelp(t.passLockout, BigTwoTerm.lockout, (r) => r.passLockout, BigTwoSources.passLockout),
      onChanged: (on) => _change(rules.copyWith(passLockout: on)),
    ),
    SwitchRow(
      key: const ValueKey('last card'),
      enabled: enabled,
      label: t.lastCardRule,
      value: rules.lastCardRule,
      help: _ruleHelp(t.lastCardRule, BigTwoTerm.lastCard, (r) => r.lastCardRule, BigTwoSources.lastCard),
      onChanged: (on) => _change(rules.copyWith(lastCardRule: on)),
    ),
    SwitchRow(
      key: const ValueKey('dragon'),
      label: t.dragonWins,
      value: rules.dragonWins,
      // Only 13-card hands can hold a dragon.
      enabled: enabled && rules.cardsEach == 13,
      help: _ruleHelp(t.dragonWins, BigTwoTerm.dragon, (r) => r.dragonWins, BigTwoSources.dragon),
      onChanged: (on) => _change(rules.copyWith(dragonWins: on)),
    ),
    SwitchRow(
      key: const ValueKey('top two'),
      enabled: enabled,
      label: t.noTopTwoFinish,
      value: rules.noTopSingleFinish,
      help: _ruleHelp(t.noTopTwoFinish, BigTwoTerm.topTwo, (r) => r.noTopSingleFinish, BigTwoSources.topTwo),
      onChanged: (on) => _change(rules.copyWith(noTopSingleFinish: on)),
    ),
  ];

  /// The match: play to a target (the scoring's choices) or No limit, and
  /// what "Scale with players" makes of it at this table ([target]: null,
  /// worked out from [rules]).
  List<Widget> match(MatchTarget match, {required ValueChanged<MatchTarget> onChanged, int? target}) {
    final at = target ?? bigTwoMatchTarget(match, rules);
    return [
      // The match: play to a target (the scoring's choices) or No limit,
      // and the target scaled for the table chosen. Last, after the rules:
      // the rules decide what the points are.
      // Greyed out with the rest, its "?" still in reach.
      MatchTargetRow(
        key: const ValueKey('match target'),
        value: match,
        choices: bigTwoTargetChoices(rules.scoring),
        terms: [
          GameTerm(
            t.term(BigTwoTerm.match),
            [
              t.definition(BigTwoTerm.match),
              t.source([for (final s in BigTwoSources.match) t.sourceName(s)]),
            ].join('\n'),
          ),
        ],
        enabled: enabled,
        onChanged: (target) {
          if (enabled) onChanged(target);
        },
      ),
      // What "Scale with players" makes of the target at this table.
      if (match.scale && at != null)
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 4),
          child: Text(
            t.scaledTarget(at),
            key: const ValueKey('scaled target'),
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
    ];
  }
}
