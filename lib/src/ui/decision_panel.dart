import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../gto/spot_strategy.dart';
import 'format.dart';
import '../l10n/strings.dart';
import 'glossary.dart';
import 'history_screen.dart';
import 'strategy_panel.dart';
import 'table_controller.dart';
import 'widgets/mix_slider.dart';

/// Everything the user decides, next to the table.
///
/// Both modes show the same choices the same way, at every decision: fold,
/// check or call and raise (any size) in one column, each raise size of the
/// user's menu and all-in in another, each with a tick box to pick the one
/// to play. Choices not allowed here are greyed out. In Guess the GTO mode
/// every row also gets a percentage, and a bar on top sets them all at once:
/// the user sets how often they think GTO takes each choice, plays the
/// ticked one (or one drawn from their mix) and sees GTO's answer with a
/// score.
class DecisionPanel extends StatefulWidget {
  const DecisionPanel({super.key, required this.controller});

  final TableController controller;

  @override
  State<DecisionPanel> createState() => DecisionPanelState();
}

/// Where fold, check or call, and the raises are in a menu.
class _Rows {
  _Rows(this.menu) {
    for (var i = 0; i < menu.length; i++) {
      switch (menu[i].kind) {
        case SpotActionKind.fold:
          fold = i;
        case SpotActionKind.check || SpotActionKind.call:
          passive = i;
        case SpotActionKind.raise || SpotActionKind.allIn:
          aggressive.add(i);
      }
    }
  }

  final List<SpotAction> menu;
  int fold = 0;
  int passive = 1;
  final List<int> aggressive = [];

  /// The raise choices allowed here, smallest first (all-in last).
  late final List<int> sizes = [
    for (final i in aggressive)
      if (menu[i].available) i,
  ];

  bool get canFold => menu[fold].available;
  bool get canRaise => sizes.isNotEmpty;

  /// The choices allowed here, in the order of the bar.
  List<int> get allowed => [if (canFold) fold, passive, ...sizes];
}

class DecisionPanelState extends State<DecisionPanel> {
  TableController get _c => widget.controller;

  List<SpotAction>? _menu;
  late _Rows _rows;

  /// Percentages for fold, check or call, and raise (any size).
  List<int> _top = const [0, 100, 0];

  /// How the raises split across [_Rows.sizes].
  List<int> _sizes = const [];

  /// The ticked choice (menu index), or null to follow the mix: the choice
  /// with the largest percentage (check or call in Play Hands mode).
  int? _choice;

  /// Play a choice drawn at random from the mix (Guess the GTO mode).
  bool _draw = false;

  /// GTO's answer as last filled in; Show GTO can be pressed again once the
  /// percentages differ from it.
  List<int>? _gtoTop;
  List<int>? _gtoSizes;

  bool get _showingGto =>
      _gtoTop != null && listEquals(_top, _gtoTop) && listEquals(_sizes, _gtoSizes);

  bool get _training => _c.heroSpot != null;

  void _reset(List<SpotAction> menu) {
    _menu = menu;
    _rows = _Rows(menu);
    // By default: always check or call, and raise the smallest size.
    _top = [0, 100, 0];
    _sizes = [for (var k = 0; k < _rows.sizes.length; k++) k == 0 ? 100 : 0];
    _choice = null;
    // With percentages to set, the action played is drawn from them (RNG)
    // unless the user ticks one.
    _draw = _training;
    _gtoTop = null;
    _gtoSizes = null;
  }

  /// How often the user plays each choice (adding up to 1).
  List<double> _mix() {
    final mix = List.filled(_rows.menu.length, 0.0);
    mix[_rows.fold] = _top[0] / 100;
    mix[_rows.passive] = _top[1] / 100;
    for (var k = 0; k < _rows.sizes.length; k++) {
      mix[_rows.sizes[k]] = _top[2] / 100 * _sizes[k] / 100;
    }
    return mix;
  }

  /// The choice that will be played (unless drawn from the mix).
  int get _played {
    final choice = _choice;
    if (choice != null) return choice;
    if (!_training) return _rows.passive;
    final mix = _mix();
    var best = _rows.passive;
    for (var i = 0; i < mix.length; i++) {
      if (mix[i] > mix[best] + 1e-9) best = i;
    }
    return best;
  }

  /// Plays the choice (in Guess the GTO mode: scores the mix first).
  void submit() {
    final menu = _menu;
    if (menu == null || _c.heroScore != null) return;
    if (_training) {
      _c.submitMix(_mix(), choice: _draw ? null : _played);
    } else {
      _c.heroAct(menu[_played].action);
    }
  }

  /// Sets one of fold / check-call / raise, rebalancing the others allowed here.
  void _setTop(int index, int value) => setState(() {
    final on = [if (_rows.canFold) 0, 1, if (_rows.canRaise) 2];
    final changed = rebalancePercents([for (final k in on) _top[k]], on.indexOf(index), value);
    _top = List.filled(3, 0);
    for (var j = 0; j < on.length; j++) {
      _top[on[j]] = changed[j];
    }
  });

  /// Takes the mix set on the bar: [shares] (percent) for the [_Rows.allowed] choices.
  void _setShares(List<double> shares) => setState(() {
    final allowed = _rows.allowed;
    double share(int i) => allowed.contains(i) ? shares[allowed.indexOf(i)] : 0;
    final fold = share(_rows.fold).round(), passive = share(_rows.passive).round();
    _top = [fold, passive, 100 - fold - passive];
    final raises = [for (final i in _rows.sizes) share(i)];
    // With no raise left, the split between the sizes stays as it was.
    if (_top[2] > 0 && raises.any((r) => r > 0)) _sizes = splitWhole(raises, 100);
  });

  /// Fills in GTO's answer as the mix (the user can still change it and
  /// then plays as usual; the decision isn't scored).
  void _reveal() => setState(() {
    final gto = _c.heroSpot!.frequencies;
    final raises = [for (final i in _rows.sizes) gto[i]];
    _top = splitWhole([gto[_rows.fold], gto[_rows.passive], raises.fold(0.0, (a, b) => a + b)], 100);
    if (raises.any((r) => r > 0)) _sizes = splitWhole(raises, 100);
    _gtoTop = List.of(_top);
    _gtoSizes = List.of(_sizes);
  });

  void _tick(int index) => setState(() {
    _choice = index;
    _draw = false;
  });

  /// Ticking "raise" picks the size with the largest share (the smallest
  /// size if they're equal), unless a size is ticked already.
  void _tickRaise() {
    if (_choice != null && _rows.sizes.contains(_choice)) return;
    var best = 0;
    for (var k = 1; k < _sizes.length; k++) {
      if (_sizes[k] > _sizes[best]) best = k;
    }
    _tick(_rows.sizes[best]);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final menu = c.heroMenu;
    if (menu != null && !identical(menu, _menu)) _reset(menu);

    final Widget body;
    if (c.preparing != null) {
      body = _preparing(context, c.preparing!);
    } else if (c.handOver) {
      body = _handOver(context);
    } else if (c.solvingSpot) {
      body = _solving(context);
    } else if (c.heroScore != null && c.heroSpot != null) {
      body = _result(context, c.heroSpot!, c.heroScore!, c.heroMix!);
    } else if (menu != null) {
      body = _input(context);
    } else {
      body = _waiting(context);
    }
    return Material(
      color: const Color(0xFF12171B),
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.guessGto) RecentScores(session: c.session),
            Expanded(
              child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: body),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Choosing
  // ---------------------------------------------------------------------------

  Widget _input(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: Colors.white60);
    final options = _c.heroOptions;
    final training = _training;
    final menu = _rows.menu;
    // In Guess the GTO mode, say why this decision isn't scored.
    final noAnswer = _c.guessGto && !training
        ? s.noAnswer(_c.session.preflop?.unavailable ?? _c.session.postflop?.unavailable)
        : null;
    // Only what the table doesn't already show: the pot odds when facing a bet.
    final potOdds = options == null || !options.canCall
        ? null
        : s.potOdds((options.toCall / (options.pot + options.toCall) * 100).round());
    final played = _played;
    final mix = _mix();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (noAnswer != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(noAnswer, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFFFCC80))),
          ),
        if (potOdds != null) Text(potOdds, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (training)
          MixSlider(
            colors: [for (final i in _rows.allowed) actionColor(menu, i)],
            shares: [for (final i in _rows.allowed) mix[i] * 100],
            // Fold's and check or call's handles above the bar, the raise sizes' below.
            upper: _rows.allowed.indexOf(_rows.passive) + 1,
            onChanged: _setShares,
          ),
        const SizedBox(height: 4),
        Expanded(child: LayoutBuilder(builder: _choices)),
        const SizedBox(height: 6),
        Row(
          children: [
            if (training) ...[
              _SquareTick(
                selected: _draw,
                onTap: () => setState(() => _draw = true),
              ),
              const SizedBox(width: 6),
              Text(s.randomize),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                key: const ValueKey('show gto'),
                onPressed: _showingGto ? null : _reveal,
                icon: const Icon(Icons.visibility, size: 18),
                label: Text(s.showGto),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _PlayButton(
                label: _draw ? s.playRandomized : spotActionLabel(s, menu[played]),
                // Rainbow for a random draw; otherwise the ticked action's own color.
                color: _draw ? null : actionColor(menu, played),
                onPressed: submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static const _percentWidth = 40.0;

  /// The rows: fold, check or call and raise (any size), then below them
  /// each raise size, the same way before and after the flop.
  Widget _choices(BuildContext context, BoxConstraints constraints) {
    final s = S.of(context);
    final menu = _rows.menu;
    final played = _played;
    final passiveLabel = spotActionLabel(s, menu[_rows.passive]);
    // Room for the longest name (and its dot); the sliders get the rest.
    final nameWidth = _textWidth(context, [
          s.fold,
          passiveLabel,
          s.raiseAnySize,
          for (final i in _rows.aggressive) _sizeLabel(s, menu[i]),
        ]) +
        18;
    final name = min(nameWidth, constraints.maxWidth / 2);

    final first = <Widget>[
      _row(
        key: const ValueKey('choice fold'),
        label: s.fold,
        nameWidth: name,
        color: actionColor(menu, _rows.fold),
        reason: _reason(s, menu[_rows.fold].unavailable),
        ticked: !_draw && played == _rows.fold,
        onTick: () => _tick(_rows.fold),
        percent: _top[0],
        onPercent: (v) => _setTop(0, v),
      ),
      _row(
        key: const ValueKey('choice passive'),
        label: passiveLabel,
        nameWidth: name,
        color: actionColor(menu, _rows.passive),
        ticked: !_draw && played == _rows.passive,
        onTick: () => _tick(_rows.passive),
        percent: _top[1],
        onPercent: (v) => _setTop(1, v),
      ),
      _row(
        key: const ValueKey('choice raise'),
        label: s.raiseAnySize,
        nameWidth: name,
        color: _rows.aggressive.isEmpty ? Colors.grey : actionColor(menu, _rows.aggressive.first),
        reason: _rows.canRaise ? null : s.unavailable(Unavailable.raisingNotAllowed),
        ticked: !_draw && _rows.sizes.contains(played),
        onTick: _tickRaise,
        percent: _top[2],
        onPercent: (v) => _setTop(2, v),
      ),
    ];
    final sizes = <Widget>[
      for (final i in _rows.aggressive)
        _row(
          key: ValueKey('choice $i'),
          label: _sizeLabel(s, menu[i]),
          nameWidth: name,
          color: actionColor(menu, i),
          reason: _reason(s, menu[i].unavailable),
          ticked: !_draw && played == i,
          onTick: () => _tick(i),
          percent: menu[i].available ? _sizes[_rows.sizes.indexOf(i)] : 0,
          onPercent: _top[2] > 0 && menu[i].available
              ? (v) => setState(() => _sizes = rebalancePercents(_sizes, _rows.sizes.indexOf(i), v))
              : null,
        ),
    ];

    return SingleChildScrollView(
      child: Column(children: [...first, const Divider(height: 10), ...sizes]),
    );
  }

  /// How wide the widest of [labels] is in the rows' text style.
  static double _textWidth(BuildContext context, List<String> labels) {
    final style = DefaultTextStyle.of(context).style;
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      widest = max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }

  /// "7.5 BB (3×)", "2.8 BB (0.5× pot)", "All-in 100 BB".
  static String _sizeLabel(S s, SpotAction a) {
    if (a.kind == SpotActionKind.allIn) return spotActionLabel(s, a);
    final size = sizeText(s, a);
    return '${formatBb(a.amount, unit: true)}${size == null ? '' : ' ($size)'}';
  }

  static String? _reason(S s, Unavailable? reason) => reason == null ? null : s.unavailable(reason);

  /// One line: tick box, name, and (Guess the GTO mode) slider and percentage.
  Widget _row({
    Key? key,
    required String label,
    required double nameWidth,
    required Color color,
    String? reason,
    required bool ticked,
    required VoidCallback onTick,
    required int percent,
    required ValueChanged<int>? onPercent,
  }) {
    final enabled = reason == null;
    final dim = enabled ? null : Colors.white38;
    final name = Row(
      children: [
        ColorDot(color: enabled ? color : Colors.grey),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: dim),
          ),
        ),
      ],
    );
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          _SquareTick(key: key, selected: enabled && ticked, onTap: enabled ? onTick : null),
          const SizedBox(width: 6),
          if (!_training)
            Expanded(
              child: InkWell(onTap: enabled ? onTick : null, child: name),
            )
          else ...[
            SizedBox(width: nameWidth, child: name),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: color,
                  thumbColor: color,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: percent.toDouble(),
                  max: 100,
                  divisions: 100,
                  onChanged: enabled && onPercent != null ? (v) => onPercent(v.round()) : null,
                ),
              ),
            ),
            SizedBox(
              width: _percentWidth,
              child: Text(
                enabled ? '$percent%' : '–',
                textAlign: TextAlign.right,
                style: TextStyle(color: dim),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // The GTO answer
  // ---------------------------------------------------------------------------

  Widget _result(BuildContext context, SpotStrategy spot, DecisionScore score, List<double> mix) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: Colors.white60);
    final played = _c.heroPlay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GradeChip(grade: score.grade),
            const SizedBox(width: 10),
            Text(s.score(score.score), style: theme.textTheme.titleMedium),
            const HelpButton(section: GlossarySection.scoring),
          ],
        ),
        if (played != null)
          Text(
            _c.heroDrew
                ? s.randomized(spotActionLabel(s, spot.actions[played]))
                : s.youPlay(spotActionLabel(s, spot.actions[played])),
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        Text(
          s.evLossAndMatch('${score.evLoss.toStringAsFixed(2)} BB', (score.mixMatch * 100).round()),
          style: muted,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            child: StrategyComparison(spot: spot, mix: mix, played: played),
          ),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          key: const ValueKey('continue'),
          onPressed: _c.continueHand,
          icon: const Icon(Icons.play_arrow),
          label: Text(s.continueHand),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Between decisions
  // ---------------------------------------------------------------------------

  Widget _preparing(BuildContext context, double progress) => _message(
    context,
    S.of(context).solvingTable((progress * 100).round()),
    LinearProgressIndicator(value: progress),
  );

  Widget _solving(BuildContext context) {
    return _message(context, S.of(context).solvingDecision, const LinearProgressIndicator());
  }

  Widget _waiting(BuildContext context) {
    final seat = _c.view.actingSeat;
    return _message(context, seat == null ? '' : S.of(context).thinking(_c.view.seats[seat].info.name), null);
  }

  Widget _handOver(BuildContext context) {
    final s = S.of(context);
    final String text;
    final Color color;
    final record = _c.session.history.lastOrNull;
    if (_c.guessGto && record != null && record.decisions.isNotEmpty) {
      // Training: what the hand's decisions gave up against optimal play
      // (the chips won or lost are mostly luck).
      text = '${s.evLoss} ${record.evLost.toStringAsFixed(2)} BB';
      color = gradeColor(DecisionGrade.forLoss(record.evLost));
    } else {
      final result = _c.view.heroResult ?? 0;
      text = result == 0 ? s.evenHand : formatSignedBb(result);
      color = result > 0 ? const Color(0xFF81C784) : (result < 0 ? const Color(0xFFE57373) : Colors.white70);
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _c.startNextHand,
          icon: const Icon(Icons.skip_next),
          label: Text(S.of(context).nextHand),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }

  Widget _message(BuildContext context, String text, Widget? progress) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white70),
      ),
      if (progress != null) ...[const SizedBox(height: 10), progress],
    ],
  );
}

/// A square tick box used to pick the choice to play.
class _SquareTick extends StatelessWidget {
  const _SquareTick({super.key, required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final box = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          selected ? Icons.check_box : Icons.check_box_outline_blank,
          size: 22,
          color: selected ? const Color(0xFF81C784) : (enabled ? Colors.white54 : Colors.white12),
        ),
      ),
    );
    return box;
  }
}

/// The button that plays the choice: in the action's color, or in rainbow
/// colors (no [color]) when the action is drawn at random.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.label, required this.color, required this.onPressed});

  final String label;
  final Color? color;
  final VoidCallback onPressed;

  static const _rainbow = [
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
  ];

  @override
  Widget build(BuildContext context) {
    final color = this.color;
    // Dark text on light colors (yellow, amber), white on the rest.
    final text = color != null && ThemeData.estimateBrightnessForColor(color) == Brightness.light
        ? Colors.black87
        : Colors.white;
    final button = FilledButton(
      key: const ValueKey('play'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        backgroundColor: color ?? Colors.transparent,
        foregroundColor: text,
        shadowColor: Colors.transparent,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            // Keeps white text readable over the rainbow's light middle.
            shadows: color == null ? const [Shadow(color: Colors.black54, blurRadius: 3)] : null,
          ),
        ),
      ),
    );
    if (color != null) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: _rainbow),
        borderRadius: BorderRadius.circular(22),
      ),
      child: button,
    );
  }
}
