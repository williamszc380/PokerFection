import 'package:flutter/material.dart';

import '../../../games/gomoku/app/gomoku_record.dart';
import '../../../games/gomoku/gomoku.dart';
import '../../../kit/game_keys.dart';
import '../../../l10n/strings.dart';
import '../../kit/help.dart';
import '../../kit/kit_scope.dart';
import '../../kit/setup_kit.dart';
import 'gomoku_screen.dart';
import 'l10n/gomoku_strings.dart';

/// Gomoku's setup: the rule (Freestyle, Standard, Renju), the board (19×19
/// greyed out under Renju, which is played on 15×15), the Player's colour
/// (the row is labelled with the user's seat, as on the table), the bot's
/// level and Training or Free Play. It starts from the last game's choices.
class GomokuSetup extends StatefulWidget {
  const GomokuSetup({super.key});

  @override
  State<GomokuSetup> createState() => _GomokuSetupState();
}

class _GomokuSetupState extends State<GomokuSetup> {
  var _options = const GomokuOptions();
  var _toggles = const <String, Object?>{};

  @override
  void initState() {
    super.initState();
    KitScope.of(context).lastGames
        .load(GameKeys.gomoku, version: gomokuRecordVersion, validate: GomokuRecord.validate)
        .then((last) {
          if (last == null || !mounted) return;
          setState(() {
            _options = GomokuOptions.fromRecord(last);
            _toggles = {if (last.extra['coach'] case final bool coach) 'coach': coach};
          });
        });
  }

  void _set(GomokuOptions options) => setState(() => _options = options);

  void _rule(WinRule rule) {
    // Renju is played on 15×15 only.
    final size = rule == WinRule.renju ? 15 : _options.rules.size;
    _set(
      _options.copyWith(
        rules: GomokuRules(size: size, winRule: rule),
      ),
    );
  }

  void _start() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GomokuScreen(options: _options, toggles: _toggles),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = GomokuStrings.of(context);
    final rules = _options.rules;
    return SetupPage(
      title: S.of(context).gomoku,
      onStart: _start,
      left: [
        SetupSection(
          label: g.rule,
          help: TermsHelpButton(
            title: g.rule,
            terms: [
              for (final t in const [
                GomokuTerm.freestyle,
                GomokuTerm.standard,
                GomokuTerm.renju,
                GomokuTerm.overline,
                GomokuTerm.forbiddenMove,
              ])
                g.entry(t),
            ],
          ),
          child: ChoiceRow<WinRule>(
            key: const ValueKey('rule'),
            values: WinRule.values,
            selected: rules.winRule,
            label: g.ruleName,
            onChanged: _rule,
          ),
        ),
        SetupSection(
          label: g.board,
          child: ChoiceRow<int>(
            key: const ValueKey('board'),
            values: const [15, 19],
            selected: rules.size,
            label: g.boardSize,
            enabled: (size) => size == 15 || rules.winRule != WinRule.renju,
            onChanged: (size) => _set(
              _options.copyWith(
                rules: GomokuRules(size: size, winRule: rules.winRule),
              ),
            ),
          ),
        ),
        SetupSection(
          label: g.you,
          help: TermsHelpButton(title: g.term(GomokuTerm.firstMove), terms: [g.entry(GomokuTerm.firstMove)]),
          child: ChoiceRow<GomokuColorChoice>(
            key: const ValueKey('color'),
            values: GomokuColorChoice.values,
            selected: _options.color,
            label: (c) => switch (c) {
              GomokuColorChoice.black => g.color(Stone.black),
              GomokuColorChoice.white => g.color(Stone.white),
              GomokuColorChoice.random => g.random,
            },
            onChanged: (c) => _set(_options.copyWith(color: c)),
          ),
        ),
      ],
      right: [
        LevelRow(
          value: _options.level,
          onChanged: (level) => _set(_options.copyWith(level: level)),
        ),
        ModeRow(
          training: _options.training,
          onChanged: (training) => _set(_options.copyWith(training: training)),
        ),
      ],
    );
  }
}
