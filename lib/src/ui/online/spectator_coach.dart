/// What a spectator sees in place of a player's choices at an online poker
/// table: the coach for whoever acts (worked out on this device, from the
/// cards it may show), and Join game.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../gto/spot_strategy.dart';
import '../../l10n/strings.dart';
import '../../online/protocol.dart';
import '../format.dart';
import '../glossary.dart';
import '../kit/l10n/kit_strings.dart';
import '../strategy_panel.dart';
import '../table_controller.dart';
import 'room_widgets.dart';

/// The Coach chip in a spectator's top bar: turns the coach on or off on
/// this device (OnlineTableController.coachOn).
class SpectatorCoachChip extends StatelessWidget {
  const SpectatorCoachChip({super.key, required this.controller});

  final OnlineTableController controller;

  @override
  Widget build(BuildContext context) {
    final on = controller.coachOn;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        key: const ValueKey('coach chip'),
        label: Text(KitStrings.of(context).coach, maxLines: 1, softWrap: false),
        selected: on,
        showCheckmark: false,
        avatar: Icon(on ? Icons.visibility : Icons.visibility_off, size: 16),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        mouseCursor: WidgetStateMouseCursor.clickable,
        onSelected: controller.ended ? null : controller.setCoach,
      ),
    );
  }
}

/// A spectator's panel (the Game tab beside the table): what is going on
/// (reconnecting, the host away), the coach for whoever acts (between
/// hands, when the next is dealt), and at the bottom Join game, or Leave
/// seat while waiting for one. The coach starts off: its place shows a
/// Coach button (as the chip in the top bar) until it is turned on.
class SpectatorPanel extends StatelessWidget {
  const SpectatorPanel({super.key, required this.controller});

  final OnlineTableController controller;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = controller;
    final theme = Theme.of(context);
    final muted = theme.textTheme.titleSmall?.copyWith(color: Colors.white70);
    final notices = [if (c.reconnecting) s.reconnecting, if (c.hostAway) s.hostAway];
    final Widget body;
    if (c.ended) {
      body = Center(
        child: Text(
          c.connectionLost
              ? (c.client.noDirectRoute ? s.noDirectRoute : s.connectionLost)
              : switch (c.client.failure) {
                  final JoinError failure => s.joinError(failure),
                  null => s.closed(c.client.closeReason),
                },
          textAlign: TextAlign.center,
          style: muted,
        ),
      );
    } else if (c.gameOver case final over?) {
      body = Center(
        child: Text(s.gameOver(over.name), textAlign: TextAlign.center, style: muted),
      );
    } else if (c.handOver) {
      final status = c.paused
          ? Text(s.waitingForPlayers, textAlign: TextAlign.center, style: muted)
          : (c.nextHandAt == null ? const SizedBox.shrink() : _Countdown(until: c.nextHandAt!, style: muted));
      body = Center(
        child: c.coachOn
            ? status
            : Column(mainAxisSize: MainAxisSize.min, children: [status, const SizedBox(height: 12), _coachOn(c)]),
      );
    } else if (!c.coachOn) {
      body = Center(child: _coachOn(c));
    } else if (c.spectatorCoach case final coach?) {
      body = SpectatorCoachPanel(coach: coach);
    } else {
      body = const SizedBox.shrink();
    }
    final room = c.client.room;
    return Material(
      color: const Color(0xFF12171B),
      child: SafeArea(
        left: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notices.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    notices.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFFFCC80)),
                  ),
                ),
              Expanded(child: body),
              if (c.ended)
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.logout),
                  label: Text(s.leave),
                )
              else if (room != null)
                SeatActions(room: room, onJoin: c.joinGame, onLeave: c.leaveSeat),
            ],
          ),
        ),
      ),
    );
  }

  /// The coach is off (it starts so): one tap turns it on, as the chip does.
  Widget _coachOn(OnlineTableController c) => Builder(
    builder: (context) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.tonalIcon(
          key: const ValueKey('coach on'),
          onPressed: () => c.setCoach(true),
          icon: const Icon(Icons.visibility, size: 18),
          label: Text(KitStrings.of(context).coach),
        ),
        const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.spectators]),
      ],
    ),
  );
}

/// The coach for whoever acts, as a spectator sees it: their name and
/// hand, GTO's mix as a bar, and each choice GTO takes (how often, and its
/// EV in big blinds). "—" when their cards are hidden from this device, a
/// thin bar while the answer is worked out, or why there is none.
class SpectatorCoachPanel extends StatelessWidget {
  const SpectatorCoachPanel({super.key, required this.coach});

  final SpectatorCoach coach;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: Colors.white60);
    final spot = coach.spot;
    final header = Row(
      children: [
        Text(KitStrings.of(context).coach, style: theme.textTheme.titleSmall?.copyWith(color: const Color(0xFFFFE082))),
        const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.spectators, GlossaryTerm.seeBots]),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            [coach.name, ?spot?.handName].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
        ),
      ],
    );
    final Widget body;
    if (coach.hidden) {
      body = Text('—', key: const ValueKey('coach hidden'), style: theme.textTheme.titleLarge?.copyWith(color: Colors.white38));
    } else if (spot != null) {
      body = _rows(context, s, spot);
    } else if (coach.thinking) {
      body = const Padding(
        key: ValueKey('coach thinking'),
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    } else {
      body = Text(s.noAnswer(coach.none), style: muted);
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, const SizedBox(height: 6), body],
      ),
    );
  }

  /// The choices GTO has here (those it hasn't solved left out), with its
  /// mix as a bar on top.
  Widget _rows(BuildContext context, S s, SpotStrategy spot) {
    final theme = Theme.of(context);
    final shown = [for (var i = 0; i < spot.actions.length; i++) if (spot.actions[i].available) i];
    var best = double.negativeInfinity;
    for (final i in shown) {
      if (!spot.evs[i].isNaN && spot.evs[i] > best) best = spot.evs[i];
    }
    return Column(
      key: const ValueKey('coach answer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MixBar(actions: spot.actions, frequencies: spot.frequencies),
        const SizedBox(height: 6),
        for (final i in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                ColorDot(color: actionColor(spot.actions, i)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    spotActionLabel(s, spot.actions[i]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text('${(spot.frequencies[i] * 100).round()}%', textAlign: TextAlign.right),
                ),
                SizedBox(
                  width: 84,
                  child: Text(
                    spot.evs[i].isNaN ? '–' : '${spot.evs[i] >= 0 ? '+' : ''}${spot.evs[i].toStringAsFixed(2)} BB',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: !spot.evs[i].isNaN && spot.evs[i] >= best - 0.005 ? const Color(0xFF81C784) : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (shown.isEmpty) Text(s.noAnswer(null), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// "Next hand in 4 s", counting down by itself.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.until, this.style});

  final DateTime until;
  final TextStyle? style;

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
    final seconds = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
    return Text(S.of(context).nextHandIn(seconds), textAlign: TextAlign.center, style: widget.style);
  }
}
