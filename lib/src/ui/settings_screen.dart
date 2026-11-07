import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../app/sounds.dart';
import '../engine/cards.dart';
import '../l10n/strings.dart';
import 'table_controller.dart' show PlaybackSpeed;
import 'kit/cards.dart';
import 'widgets/card_view.dart';
import 'widgets/gomoku_board.dart';

/// The app's looks and feel, from Home, in three groups: General
/// (animation speed, sound), Cards & table (the deck and the felt, shared
/// by every card game) and Board & stones (Gomoku's). Each choice shows
/// what it looks like.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    final theme = Theme.of(context);
    final s = S.of(context);
    Widget group(String title) => Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
          ),
        );
    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(title, style: theme.textTheme.titleMedium), const SizedBox(height: 8), child],
          ),
        );
    // A choice with its name under it.
    Widget named(Widget preview, String name) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [preview, const SizedBox(height: 4), Text(name)],
        );
    Widget selectable({required bool selected, required VoidCallback onTap, required Widget child}) => InkWell(
          onTap: onTap,
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? theme.colorScheme.primary : Colors.transparent, width: 2),
            ),
            child: child,
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              group(s.general),
              section(
                s.animations,
                SegmentedButton<PlaybackSpeed>(
                  segments: [
                    for (final speed in PlaybackSpeed.values) ButtonSegment(value: speed, label: Text(s.speed(speed))),
                  ],
                  selected: {settings.speed},
                  onSelectionChanged: (v) => settings.update((a) => a.speed = v.single),
                ),
              ),
              section(
                s.sound,
                Row(
                  children: [
                    Icon(settings.volume == 0 ? Icons.volume_off : Icons.volume_up),
                    Expanded(
                      child: Slider(
                        value: settings.volume,
                        divisions: 20,
                        onChanged: (v) => settings.update((a) => a.volume = v),
                        onChangeEnd: (_) => Sounds.instance.play(SoundEffect.chips),
                      ),
                    ),
                    SizedBox(width: 44, child: Text('${(settings.volume * 100).round()}%', textAlign: TextAlign.right)),
                  ],
                ),
              ),
              group(s.cardsAndTable),
              section(
                s.cardBack,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final back in CardBackStyle.values)
                      selectable(
                        selected: settings.cardBack == back,
                        onTap: () => settings.update((a) => a.cardBack = back),
                        child: CardView(width: 44, faceUp: false, backStyle: back),
                      ),
                  ],
                ),
              ),
              section(
                s.cardFaces,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final style in CardFaceStyle.values)
                      selectable(
                        selected: settings.cardFaces == style,
                        onTap: () => settings.update((a) => a.cardFaces = style),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final card in ['As', 'Kh', 'Qd', 'Jc'])
                                  Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: CardView(width: 40, card: PlayingCard.parse(card), faceStyle: style),
                                  ),
                                // Fight the Landlord's big joker, in the same look.
                                Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: GameCardView(
                                    key: ValueKey('joker ${style.name}'),
                                    width: 40,
                                    face: const CardFace.joker(big: true),
                                    faceStyle: style,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(switch (style) {
                              CardFaceStyle.twoColors => s.twoColors,
                              CardFaceStyle.fourColors => s.fourColors,
                              CardFaceStyle.colored => s.coloredCards,
                            }),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              section(
                s.tableColor,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final felt in FeltStyle.values)
                      selectable(
                        selected: settings.felt == felt,
                        onTap: () => settings.update((a) => a.felt = felt),
                        child: Container(
                          width: 56,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFF5D4037), width: 4),
                            gradient: RadialGradient(colors: [felt.center, felt.middle, felt.edge]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              group(s.boardAndStones),
              section(
                s.boardColor,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final board in BoardStyle.values)
                      selectable(
                        selected: settings.board == board,
                        onTap: () => settings.update((a) => a.board = board),
                        child: named(_preview(board: board), s.boardStyle(board)),
                      ),
                  ],
                ),
              ),
              section(
                s.stoneLook,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final style in StoneStyle.values)
                      selectable(
                        selected: settings.stones == style,
                        onTap: () => settings.update((a) => a.stones = style),
                        child: named(_preview(stones: style), s.stoneStyle(style)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A corner of a Gomoku board with a few stones, the last one marked:
  /// in the given board color or stone look, the other one as set.
  static Widget _preview({BoardStyle? board, StoneStyle? stones}) => SizedBox.square(
        dimension: 84,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: GomokuBoard(
            lines: 5,
            stones: const {(1, 1): Stone.black, (2, 1): Stone.white, (2, 2): Stone.black, (3, 2): Stone.white},
            lastMove: (3, 2),
            boardStyle: board,
            stoneStyle: stones,
          ),
        ),
      );
}
