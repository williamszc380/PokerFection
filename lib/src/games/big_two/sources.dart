/// Where Big Two's rules come from: the documents the engine cites (see
/// rules.dart), and which of them each preset, straight order, flush order
/// and rule switch follows. The app shows these beside its explanations so
/// a player can check a rule at its source.
library;

import 'rules.dart';

/// A document the rules follow. The Pagat entries are sections of one page:
/// its standard game and its regional variations.
enum BigTwoSource {
  /// Pagat, "Big Two": the standard game.
  pagat('https://www.pagat.com/climbing/bigtwo.html'),

  /// Pagat, "Big Two", the Hong Kong variation.
  pagatHongKong('https://www.pagat.com/climbing/bigtwo.html'),

  /// Pagat, "Big Two", the Philippine game (Pusoy Dos).
  pagatPhilippines('https://www.pagat.com/climbing/bigtwo.html'),

  /// Pagat, "Big Two", the Indonesian variation (passing locks you out).
  pagatIndonesia('https://www.pagat.com/climbing/bigtwo.html'),

  /// Wikipedia, "Big two": straight orders and the doublings in scoring.
  wikipedia('https://en.wikipedia.org/wiki/Big_two'),

  /// Chinese Wikipedia, "大老二": Taiwan's suits, straights and bombs.
  zhWikipedia('https://zh.wikipedia.org/zh-tw/大老二'),

  /// Charlesworth's Big Two research (arXiv:1808.10442): straights in plain
  /// rank order, J-Q-K-A-2 the highest.
  charlesworth('https://arxiv.org/abs/1808.10442'),

  /// Denexa Games, "Big Two": deals played until someone reaches a target
  /// such as 100, the lowest total winning.
  denexa('https://www.denexa.com/blog/big-two'),

  /// Wikipedia, "Pusoy dos": playing on until one player reaches a number
  /// of wins that depends on the player count.
  wikipediaPusoy('https://en.wikipedia.org/wiki/Pusoy_dos');

  const BigTwoSource(this.url);

  final String url;

  /// The documents behind the sources, once each, in this order.
  static const documents = [pagat, wikipedia, zhWikipedia, charlesworth, denexa, wikipediaPusoy];
}

/// Which sources each choice follows.
abstract final class BigTwoSources {
  static List<BigTwoSource> ofPreset(BigTwoPreset preset) => switch (preset) {
    BigTwoPreset.standard => const [BigTwoSource.pagat],
    BigTwoPreset.hongKong => const [BigTwoSource.pagatHongKong],
    // Pagat gives Taiwan's suit order; Chinese Wikipedia the rest.
    BigTwoPreset.taiwan => const [BigTwoSource.zhWikipedia, BigTwoSource.pagat],
    BigTwoPreset.pusoyDos => const [BigTwoSource.pagatPhilippines],
  };

  static List<BigTwoSource> ofStraights(StraightRule rule) => switch (rule.name) {
    'pagat' => const [BigTwoSource.pagat],
    'hongKong' => const [BigTwoSource.pagatHongKong],
    'taiwan' => const [BigTwoSource.zhWikipedia],
    'twoHigh' => const [BigTwoSource.charlesworth],
    _ => const [],
  };

  static List<BigTwoSource> ofFlushes(FlushOrder order) => switch (order) {
    FlushOrder.suitFirst => const [BigTwoSource.pagat],
    FlushOrder.rankFirst => const [BigTwoSource.pagatHongKong],
    FlushOrder.allRanks => const [BigTwoSource.zhWikipedia],
  };

  /// Honour hands beating singles, pairs and triples (Pagat); Taiwan's bombs
  /// (Chinese Wikipedia).
  static const bombs = [BigTwoSource.pagat, BigTwoSource.zhWikipedia];
  static const sameType = [BigTwoSource.zhWikipedia];
  static const passLockout = [BigTwoSource.pagatIndonesia];
  static const lastCard = [BigTwoSource.pagat];
  static const dragon = [BigTwoSource.pagatHongKong];
  static const topTwo = [BigTwoSource.pagatHongKong];
  static const scoring = [BigTwoSource.pagat, BigTwoSource.pagatPhilippines];
  static const doubling = [BigTwoSource.wikipedia];

  /// Playing a match to a target (see big_two_match.dart).
  static const match = [BigTwoSource.denexa, BigTwoSource.wikipediaPusoy];
}
