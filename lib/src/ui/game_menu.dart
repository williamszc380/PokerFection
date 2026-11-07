import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../online/protocol.dart' show RoomPhase;
import 'games.dart';
import 'online/room_scope.dart';
import 'online/room_widgets.dart' show playableInRoom, roomGameKey;

/// A game's menu, the same for every game: its name with a back arrow
/// (to Home), its emblem, then its buttons (see GameInfo.menu), the first
/// one standing out. A button with choices (Guides) opens them right under
/// it: the menu always keeps room for one row of choices at its bottom, so
/// opening one only slides the buttons below it down, and nothing above
/// moves. A button that can't be used now (Last game, with none saved) is
/// greyed out, and asked again each time the menu is back on top. While
/// hosting a room, Play of a game played online makes it the room's game
/// (Hold'em's goes through its setup: see SetupScreen).
class GameMenu extends StatefulWidget {
  const GameMenu({super.key, required this.game});

  final GameInfo game;

  @override
  State<GameMenu> createState() => _GameMenuState();
}

class _GameMenuState extends State<GameMenu> {
  /// The button whose choices are open, if any.
  GameMenuButton? _open;

  /// One row of choices (with the gap above it), and how fast it opens.
  static const _choicesHeight = 52.0;
  static const _slide = Duration(milliseconds: 180);

  /// The answers of the buttons that have an `enabled` check; a button with
  /// no answer yet stays greyed out.
  final _enabled = <GameMenuButton, bool>{};

  /// Counts the rounds of checks, so a slow answer from an older round
  /// can't overwrite a newer one.
  var _round = 0;

  /// Whether the menu was the top screen when last asked.
  var _onTop = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Asked when the menu opens and each time it is back on top: a game
    // just played makes Last game usable. Not when a pushed screen's
    // future completes: a setup that replaces itself with the game
    // (pushReplacement) completes it as the game starts, before it has
    // saved anything, and the game's own close completes nothing here.
    final onTop = ModalRoute.isCurrentOf(context) ?? true;
    if (onTop && !_onTop) _check();
    _onTop = onTop;
  }

  /// Asks every button with an `enabled` check whether it can be used now.
  void _check() {
    final round = ++_round;
    final buttons = [
      for (final button in widget.game.menu ?? const <GameMenuButton>[]) ...[button, ...button.choices],
    ];
    for (final button in buttons) {
      final enabled = button.enabled;
      if (enabled == null) continue;
      Future<bool>.sync(() => enabled(context)).then(
        (yes) => _answer(round, button, yes),
        onError: (Object _) => _answer(round, button, false),
      );
    }
  }

  void _answer(int round, GameMenuButton button, bool yes) {
    if (!mounted || round != _round) return;
    setState(() => _enabled[button] = yes);
  }

  bool _usable(GameMenuButton button) => button.enabled == null || _enabled[button] == true;

  /// Opens [screen]; the buttons are asked again when the menu is back on
  /// top (see didChangeDependencies).
  void _push(WidgetBuilder screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: screen));

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final game = widget.game;
    final buttons = game.menu ?? const [];
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, button) in buttons.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          _button(context, button, main: i == 0),
        ],
        // The room a row of choices takes when one is open: the menu keeps
        // the same height, so it doesn't move on screen.
        if (buttons.any((b) => b.choices.isNotEmpty))
          AnimatedContainer(duration: _slide, curve: Curves.easeOut, height: _open == null ? _choicesHeight : 0),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(game.name(s))),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Phones held sideways: the emblem beside the buttons. Small
            // phones (568 or 592 wide, with the buttons bar on the side)
            // get a smaller emblem and gap, and the buttons take what is
            // left, up to their usual 400.
            if (constraints.maxWidth > constraints.maxHeight && constraints.maxHeight < 420) {
              final small = constraints.maxWidth < 680;
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      game.emblem(small ? 104 : 120),
                      SizedBox(width: small ? 32 : 48),
                      Flexible(
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: column),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: game.emblem(constraints.maxHeight < 600 ? 112 : 144)),
                      const SizedBox(height: 28),
                      column,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// A button, with its row of choices (if any) under it.
  Widget _button(BuildContext context, GameMenuButton button, {required bool main}) {
    final theme = Theme.of(context);
    final open = _open == button;
    void onPressed() {
      // Hosting a room: Play of a game played online (other than Hold'em, whose setup does it) makes it
      // the room's game and opens its table.
      final rooms = RoomScope.maybeOf(context);
      if (main &&
          rooms != null &&
          rooms.stage == RoomStage.open &&
          rooms.isHost &&
          widget.game.id != GameId.holdem &&
          playableInRoom(widget.game, rooms)) {
        if (rooms.room?.phase == RoomPhase.playing) {
          // The game can only change between games.
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).endGameFirst)));
        } else {
          rooms.hostPick(roomGameKey(widget.game));
        }
        return;
      }
      if (button.open case final screen?) {
        _push(screen);
      } else {
        setState(() => _open = open ? null : button);
      }
    }

    // Greyed out, not hidden, while it can't be used.
    final usable = _usable(button);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        main
            ? FilledButton.icon(
                onPressed: usable ? onPressed : null,
                icon: Icon(button.icon),
                label: Text(button.label(context)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  textStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              )
            : OutlinedButton.icon(
                onPressed: usable ? onPressed : null,
                icon: Icon(button.icon),
                label: Text(button.label(context)),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
        if (button.choices.isNotEmpty)
          AnimatedContainer(
            duration: _slide,
            curve: Curves.easeOut,
            height: open ? _choicesHeight : 0,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: _choicesHeight,
              maxHeight: _choicesHeight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    for (final (k, choice) in button.choices.indexed) ...[
                      if (k > 0) const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: open && choice.open != null && _usable(choice) ? () => _push(choice.open!) : null,
                          icon: Icon(choice.icon, size: 20),
                          // A long name takes two lines (Spanish on a phone).
                          label: Text(
                            choice.label(context),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(height: 1.1),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: const Size.fromHeight(44),
                            maximumSize: const Size.fromHeight(44),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
