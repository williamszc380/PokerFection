/// The rule set of one game of Big Two, with the regional presets.
///
/// Sources, cited again where each rule is used:
/// - Pagat, "Big Two" (https://www.pagat.com/climbing/bigtwo.html): the
///   standard game and the Hong Kong, Philippine (Pusoy Dos), Taiwanese and
///   Indonesian variations, honour hands (bombs), the last-card rule, 3 and
///   2 player deals.
/// - Wikipedia, "Big two" (https://en.wikipedia.org/wiki/Big_two): straight
///   orders and the doubling rules in scoring.
/// - Chinese Wikipedia, "大老二" (https://zh.wikipedia.org/zh-tw/大老二):
///   Taiwan's suit order (♠ > ♥ > ♦ > ♣), four of a kind and straight
///   flushes as bombs that beat any play, and five-card replies having to
///   match the type led.
library;

import 'dart:typed_data';

import 'cards.dart';

/// The ready-made rule sets the app offers. A preset only fills in the
/// switches of [BigTwoRules]; every switch can still be changed after.
enum BigTwoPreset {
  /// Pagat's standard game.
  standard,

  /// Hong Kong "Choh Dai Di".
  hongKong,

  /// Taiwanese "Da Lao Er" (大老二).
  taiwan,

  /// The Philippine game, Pusoy Dos.
  pusoyDos,
}

/// How two flushes compare.
enum FlushOrder {
  /// The suit decides first, then the top card's rank. Pagat's standard
  /// game: "A flush in a higher suit beats a flush in a lower suit,
  /// irrespective of the ranks."
  suitFirst,

  /// The top card's rank decides first, then its suit. Pagat's Hong Kong
  /// game: "Flushes are compared according to the rank of the highest card."
  rankFirst,

  /// Poker style: compare the ranks from the top card down, and only when
  /// all five match does the suit decide (Chinese Wikipedia, flush
  /// version 3).
  allRanks,
}

/// How a game is scored.
enum BigTwoScoring {
  /// Pagat's standard penalties: each loser pays one point per card left
  /// with 9 or fewer, two per card with 10 to 12, three per card with all
  /// 13. The winner collects what the others pay.
  penalty,

  /// Pagat's Pusoy Dos: "The winner normally scores 1 point and the others
  /// score nothing", doubled for each 2 in the winning play (2, 4, 8, 16).
  pusoyDos,
}

/// Which card's suit breaks a tie between two straights of the same ranks.
enum StraightTieBreak {
  /// The top of the sequence: the 5 in 5-4-3-2-A, the 6 in 6-5-4-3-2.
  /// Pagat writes straights from the top down and says "the suit of the top
  /// card determines which is higher".
  sequenceTop,

  /// The card that ranks highest on its own: the 2 in A-2-3-4-5 and in
  /// 2-3-4-5-6. Used with the rules where those straights rank high.
  highestCard,
}

/// Which five-card runs count as straights, and their order.
///
/// A run is named by its lowest card going round the ranks: rank 11 (the
/// ace) starts A-2-3-4-5, rank 12 (the 2) starts 2-3-4-5-6, rank 0 starts
/// 3-4-5-6-7, ..., rank 7 starts 10-J-Q-K-A and rank 8 starts J-Q-K-A-2.
/// [order] lists the allowed runs from the lowest straight to the highest;
/// any run not listed is not a straight (nor a straight flush).
class StraightRule {
  /// A custom order, for house rules the presets don't cover.
  const StraightRule(this.order, {this.tieBreak = StraightTieBreak.highestCard, this.name = 'custom'});

  /// Pagat's standard: "the lowest type of straight 5-4-3-2-A, which is
  /// beaten by 6-5-4-3-2 and 7-6-5-4-3", up to A-K-Q-J-10 as the highest.
  /// The ace may be low or high "but not in the middle", so J-Q-K-A-2,
  /// Q-K-A-2-3 and K-A-2-3-4 are not straights.
  static const pagat = StraightRule(
    [11, 12, 0, 1, 2, 3, 4, 5, 6, 7],
    tieBreak: StraightTieBreak.sequenceTop,
    name: 'pagat',
  );

  /// Pagat's Hong Kong order: "JQKA2 is not a valid straight or straight
  /// flush. The highest straight or straight flush is A2345, then 23456,
  /// TJQKA, 9TJQK, and so on down to 34567 (lowest)." Ties go to the suit of
  /// the 2 in the two runs that hold one.
  static const hongKong = StraightRule(
    [0, 1, 2, 3, 4, 5, 6, 7, 12, 11],
    tieBreak: StraightTieBreak.highestCard,
    name: 'hongKong',
  );

  /// The common Taiwanese order: 2-3-4-5-6 is the highest straight, then
  /// 10-J-Q-K-A, down to 3-4-5-6-7, with A-2-3-4-5 the lowest (Chinese
  /// Wikipedia's straight version 7, "A2345 is lowest, 23456 is highest").
  /// Sources disagree on Taiwan; the switch lets a table pick another.
  static const taiwan = StraightRule(
    [11, 0, 1, 2, 3, 4, 5, 6, 7, 12],
    tieBreak: StraightTieBreak.highestCard,
    name: 'taiwan',
  );

  /// Runs only in plain rank order 3 .. 2, so J-Q-K-A-2 is the highest
  /// straight and neither A-2-3-4-5 nor 2-3-4-5-6 is a straight (the rules
  /// used in Charlesworth's Big Two research, arXiv:1808.10442).
  static const twoHigh = StraightRule(
    [0, 1, 2, 3, 4, 5, 6, 7, 8],
    tieBreak: StraightTieBreak.highestCard,
    name: 'twoHigh',
  );

  /// Allowed runs by starting rank, lowest straight first.
  final List<int> order;

  /// Which card breaks ties between straights of the same ranks.
  final StraightTieBreak tieBreak;

  /// A short id for logs and saved settings.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is StraightRule && other.tieBreak == tieBreak && _listEquals(other.order, order);

  @override
  int get hashCode => Object.hash(tieBreak, Object.hashAll(order));
}

/// One game's rules. A value object: two equal rule sets play the same game.
///
/// The defaults are Pagat's standard four-player game. Lookup tables for the
/// engine are built once in the constructor, so keep one instance per game
/// rather than building it for every move.
class BigTwoRules {
  /// Any combination of switches. Prefer [BigTwoRules.preset] plus
  /// [copyWith] so the table starts from a known regional game.
  BigTwoRules({
    this.players = 4,
    int? cardsEach,
    this.suitOrder = const [Suit.diamonds, Suit.clubs, Suit.hearts, Suit.spades],
    this.straights = StraightRule.pagat,
    this.flushOrder = FlushOrder.suitFirst,
    this.bombs = false,
    this.fiveCardSameType = false,
    this.passLockout = false,
    this.mustPlayStartCard = true,
    this.lastCardRule = false,
    this.dragonWins = false,
    this.noTopSingleFinish = false,
    this.scoring = BigTwoScoring.penalty,
    this.doubleTwosLeft = false,
    this.doubleBombLeft = false,
  }) : cardsEach = cardsEach ?? (players == 4 ? 13 : 17) {
    if (players < 2 || players > 4) throw ArgumentError.value(players, 'players', 'Big Two is for 2 to 4 players');
    final expected = switch (players) { 4 => const [13], 3 => const [17], _ => const [13, 17, 21] };
    if (!expected.contains(this.cardsEach)) {
      throw ArgumentError.value(this.cardsEach, 'cardsEach', 'With $players players deal one of $expected');
    }
    if (suitOrder.length != 4 || suitOrder.toSet().length != 4) {
      throw ArgumentError.value(suitOrder, 'suitOrder', 'List each suit once, lowest first');
    }
    for (var i = 0; i < 4; i++) {
      _suitRank[suitOrder[i].index] = i;
    }
    _straightPos.fillRange(0, _straightPos.length, -1);
    for (var pos = 0; pos < straights.order.length; pos++) {
      final start = straights.order[pos];
      var mask = 0, top = 0, high = -1;
      for (var k = 0; k < 5; k++) {
        final r = (start + k) % 13;
        mask |= 1 << r;
        if (r > high) high = r;
        top = r;
      }
      _straightPos[mask] = pos;
      _straightTieRank.add(straights.tieBreak == StraightTieBreak.sequenceTop ? top : high);
      _straightStart.add(start);
    }
  }

  /// A preset, ready to adjust with [copyWith].
  factory BigTwoRules.preset(BigTwoPreset preset, {int players = 4, int? cardsEach}) => switch (preset) {
        BigTwoPreset.standard => BigTwoRules.standard(players: players, cardsEach: cardsEach),
        BigTwoPreset.hongKong => BigTwoRules.hongKong(players: players, cardsEach: cardsEach),
        BigTwoPreset.taiwan => BigTwoRules.taiwan(players: players, cardsEach: cardsEach),
        BigTwoPreset.pusoyDos => BigTwoRules.pusoyDos(players: players, cardsEach: cardsEach),
      };

  /// Pagat's standard game: suits ♠ > ♥ > ♣ > ♦, the 3♦ starts and must be
  /// played, Pagat straights, flushes by suit first, no bombs, passing never
  /// locks you out, penalty scoring.
  factory BigTwoRules.standard({int players = 4, int? cardsEach}) =>
      BigTwoRules(players: players, cardsEach: cardsEach);

  /// Hong Kong (Pagat): Hong Kong straights (A-2-3-4-5 highest, no
  /// J-Q-K-A-2), flushes by rank first, a dealt dragon (one card of every
  /// rank, in a 13-card hand) wins the deal outright, and nobody may go out
  /// with a lone ♠2. Suits and scoring as standard.
  factory BigTwoRules.hongKong({int players = 4, int? cardsEach}) => BigTwoRules(
        players: players,
        cardsEach: cardsEach,
        straights: StraightRule.hongKong,
        flushOrder: FlushOrder.rankFirst,
        dragonWins: true,
        noTopSingleFinish: true,
      );

  /// Taiwan: suits ♠ > ♥ > ♦ > ♣ so the 3♣ starts (Pagat; Chinese
  /// Wikipedia); four of a kind and straight flushes are bombs that beat any
  /// play; a five-card reply must be the type that was led unless it is a
  /// bomb (Chinese Wikipedia); Taiwanese straights.
  ///
  /// Not built yet: Chinese Wikipedia's 一條龍 (a 13-card run of every rank,
  /// any suits), which can be played on anything and beats even a straight
  /// flush. It is a play, not a win before play, so [dragonWins] stays off.
  factory BigTwoRules.taiwan({int players = 4, int? cardsEach}) => BigTwoRules(
        players: players,
        cardsEach: cardsEach,
        suitOrder: const [Suit.clubs, Suit.diamonds, Suit.hearts, Suit.spades],
        straights: StraightRule.taiwan,
        bombs: true,
        fiveCardSameType: true,
      );

  /// Pusoy Dos (Pagat): suits ♦ > ♥ > ♠ > ♣ so the 3♣ starts, and the
  /// winner scores 1 point, doubled for each 2 in the winning play.
  factory BigTwoRules.pusoyDos({int players = 4, int? cardsEach}) => BigTwoRules(
        players: players,
        cardsEach: cardsEach,
        suitOrder: const [Suit.clubs, Suit.spades, Suit.hearts, Suit.diamonds],
        scoring: BigTwoScoring.pusoyDos,
      );

  /// Number of players, 2 to 4.
  final int players;

  /// Cards dealt to each player. Pagat: 13 each with four players; with
  /// three, "Seventeen cards are dealt to each player, and the last card is
  /// placed face up" and goes to whoever holds the starting card; with two,
  /// "17 cards each with 18 unused, 21 cards each with 10 unused, or 13
  /// cards each with 26 unused".
  final int cardsEach;

  /// The suits from lowest to highest. Standard (Pagat): "spades, hearts,
  /// clubs, diamonds" from high to low.
  final List<Suit> suitOrder;

  /// Which runs are straights, and their order.
  final StraightRule straights;

  /// How flushes compare.
  final FlushOrder flushOrder;

  /// Four of a kind (with its fifth card) and straight flushes also beat any
  /// single, pair or triple. Pagat calls these honour hands: "Some allow an
  /// honour hand to be played not only to beat a lower 5-card hand, but
  /// also to beat singles pairs or triples."
  final bool bombs;

  /// A five-card hand can only be beaten by a five-card hand of the same
  /// type (a straight by a higher straight, and so on), apart from bombs
  /// when [bombs] is on. Taiwanese rule (Chinese Wikipedia).
  final bool fiveCardSameType;

  /// Once you pass you may not play again until someone wins the trick and
  /// leads. Pagat (Indonesia): "A player who has passed is not allowed to
  /// play cards in subsequent turns of the same trick."
  final bool passLockout;

  /// The first play must contain the starting card. Pagat: "The player who
  /// holds the three of diamonds begins and must play this card, either by
  /// itself or as part of a legal combination." When off, the holder still
  /// leads but may lead anything.
  final bool mustPlayStartCard;

  /// When the next player has one card left, a single you play must be your
  /// highest card. Pagat: "if you are playing immediately before a player
  /// who has only one card you must play your highest single card or a
  /// combination of more than one card." You may still pass when following.
  final bool lastCardRule;

  /// Being dealt a dragon (one card of every rank, 3 to 2) wins the deal at
  /// once. Pagat (Hong Kong): "a player who is dealt a dragon, which is one
  /// card of each rank ... immediately wins the game." Only 13-card deals
  /// have dragons: a 17- or 21-card hand usually holds every rank.
  final bool dragonWins;

  /// Nobody may go out by playing the highest card (the ♠2 under standard
  /// suits) alone as their last card. Pagat (Hong Kong): "The deal cannot be
  /// won by playing a single ♠2 as your last card." A player left holding
  /// only that card can never go out; on lead they pass the lead on.
  final bool noTopSingleFinish;

  /// How the deal is scored.
  final BigTwoScoring scoring;

  /// Penalty scoring: a loser's penalty doubles for each 2 still in hand
  /// (Wikipedia: "doubled ... If the player has an unused two").
  final bool doubleTwosLeft;

  /// Penalty scoring: a loser's penalty doubles once if they still hold a
  /// four of a kind or a straight flush (Wikipedia: "If the player has an
  /// unused Four-of-a-Kind or straight flush").
  final bool doubleBombLeft;

  final _suitRank = Int8List(4);
  final _straightPos = Int16List(8192);
  final _straightTieRank = <int>[];
  final _straightStart = <int>[];

  /// How many cards are dealt in total (the rest stay unused in 2-player
  /// games). With three players the 52nd card is dealt face up as well.
  int get cardsDealt => players == 3 ? 52 : players * cardsEach;

  /// Engine code of a card: `rank * 4 + suit strength`, so a higher code is
  /// a higher single under these rules. Codes are what the engine stores.
  int codeOf(Card card) => (card.rank << 2) | _suitRank[card.suit.index];

  /// The card with engine [code] under these rules.
  Card cardOf(int code) => Card.of(code >> 2, suitOrder[code & 3]);

  /// Strength of [suit] under these rules, 0 (lowest) to 3 (highest).
  int suitStrength(Suit suit) => _suitRank[suit.index];

  /// The position of the straight made by these 13-bit rank bits, or -1 if
  /// the ranks are not an allowed run. Bit r is rank r (0 = the 3).
  int straightPosition(int rankBits) => _straightPos[rankBits];

  /// The rank whose suit breaks ties for the straight at [position].
  int straightTieRank(int position) => _straightTieRank[position];

  /// The first rank of the straight at [position] (see [StraightRule]).
  int straightStart(int position) => _straightStart[position];

  /// A copy with some switches changed. Changing [players] picks that player
  /// count's default deal unless [cardsEach] is given too.
  BigTwoRules copyWith({
    int? players,
    int? cardsEach,
    List<Suit>? suitOrder,
    StraightRule? straights,
    FlushOrder? flushOrder,
    bool? bombs,
    bool? fiveCardSameType,
    bool? passLockout,
    bool? mustPlayStartCard,
    bool? lastCardRule,
    bool? dragonWins,
    bool? noTopSingleFinish,
    BigTwoScoring? scoring,
    bool? doubleTwosLeft,
    bool? doubleBombLeft,
  }) =>
      BigTwoRules(
        players: players ?? this.players,
        cardsEach: cardsEach ?? (players == null ? this.cardsEach : null),
        suitOrder: suitOrder ?? this.suitOrder,
        straights: straights ?? this.straights,
        flushOrder: flushOrder ?? this.flushOrder,
        bombs: bombs ?? this.bombs,
        fiveCardSameType: fiveCardSameType ?? this.fiveCardSameType,
        passLockout: passLockout ?? this.passLockout,
        mustPlayStartCard: mustPlayStartCard ?? this.mustPlayStartCard,
        lastCardRule: lastCardRule ?? this.lastCardRule,
        dragonWins: dragonWins ?? this.dragonWins,
        noTopSingleFinish: noTopSingleFinish ?? this.noTopSingleFinish,
        scoring: scoring ?? this.scoring,
        doubleTwosLeft: doubleTwosLeft ?? this.doubleTwosLeft,
        doubleBombLeft: doubleBombLeft ?? this.doubleBombLeft,
      );

  /// Plain data for saving the table's settings or sending them to a
  /// worker; [BigTwoRules.fromJson] reads it back.
  Map<String, Object?> toJson() => {
        'players': players,
        'cardsEach': cardsEach,
        'suits': [for (final s in suitOrder) s.name],
        'straights': straights.order,
        'straightTie': straights.tieBreak.name,
        'straightName': straights.name,
        'flush': flushOrder.name,
        'bombs': bombs,
        'fiveCardSameType': fiveCardSameType,
        'passLockout': passLockout,
        'mustPlayStartCard': mustPlayStartCard,
        'lastCardRule': lastCardRule,
        'dragonWins': dragonWins,
        'noTopSingleFinish': noTopSingleFinish,
        'scoring': scoring.name,
        'doubleTwosLeft': doubleTwosLeft,
        'doubleBombLeft': doubleBombLeft,
      };

  /// Reads [toJson]'s output.
  factory BigTwoRules.fromJson(Map<String, Object?> j) => BigTwoRules(
        players: j['players'] as int,
        cardsEach: j['cardsEach'] as int,
        suitOrder: [for (final s in j['suits'] as List) Suit.values.byName(s as String)],
        straights: StraightRule(
          [for (final v in j['straights'] as List) v as int],
          tieBreak: StraightTieBreak.values.byName(j['straightTie'] as String),
          name: j['straightName'] as String,
        ),
        flushOrder: FlushOrder.values.byName(j['flush'] as String),
        bombs: j['bombs'] as bool,
        fiveCardSameType: j['fiveCardSameType'] as bool,
        passLockout: j['passLockout'] as bool,
        mustPlayStartCard: j['mustPlayStartCard'] as bool,
        lastCardRule: j['lastCardRule'] as bool,
        dragonWins: j['dragonWins'] as bool,
        noTopSingleFinish: j['noTopSingleFinish'] as bool,
        scoring: BigTwoScoring.values.byName(j['scoring'] as String),
        doubleTwosLeft: j['doubleTwosLeft'] as bool,
        doubleBombLeft: j['doubleBombLeft'] as bool,
      );

  @override
  bool operator ==(Object other) =>
      other is BigTwoRules &&
      other.players == players &&
      other.cardsEach == cardsEach &&
      _listEquals(other.suitOrder, suitOrder) &&
      other.straights == straights &&
      other.flushOrder == flushOrder &&
      other.bombs == bombs &&
      other.fiveCardSameType == fiveCardSameType &&
      other.passLockout == passLockout &&
      other.mustPlayStartCard == mustPlayStartCard &&
      other.lastCardRule == lastCardRule &&
      other.dragonWins == dragonWins &&
      other.noTopSingleFinish == noTopSingleFinish &&
      other.scoring == scoring &&
      other.doubleTwosLeft == doubleTwosLeft &&
      other.doubleBombLeft == doubleBombLeft;

  @override
  int get hashCode => Object.hash(players, cardsEach, Object.hashAll(suitOrder), straights, flushOrder, bombs,
      fiveCardSameType, passLockout, mustPlayStartCard, lastCardRule, dragonWins, noTopSingleFinish, scoring,
      doubleTwosLeft, doubleBombLeft);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
