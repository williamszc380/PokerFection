import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engine/actions.dart';
import '../engine/events.dart';
import '../bots/preflop_ranking.dart';
import '../game/pre_action.dart';
import '../game/table_session.dart';
import '../gto/hand_read.dart';
import '../gto/raise_sizes.dart';
import '../gto/spot_strategy.dart';
import 'format.dart';
import '../l10n/strings.dart';
import '../online/protocol.dart' show JoinError;
import 'glossary.dart';
import 'history_screen.dart';
import 'strategy_panel.dart';
import 'table_controller.dart';
import 'widgets/mix_slider.dart';
import 'widgets/turn_clock.dart';

/// Everything the user decides, next to the table.
///
/// Free Play and simple training show big Fold and Check or Call buttons,
/// and Raise with a slider for any amount up to all-in. Show GTO (a toggle)
/// switches simple training to the list below, with GTO's answer. While
/// someone else acts, toggles take the buttons' places: the pre-actions
/// (Check/Fold, Check or Call, Call Any), played the moment the turn comes.
///
/// The list shows the same choices the same way, at every decision: fold,
/// check or call and raise (any size) in one column, each raise size of the
/// user's menu and all-in in another, each with a tick box to pick the one
/// to play. Choices not allowed here are greyed out. In Guess the GTO mode
/// every row also gets a percentage, and a bar on top sets them all at once:
/// the user sets how often they think GTO takes each choice, plays the
/// ticked one (or one drawn from their mix) and sees GTO's answer with a
/// score.
///
/// Online, the choices show at once and GTO's answer joins them when it is
/// worked out; a move is sent as soon as it is chosen, and its score shows
/// without holding the table. A player out of chips gets Rebuy or Leave
/// (with rebuys), else watches, with the room's Lobby and Leave; one who
/// sits out watches, with I'm Back and Leave.
///
/// In the drills, a line on top says what is played (a saved spot, or
/// random hands); a saved spot's result says when it is back, and Show GTO
/// waits until the spot is played.
class DecisionPanel extends StatefulWidget {
  const DecisionPanel({super.key, required this.controller, this.onLobby});

  final TableController controller;

  /// Online, for a player out of chips: opens the room's lobby.
  final VoidCallback? onLobby;

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

  /// There is a GTO answer for this decision (GTO Training).
  bool get _training => _c.heroSpot != null;

  /// Online: GTO's answer for this decision is still being worked out.
  bool get _awaitingHelp => _online?.helpPending ?? false;

  /// Advanced training: the user sets percentages and gets a score.
  bool get _percentages => (_training || _awaitingHelp) && _c.advanced;

  /// Show GTO was pressed for this decision: each choice's EV loss shows
  /// (and in simple training GTO's percentages, which advanced training
  /// fills in).
  bool _gtoShown = false;

  /// Advanced training: the user's own percentages while Show GTO is on,
  /// put back when it is turned off.
  List<int>? _ownTop;
  List<int>? _ownSizes;

  /// The raise picked on the slider (chips, the total bet).
  int _raiseTo = 0;

  /// What [_reset] started [_draw] and [_raiseTo] at.
  bool _startDraw = false;
  int _startRaiseTo = 0;

  /// The user has changed something since the decision showed.
  bool get _touched =>
      !listEquals(_top, const [0, 100, 0]) ||
      !listEquals(_sizes, [for (var k = 0; k < _rows.sizes.length; k++) k == 0 ? 100 : 0]) ||
      _choice != null ||
      _draw != _startDraw ||
      _raiseTo != _startRaiseTo;

  /// Whether [menu] is the decision showing (online, now with GTO's answer).
  bool _sameDecision(List<SpotAction> menu) {
    final old = _menu;
    if (old == null || old.length != menu.length) return false;
    for (var i = 0; i < menu.length; i++) {
      if (old[i].kind != menu[i].kind || old[i].amount != menu[i].amount) return false;
    }
    return true;
  }

  /// Online: GTO's answer came for the decision showing, after the user
  /// started on it. What they set stays; raise sizes GTO hasn't solved
  /// drop out.
  void _adopt(List<SpotAction> menu) {
    final oldSizes = _rows.sizes, oldShares = _sizes;
    _menu = menu;
    _rows = _Rows(menu);
    final shares = [
      for (final i in _rows.sizes) oldSizes.contains(i) ? oldShares[oldSizes.indexOf(i)].toDouble() : 0.0,
    ];
    _sizes = shares.any((v) => v > 0)
        ? splitWhole(shares, 100)
        : [for (var k = 0; k < _rows.sizes.length; k++) k == 0 ? 100 : 0];
    if (!_rows.canRaise && _top[2] > 0) _top = [_top[0], _top[1] + _top[2], 0];
    final choice = _choice;
    if (choice != null && !menu[choice].available) _choice = null;
  }

  void _reset(List<SpotAction> menu) {
    _menu = menu;
    _rows = _Rows(menu);
    // By default: always check or call, and raise the smallest size.
    _top = [0, 100, 0];
    _sizes = [for (var k = 0; k < _rows.sizes.length; k++) k == 0 ? 100 : 0];
    _choice = null;
    // With percentages to set, the action played is drawn from them (RNG)
    // unless the user ticks one.
    _draw = _percentages;
    _gtoShown = false;
    _gtoTop = null;
    _gtoSizes = null;
    _ownTop = null;
    _ownSizes = null;
    // The slider starts at the smallest raise of the menu.
    final firstRaise = _rows.sizes.where((i) => menu[i].kind == SpotActionKind.raise).firstOrNull;
    _raiseTo = firstRaise != null ? menu[firstRaise].amount : (_rows.sizes.isEmpty ? 0 : menu[_rows.sizes.last].amount);
    _startDraw = _draw;
    _startRaiseTo = _raiseTo;
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
    if (!_percentages) return _rows.passive;
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
    if (_percentages) {
      _c.submitMix(_mix(), choice: _draw ? null : _played);
    } else if (_training || _awaitingHelp) {
      _c.playGraded(_played);
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
    _gtoShown = true;
  });

  /// Show GTO is a toggle. In simple training it switches between the
  /// buttons and the list with GTO's answer; in advanced training it fills
  /// in GTO's mix, and turning it off puts the user's own back. Online,
  /// everyone at the table is told when it is turned on.
  void _toggleGto() {
    if (!_percentages) {
      setState(() => _gtoShown = !_gtoShown);
      if (_gtoShown) _online?.usedHelp();
    } else if (_showingGto) {
      setState(() {
        _top = _ownTop ?? _top;
        _sizes = _ownSizes ?? _sizes;
        _gtoShown = false;
      });
    } else {
      _ownTop = List.of(_top);
      _ownSizes = List.of(_sizes);
      _reveal();
      _online?.usedHelp();
    }
  }

  /// Plays [choice] at once (simple training grades it first); [action] is
  /// a raise of another amount, graded as [choice].
  void _quickPlay(int choice, {PlayerAction? action}) {
    if (_c.heroScore != null) return;
    // Online, a move made before GTO's answer comes is graded once it does.
    if (_training || _awaitingHelp) {
      _c.playGraded(choice, action: action);
    } else {
      _c.heroAct(action ?? _rows.menu[choice].action);
    }
  }

  /// The menu's choice for a raise to [to]: all-in, or the nearest size GTO
  /// has (by ratio, as the trackers match it).
  int _nearestRaise(int to) {
    final menu = _rows.menu;
    final allIn = _rows.aggressive.last;
    if (to >= menu[allIn].amount) return allIn;
    var best = allIn;
    var distance = double.infinity;
    for (final i in _rows.sizes) {
      if (menu[i].kind != SpotActionKind.raise) continue;
      final d = (log(menu[i].amount) - log(to)).abs();
      if (d < distance) (distance, best) = (d, i);
    }
    return best;
  }

  /// Where [to] sits on the raise slider: ratios are spread evenly, so small
  /// raises get as much room as big ones.
  static double _sliderPosition(int to, int minTo, int maxTo) =>
      maxTo <= minTo ? 1 : (log(to / minTo) / log(maxTo / minTo)).clamp(0.0, 1.0);

  /// The raise at [position] on the slider, to 0.5 BB (all-in at the end).
  static int _amountAt(double position, int minTo, int maxTo) {
    if (position >= 1 || maxTo <= minTo) return maxTo;
    final to = roundToHalfBb(minTo * pow(maxTo / minTo, position), TableConfig.bigBlind);
    return to.clamp(minTo, maxTo);
  }

  /// One 0.5 BB step up or down from [to], between the min-raise and all-in.
  static int _stepRaise(int to, int direction, int minTo, int maxTo) {
    final step = halfBigBlind(TableConfig.bigBlind);
    final next = direction > 0 ? (to ~/ step + 1) * step : (to - 1) ~/ step * step;
    return next.clamp(minTo, maxTo);
  }

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

  /// Online: the table's controller.
  OnlineTableController? get _online => switch (_c) {
        final OnlineTableController online => online,
        _ => null,
      };

  /// The mistake drills: the table's controller.
  DrillController? get _drill => switch (_c) {
        final DrillController drill => drill,
        _ => null,
      };

  /// A saved spot is played again: GTO's answer would give it away until
  /// it is played.
  bool get _answerHidden => _drill?.spot != null && _c.heroScore == null;

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final online = _online;
    final menu = c.heroMenu;
    if (menu != null && !identical(menu, _menu)) {
      // Online, GTO's answer can come after the choices: what the user set stays.
      if (online != null && _sameDecision(menu) && _touched) {
        _adopt(menu);
      } else {
        _reset(menu);
      }
    }

    final Widget body;
    if (online != null && online.ended) {
      body = _ended(context, online);
    } else if (online != null) {
      // Online the table doesn't wait: the user's choices first, then the
      // score of their last move (until OK), then whoever acts.
      if (menu != null && c.heroOptions != null && c.heroScore == null) {
        body = _input(context);
      } else if (c.heroScore != null && c.heroSpot != null) {
        body = _result(context, c.heroSpot!, c.heroScore!, c.heroMix!);
      } else if (c.handOver) {
        body = _handOver(context);
      } else if (c.preActionCall case final toCall?) {
        body = _preActions(context, toCall);
      } else {
        body = _waiting(context);
      }
    } else if (c.preparing != null) {
      body = _preparing(context, c.preparing!);
    } else if (c.handOver) {
      body = _handOver(context);
    } else if (c.preActionCall case final toCall?) {
      // Someone else acts (or their answer is being solved): the pre-actions.
      body = _preActions(context, toCall);
    } else if (c.solvingSpot) {
      body = _solving(context);
    } else if (c.heroScore != null && c.heroSpot != null) {
      body = _result(context, c.heroSpot!, c.heroScore!, c.heroMix!);
    } else if (_drill?.outcome case final outcome?) {
      // A saved spot without GTO's answer this time: not graded.
      body = _ungraded(context, outcome);
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
            if (_drill case final drill?) _drillLine(context, drill),
            if (online != null && !online.ended) _onlineNotices(context, online),
            if (online != null && (online.out || online.rebuying))
              _outOfChips(context, online)
            else if (online != null && (online.sittingOut || online.backNextHand))
              _sittingOut(context, online),
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
    // In Guess the GTO mode, say why this decision isn't scored (online,
    // once GTO's answer has been worked out).
    final awaiting = _awaitingHelp;
    final noAnswer = _c.guessGto && !training && !awaiting
        ? s.noAnswer(_c.session.preflop?.unavailable ?? _c.session.postflop?.unavailable)
        : null;
    // With more than two players after the flop, GTO's answer is approximate.
    final hand = _c.session.hand;
    final approximate = training &&
        hand != null &&
        hand.street != Street.preflop &&
        (_c.session.postflop?.approximate ?? false);
    // Only what the table doesn't already show: the pot odds when facing a
    // bet (not online without help: there it is player against player).
    final potOdds = options == null || !options.canCall || (_online != null && !_c.guessGto)
        ? null
        : s.potOdds((options.toCall / (options.pot + options.toCall) * 100).round());
    final notices = [
      if (noAnswer != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(noAnswer, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFFFCC80))),
        ),
      if (approximate)
        Text(s.approxMultiway, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFFFCC80))),
      // Online: GTO's answer is on its way (play on: the move is graded when it comes).
      if (awaiting) _solvingLine(context),
      if (potOdds != null) Text(potOdds, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
      // Online, with a time limit: the time left.
      if (_c.view.turnEnds case final ends?)
        TurnClock.bar(
          ends: ends,
          limit: _c.view.turnLimit ?? Duration.zero,
          text: s.secondsLeft,
          style: muted?.copyWith(color: const Color(0xFFFFE082)),
        ),
    ];
    // Free Play, and simple training until Show GTO: the buttons.
    if (!_percentages && !(training && _gtoShown)) return _quick(context, notices);
    final played = _played;
    final mix = _mix();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...notices,
        if (_percentages)
          MixSlider(
            colors: [for (final i in _rows.allowed) actionColor(menu, i)],
            shares: [for (final i in _rows.allowed) mix[i] * 100],
            // Fold's and check or call's handles above the bar, the raise sizes' below.
            upper: _rows.allowed.indexOf(_rows.passive) + 1,
            onChanged: _setShares,
          ),
        // Simple training, after Show GTO: GTO's mix.
        if (training && !_percentages && _gtoShown) ...[
          const SizedBox(height: 4),
          MixBar(actions: menu, frequencies: _c.heroSpot!.frequencies),
        ],
        const SizedBox(height: 4),
        Expanded(child: LayoutBuilder(builder: _choices)),
        const SizedBox(height: 6),
        Row(
          children: [
            if (_percentages) ...[
              _SquareTick(
                selected: _draw,
                onTap: () => setState(() => _draw = true),
              ),
              const SizedBox(width: 6),
              Text(s.randomize),
              const SizedBox(width: 12),
            ],
            if (training || awaiting) ...[
              _showGtoButton(s),
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

  /// Show GTO, a toggle: highlighted while GTO's answer shows (greyed out
  /// online until it comes, [waiting] for the user's turn, and at a saved
  /// spot until it is played).
  Widget _showGtoButton(S s, {bool waiting = false}) {
    final on = !waiting && (_percentages ? _showingGto : _gtoShown);
    return OutlinedButton.icon(
      key: waiting ? null : const ValueKey('show gto'),
      onPressed: _training && !waiting && !_answerHidden ? _toggleGto : null,
      icon: Icon(on ? Icons.visibility_off : Icons.visibility, size: 18),
      label: Text(s.showGto),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: on ? Colors.white24 : null,
      ),
    );
  }

  /// Free Play, and simple training until Show GTO: big Fold and Check or
  /// Call buttons, and Raise with a slider below it for any amount (to
  /// 0.5 BB) up to all-in. Each button plays at once.
  Widget _quick(BuildContext context, List<Widget> notices) {
    final s = S.of(context);
    final menu = _rows.menu;
    final options = _c.heroOptions;
    final canRaise = options != null && options.canRaise && _rows.canRaise;
    final minTo = options?.minRaiseTo ?? 0, maxTo = options?.maxRaiseTo ?? 0;
    final to = canRaise ? _raiseTo.clamp(minTo, maxTo) : maxTo;
    final raise = _nearestRaise(to);
    final allIn = raise == _rows.aggressive.last;
    final passive = menu[_rows.passive];
    final allInWord = s.allIn('').trim();
    return _buttons(
      notices: notices,
      left: _bigButton(
        key: const ValueKey('quick fold'),
        label: s.fold,
        color: actionColor(menu, _rows.fold),
        onPressed: _rows.canFold ? () => _quickPlay(_rows.fold) : null,
      ),
      right: _bigButton(
        key: const ValueKey('quick call'),
        label: passive.kind == SpotActionKind.check ? s.check : s.callWord,
        amount: passive.kind == SpotActionKind.call ? formatBb(passive.amount, unit: true) : null,
        color: actionColor(menu, _rows.passive),
        onPressed: () => _quickPlay(_rows.passive),
      ),
      wide: _bigButton(
        key: const ValueKey('quick raise'),
        label: allIn ? allInWord : s.raiseAnySize,
        amount: formatBb(to, unit: true),
        color: actionColor(menu, raise),
        onPressed: canRaise
            ? () => _quickPlay(raise, action: allIn || menu[raise].amount == to ? null : PlayerAction.raiseTo(to))
            : null,
      ),
      below: _raiseSlider(s, canRaise: canRaise, to: to, minTo: minTo, maxTo: maxTo, color: actionColor(menu, raise)),
      gto: _training || _awaitingHelp,
    );
  }

  /// The quick view's layout, the same at the user's turn and while
  /// someone else acts (the pre-actions take the buttons' places): [left]
  /// and [right] side by side, [wide] under them, then [below] (the raise
  /// slider) and, with [gto], Show GTO, at the bottom of the panel.
  Widget _buttons({
    required List<Widget> notices,
    required Widget left,
    required Widget right,
    required Widget wide,
    required Widget below,
    required bool gto,
    bool waiting = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...notices,
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: 8),
                      Expanded(child: right),
                    ],
                  ),
                  const SizedBox(height: 8),
                  wide,
                  below,
                  if (gto) ...[
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerLeft, child: _showGtoButton(S.of(context), waiting: waiting)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One of the quick view's big buttons. With [ticked] it is a toggle (a
  /// pre-action): a tick box before its name, and its full color only
  /// while ticked.
  static Widget _bigButton({
    required Key key,
    required String label,
    String? amount,
    required Color color,
    VoidCallback? onPressed,
    bool? ticked,
  }) {
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        if (amount != null) Text(amount, maxLines: 1, style: const TextStyle(fontSize: 13)),
      ],
    );
    final dim = ticked == false;
    return FilledButton(
      key: key,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: dim ? color.withValues(alpha: 0.18) : color,
        foregroundColor: dim ? Colors.white70 : Colors.white,
        disabledBackgroundColor: Colors.white10,
        disabledForegroundColor: Colors.white38,
        minimumSize: const Size.fromHeight(60),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: ticked == null ? null : BorderSide(color: color, width: 2),
      ),
      child: switch (ticked) {
        null => text,
        final on => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(on ? Icons.check_box : Icons.check_box_outline_blank, size: 20),
              const SizedBox(width: 6),
              Flexible(child: text),
            ],
          ),
      },
    );
  }

  /// The raise slider (any amount, to 0.5 BB, up to all-in), with − and +
  /// for one step, and its two ends under it (or why raising isn't allowed).
  Widget _raiseSlider(
    S s, {
    required bool canRaise,
    required int to,
    required int minTo,
    required int maxTo,
    required Color color,
  }) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('raise less'),
              icon: const Icon(Icons.remove),
              onPressed:
                  canRaise && to > minTo ? () => setState(() => _raiseTo = _stepRaise(to, -1, minTo, maxTo)) : null,
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('raise slider'),
                value: canRaise ? _sliderPosition(to, minTo, maxTo) : 1,
                activeColor: color,
                onChanged: canRaise ? (p) => setState(() => _raiseTo = _amountAt(p, minTo, maxTo)) : null,
              ),
            ),
            IconButton(
              key: const ValueKey('raise more'),
              icon: const Icon(Icons.add),
              onPressed:
                  canRaise && to < maxTo ? () => setState(() => _raiseTo = _stepRaise(to, 1, minTo, maxTo)) : null,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: canRaise
              ? Row(children: [
                  Text(formatBb(minTo, unit: true), style: muted),
                  const Spacer(),
                  Text(s.allIn('').trim(), style: muted),
                ])
              : Text(s.unavailable(Unavailable.raisingNotAllowed), style: muted, textAlign: TextAlign.center),
        ),
      ],
    );
  }

  /// While someone else acts in Free Play, simple training or online:
  /// toggles in the buttons' places (see [PreAction]), Check/Fold, Check
  /// (or Call the amount faced now) and Call Any. The one ticked is played
  /// the moment the user's turn comes (in simple training, graded as usual);
  /// a second tap drops it.
  Widget _preActions(BuildContext context, int toCall) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final c = _c;
    final muted = theme.textTheme.bodySmall?.copyWith(color: Colors.white60);
    final picked = c.preAction?.kind;
    final seat = c.view.actingSeat;
    Widget toggle(PreAction kind, String label, Color color, {String? amount}) => _bigButton(
          key: ValueKey('pre ${kind.name}'),
          label: label,
          amount: amount,
          color: color,
          ticked: picked == kind,
          onPressed: () => c.togglePreAction(kind),
        );
    return _buttons(
      notices: [
        // Who acts (online, with their time left), as while waiting.
        if (seat != null)
          Text(
            s.thinking(c.view.seats[seat].info.name),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(color: Colors.white70),
          ),
        if (c.solvingSpot) _solvingLine(context),
        if (c.view.turnEnds case final ends?) ...[
          const SizedBox(height: 6),
          TurnClock.bar(ends: ends, limit: c.view.turnLimit ?? Duration.zero, text: s.secondsLeft, style: muted),
        ],
      ],
      left: toggle(PreAction.checkFold, s.checkFold, foldColor),
      right: toCall > 0
          ? toggle(PreAction.call, s.callWord, passiveColor, amount: formatBb(toCall, unit: true))
          : toggle(PreAction.check, s.check, passiveColor),
      wide: toggle(PreAction.callAny, s.callAny, passiveColor),
      // In the raise slider's place (kept, unseen, so the toggles sit where
      // the buttons will): what the toggles do.
      below: Stack(
        alignment: Alignment.center,
        children: [
          Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: _raiseSlider(s, canRaise: false, to: 0, minTo: 0, maxTo: 0, color: passiveColor),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: Text(s.playsAtYourTurn, style: muted, overflow: TextOverflow.ellipsis)),
              const HelpButton(section: GlossarySection.actions, terms: [GlossaryTerm.preActions]),
            ],
          ),
        ],
      ),
      gto: c.guessGto,
      waiting: true,
    );
  }

  static const _percentWidth = 64.0;

  /// The rows: fold, check or call and raise (any size), then below them
  /// each raise size, the same way before and after the flop.
  Widget _choices(BuildContext context, BoxConstraints constraints) {
    final s = S.of(context);
    final menu = _rows.menu;
    final played = _played;
    final passiveLabel = spotActionLabel(s, menu[_rows.passive]);
    // After Show GTO: each choice's EV loss, and (simple training) GTO's percentages.
    final spot = _training && _gtoShown ? _c.heroSpot : null;
    final gto = spot != null && !_percentages ? spot.frequencies : null;
    double? gtoOf(Iterable<int> actions) => gto == null ? null : actions.fold<double>(0, (sum, i) => sum + gto[i]);
    final evs = [for (final ev in spot?.evs ?? const <double>[]) if (!ev.isNaN) ev];
    final bestEv = evs.isEmpty ? null : evs.reduce(max);
    // What the best of [actions] gives up against the best choice ("–" if none is allowed).
    String? lossOf(Iterable<int> actions) {
      if (spot == null || bestEv == null) return null;
      final own = [for (final i in actions) if (!spot.evs[i].isNaN) spot.evs[i]];
      return own.isEmpty ? '–' : (bestEv - own.reduce(max)).toStringAsFixed(2);
    }
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
        gto: gtoOf([_rows.fold]),
        evLoss: lossOf([_rows.fold]),
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
        gto: gtoOf([_rows.passive]),
        evLoss: lossOf([_rows.passive]),
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
        gto: gtoOf(_rows.sizes),
        evLoss: lossOf(_rows.sizes),
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
          gto: gtoOf([i]),
          evLoss: lossOf([i]),
          percent: menu[i].available ? _sizes[_rows.sizes.indexOf(i)] : 0,
          onPercent: _top[2] > 0 && menu[i].available
              ? (v) => setState(() => _sizes = rebalancePercents(_sizes, _rows.sizes.indexOf(i), v))
              : null,
        ),
    ];

    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60);
    return SingleChildScrollView(
      child: Column(
        children: [
          // After Show GTO: what the extra columns are.
          if (spot != null)
            Row(
              children: [
                const Spacer(),
                if (gto != null)
                  SizedBox(width: _percentWidth, child: Text(s.columnGto, textAlign: TextAlign.right, style: muted)),
                SizedBox(width: _evWidth, child: Text(s.columnEvLoss, textAlign: TextAlign.right, style: muted)),
              ],
            ),
          ...first,
          const Divider(height: 10),
          ...sizes,
        ],
      ),
    );
  }

  static const _evWidth = 64.0;

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

  /// "8.00 BB", "All-in 100.00 BB".
  static String _sizeLabel(S s, SpotAction a) =>
      a.kind == SpotActionKind.allIn ? spotActionLabel(s, a) : formatBb(a.amount, unit: true);

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
    double? gto,
    String? evLoss,
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
          if (!_percentages) ...[
            Expanded(
              child: InkWell(onTap: enabled ? onTick : null, child: name),
            ),
            if (gto != null)
              SizedBox(
                width: _percentWidth,
                child: Text(
                  enabled ? gtoPercent(gto) : '–',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white60),
                ),
              ),
          ] else ...[
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
          // After Show GTO: what this choice gives up against the best one (the best in green).
          if (evLoss != null)
            SizedBox(
              width: _evWidth,
              child: Text(
                enabled ? evLoss : '–',
                textAlign: TextAlign.right,
                style: evLoss == '0.00' && enabled
                    ? const TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.w700)
                    : const TextStyle(color: Colors.white60),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // The GTO answer
  // ---------------------------------------------------------------------------

  /// Why a mistake was one (see [reasonFor]), worked out once per decision:
  /// against the opponent whose range beats the user's hand most often
  /// after the flop, from the starting hand before it.
  Reason? _why(DecisionScore score, MistakeKind kind) {
    if (identical(_whyScore, score)) return _whyReason;
    _whyScore = score;
    final session = _c.session, hand = session.hand;
    if (hand == null) return _whyReason = null;
    final hole = hand.holeCards(TableSession.heroSeat);
    final options = _c.heroOptions;
    final odds = options != null && options.canCall ? options.toCall / (options.pot + options.toCall) : null;
    if (hand.street == Street.preflop) {
      return _whyReason = reasonFor(kind, percentile: preflopPercentile(hole[0], hole[1]), odds: odds);
    }
    HandRead? read;
    for (var seat = 0; seat < hand.playerCount; seat++) {
      if (seat == TableSession.heroSeat || hand.isFolded(seat)) continue;
      final range = session.postflop?.currentRange(hand, seat);
      final r = range == null ? null : readHand(hole, hand.board, range);
      if (r != null && (read == null || r.beaten > read.beaten)) read = r;
    }
    return _whyReason = read == null ? null : reasonFor(kind, read: read, odds: odds);
  }

  DecisionScore? _whyScore;
  Reason? _whyReason;

  Widget _result(BuildContext context, SpotStrategy spot, DecisionScore score, List<double> mix) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: Colors.white60);
    final played = _c.heroPlay;
    final outcome = _drill?.outcome;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GradeChip(grade: score.grade),
            const SizedBox(width: 10),
            // Simple training scores the one action played.
            Flexible(
              child: Text(
                s.score(_c.advanced ? score.score : score.playScore),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const HelpButton(section: GlossarySection.scoring),
          ],
        ),
        // A saved spot played again: when it is back.
        if (outcome != null) _queuedLine(context, outcome),
        // A mistake or a blunder: why, in a few words.
        if (score.grade.index >= DecisionGrade.mistake.index)
          if (mistakeOf(spot, mix) case (final kind, final gto)?)
            Text(
              [
                s.mistakeReason(kind, spot.actions[gto].kind, formatBb(spot.actions[gto].amount, unit: true)),
                if (_why(score, kind) case final why?) s.mistakeWhy(why, spot.handName),
              ].join(' '),
              style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFFFCC80)),
            ),
        if (played != null)
          Text(
            _c.heroDrew
                ? s.randomized(spotActionLabel(s, spot.actions[played]))
                : s.youPlay(switch (_c.heroAction) {
                    final PlayerAction a => s.raiseTo(formatBb(a.amount, unit: true), null),
                    null => spotActionLabel(s, spot.actions[played]),
                  }),
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        Text(
          _c.advanced
              ? s.evLossAndMatch('${score.evLoss.toStringAsFixed(2)} BB', (score.mixMatch * 100).round())
              : '${s.evLoss} ${score.evLoss.toStringAsFixed(2)} BB',
          style: muted,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            child: StrategyComparison(spot: spot, mix: mix, played: played),
          ),
        ),
        const SizedBox(height: 6),
        // Online the move is played already: OK just puts the score away.
        // A saved spot stops at its decision: the next hand.
        FilledButton.icon(
          key: const ValueKey('continue'),
          onPressed: _c.continueHand,
          icon: Icon(_online != null ? Icons.check : (outcome != null ? Icons.skip_next : Icons.play_arrow)),
          label: Text(_online != null ? s.ok : (outcome != null ? s.nextHand : s.continueHand)),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Drills
  // ---------------------------------------------------------------------------

  /// Above everything else: a saved spot played again (as it was graded,
  /// and how many are due), or random hands (and when the next spot is due).
  Widget _drillLine(BuildContext context, DrillController drill) {
    final s = S.of(context);
    final spot = drill.spot, drills = drill.drills, now = drills.now();
    // A spot that fell due during a random hand comes next.
    final next = drills.dueCount > 0 ? now : drills.nextDue;
    final text = spot != null
        ? s.drillSpot(s.grade(spot.grade), drills.dueCount)
        : s.randomHands(next == null ? null : formatWait(s, next.difference(now)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFFFCC80))),
          ),
          const HelpButton(section: GlossarySection.modes, terms: [GlossaryTerm.drills]),
        ],
      ),
    );
  }

  /// "✓ Next review in 3 days" (played right), "Back in 10 min" (wrong).
  Widget _queuedLine(BuildContext context, DrillOutcome outcome) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        s.drillQueued(formatWait(s, outcome.wait), right: outcome.right),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: outcome.right == true ? const Color(0xFF81C784) : const Color(0xFFFFCC80),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  /// A saved spot with no GTO answer this time (and why): it isn't graded,
  /// comes back after its cooldown again, and Next Hand deals the next.
  Widget _ungraded(BuildContext context, DrillOutcome outcome) {
    final s = S.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.noAnswer(_c.session.preflop?.unavailable ?? _c.session.postflop?.unavailable),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        Center(child: _queuedLine(context, outcome)),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('continue'),
          onPressed: _c.continueHand,
          icon: const Icon(Icons.skip_next),
          label: Text(s.nextHand),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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
    final s = S.of(context);
    final ends = _c.view.turnEnds;
    return _message(
      context,
      // Online, the user's own move may be on its way; a drill replays it.
      seat == null || _c.isUserSeat(seat) ? '' : s.thinking(_c.view.seats[seat].info.name),
      // Online, with a time limit: the time they have left.
      ends == null || seat == null
          ? null
          : TurnClock.bar(
              ends: ends,
              limit: _c.view.turnLimit ?? Duration.zero,
              text: s.secondsLeft,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
    );
  }

  /// Online: "Solving…" while GTO's answer for the decision is worked out.
  Widget _solvingLine(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            S.of(context).solvingDecision,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
          ),
        ),
      ],
    ),
  );

  /// Online: what the user should know right now (above everything else):
  /// first that the connection dropped and is being got back (the choices
  /// stay: a move made meanwhile goes once it is back).
  Widget _onlineNotices(BuildContext context, OnlineTableController online) {
    final s = S.of(context);
    final notices = [
      if (online.reconnecting) s.reconnecting,
      if (online.notice case final notice?) s.onlineNotice(notice),
      if (online.hostAway) s.hostAway,
      if (online.sitsOutNextHand) s.sitOutNextHand,
    ];
    if (notices.isEmpty) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFFFCC80));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          if (online.reconnecting) ...[
            const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(notices.join(' · '), style: style)),
          if (online.reconnecting) const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.away]),
        ],
      ),
    );
  }

  /// Online, out of chips: with rebuys, Rebuy (the starting stack, from the
  /// next hand) or Leave; without, the user watches the game: the room's
  /// Lobby, or Leave (asked first). Once rebought, they sit down at the
  /// next hand.
  Widget _outOfChips(BuildContext context, OnlineTableController online) {
    final s = S.of(context);
    final rebuys = online.rules.rebuys;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  online.rebuying ? s.joinNextHand : s.outOfChips(rebuys: rebuys),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: const Color(0xFFFFCC80)),
                ),
              ),
              const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.rebuys]),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (rebuys)
                FilledButton.icon(
                  key: const ValueKey('rebuy'),
                  onPressed: online.canRebuy ? online.rebuy : null,
                  icon: const Icon(Icons.replay),
                  label: Text(s.rebuy(formatBb(online.rules.startingStack, unit: true))),
                )
              else
                OutlinedButton.icon(
                  key: const ValueKey('lobby'),
                  onPressed: widget.onLobby,
                  icon: const Icon(Icons.groups_outlined),
                  label: Text(s.lobby),
                ),
              OutlinedButton.icon(
                key: const ValueKey('out leave'),
                // The table asks first.
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.logout),
                label: Text(s.leave),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Online, sitting out: the user watches, not dealt in; I'm Back deals
  /// them in again from the next hand (until then they are told so), or
  /// Leave (asked first).
  Widget _sittingOut(BuildContext context, OnlineTableController online) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  online.backNextHand ? s.joinNextHand : s.youSitOut,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: const Color(0xFFFFCC80)),
                ),
              ),
              const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.sitOut]),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.icon(
                key: const ValueKey('im back'),
                onPressed: online.sittingOut ? () => online.sitOut(false) : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(s.imBack),
              ),
              OutlinedButton.icon(
                key: const ValueKey('sit out leave'),
                // The table asks first.
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.logout),
                label: Text(s.leave),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Online: the room closed, or the connection was lost.
  Widget _ended(BuildContext context, OnlineTableController online) {
    final s = S.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          online.connectionLost
              ? s.connectionLost
              : switch (online.client.failure) {
                  final JoinError failure => s.joinError(failure),
                  null => s.closed(online.client.closeReason),
                },
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.home_outlined),
          label: Text(s.mainMenu),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }

  Widget _handOver(BuildContext context) {
    final s = S.of(context);
    final String text;
    final Color color;
    final record = _c.session.history.lastOrNull;
    final online = _online;
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
        // Online, before the first hand there is no result yet.
        if (online == null || _c.view.heroResult != null) ...[
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
        ],
        // Online, the server deals the next hand by itself (once 2 seats are taken), until the game is over.
        if (online == null)
          FilledButton.icon(
            onPressed: _c.startNextHand,
            icon: const Icon(Icons.skip_next),
            label: Text(S.of(context).nextHand),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          )
        else if (online.gameOver case final over?)
          Text(
            s.gameOver(over.name, you: over.seat != null && over.seat == online.client.mySeat),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFFFE082),
                  fontWeight: FontWeight.w700,
                ),
          )
        else if (online.paused)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  s.waitingForPlayers,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white70),
                ),
              ),
              const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.onlineBots]),
            ],
          )
        else if (online.nextHandAt case final next?)
          _Countdown(
            until: next,
            text: s.nextHandIn,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white70),
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

/// Seconds left until [until], counting down by itself (so nothing else
/// rebuilds every second); never below 0.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.until, required this.text, this.style, this.textAlign});

  final DateTime until;
  final String Function(int seconds) text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.until.difference(DateTime.now());
    final seconds = max(0, (left.inMilliseconds / 1000).ceil());
    return Text(widget.text(seconds), style: widget.style, textAlign: widget.textAlign);
  }
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
