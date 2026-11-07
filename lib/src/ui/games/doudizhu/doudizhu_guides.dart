import 'package:flutter/material.dart';

import '../../../games/doudizhu/doudizhu.dart';
import '../../../l10n/strings.dart';
import '../../kit/guide_kit.dart';
import 'doudizhu_cards.dart';
import 'l10n/doudizhu_strings.dart';

/// One example of each kind of play, as rank text (see parseRanks: T is the
/// 10, B the little joker, R the big one). A test checks the engine reads
/// each one as its kind.
const landlordExamples = <PlayType, String>{
  PlayType.solo: '7',
  PlayType.pair: '77',
  PlayType.trio: '999',
  PlayType.trioSolo: '9994',
  PlayType.trioPair: 'QQQ66',
  PlayType.straight: '34567',
  PlayType.pairStraight: '334455',
  PlayType.airplane: '777888',
  PlayType.airplaneSolos: '33344459',
  PlayType.airplanePairs: '3334445577',
  PlayType.fourTwoSolos: '666689',
  PlayType.fourTwoPairs: '66668899',
  PlayType.bomb: '8888',
  PlayType.rocket: 'BR',
};

/// The engine's reading of [type]'s example (standard rules).
Play landlordExample(PlayType type) =>
    classifyPlay(parseRanks(landlordExamples[type]!)).firstWhere((p) => p.type == type);

/// Guides > Rules (also ☰ Rules in the game).
class LandlordRulesGuide extends StatelessWidget {
  const LandlordRulesGuide({super.key});

  @override
  Widget build(BuildContext context) =>
      GuidePage(title: S.of(context).rules, sections: LandlordStrings.of(context).rulesSections);
}

/// Guides > Combinations: the ranks from low to high, then every kind of
/// play with an example and what it beats.
class LandlordCombinationsGuide extends StatelessWidget {
  const LandlordCombinationsGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final s = LandlordStrings.of(context);
    final theme = Theme.of(context);
    final ranks = [for (var r = 0; r < Rank.count; r++) r];
    return GuidePage(
      title: s.combinations,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: LayoutBuilder(
            // The 15 ranks, low to high, in one row that fits the width.
            builder: (context, box) => Center(
              child: DdzMiniCards(
                key: const ValueKey('rank order'),
                ids: ddzIdsForRanks(ranks),
                width: (box.maxWidth / (1 + 14 * 0.45)).clamp(16.0, 40.0),
                overlap: 0.55,
              ),
            ),
          ),
        ),
        for (final type in PlayType.values)
          Padding(
            key: ValueKey('kind ${type.name}'),
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.kind(type), style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                const SizedBox(height: 6),
                DdzMiniCards(
                  ids: ddzIdsForRanks(parseRanks(landlordExamples[type]!)),
                  play: landlordExample(type),
                  width: 30,
                  overlap: 0.45,
                ),
                const SizedBox(height: 6),
                Text('${s.beats}: ${s.kindRule(type)}'),
              ],
            ),
          ),
      ],
    );
  }
}
