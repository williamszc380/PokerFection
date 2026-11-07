/// The rule variants of Fight the Landlord, as one value object.
///
/// The defaults are the standard game as Pagat describes it
/// (https://www.pagat.com/climbing/doudizhu.html): 3 players, 1 to 3 point
/// bidding, a redeal when everyone passes, four-with-two allowed, every bomb
/// or rocket doubling the stake and spring / anti-spring doubling it too.
/// The house rules people argue about are switches, so a room can match
/// what its players are used to and the bots and coach play the same game.
library;

/// How the landlord is chosen.
enum BiddingStyle {
  /// Pagat: "Each player in turn may either pass or bid higher than the
  /// highest bid so far ... until two consecutive players pass or someone
  /// bids 3." The winning bid (1, 2 or 3) is the stake.
  points,

  /// Call and rob (叫地主 / 抢地主), as in Tencent's Happy Dou Dizhu and
  /// most Chinese apps. Source: the MAIGOO encyclopedia entry on Dou Dizhu
  /// rules (https://www.maigoo.com/citiao/137419.html): once someone calls,
  /// "按照次序每位玩家均有且只有一次'抢地主'的机会" (in turn, every player
  /// has exactly one chance to rob); "凡是有过'不叫地主'操作的玩家无法进行
  /// '抢地主'的操作" (a player who declined to call may not rob); and
  /// "每'抢地主'一次，游戏倍数×2" (each rob doubles the stake, which starts
  /// at 1). The last player to rob becomes landlord. The caller's one
  /// chance comes last, after the others, and only if someone robbed (with
  /// no rob the caller simply keeps the seat).
  callRob,
}

/// What happens when nobody bids or calls.
enum AllPassRule {
  /// Pagat: "If everyone passes the hand is thrown in and there is a new
  /// deal." The game ends with [DdzPhase.thrownIn] and the app deals again.
  redeal,

  /// A house rule (no published source; some tables use it to avoid
  /// endless redeals): when nobody bids, the first player to bid becomes
  /// landlord at the lowest stake (1).
  firstBidderLandlord,
}

/// The cards and hand sizes of a table. Only [threePlayer] can be played
/// today; [fourPlayer] is here as data so the 4-player game can be added
/// later without changing the rules object.
class DeckSpec {
  const DeckSpec({
    required this.players,
    required this.decks,
    required this.handSize,
    required this.kittySize,
    required this.minBombSize,
    required this.rocketJokers,
    required this.solosAsKickers,
    required this.fourWithTwoExists,
    required this.minDoublingBomb,
  });

  /// One deck, 17 cards each and a kitty of 3 (Pagat).
  static const threePlayer = DeckSpec(
    players: 3,
    decks: 1,
    handSize: 17,
    kittySize: 3,
    minBombSize: 4,
    rocketJokers: 2,
    solosAsKickers: true,
    fourWithTwoExists: true,
    minDoublingBomb: 4,
  );

  /// Pagat's 4-player game: two decks (108 cards), 25 each, a kitty of 8;
  /// bombs of 4 or more cards, the rocket needs all four jokers, single
  /// kickers and four-with-two don't exist, and only bombs of 6 or more
  /// double the stake. Not playable yet.
  static const fourPlayer = DeckSpec(
    players: 4,
    decks: 2,
    handSize: 25,
    kittySize: 8,
    minBombSize: 4,
    rocketJokers: 4,
    solosAsKickers: false,
    fourWithTwoExists: false,
    minDoublingBomb: 6,
  );

  final int players;
  final int decks;
  final int handSize;
  final int kittySize;
  final int minBombSize;
  final int rocketJokers;
  final bool solosAsKickers;
  final bool fourWithTwoExists;
  final int minDoublingBomb;
}

/// Every rule switch of a game. Pass one to the game, the bots and the coach.
class DdzRules {
  const DdzRules({
    this.bidding = BiddingStyle.points,
    this.allPass = AllPassRule.redeal,
    this.fourWithTwo = true,
    this.rocketAsKickers = false,
    this.kittyShown = true,
    this.bombsDouble = true,
    this.springDoubles = true,
    this.maxMultiplier,
    this.deck = DeckSpec.threePlayer,
  });

  /// Pagat's standard game.
  static const standard = DdzRules();

  /// The game as Chinese apps play it: call and rob. When nobody calls the
  /// cards are dealt again, as in the same source ("如果都'不叫'，则重新发牌"),
  /// see [BiddingStyle.callRob].
  static const app = DdzRules(bidding: BiddingStyle.callRob);

  /// A gentler table: no four-with-two (fewer combinations to learn), and
  /// the stake can never grow past 8 times the bid.
  static const beginner = DdzRules(fourWithTwo: false, maxMultiplier: 8);

  /// The presets by name, for a settings menu.
  static const presets = {'standard': standard, 'app': app, 'beginner': beginner};

  /// See [BiddingStyle].
  final BiddingStyle bidding;

  /// See [AllPassRule].
  final AllPassRule allPass;

  /// Whether "four with two" exists: a four of a kind with two solos of
  /// different ranks, or with two pairs of different ranks (Pagat's
  /// "quadplex set"). It is not a bomb. Some tables leave it out.
  final bool fourWithTwo;

  /// Whether both jokers may be kickers in one play. Pagat forbids it for
  /// four-with-two ("you cannot use both jokers in one quadplex set") and
  /// most apps extend that to trios and airplanes, since the two jokers are
  /// the rocket. Off by default.
  final bool rocketAsKickers;

  /// Whether the kitty is shown to everyone when the landlord takes it.
  /// Pagat: the custom "in some groups for the landlord to reveal the three
  /// cards"; every app does. On by default; when off, only the landlord
  /// knows them.
  final bool kittyShown;

  /// Pagat: "For each occasion when any player played a bomb or rocket, the
  /// payment for the hand is doubled."
  final bool bombsDouble;

  /// Pagat: the payment doubles for a spring (the peasants never play a
  /// card) and for an anti-spring (the landlord played only the first
  /// combination before a peasant went out).
  final bool springDoubles;

  /// The largest multiplier, or null for no limit. Many apps cap it.
  final int? maxMultiplier;

  /// The deck and hand sizes. Must be [DeckSpec.threePlayer] for now.
  final DeckSpec deck;

  /// Number of players at the table.
  int get players => deck.players;

  /// A copy with some switches changed.
  DdzRules copyWith({
    BiddingStyle? bidding,
    AllPassRule? allPass,
    bool? fourWithTwo,
    bool? rocketAsKickers,
    bool? kittyShown,
    bool? bombsDouble,
    bool? springDoubles,
    int? maxMultiplier,
    bool clearMaxMultiplier = false,
  }) =>
      DdzRules(
        bidding: bidding ?? this.bidding,
        allPass: allPass ?? this.allPass,
        fourWithTwo: fourWithTwo ?? this.fourWithTwo,
        rocketAsKickers: rocketAsKickers ?? this.rocketAsKickers,
        kittyShown: kittyShown ?? this.kittyShown,
        bombsDouble: bombsDouble ?? this.bombsDouble,
        springDoubles: springDoubles ?? this.springDoubles,
        maxMultiplier: clearMaxMultiplier ? null : (maxMultiplier ?? this.maxMultiplier),
        deck: deck,
      );

  /// For online rooms and saved games.
  Map<String, Object?> toJson() => {
        'bidding': bidding.name,
        'allPass': allPass.name,
        'fourWithTwo': fourWithTwo,
        'rocketAsKickers': rocketAsKickers,
        'kittyShown': kittyShown,
        'bombsDouble': bombsDouble,
        'springDoubles': springDoubles,
        'maxMultiplier': maxMultiplier,
      };

  /// Reads [toJson]; unknown or missing values fall back to the standard.
  factory DdzRules.fromJson(Map<String, Object?> json) => DdzRules(
        bidding: BiddingStyle.values.asNameMap()[json['bidding']] ?? BiddingStyle.points,
        allPass: AllPassRule.values.asNameMap()[json['allPass']] ?? AllPassRule.redeal,
        fourWithTwo: json['fourWithTwo'] as bool? ?? true,
        rocketAsKickers: json['rocketAsKickers'] as bool? ?? false,
        kittyShown: json['kittyShown'] as bool? ?? true,
        bombsDouble: json['bombsDouble'] as bool? ?? true,
        springDoubles: json['springDoubles'] as bool? ?? true,
        maxMultiplier: json['maxMultiplier'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      other is DdzRules &&
      other.bidding == bidding &&
      other.allPass == allPass &&
      other.fourWithTwo == fourWithTwo &&
      other.rocketAsKickers == rocketAsKickers &&
      other.kittyShown == kittyShown &&
      other.bombsDouble == bombsDouble &&
      other.springDoubles == springDoubles &&
      other.maxMultiplier == maxMultiplier &&
      identical(other.deck, deck);

  @override
  int get hashCode => Object.hash(bidding, allPass, fourWithTwo, rocketAsKickers, kittyShown,
      bombsDouble, springDoubles, maxMultiplier, deck.players);
}
