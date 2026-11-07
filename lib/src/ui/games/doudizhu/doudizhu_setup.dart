import 'package:flutter/material.dart';

import '../../../games/doudizhu/doudizhu.dart';
import '../../../kit/match.dart';
import '../../../l10n/strings.dart';
import '../../kit/help.dart';
import '../../kit/kit_scope.dart';
import '../../kit/l10n/game_strings.dart';
import '../../kit/l10n/kit_strings.dart';
import '../../kit/setup_kit.dart';
import 'doudizhu_controller.dart';
import 'doudizhu_review.dart';
import 'doudizhu_screen.dart';
import 'l10n/doudizhu_strings.dart';

/// The multiplier caps offered (null: no cap).
const landlordCaps = <int?>[null, 8, 16, 32, 64];

/// Setting up a game of Fight the Landlord: the bots' level (one for both,
/// or one per seat), Training or Free Play, the match's target, then the
/// rules: a preset or each switch on its own. Three players always (the
/// engine plays the 3-player game). Starts from the last game's choices.
class LandlordSetup extends StatefulWidget {
  const LandlordSetup({super.key});

  @override
  State<LandlordSetup> createState() => _LandlordSetupState();
}

class _LandlordSetupState extends State<LandlordSetup> {
  var _rules = DdzRules.standard;
  var _level = KitLevel.medium;
  var _custom = false;
  var _levels = [KitLevel.medium, KitLevel.medium];
  var _training = true;
  var _match = landlordStandardMatch;
  Map<String, Object?> _extra = const {};
  var _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    loadLastDeal(KitScope.of(context).lastGames).then((record) {
      if (record == null || !mounted) return;
      final last = LandlordChoice.of(record);
      setState(() {
        _rules = last.rules;
        _levels = [...last.levels];
        _custom = _levels.toSet().length > 1;
        _level = _levels.first;
        _training = last.training;
        _match = last.match;
        _extra = last.extra;
      });
    });
  }

  void _start() {
    final choice = LandlordChoice(
      rules: _rules,
      levels: _custom ? _levels : [_level, _level],
      training: _training,
      match: _match,
      extra: _extra,
    );
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => LandlordScreen(choice: choice)));
  }

  void _set(DdzRules rules) => setState(() => _rules = rules);

  @override
  Widget build(BuildContext context) {
    final s = LandlordStrings.of(context);
    final k = KitStrings.of(context);
    Widget seatLevel(int i, IconData side) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(side, size: 18, color: _custom ? Colors.white70 : Theme.of(context).disabledColor),
          const SizedBox(width: 8),
          Flexible(
            child: ChoiceRow<KitLevel>(
              key: ValueKey('seat level $i'),
              values: KitLevel.values,
              selected: _custom ? _levels[i] : _level,
              label: k.kitLevel,
              enabled: (_) => _custom,
              onChanged: (l) => setState(() => _levels[i] = l),
            ),
          ),
        ],
      ),
    );
    return SetupPage(
      title: S.of(context).fightTheLandlord,
      onStart: _start,
      left: [
        LevelRow(
          value: _level,
          onChanged: (l) => setState(() {
            _level = l;
            _levels = [l, l];
          }),
        ),
        SwitchRow(
          key: const ValueKey('customize seats'),
          label: s.customizeSeats,
          value: _custom,
          onChanged: (on) => setState(() {
            _custom = on;
            if (on) _levels = [_level, _level];
          }),
        ),
        // The left bot (seat 2) and the right one (seat 1), as at the table.
        seatLevel(1, Icons.west),
        seatLevel(0, Icons.east),
        ModeRow(training: _training, onChanged: (t) => setState(() => _training = t)),
        LandlordMatchRow(
          value: _match,
          help: [s.entry(LandlordTerm.match)],
          onChanged: (m) => setState(() => _match = m),
        ),
      ],
      right: landlordRulesRows(context, _rules, _set),
    );
  }
}

/// The match's target: "Play to" 20, 30, 50, 100 points (see
/// [landlordTargets]) or No limit, and "Scale with players", greyed out:
/// Fight the Landlord always has three players, so there is nothing to
/// scale (its "?" says so). The kit's MatchTargetRow, with that switch
/// greyed out; [help] adds the game's scoring to the "?".
class LandlordMatchRow extends StatelessWidget {
  const LandlordMatchRow({super.key, required this.value, required this.onChanged, this.help = const []});

  final MatchTarget value;
  final ValueChanged<MatchTarget> onChanged;
  final List<GameTerm> help;

  @override
  Widget build(BuildContext context) {
    final k = KitStrings.of(context);
    return SetupSection(
      label: k.playTo,
      help: TermsHelpButton(title: k.playTo, terms: [k.entry(KitTerm.playTo), ...help]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ChoiceRow<int?>(
            key: const ValueKey('play to'),
            values: const [...landlordTargets, null],
            selected: value.points,
            label: (points) => points == null ? k.noLimit : '$points',
            onChanged: (points) => onChanged(value.copyWith(points: () => points)),
          ),
          const SizedBox(height: 4),
          SwitchRow(
            key: const ValueKey('scale with players'),
            label: k.scaleWithPlayers,
            value: false,
            // Always three players: greyed out, never hidden.
            enabled: false,
            onChanged: (_) {},
          ),
        ],
      ),
    );
  }
}

/// The setup's rules, its right column: a preset (Standard, App, Beginner,
/// or Custom) or each switch on its own, with each one's "?". A room's
/// Rules show the same rows (doudizhu_online_ui.dart), greyed out unless
/// [enabled] (only the host changes them, between games); [set] gets the
/// new rules.
List<Widget> landlordRulesRows(BuildContext context, DdzRules r, ValueChanged<DdzRules> set, {bool enabled = true}) {
  final s = LandlordStrings.of(context);
  final k = KitStrings.of(context);
  final preset = DdzRules.presets.entries.where((e) => e.value == r).firstOrNull?.key;
  Widget help(List<GameTerm> terms) => TermsHelpButton(title: terms.first.term, terms: terms, all: s.glossary);
  final multiplies = r.bombsDouble || r.springDoubles;
  final presets = DdzRules.presets.keys.toList();
  return [
    if (enabled)
      PresetRow<String>(
        label: S.of(context).rules,
        presets: presets,
        selected: preset,
        name: s.presetName,
        onChanged: (p) => set(DdzRules.presets[p]!),
      )
    else
      // The kit's PresetRow, greyed out: its segments, none to pick.
      SetupSection(
        label: S.of(context).rules,
        child: ChoiceRow<int>(
          values: [for (var i = 0; i < presets.length; i++) i, -1],
          selected: preset == null ? -1 : presets.indexOf(preset),
          label: (i) => i < 0 ? k.custom : s.presetName(presets[i]),
          enabled: (_) => false,
          onChanged: (_) {},
        ),
      ),
    SetupSection(
      label: s.bidding,
      help: help([s.entry(LandlordTerm.bidding), s.entry(LandlordTerm.callRob), s.entry(LandlordTerm.faceUpCard)]),
      child: ChoiceRow<BiddingStyle>(
        values: BiddingStyle.values,
        selected: r.bidding,
        label: s.biddingStyle,
        enabled: (_) => enabled,
        onChanged: (b) => set(r.copyWith(bidding: b)),
      ),
    ),
    SetupSection(
      label: s.allPass,
      child: ChoiceRow<AllPassRule>(
        values: AllPassRule.values,
        selected: r.allPass,
        label: s.allPassRule,
        enabled: (_) => enabled,
        onChanged: (a) => set(r.copyWith(allPass: a)),
      ),
    ),
    const SizedBox(height: 10),
    SwitchRow(
      key: const ValueKey('four with two'),
      label: s.fourWithTwo,
      value: r.fourWithTwo,
      enabled: enabled,
      // What it is first; then, as in the guide, what each kind beats.
      help: help([
        GameTerm(s.fourWithTwo, s.fourWithTwoInfo),
        for (final kind in const [PlayType.fourTwoSolos, PlayType.fourTwoPairs])
          GameTerm(s.kind(kind), '${s.beats}: ${s.kindRule(kind)}'),
      ]),
      onChanged: (v) => set(r.copyWith(fourWithTwo: v)),
    ),
    SwitchRow(
      key: const ValueKey('rocket as kickers'),
      label: s.rocketAsKickers,
      value: r.rocketAsKickers,
      enabled: enabled,
      help: help([GameTerm(s.rocketAsKickers, s.rocketAsKickersInfo), s.entry(LandlordTerm.rocket)]),
      onChanged: (v) => set(r.copyWith(rocketAsKickers: v)),
    ),
    SwitchRow(
      key: const ValueKey('kitty shown'),
      label: s.kittyShown,
      value: r.kittyShown,
      enabled: enabled,
      help: help([s.entry(LandlordTerm.kitty)]),
      onChanged: (v) => set(r.copyWith(kittyShown: v)),
    ),
    SwitchRow(
      key: const ValueKey('bombs double'),
      label: s.bombsDouble,
      value: r.bombsDouble,
      enabled: enabled,
      help: help([s.entry(LandlordTerm.bomb), s.entry(LandlordTerm.rocket), s.entry(LandlordTerm.multiplier)]),
      onChanged: (v) => set(r.copyWith(bombsDouble: v)),
    ),
    SwitchRow(
      key: const ValueKey('spring doubles'),
      label: s.springDoubles,
      value: r.springDoubles,
      enabled: enabled,
      help: help([s.entry(LandlordTerm.spring)]),
      onChanged: (v) => set(r.copyWith(springDoubles: v)),
    ),
    SetupSection(
      label: s.maxMultiplier,
      help: help([s.entry(LandlordTerm.multiplier)]),
      child: ChoiceRow<int?>(
        key: const ValueKey('max multiplier'),
        values: landlordCaps,
        selected: r.maxMultiplier,
        label: (cap) => cap == null ? s.noLimit : s.multiplier(cap),
        // Nothing doubles: there is nothing to cap.
        enabled: (_) => enabled && multiplies,
        onChanged: (cap) => set(cap == null ? r.copyWith(clearMaxMultiplier: true) : r.copyWith(maxMultiplier: cap)),
      ),
    ),
  ];
}
