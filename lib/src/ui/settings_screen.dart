import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../app/sounds.dart';
import '../engine/cards.dart';
import '../l10n/strings.dart';
import 'table_controller.dart' show PlaybackSpeed;
import 'widgets/card_view.dart';

/// The app's preferences: language, animation speed, sound, the deck and
/// the table.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    final theme = Theme.of(context);
    final s = S.of(context);
    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(title, style: theme.textTheme.titleMedium), const SizedBox(height: 8), child],
          ),
        );
    Widget selectable({required bool selected, required VoidCallback onTap, required Widget child}) => InkWell(
          onTap: onTap,
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
            ],
          ),
        ),
      ),
    );
  }
}
