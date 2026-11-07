/// The rule set of a blackjack table, with researched presets.
///
/// Sources, cited again where each rule is used:
/// - Wizard of Odds, "Blackjack House Edge Calculator"
///   (https://wizardofodds.com/games/blackjack/calculator/): the list of
///   switches below (decks, soft 17, double after split, doubling on any
///   two / 9-11 / 10-11, splitting to 2-4 hands, resplitting and hitting
///   split aces, original bets only, late surrender, 3:2 or 6:5) and the
///   house edges the tests check against.
/// - Wizard of Odds, "Blackjack Rule Variations"
///   (https://wizardofodds.com/games/blackjack/rule-variations/): early
///   surrender, European no hole card, 1:1 blackjacks.
/// - Wizard of Odds, "Basic Strategy for European Blackjack"
///   (https://wizardofodds.com/games/blackjack/strategy/european/): the
///   European game (dealer stands on soft 17, doubling on 9-11 only, no
///   hole card).
/// - Wizard of Odds, "Blackjack basics"
///   (https://wizardofodds.com/games/blackjack/basics/): Atlantic City
///   rules ("dealer stands on soft 17, split up to 4 hands, double after
///   split, double any two cards").
/// - Las Vegas Advisor, "Best blackjack rules"
///   (https://www.lasvegasadvisor.com/question/best-blackjack-rules/): Strip
///   and Downtown rule sets, and the "old Las Vegas Strip rules" single deck
///   with a 0.04% player edge (checked in the tests).
/// - Wikipedia, "Blackjack" (https://en.wikipedia.org/wiki/Blackjack):
///   hole card and peek, late versus early surrender, the Reno 9-11 rule,
///   no hole card with "original bets only", 6:5 and 1:1 payouts, and
///   reshuffling with a cut card.
library;

/// What a player's blackjack (an ace and a ten-value card as the first
/// two cards) pays.
enum BlackjackPayout {
  /// 3 to 2: the traditional payout.
  threeToTwo,

  /// 6 to 5: common on low-limit tables; adds about 1.4% to the house
  /// edge (Wikipedia, "Blackjack": "the 6:5 game adds 1.4%").
  sixToFive,

  /// 1 to 1, like any other win: adds about 2.3% (same source).
  oneToOne;

  /// What a 1-unit bet wins with a blackjack.
  double get multiplier => switch (this) {
    BlackjackPayout.threeToTwo => 1.5,
    BlackjackPayout.sixToFive => 1.2,
    BlackjackPayout.oneToOne => 1.0,
  };
}

/// Which first two cards may be doubled.
enum DoubleRule {
  /// Any first two cards, hard or soft.
  anyTwo,

  /// Hard 9, 10 or 11 only (the "Reno rule").
  nineToEleven,

  /// Hard 10 or 11 only (the common European rule).
  tenToEleven;

  /// Whether a two-card hand of [hard] points (aces as 1) with or without
  /// an ace may be doubled.
  bool allows(int hard, bool hasAce) {
    switch (this) {
      case DoubleRule.anyTwo:
        return true;
      case DoubleRule.nineToEleven:
        // A two-card hand with an ace is always soft (A-8 is soft 19, not
        // a 9), so "hard totals of 9-11 only" means no ace.
        return !hasAce && hard >= 9 && hard <= 11;
      case DoubleRule.tenToEleven:
        return !hasAce && hard >= 10 && hard <= 11;
    }
  }
}

/// When a player may give up half the bet instead of playing the hand.
enum Surrender {
  /// No surrender.
  none,

  /// After the dealer checks for blackjack (or, without a hole card, a
  /// surrender only counts if the dealer ends without blackjack).
  late,

  /// Before the dealer checks for blackjack: half the bet back even if
  /// the dealer has one. Rare and very good for the player.
  early,
}

/// What a player loses to a dealer blackjack in a no-hole-card game.
enum NoHoleCardLoss {
  /// Every bet on the table, doubles and splits included (the usual
  /// European rule).
  allBets,

  /// Only the original bet ("OBO"); doubles and splits are returned. This
  /// makes the game play exactly like a hole card game (Wikipedia).
  originalBetsOnly,
}

/// The ready-made rule sets the app offers. A preset only fills in the
/// switches of [BlackjackRules]; every switch can still be changed.
enum BlackjackPreset {
  /// The app's default: 6 decks, dealer stands on soft 17, 3:2,
  /// peek, double any two, double after split, split to 4 hands, aces
  /// split once with one card each, no surrender, insurance offered.
  standard,

  /// A liberal Las Vegas Strip shoe game (the high-limit rooms): 6 decks,
  /// stands on soft 17, double after split, resplit aces, late surrender.
  vegasStrip,

  /// Downtown Las Vegas double deck: the dealer hits soft 17, double any
  /// two, double after split, split to 4 hands.
  downtown,

  /// Atlantic City: 8 decks, stands on soft 17, double after split, late
  /// surrender, split to 4 hands, no resplitting aces.
  atlanticCity,

  /// European no hole card: 6 decks, stands on soft 17, double on 9-11
  /// only, no hole card (a dealer blackjack takes every bet), split to 2
  /// hands, no surrender.
  european,

  /// Single deck: the dealer hits soft 17, double any two, no double after
  /// split, a shallower cut.
  singleDeck,
}

/// Every rule of a blackjack table. Immutable; [copyWith] changes some.
class BlackjackRules {
  /// A rule set; the defaults are the [BlackjackPreset.standard] game.
  const BlackjackRules({
    this.decks = 6,
    this.continuousShuffle = false,
    this.dealerHitsSoft17 = false,
    this.payout = BlackjackPayout.threeToTwo,
    this.doubling = DoubleRule.anyTwo,
    this.doubleAfterSplit = true,
    this.maxHands = 4,
    this.resplitAces = false,
    this.hitSplitAces = false,
    this.surrender = Surrender.none,
    this.holeCard = true,
    this.noHoleCardLoss = NoHoleCardLoss.allBets,
    this.insurance = true,
    this.penetration = 0.75,
  }) : assert(decks >= 1 && decks <= 8),
       assert(maxHands >= 1 && maxHands <= 4),
       assert(penetration > 0 && penetration < 1);

  /// The rules of a [preset].
  factory BlackjackRules.preset(BlackjackPreset preset) {
    switch (preset) {
      case BlackjackPreset.standard:
        return const BlackjackRules();
      case BlackjackPreset.vegasStrip:
        // Las Vegas Advisor, "Best blackjack rules"
        // (https://www.lasvegasadvisor.com/question/best-blackjack-rules/):
        // the most liberal Strip games stand on soft 17 with double after
        // split, resplit aces and late surrender (the Wynn's example there);
        // six decks is the usual Strip shoe.
        return const BlackjackRules(resplitAces: true, surrender: Surrender.late);
      case BlackjackPreset.downtown:
        // Downtown Las Vegas dealers hit soft 17 (same source: Binion's
        // "H17, double any first two cards") and keep hand-held games;
        // a double deck with 3:2, double any two and double after split.
        return const BlackjackRules(decks: 2, dealerHitsSoft17: true, penetration: 0.65);
      case BlackjackPreset.atlanticCity:
        // Wizard of Odds, "Blackjack basics": "Atlantic City rules (dealer
        // stands on soft 17, split up to 4 hands, double after split,
        // double any two cards)"; 8 decks with late surrender is the
        // usual Atlantic City shoe.
        return const BlackjackRules(decks: 8, surrender: Surrender.late);
      case BlackjackPreset.european:
        // Wizard of Odds, "Basic Strategy for European Blackjack": dealer
        // stands on soft 17, double on hard 9-11 only, no hole card;
        // Wikipedia: no-hole-card dealers take doubles and splits on a
        // blackjack unless "original bets only" is posted. Resplitting is
        // usually not allowed in European casinos.
        return const BlackjackRules(doubling: DoubleRule.nineToEleven, maxHands: 2, holeCard: false);
      case BlackjackPreset.singleDeck:
        // Single deck with the dealer hitting soft 17 and no double after
        // split (Wizard of Odds' single-deck H17 chart marks the double
        // after split plays separately); single decks are cut shallower.
        return const BlackjackRules(decks: 1, dealerHitsSoft17: true, doubleAfterSplit: false, penetration: 0.6);
    }
  }

  /// Decks in the shoe: 1, 2, 4, 6 or 8 (any 1-8 works).
  final int decks;

  /// A continuous shuffling machine: every round is dealt from a freshly
  /// shuffled full shoe, so nothing is gained by remembering cards.
  final bool continuousShuffle;

  /// The dealer hits soft 17 ("H17"); otherwise stands on all 17s ("S17").
  final bool dealerHitsSoft17;

  /// What a blackjack pays.
  final BlackjackPayout payout;

  /// Which first two cards may be doubled.
  final DoubleRule doubling;

  /// Doubling is allowed on the first two cards of a split hand ("DAS").
  final bool doubleAfterSplit;

  /// The most hands one seat can split into (1 = no splitting, 2 = split
  /// once, up to 4).
  final int maxHands;

  /// Aces may be split again when a split ace draws another ace.
  final bool resplitAces;

  /// Split aces may be played on (hit, and doubled if [doubleAfterSplit]).
  /// Otherwise each split ace gets exactly one card.
  final bool hitSplitAces;

  /// When surrender is allowed.
  final Surrender surrender;

  /// The dealer takes a hole card and peeks for blackjack with an ace or
  /// ten-value card showing (the US game). Otherwise the dealer's second
  /// card comes after the players have played ("European no hole card").
  final bool holeCard;

  /// Without a hole card, what a dealer blackjack takes.
  final NoHoleCardLoss noHoleCardLoss;

  /// Insurance (and even money) is offered when the dealer shows an ace.
  /// Insurance costs half the bet and pays 2 to 1.
  final bool insurance;

  /// The share of the shoe dealt before the cut card comes out and the
  /// shoe is reshuffled (after that round). Ignored with
  /// [continuousShuffle].
  final double penetration;

  /// Splitting is allowed at all.
  bool get canSplit => maxHands >= 2;

  /// Whether the dealer peeks for blackjack before the players act. True
  /// for hole card games; a no-hole-card game with "original bets only"
  /// plays the same way but settles at the end.
  bool get dealerPeeks => holeCard;

  /// The dealer-blackjack loss works like a hole card game's: true for
  /// hole card games and for no-hole-card games with original bets only.
  bool get losesOriginalOnly => holeCard || noHoleCardLoss == NoHoleCardLoss.originalBetsOnly;

  /// A copy with some rules changed.
  BlackjackRules copyWith({
    int? decks,
    bool? continuousShuffle,
    bool? dealerHitsSoft17,
    BlackjackPayout? payout,
    DoubleRule? doubling,
    bool? doubleAfterSplit,
    int? maxHands,
    bool? resplitAces,
    bool? hitSplitAces,
    Surrender? surrender,
    bool? holeCard,
    NoHoleCardLoss? noHoleCardLoss,
    bool? insurance,
    double? penetration,
  }) => BlackjackRules(
    decks: decks ?? this.decks,
    continuousShuffle: continuousShuffle ?? this.continuousShuffle,
    dealerHitsSoft17: dealerHitsSoft17 ?? this.dealerHitsSoft17,
    payout: payout ?? this.payout,
    doubling: doubling ?? this.doubling,
    doubleAfterSplit: doubleAfterSplit ?? this.doubleAfterSplit,
    maxHands: maxHands ?? this.maxHands,
    resplitAces: resplitAces ?? this.resplitAces,
    hitSplitAces: hitSplitAces ?? this.hitSplitAces,
    surrender: surrender ?? this.surrender,
    holeCard: holeCard ?? this.holeCard,
    noHoleCardLoss: noHoleCardLoss ?? this.noHoleCardLoss,
    insurance: insurance ?? this.insurance,
    penetration: penetration ?? this.penetration,
  );

  /// The rules as plain JSON (enum values by name), for saved games and
  /// background jobs. [BlackjackRules.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'decks': decks,
    'continuousShuffle': continuousShuffle,
    'dealerHitsSoft17': dealerHitsSoft17,
    'payout': payout.name,
    'doubling': doubling.name,
    'doubleAfterSplit': doubleAfterSplit,
    'maxHands': maxHands,
    'resplitAces': resplitAces,
    'hitSplitAces': hitSplitAces,
    'surrender': surrender.name,
    'holeCard': holeCard,
    'noHoleCardLoss': noHoleCardLoss.name,
    'insurance': insurance,
    'penetration': penetration,
  };

  /// The rules written by [toJson]. A missing switch takes its default (so
  /// a rule added later doesn't break older saves); a value of the wrong
  /// type, an unknown name or a number out of range throws a
  /// [FormatException], so a broken save is noticed rather than played.
  factory BlackjackRules.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('blackjack rules: not a map');
    T read<T>(String key, T fallback) {
      final v = json[key];
      if (v == null) return fallback;
      if (v is! T) throw FormatException('blackjack rules: bad $key');
      return v;
    }

    E pick<E extends Enum>(List<E> values, String key, E fallback) {
      final name = read<String?>(key, null);
      if (name == null) return fallback;
      for (final v in values) {
        if (v.name == name) return v;
      }
      throw FormatException('blackjack rules: unknown $key $name');
    }

    const d = BlackjackRules();
    final decks = read<int>('decks', d.decks);
    final maxHands = read<int>('maxHands', d.maxHands);
    final penetration = read<num>('penetration', d.penetration).toDouble();
    if (decks < 1 || decks > 8 || maxHands < 1 || maxHands > 4 || penetration <= 0 || penetration >= 1) {
      throw const FormatException('blackjack rules: number out of range');
    }
    return BlackjackRules(
      decks: decks,
      continuousShuffle: read<bool>('continuousShuffle', d.continuousShuffle),
      dealerHitsSoft17: read<bool>('dealerHitsSoft17', d.dealerHitsSoft17),
      payout: pick(BlackjackPayout.values, 'payout', d.payout),
      doubling: pick(DoubleRule.values, 'doubling', d.doubling),
      doubleAfterSplit: read<bool>('doubleAfterSplit', d.doubleAfterSplit),
      maxHands: maxHands,
      resplitAces: read<bool>('resplitAces', d.resplitAces),
      hitSplitAces: read<bool>('hitSplitAces', d.hitSplitAces),
      surrender: pick(Surrender.values, 'surrender', d.surrender),
      holeCard: read<bool>('holeCard', d.holeCard),
      noHoleCardLoss: pick(NoHoleCardLoss.values, 'noHoleCardLoss', d.noHoleCardLoss),
      insurance: read<bool>('insurance', d.insurance),
      penetration: penetration,
    );
  }

  /// A short key naming every rule that changes strategy or odds (not
  /// penetration or insurance), used to cache charts per rule set.
  String get strategyKey =>
      '${decks}d${dealerHitsSoft17 ? 'H' : 'S'}17-${payout.index}-${doubling.index}-'
      '${doubleAfterSplit ? 1 : 0}-$maxHands-${resplitAces ? 1 : 0}${hitSplitAces ? 1 : 0}-'
      '${surrender.index}-${holeCard ? 'hole' : 'nhc${noHoleCardLoss.index}'}';

  @override
  bool operator ==(Object other) =>
      other is BlackjackRules &&
      other.strategyKey == strategyKey &&
      other.continuousShuffle == continuousShuffle &&
      other.insurance == insurance &&
      other.penetration == penetration;

  @override
  int get hashCode => Object.hash(strategyKey, continuousShuffle, insurance, penetration);

  @override
  String toString() =>
      '$decks deck${decks == 1 ? '' : 's'}${continuousShuffle ? ' (CSM)' : ''}, '
      '${dealerHitsSoft17 ? 'H17' : 'S17'}, BJ pays ${payout.name}, double ${doubling.name}'
      '${doubleAfterSplit ? ', DAS' : ', no DAS'}, split to $maxHands'
      '${resplitAces ? ', RSA' : ''}${hitSplitAces ? ', hit split aces' : ''}'
      '${surrender == Surrender.none ? '' : ', ${surrender.name} surrender'}'
      '${holeCard ? '' : ', no hole card (${noHoleCardLoss.name})'}'
      '${insurance ? '' : ', no insurance'}';
}
