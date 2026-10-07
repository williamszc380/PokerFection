import 'package:flutter/material.dart';

import '../engine/cards.dart';
import '../engine/hand_evaluator.dart';
import '../l10n/strings.dart';
import 'widgets/card_view.dart';

/// The poker hands from best to worst, each with an example (cards that
/// don't count toward the hand are faded) and how often it comes.
class HandRankingsScreen extends StatelessWidget {
  const HandRankingsScreen({super.key});

  /// An example of each hand, best first, how many of its cards make it,
  /// and in how many of the 133,784,560 sets of 7 cards it is the best hand.
  static final _examples = [
    (null, parseCards('As Ks Qs Js Ts'), 5, 4324),
    (HandCategory.straightFlush, parseCards('9h 8h 7h 6h 5h'), 5, 37260),
    (HandCategory.quads, parseCards('Qc Qd Qh Qs 7d'), 4, 224848),
    (HandCategory.fullHouse, parseCards('Kh Kd Ks 7c 7h'), 5, 3473184),
    (HandCategory.flush, parseCards('Ad Jd 8d 6d 2d'), 5, 4047644),
    (HandCategory.straight, parseCards('Tc 9d 8s 7h 6c'), 5, 6180020),
    (HandCategory.trips, parseCards('8c 8d 8h Ks 3d'), 3, 6461620),
    (HandCategory.twoPair, parseCards('Jh Jc 4s 4d As'), 4, 31433400),
    (HandCategory.pair, parseCards('Th Tc Ad 7s 3h'), 2, 58627800),
    (HandCategory.highCard, parseCards('Ah Qd 9c 6s 2h'), 1, 23294460),
  ];

  static const _sevenCardSets = 133784560;

  /// "30,940" or "38.5": the X of "1 in X".
  static String _oneIn(int count) {
    final x = _sevenCardSets / count;
    if (x < 100) return x.toStringAsFixed(1);
    final digits = x.round().toString();
    return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
  }

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
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(s.rankingOddsNote, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
                ),
                for (final (i, (category, cards, used, count)) in _examples.indexed)
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category == null ? s.royalFlush : s.handCategory(category),
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                s.oneIn(_oneIn(count)),
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                              ),
                            ],
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
