import 'package:flutter/material.dart';

import '../engine/cards.dart';
import '../engine/hand_evaluator.dart';
import '../l10n/strings.dart';
import 'widgets/card_view.dart';

/// The poker hands from best to worst, each with an example (cards that
/// don't count toward the hand are faded).
class HandRankingsScreen extends StatelessWidget {
  const HandRankingsScreen({super.key});

  /// An example of each hand, best first, and how many of its cards make it.
  static final _examples = [
    (null, parseCards('As Ks Qs Js Ts'), 5),
    (HandCategory.straightFlush, parseCards('9h 8h 7h 6h 5h'), 5),
    (HandCategory.quads, parseCards('Qc Qd Qh Qs 7d'), 4),
    (HandCategory.fullHouse, parseCards('Kh Kd Ks 7c 7h'), 5),
    (HandCategory.flush, parseCards('Ad Jd 8d 6d 2d'), 5),
    (HandCategory.straight, parseCards('Tc 9d 8s 7h 6c'), 5),
    (HandCategory.trips, parseCards('8c 8d 8h Ks 3d'), 3),
    (HandCategory.twoPair, parseCards('Jh Jc 4s 4d As'), 4),
    (HandCategory.pair, parseCards('Th Tc Ad 7s 3h'), 2),
    (HandCategory.highCard, parseCards('Ah Qd 9c 6s 2h'), 1),
  ];

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.handRankings)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final (i, (category, cards, used)) in _examples.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text('${i + 1}', style: theme.textTheme.titleMedium?.copyWith(color: Colors.white54)),
                        ),
                        for (final (k, card) in cards.indexed)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Opacity(opacity: k < used ? 1 : 0.35, child: CardView(width: 38, card: card)),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            category == null ? s.royalFlush : s.handCategory(category),
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
