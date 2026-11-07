import '../../../../games/doudizhu/doudizhu.dart';
import 'doudizhu_strings.dart';

/// Fight the Landlord in English (Pagat's and the English apps' words).
class LandlordStringsEn extends LandlordStrings {
  const LandlordStringsEn();

  @override
  String get pickLabel => 'GTO';

  @override
  String get landlord => 'Landlord';
  @override
  String get peasant => 'Peasant';
  @override
  String get kitty => 'Kitty';
  @override
  String get cantBeat => "Can't beat";
  @override
  String get everyonePassed => 'Everyone passed';
  @override
  String firstToBid(String name, BiddingStyle style) =>
      style == BiddingStyle.callRob ? '$name calls first' : '$name bids first';
  @override
  String get spring => 'Spring';
  @override
  String get antiSpring => 'Anti-spring';
  @override
  String cardsLeft(int n) => n == 1 ? '1 card' : '$n cards';

  @override
  String get play => 'Play';
  @override
  String get pass => 'Pass';
  @override
  String get clear => 'Clear';
  @override
  String get noBid => 'No bid';
  @override
  String bid(int points) => 'Bid $points';
  @override
  String get call => 'Call';
  @override
  String get noCall => 'No call';
  @override
  String get rob => 'Rob';
  @override
  String get noRob => 'No rob';

  @override
  String kind(PlayType type) => switch (type) {
    PlayType.solo => 'Single',
    PlayType.pair => 'Pair',
    PlayType.trio => 'Trio',
    PlayType.trioSolo => 'Trio + 1',
    PlayType.trioPair => 'Trio + pair',
    PlayType.straight => 'Straight',
    PlayType.pairStraight => 'Pair straight',
    PlayType.airplane => 'Airplane',
    PlayType.airplaneSolos => 'Airplane + singles',
    PlayType.airplanePairs => 'Airplane + pairs',
    PlayType.fourTwoSolos => 'Four + 2',
    PlayType.fourTwoPairs => 'Four + 2 pairs',
    PlayType.bomb => 'Bomb',
    PlayType.rocket => 'Rocket',
  };

  @override
  String joker({required bool big}) => big ? 'Big Joker' : 'Little Joker';

  @override
  String jokerShort({required bool big}) => big ? 'BJ' : 'LJ';

  @override
  String rangeKind(String kind) => switch (kind) {
    'pair' => 'Pairs',
    'trio' => 'Trios',
    'straight' => 'Straights',
    'pairs' => 'Pair straights',
    'airplane' => 'Airplanes',
    'bomb' => 'Bombs',
    'rocket' => 'Rocket',
    _ => kind,
  };

  @override
  String rangeKindInfo(String kind) => switch (kind) {
    'pair' => 'Two cards of one rank. A bomb can be split into pairs too.',
    'trio' => 'Three cards of one rank, played alone or with a single or a pair.',
    'straight' => '5 or more ranks in a row, 3 to A. Shown by their first 5 cards.',
    'pairs' => '3 or more pairs in a row, 3 to A. Shown by their first 3 pairs.',
    'airplane' => '2 or more trios in a row, 3 to A. Shown by their first 2 trios.',
    'bomb' => 'Four of a kind. Beats any other kind and doubles the stake.',
    'rocket' => 'Both jokers (LJ and BJ). Beats everything and doubles the stake.',
    _ => kind,
  };

  @override
  String reason(DdzReason reason) => switch (reason) {
    DdzReason.goesOut => 'Goes out',
    DdzReason.finishesNext => 'Goes out next turn',
    DdzReason.partnerWinning => 'Your partner wins the trick',
    DdzReason.keepsBomb => 'Keeps your bomb',
    DdzReason.breaksBomb => 'Breaks your bomb',
    DdzReason.usesBomb => 'Bomb: doubles the stake',
    DdzReason.usesRocket => 'Rocket: doubles the stake',
    DdzReason.leadsSmallForPartner => 'Leads low for your partner',
    DdzReason.opponentsCantBeat => 'Nobody can beat it',
    DdzReason.keepsHighCards => 'Keeps your 2s and jokers',
    DdzReason.breaksGroup => 'Breaks up a combination',
    DdzReason.shedsMany => 'Sheds many cards',
    DdzReason.stopsOpponent => 'Stops an opponent going out',
    DdzReason.opponentCanFollow => 'An opponent can follow',
    DdzReason.takesLead => 'Takes the lead',
    DdzReason.leadsWeakGroup => 'Gets rid of your weakest',
    DdzReason.waits => 'Waits',
    DdzReason.strongHand => 'Strong hand',
    DdzReason.weakHand => 'Weak hand',
    DdzReason.holdsRocket => 'Holds the rocket',
    DdzReason.holdsBomb => 'Holds a bomb',
  };

  @override
  String get sureWin => 'Sure win';
  @override
  String get sureLoss => 'Sure loss';
  @override
  String get cardCounter => 'Card counter';
  @override
  String get partner => 'Partner';

  @override
  String presetName(String preset) => switch (preset) {
    'standard' => 'Standard',
    'app' => 'Call & rob',
    'beginner' => 'Beginner',
    _ => preset,
  };
  @override
  String get bidding => 'Bidding';
  @override
  String biddingStyle(BiddingStyle style) => switch (style) {
    BiddingStyle.points => 'Points',
    BiddingStyle.callRob => 'Call & rob',
  };
  @override
  String get allPass => 'If everyone passes';
  @override
  String allPassRule(AllPassRule rule) => switch (rule) {
    AllPassRule.redeal => 'Redeal',
    AllPassRule.firstBidderLandlord => 'First bidder',
  };
  @override
  String get fourWithTwo => 'Four with two';
  @override
  String get fourWithTwoInfo => 'Four of a kind with 2 singles or 2 pairs. It is not a bomb.';
  @override
  String get rocketAsKickers => 'Rocket as kickers';
  @override
  String get rocketAsKickersInfo => 'Both jokers may be the 2 singles of a four with two or of an airplane.';
  @override
  String get kittyShown => 'Kitty shown';
  @override
  String get bombsDouble => 'Bombs double';
  @override
  String get springDoubles => 'Spring doubles';
  @override
  String get maxMultiplier => 'Max multiplier';
  @override
  String get noLimit => 'None';
  @override
  String get customizeSeats => 'Customize seats';

  @override
  String get combinations => 'Combinations';
  @override
  String get beats => 'Beats';
  @override
  String get example => 'Example';
  @override
  String kindRule(PlayType type) => switch (type) {
    PlayType.solo => 'A lower single. Jokers are the highest.',
    PlayType.pair => 'A lower pair. The two jokers are not a pair.',
    PlayType.trio => 'A lower trio.',
    PlayType.trioSolo => 'A lower trio + 1. Only the trio counts.',
    PlayType.trioPair => 'A lower trio + pair. Only the trio counts.',
    PlayType.straight => 'A lower straight of the same length. 5 or more, 3 to A.',
    PlayType.pairStraight => 'A lower pair straight of the same length. 3 pairs or more.',
    PlayType.airplane => 'A lower airplane of the same length. 2 trios or more.',
    PlayType.airplaneSolos => 'A lower one of the same length. One single per trio.',
    PlayType.airplanePairs => 'A lower one of the same length. One pair per trio.',
    PlayType.fourTwoSolos => 'A lower four + 2. It is not a bomb.',
    PlayType.fourTwoPairs => 'A lower four + 2 pairs. It is not a bomb.',
    PlayType.bomb => 'Anything but a higher bomb or the rocket. Doubles the stake.',
    PlayType.rocket => 'Everything. Doubles the stake.',
  };

  @override
  String term(LandlordTerm term) => switch (term) {
    LandlordTerm.landlord => 'Landlord',
    LandlordTerm.peasants => 'Peasants',
    LandlordTerm.kitty => 'Kitty',
    LandlordTerm.faceUpCard => 'Face-up card',
    LandlordTerm.bidding => 'Bidding',
    LandlordTerm.callRob => 'Call & rob',
    LandlordTerm.multiplier => 'Multiplier',
    LandlordTerm.bomb => 'Bomb',
    LandlordTerm.rocket => 'Rocket',
    LandlordTerm.spring => 'Spring',
    LandlordTerm.cardCounter => 'Card counter',
    LandlordTerm.match => 'Match',
  };

  @override
  String definition(LandlordTerm term) => switch (term) {
    LandlordTerm.landlord =>
      'The player who won the bidding. Takes the kitty, leads first and plays alone '
          'against the other two. Wins or loses double.',
    LandlordTerm.peasants => 'The two players against the landlord. They win together when either one goes out.',
    LandlordTerm.kitty => 'The 3 cards left after the deal. The landlord adds them to their hand.',
    LandlordTerm.faceUpCard =>
      'One card is dealt face up. Whoever gets it bids first. Everyone sees it until it is played.',
    LandlordTerm.bidding =>
      'Bid 1, 2 or 3, or pass. The highest bidder becomes landlord, '
          'and the bid is the stake. A bid of 3 ends the bidding.',
    LandlordTerm.callRob =>
      'Bidding as most apps play it: the first to call may be robbed by the others, '
          'once each. Each rob doubles the stake; the last to rob is landlord.',
    LandlordTerm.multiplier =>
      'What the stake is multiplied by: ×2 for each bomb or rocket played, '
          'and ×2 for a spring.',
    LandlordTerm.bomb => 'Four of a kind. Beats any other kind of play and doubles the stake.',
    LandlordTerm.rocket => 'Both jokers together. Beats everything and doubles the stake.',
    LandlordTerm.spring =>
      'The landlord goes out before either peasant plays a card, or the peasants win '
          'after the landlord played only once. Doubles the stake.',
    LandlordTerm.cardCounter => 'How many cards of each rank are still in the other hands.',
    LandlordTerm.match =>
      'Each deal\'s points are added up: the bid times the multiplier for each peasant, '
          'twice that for the landlord. The first to reach the target ends the match, and the highest total wins. '
          'Always 3 players, so the target never scales.',
  };

  @override
  List<(String, String)> get rulesSections => const [
    (
      'Goal',
      'Three players: one landlord against two peasants. The first to play all their cards wins for their side.',
    ),
    (
      'Deal',
      'One deck with two jokers: 17 cards each and 3 face down, the kitty. '
          'One card is dealt face up: whoever gets it bids first. '
          'Ranks from low to high: 3 4 5 6 7 8 9 10 J Q K A 2, Little Joker, Big Joker. Suits do not matter.',
    ),
    (
      'Bidding',
      'In turn, bid higher than the last bid (1, 2 or 3) or pass. A bid of 3, or two passes after a bid, '
          'ends it. The highest bidder is landlord and takes the kitty, shown to everyone. '
          'If everyone passes, the cards are dealt again.',
    ),
    (
      'Play',
      'The landlord leads any combination. Each next player plays the same kind and length, higher, or passes. '
          'Bombs and the rocket beat other kinds. After two passes in a row, the last player to play leads again. '
          'Passing does not stop you playing later.',
    ),
    (
      'Scoring',
      'Each peasant wins or loses the bid times the multiplier; the landlord wins or loses twice that. '
          'Every bomb or rocket doubles it, and so does a spring. '
          'The points add up deal after deal: the first to reach the target (Play to) ends the match, '
          'and the highest total wins.',
    ),
    (
      'Variants',
      'Call & rob bidding, what happens when everyone passes, four with two, the rocket as kickers, '
          'a hidden kitty, and a cap on the multiplier can all be set before the game.',
    ),
  ];
}
