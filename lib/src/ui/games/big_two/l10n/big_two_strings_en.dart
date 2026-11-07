import '../../../../games/big_two/big_two.dart';
import 'big_two_strings.dart';

/// Big Two in English.
class BigTwoStringsEn extends BigTwoStrings {
  const BigTwoStringsEn();

  @override
  String get pickLabel => 'GTO';

  @override
  String get play => 'Play';
  @override
  String get pass => 'Pass';
  @override
  String get cantBeat => "Can't beat";
  @override
  String starts(String name, String? card) => '$name starts${card == null ? '' : ': $card'}';
  @override
  String get whoStarts => 'Who starts?';
  @override
  String get clear => 'Clear';
  @override
  String get cardCounter => 'Card counter';
  @override
  String get stillOut => 'Still out';
  @override
  String get highestOut => 'Highest out';
  @override
  String get handPlan => 'Hand plan';
  @override
  String planSummary(int plays, int unbeatable) => '$plays plays · $unbeatable unbeatable';
  @override
  String kind(PlayKind kind) => switch (kind) {
    PlayKind.pass => 'Pass',
    PlayKind.single => 'Single',
    PlayKind.pair => 'Pair',
    PlayKind.triple => 'Triple',
    PlayKind.straight => 'Straight',
    PlayKind.flush => 'Flush',
    PlayKind.fullHouse => 'Full house',
    PlayKind.fourOfAKind => 'Four of a kind',
    PlayKind.straightFlush => 'Straight flush',
  };
  @override
  String reason(CoachReason reason) => switch (reason) {
    CoachReason.goesOut => 'Goes out',
    CoachReason.sureWin => 'Sure win',
    CoachReason.cantBeBeaten => "Can't be beaten",
    CoachReason.shedsFive => 'Sheds five cards',
    CoachReason.shedsLowest => 'Sheds your lowest card',
    CoachReason.keepsTwo => 'Keeps your 2s',
    CoachReason.usesTwo => 'Spends a 2',
    CoachReason.breaksPair => 'Breaks a pair',
    CoachReason.breaksTriple => 'Breaks a triple',
    CoachReason.breaksFour => 'Breaks four of a kind',
    CoachReason.followsPlan => 'Follows your plan',
    CoachReason.addsPlays => 'Adds plays to finish',
    CoachReason.blocksLastCard => 'Stops the last card',
    CoachReason.lastCardDanger => 'May let the last card out',
    CoachReason.passKeepsHand => 'Keeps your hand together',
    CoachReason.opponentNearlyOut => 'Someone is nearly out',
  };
  @override
  String get sureWin => 'Sure win';

  @override
  String preset(BigTwoPreset preset) => switch (preset) {
    BigTwoPreset.standard => 'Standard',
    BigTwoPreset.hongKong => 'Hong Kong',
    BigTwoPreset.taiwan => 'Taiwan',
    BigTwoPreset.pusoyDos => 'Pusoy Dos',
  };
  @override
  String get cardsEach => 'Cards each';
  @override
  String get straights => 'Straights';
  @override
  String straightName(StraightRule rule) => switch (rule.name) {
    'hongKong' => 'Hong Kong',
    'taiwan' => 'Taiwan',
    'twoHigh' => 'J-Q-K-A-2',
    _ => 'Standard',
  };
  @override
  String get flushes => 'Flushes';
  @override
  String flushOrder(FlushOrder order) => switch (order) {
    FlushOrder.suitFirst => 'Suit first',
    FlushOrder.rankFirst => 'Rank first',
    FlushOrder.allRanks => 'Like poker',
  };
  @override
  String get bombs => 'Bombs';
  @override
  String get sameFiveType => 'Match 5-card type';
  @override
  String get passLockout => 'Pass locks you out';
  @override
  String get lastCardRule => 'Last-card rule';
  @override
  String get dragonWins => 'Dragon wins';
  @override
  String get noTopTwoFinish => 'No going out on top 2';
  @override
  String get scoring => 'Scoring';
  @override
  String scoringName(BigTwoScoring scoring) => switch (scoring) {
    BigTwoScoring.penalty => 'Penalty',
    BigTwoScoring.pusoyDos => 'Pusoy Dos',
  };
  @override
  String get doubleTwosLeft => 'Double for 2s left';
  @override
  String get doubleBombLeft => 'Double for bombs left';
  @override
  String get customizeSeats => 'Customize seats';
  @override
  String scaledTarget(int points) => 'At this table: to $points';
  @override
  String twosHeld(int n) => '2s: $n+';

  @override
  String get handRanks => 'Hand ranks';
  @override
  String get suitsLowToHigh => 'Suits, low to high';
  @override
  String get ranksLowToHigh => 'Ranks, low to high';
  @override
  String get smallPlays => 'Singles, pairs, triples';
  @override
  String get fiveCardHands => 'Five-card hands, low to high';
  @override
  String kindHint(PlayKind kind) => switch (kind) {
    PlayKind.pass => 'No cards this turn.',
    PlayKind.single => 'Any card. Rank first, then suit.',
    PlayKind.pair => 'Two of a rank. The higher card decides.',
    PlayKind.triple => 'Three of a rank.',
    PlayKind.straight => 'Five ranks in a row, mixed suits.',
    PlayKind.flush => 'Five cards of one suit.',
    PlayKind.fullHouse => 'Three of a rank and a pair. The three decide.',
    PlayKind.fourOfAKind => 'Four of a rank and any card. The four decide.',
    PlayKind.straightFlush => 'Five in a row, all one suit.',
  };
  @override
  String get lowestStraight => 'Lowest straight';
  @override
  String get highestStraight => 'Highest straight';
  @override
  String flushHint(FlushOrder order) => switch (order) {
    FlushOrder.suitFirst => 'Two flushes: the higher suit wins, then the top card.',
    FlushOrder.rankFirst => 'Two flushes: the higher top card wins, then its suit.',
    FlushOrder.allRanks => 'Two flushes: compare cards from the top down, as in poker; suit last.',
  };
  @override
  String get bombsHint => 'Bombs: four of a kind and straight flushes also beat any single, pair or triple.';
  @override
  String get sameTypeHint => 'A five-card hand can only be beaten by a higher one of the same type, or a bomb.';

  @override
  String term(BigTwoTerm term) => switch (term) {
    BigTwoTerm.single => 'Single',
    BigTwoTerm.pair => 'Pair',
    BigTwoTerm.triple => 'Triple',
    BigTwoTerm.fiveCard => 'Five-card hand',
    BigTwoTerm.straight => 'Straight',
    BigTwoTerm.flush => 'Flush',
    BigTwoTerm.fullHouse => 'Full house',
    BigTwoTerm.fourOfAKind => 'Four of a kind',
    BigTwoTerm.straightFlush => 'Straight flush',
    BigTwoTerm.bomb => 'Bomb',
    BigTwoTerm.sameType => sameFiveType,
    BigTwoTerm.pass => 'Pass',
    BigTwoTerm.lead => 'Lead',
    BigTwoTerm.startingCard => 'Starting card',
    BigTwoTerm.suitOrder => 'Suit order',
    BigTwoTerm.lastCard => 'Last-card rule',
    BigTwoTerm.lockout => 'Pass locks you out',
    BigTwoTerm.dragon => 'Dragon',
    BigTwoTerm.topTwo => 'No going out on top 2',
    BigTwoTerm.penalty => 'Penalty scoring',
    BigTwoTerm.pusoyScoring => 'Pusoy Dos scoring',
    BigTwoTerm.doubling => 'Doubling',
    BigTwoTerm.handPlan => 'Hand plan',
    BigTwoTerm.unbeatable => 'Unbeatable',
    BigTwoTerm.cardCounter => 'Card counter',
    BigTwoTerm.match => 'Match',
  };
  @override
  String definition(BigTwoTerm term) => switch (term) {
    BigTwoTerm.single => 'One card. Beaten by a higher card: rank first, then suit.',
    BigTwoTerm.pair => 'Two cards of one rank. The pair with the higher top card wins.',
    BigTwoTerm.triple => 'Three cards of one rank. The higher rank wins.',
    BigTwoTerm.fiveCard =>
      'Straight, flush, full house, four of a kind (plus any card) or straight flush, '
          'from low to high. Only another five-card hand beats one.',
    BigTwoTerm.straight =>
      'Five ranks in a row, not all one suit. Which runs count, and their order, '
          'depend on the rules (Straights in setup).',
    BigTwoTerm.flush =>
      'Five cards of one suit, not in a row. How two flushes compare depends on the '
          'rules (Flushes in setup).',
    BigTwoTerm.fullHouse => 'Three of a rank plus a pair. The rank of the three decides.',
    BigTwoTerm.fourOfAKind => 'Four of a rank plus any fifth card. Four cards alone are not a play.',
    BigTwoTerm.straightFlush => 'Five ranks in a row, all one suit: the highest five-card hand.',
    BigTwoTerm.bomb =>
      'With Bombs on, four of a kind and straight flushes also beat any single, pair or '
          'triple.',
    BigTwoTerm.sameType => sameTypeHint,
    BigTwoTerm.pass =>
      'Play no cards this turn. You may still play on your next turn, unless Pass locks '
          'you out is on.',
    BigTwoTerm.lead =>
      'When everyone else passes, the last player to play starts a new round with any '
          'play.',
    BigTwoTerm.startingCard =>
      'The lowest card dealt (the 3 of diamonds in the standard game). Its holder leads first, '
          'and that first play must include it. Everyone sees it until it is played. With two players, cards are '
          'called from the lowest up until someone holds one, so the other player holds nothing lower.',
    BigTwoTerm.suitOrder =>
      'Suits break ties between equal ranks. Standard: diamonds < clubs < hearts < spades. '
          'Taiwan: clubs < diamonds < hearts < spades. Pusoy Dos: clubs < spades < hearts < diamonds.',
    BigTwoTerm.lastCard =>
      'When the next player has one card left, a single you play must be your '
          'highest card. You may still pass, or play two or more cards.',
    BigTwoTerm.lockout => 'Once you pass, you can\'t play again until a new round starts.',
    BigTwoTerm.dragon =>
      'One card of every rank, 3 to 2, dealt in a 13-card hand. With Dragon wins on, '
          'it wins the deal at once.',
    BigTwoTerm.topTwo =>
      'You can\'t play your last card if it is the highest card (the 2 of spades in the standard '
          'game) played alone.',
    BigTwoTerm.penalty =>
      'Each loser pays 1 point per card left with up to 9 cards, 2 per card with 10 '
          'or more, 3 per card if they never played. The winner gets it all.',
    BigTwoTerm.pusoyScoring => 'Only the winner scores: 1 point, doubled for each 2 in their last play.',
    BigTwoTerm.doubling =>
      'Penalty scoring can double a loser\'s penalty for each 2 still in hand, and '
          'again for a four of a kind or straight flush still in hand.',
    BigTwoTerm.handPlan =>
      'The fewest plays that empty your hand. Each play nobody can beat wins the '
          'lead back; each other play needs a lead of your own.',
    BigTwoTerm.unbeatable =>
      'No cards you haven\'t seen could beat this play, so after it you lead '
          'again.',
    BigTwoTerm.cardCounter =>
      'The 2s, aces and kings you haven\'t seen played, and the highest card '
          'still out.',
    BigTwoTerm.match =>
      'Deals add up until someone reaches the target. Penalty scoring: each loser adds their penalty '
          'and the lowest total wins (usually played to 100). Pusoy Dos scoring: the winner adds their '
          'points and the highest total wins. Scale with players: the target changes with the table, so '
          'a match lasts about as many deals as with four players (about 20).',
  };

  @override
  List<(String, String)> get rulesSections => const [
    ('Goal', 'Be the first to play all your cards.'),
    (
      'Cards',
      'Ranks from low to high: 3 4 5 6 7 8 9 10 J Q K A 2. Suits break ties: in the standard game '
          'diamonds < clubs < hearts < spades, so the 3 of diamonds is the lowest card and the 2 of spades the highest.',
    ),
    (
      'Deal',
      'Four players get 13 cards each. With three, each gets 17 and the last card is dealt face up: the '
          'holder of the lowest card takes it, and everyone knows who has it. With two, each gets 17 (or 13 '
          'or 21) and the rest are not used.',
    ),
    (
      'Start',
      'The player with the lowest card dealt (the 3 of diamonds when all cards are dealt) plays first, '
          'and that play must include it. Everyone sees it until it is played. With two players, cards are called '
          'from the lowest up until someone holds one.',
    ),
    (
      'Plays',
      'A single, a pair, a triple, or a five-card hand: straight, flush, full house, four of a kind '
          '(plus any card) and straight flush, from low to high.',
    ),
    (
      'Turns',
      'Play goes round to the right. Beat the last play with a higher one of the same number of cards, '
          'or pass. When everyone else passes, the last player to play starts a new round with anything.',
    ),
    (
      'Scoring',
      'Penalty: each loser pays 1 point per card left with up to 9 cards, 2 per card with 10 or more, '
          '3 per card if they never played; the winner gets it all. Pusoy Dos: the winner scores 1, '
          'doubled for each 2 in their last play.',
    ),
    (
      'Match',
      'Deals add up until someone reaches the target: with penalties the lowest total wins, '
          'with Pusoy Dos scoring the highest.',
    ),
    (
      'Variants',
      'Hong Kong: A-2-3-4-5 is the highest straight, flushes compare by rank, a dealt dragon wins, and '
          'nobody goes out on a lone 2 of spades. Taiwan: the 3 of clubs starts, bombs beat anything, five-card replies must '
          'match the type led. Pusoy Dos: the 3 of clubs starts, suits clubs < spades < hearts < diamonds, the winner alone scores.',
    ),
  ];

  @override
  String presetTerm(BigTwoPreset preset) => switch (preset) {
    BigTwoPreset.standard => 'Standard rules',
    BigTwoPreset.hongKong => 'Hong Kong rules',
    BigTwoPreset.taiwan => 'Taiwan rules',
    BigTwoPreset.pusoyDos => 'Pusoy Dos rules',
  };
  @override
  String presetIntro(BigTwoPreset preset) => switch (preset) {
    BigTwoPreset.standard => 'Big Two as Pagat gives it.',
    BigTwoPreset.hongKong => 'Choh Dai Di (锄大地), as played in Hong Kong.',
    BigTwoPreset.taiwan => 'Da Lao Er (大老二), as played in Taiwan. Sources disagree on its straights.',
    BigTwoPreset.pusoyDos => 'The Philippine game.',
  };
  @override
  String suitsLine(String suits) => 'Suits: $suits.';
  @override
  String startLine(String card, {required bool mustPlay}) => mustPlay
      ? 'The lowest card dealt starts (the $card when all are dealt) and must be in the first play.'
      : 'Whoever holds the lowest card dealt (the $card when all are dealt) starts, with any play.';
  @override
  String straightsLine(String lowest, String highest) => 'Straights: $lowest lowest, $highest highest.';
  @override
  String get noBombs => 'No bombs.';
  @override
  String get lockoutOn => 'Once you pass, you are out until the next lead.';
  @override
  String get lockoutOff => 'A pass never locks you out.';
  @override
  String get lastCardOn => 'Last-card rule.';
  @override
  String get dragonOn => 'A dealt dragon wins at once.';
  @override
  String topTwoOn(String card) => 'Nobody may go out on a lone $card.';
  @override
  String scoringLine(String name) => 'Scoring: $name.';
  @override
  String straightTerm(StraightRule rule) => switch (rule.name) {
    'hongKong' => 'Hong Kong straights',
    'taiwan' => 'Taiwan straights',
    'twoHigh' => 'J-Q-K-A-2 straights',
    _ => 'Standard straights',
  };
  @override
  String runsLowToHigh(String runs) => 'Low to high: $runs.';
  @override
  String notStraights(String runs) => 'Not straights: $runs.';
  @override
  String straightTie(StraightTieBreak tieBreak, {required String card, required String run}) => switch (tieBreak) {
    StraightTieBreak.sequenceTop => 'Equal straights: the suit of the run\'s top card wins (the $card in $run).',
    StraightTieBreak.highestCard => 'Equal straights: the suit of the highest card wins (the $card in $run).',
  };
  @override
  String flushTerm(FlushOrder order) => switch (order) {
    FlushOrder.suitFirst => 'Flushes: suit first',
    FlushOrder.rankFirst => 'Flushes: rank first',
    FlushOrder.allRanks => 'Flushes: like poker',
  };
  @override
  String usedBy(List<String> presets) => 'Presets: ${presets.join(', ')}.';
  @override
  String get noPreset => 'No preset uses it.';
  @override
  String get byPreset => 'By preset';
  @override
  String get on => 'On';
  @override
  String get off => 'Off';
  @override
  String labelled(String label, String value) => '$label: $value';
  @override
  String source(List<String> names) => '${names.length > 1 ? 'Sources' : 'Source'}: ${names.join('; ')}.';
  @override
  String sourceName(BigTwoSource source) => switch (source) {
    BigTwoSource.pagat => 'Pagat, Big Two',
    BigTwoSource.pagatHongKong => 'Pagat, Big Two (Hong Kong)',
    BigTwoSource.pagatPhilippines => 'Pagat, Big Two (Philippines)',
    BigTwoSource.pagatIndonesia => 'Pagat, Big Two (Indonesia)',
    BigTwoSource.wikipedia => 'Wikipedia, Big two',
    BigTwoSource.zhWikipedia => 'Chinese Wikipedia, 大老二',
    BigTwoSource.charlesworth => 'Charlesworth, arXiv:1808.10442',
    BigTwoSource.denexa => 'Denexa, Big Two',
    BigTwoSource.wikipediaPusoy => 'Wikipedia, Pusoy dos',
  };
  @override
  String get presetsCompared => 'Presets compared';
  @override
  String get sourcesTitle => 'Sources';
}
