import '../../../../games/blackjack/app/blackjack_grading.dart';
import '../../../../games/blackjack/blackjack.dart';
import 'blackjack_strings.dart';

/// Blackjack in English, in blackjack players' own words.
class BlackjackStringsEn extends BlackjackStrings {
  const BlackjackStringsEn();

  @override
  String get pickLabel => 'Basic strategy';

  @override
  String? tagLabel(String tag) => tag == 'count' ? 'Count' : null;

  @override
  String get dealer => 'Dealer';
  @override
  String get dealerSeat => 'Dealer';

  @override
  String action(BlackjackAction action) => switch (action) {
    BlackjackAction.hit => 'Hit',
    BlackjackAction.stand => 'Stand',
    BlackjackAction.double => 'Double',
    BlackjackAction.split => 'Split',
    BlackjackAction.surrender => 'Surrender',
    BlackjackAction.insurance => 'Insurance',
    BlackjackAction.noInsurance => 'No insurance',
    BlackjackAction.keepPlaying => 'Keep playing',
  };

  @override
  String get evenMoney => 'Even money';
  @override
  String softTotal(int total) => 'Soft $total';
  @override
  String get bust => 'Bust';
  @override
  String get blackjackHand => 'Blackjack';
  @override
  String totalsFromTo(int low, int high) => '$low–$high';
  @override
  String totalOrLess(int total) => '$total or less';

  @override
  String outcome(HandOutcome outcome) => switch (outcome) {
    HandOutcome.pending => 'Playing',
    HandOutcome.blackjack => 'Blackjack',
    HandOutcome.win => 'Win',
    HandOutcome.push => 'Push',
    HandOutcome.lose => 'Lose',
    HandOutcome.bust => 'Bust',
    HandOutcome.dealerBlackjack => 'Dealer blackjack',
    HandOutcome.surrender => 'Surrender',
  };

  @override
  String get insured => 'Insured';
  @override
  String get countToggle => 'Count';
  @override
  String runningCount(String count) => 'Count $count';
  @override
  String trueCount(String count) => 'True $count';
  @override
  String cardsLeft(int cards) => '$cards left';
  @override
  String round(int n) => 'Round $n';

  @override
  String get presetLabel => 'Table';
  @override
  String preset(BlackjackPreset preset) => switch (preset) {
    BlackjackPreset.standard => 'Standard',
    BlackjackPreset.vegasStrip => 'Vegas Strip',
    BlackjackPreset.downtown => 'Downtown',
    BlackjackPreset.atlanticCity => 'Atlantic City',
    BlackjackPreset.european => 'European',
    BlackjackPreset.singleDeck => 'Single deck',
  };
  @override
  String get decks => 'Decks';
  @override
  String get dealerHitsSoft17 => 'Dealer hits soft 17';
  @override
  String get blackjackPays => 'Blackjack pays';
  @override
  String get doubleLabel => 'Double';
  @override
  String doubleRule(DoubleRule rule) => switch (rule) {
    DoubleRule.anyTwo => 'Any two',
    DoubleRule.nineToEleven => '9–11',
    DoubleRule.tenToEleven => '10–11',
  };
  @override
  String get doubleAfterSplit => 'Double after split';
  @override
  String get surrenderLabel => 'Surrender';
  @override
  String surrenderRule(Surrender rule) => switch (rule) {
    Surrender.none => 'No',
    Surrender.late => 'Late',
    Surrender.early => 'Early',
  };
  @override
  String get holeCard => 'Hole card';
  @override
  String get noHoleCardLossLabel => 'Dealer blackjack';
  @override
  String noHoleCardLoss(NoHoleCardLoss rule) => switch (rule) {
    NoHoleCardLoss.allBets => 'All bets',
    NoHoleCardLoss.originalBetsOnly => 'Original bet',
  };
  @override
  String get resplitAces => 'Resplit aces';
  @override
  String get continuousShuffle => 'Continuous shuffle';
  @override
  String get penetration => 'Penetration';
  @override
  String coachMode(CoachMode mode) => switch (mode) {
    CoachMode.fresh => 'Fresh shoe',
    CoachMode.seen => 'Cards seen',
  };

  @override
  String get hardTotals => 'Hard totals';
  @override
  String get softTotals => 'Soft totals';
  @override
  String get pairs => 'Pairs';
  @override
  String get dealerShows => 'Dealer';
  @override
  String chartLetter(ChartCode code) => switch (code) {
    ChartCode.hit => 'H',
    ChartCode.stand => 'S',
    ChartCode.doubleOrHit => 'D',
    ChartCode.doubleOrStand => 'Ds',
    ChartCode.split => 'P',
    ChartCode.surrenderOrHit => 'Rh',
    ChartCode.surrenderOrStand => 'Rs',
    ChartCode.surrenderOrSplit => 'Rp',
  };
  @override
  String chartMeaning(ChartCode code) => switch (code) {
    ChartCode.hit => 'Hit',
    ChartCode.stand => 'Stand',
    ChartCode.doubleOrHit => 'Double, else hit',
    ChartCode.doubleOrStand => 'Double, else stand',
    ChartCode.split => 'Split',
    ChartCode.surrenderOrHit => 'Surrender, else hit',
    ChartCode.surrenderOrStand => 'Surrender, else stand',
    ChartCode.surrenderOrSplit => 'Surrender, else split',
  };
  @override
  String get chartFailed => 'The chart could not be made.';

  @override
  String reason(CoachReason r) {
    final up = BlackjackStrings.upcard(r.upcard);
    final hand = r.soft ? 'Soft ${r.total}' : '${r.total}';
    final pct = BlackjackStrings.percent(r.chance ?? 0);
    final play = r.action == null ? '' : action(r.action!);
    final chart = r.basicAction == null ? '' : action(r.basicAction!);
    return switch (r.kind) {
      ReasonKind.standMadeHand => '17 or more: stand',
      ReasonKind.cantBust => '11 or less: can\'t bust',
      ReasonKind.dealerBustsOften => 'Dealer\'s $up busts often',
      ReasonKind.dealerStrong => 'Dealer\'s $up usually makes 17+',
      ReasonKind.doubleStrong => '$hand vs $up: double',
      ReasonKind.doubleSoft => '$hand vs $up: double',
      ReasonKind.splitAces => 'Always split aces',
      ReasonKind.splitEights => 'Always split eights',
      ReasonKind.neverSplitTens => 'Never split tens',
      ReasonKind.neverSplitFives => 'Never split fives',
      ReasonKind.splitVsWeak => 'Split against a weak $up',
      ReasonKind.noSplitVsStrong => 'Don\'t split against a $up',
      ReasonKind.surrenderSaves => 'Wins too rarely: surrender',
      ReasonKind.softCantBust => 'Soft hand: can\'t bust',
      ReasonKind.softStand => 'Good soft total: stand',
      ReasonKind.insuranceBad => 'Tens $pct: insurance loses',
      ReasonKind.insuranceGood => 'Tens $pct: insurance pays',
      ReasonKind.countDeviation =>
        'True ${BlackjackStrings.signed(r.trueCount ?? 0, decimals: 1)}: $play (chart: $chart)',
      ReasonKind.exactCardsPlay => 'These cards: $play (chart: $chart)',
      ReasonKind.bustRisk => 'Busts $pct of the time',
      ReasonKind.tooRisky => 'Too risky against a $up',
      ReasonKind.dealerBustsLess => 'Dealer\'s $up busts less than you\'d think',
      ReasonKind.betterPlay => '$play is better',
    };
  }

  @override
  String term(BlackjackTerm term) => switch (term) {
    BlackjackTerm.blackjack => 'Blackjack',
    BlackjackTerm.hit => 'Hit',
    BlackjackTerm.stand => 'Stand',
    BlackjackTerm.double => 'Double',
    BlackjackTerm.split => 'Split',
    BlackjackTerm.surrender => 'Surrender',
    BlackjackTerm.insurance => 'Insurance',
    BlackjackTerm.evenMoney => 'Even money',
    BlackjackTerm.soft => 'Soft hand',
    BlackjackTerm.bust => 'Bust',
    BlackjackTerm.push => 'Push',
    BlackjackTerm.holeCard => 'Hole card',
    BlackjackTerm.dealerStart => "Dealer's two cards",
    BlackjackTerm.noHoleCardLoss => 'Dealer blackjack',
    BlackjackTerm.soft17 => 'Soft 17',
    BlackjackTerm.doubleAfterSplit => 'Double after split',
    BlackjackTerm.resplitAces => 'Resplit aces',
    BlackjackTerm.shoe => 'Shoe',
    BlackjackTerm.penetration => 'Penetration',
    BlackjackTerm.continuousShuffle => 'Continuous shuffle',
    BlackjackTerm.basicStrategy => 'Basic strategy',
    BlackjackTerm.runningCount => 'Running count',
    BlackjackTerm.trueCount => 'True count',
    BlackjackTerm.freshShoe => 'Fresh shoe',
    BlackjackTerm.cardsSeen => 'Cards seen',
    BlackjackTerm.bets => 'Bets',
  };

  @override
  String definition(BlackjackTerm term) => switch (term) {
    BlackjackTerm.blackjack => 'An ace and a ten-value card as your first two cards. It pays 3 to 2 (6 to 5 at some tables) unless the dealer has one too.',
    BlackjackTerm.hit => 'Take one more card.',
    BlackjackTerm.stand => 'Keep your hand as it is; the next hand or the dealer plays.',
    BlackjackTerm.double => 'Double your bet and take exactly one more card.',
    BlackjackTerm.split =>
      'Turn a pair into two hands, each with its own bet. Each hand gets a second card and is played on its own.',
    BlackjackTerm.surrender => 'Give up the hand and get half your bet back. Late surrender comes after the dealer checks for blackjack, early surrender before.',
    BlackjackTerm.insurance => 'A side bet of half your bet when the dealer shows an ace. It pays 2 to 1 if the dealer has blackjack. It only pays off when more than a third of the cards left are tens.',
    BlackjackTerm.evenMoney =>
      'Insurance on your own blackjack at a 3:2 table: you are paid 1 to 1 whatever the dealer has.',
    BlackjackTerm.soft =>
      'A hand with an ace counted as 11, like A-6 (soft 17). One more card can\'t bust it: the ace goes back to 1.',
    BlackjackTerm.bust => 'Over 21. The hand loses at once, even if the dealer busts later.',
    BlackjackTerm.push => 'A tie with the dealer: your bet comes back.',
    BlackjackTerm.holeCard => 'The dealer\'s face-down card. With a ten or an ace showing, the dealer checks it for blackjack before you play. Without a hole card (European tables) the dealer\'s second card comes after you play.',
    BlackjackTerm.dealerStart => "What the dealer's upcard and hole card add up to. 17–21: the dealer stands (a soft 17 draws at tables where the dealer hits it). 12–16: the dealer must draw, and a hard total can bust. 11 or less: the dealer draws and can't bust on the next card. In Training, tap the dealer to see the chances, worked out from the cards you have seen.",
    BlackjackTerm.noHoleCardLoss => 'Without a hole card the dealer can turn up blackjack after you have doubled or split. Most tables then take every bet (All bets); some take only your original bet (Original bet), which makes doubling and splitting against a ten or an ace safer.',
    BlackjackTerm.soft17 => 'A 17 with an ace counted as 11. Some tables make the dealer hit it, which costs the player about 0.2% of each bet.',
    BlackjackTerm.doubleAfterSplit => 'You may double on the hands a split makes.',
    BlackjackTerm.resplitAces => 'If a split ace draws another ace, you may split again.',
    BlackjackTerm.shoe => 'The box the cards are dealt from: 1 to 8 decks shuffled together.',
    BlackjackTerm.penetration => 'How much of the shoe is dealt before the cut card comes out and the cards are shuffled. Here a shoe is one game.',
    BlackjackTerm.continuousShuffle =>
      'A machine puts the cards back after every round, so remembering cards gains nothing. A game is 50 rounds.',
    BlackjackTerm.basicStrategy => 'The best play for each total against each dealer card, for the table\'s rules, assuming a full shoe. It is the coach\'s pick and the chart in the guides.',
    BlackjackTerm.runningCount => 'Card counting (Hi-Lo): +1 for each 2 to 6 seen, −1 for each ten or ace. A high count means the cards left are rich in tens and aces, which helps you.',
    BlackjackTerm.trueCount => 'The running count divided by the decks left: the count that changes plays.',
    BlackjackTerm.freshShoe =>
      'The coach assumes a full shoe minus this round\'s cards: basic strategy. You are graded on the chart.',
    BlackjackTerm.cardsSeen => 'The coach uses every card seen since the shuffle, as a perfect counter would. Its best play is tagged Count when it differs from the chart, and you are graded on it.',
    BlackjackTerm.bets => 'The coach\'s numbers: what each play wins or loses on average, in bets. −0.05 means losing 5% of the bet in the long run.',
  };

  @override
  List<(String, String)> get rulesSections => const [
    (
      'Goal',
      'Beat the dealer: finish closer to 21 than the dealer without going over. You play alone against the dealer and bet 1 each round.',
    ),
    (
      'Card values',
      '2 to 10 count their number, J, Q and K count 10, and an ace counts 11 or 1. A hand with an ace counted as 11 is soft.',
    ),
    (
      'The deal',
      'You and the dealer get two cards each; one dealer card is face down (the hole card). With a ten or an ace showing, the dealer checks it for blackjack before you play. Without a hole card, the dealer\'s second card comes after you play.',
    ),
    (
      'Your choices',
      'Hit: take a card. Stand: keep your hand. Double: double the bet and take exactly one card. Split: a pair becomes two hands, each with its own bet. Surrender: give up the hand and get half the bet back, where the table allows it.',
    ),
    (
      'Insurance',
      'When the dealer shows an ace you may buy insurance for half your bet; it pays 2 to 1 if the dealer has blackjack. With your own blackjack at a 3:2 table it is even money: paid 1 to 1 whatever happens.',
    ),
    (
      'The dealer',
      'The dealer draws to 16 and stands on 17. At tables where the dealer hits soft 17, the dealer also draws to a soft 17.',
    ),
    (
      'Payouts',
      'A win pays 1 to 1. A blackjack pays 3 to 2 (6 to 5 at some tables). A tie is a push and the bet comes back. A hand over 21 loses at once.',
    ),
    (
      'The shoe',
      'The cards come from a shoe of 1 to 8 decks. When the cut card comes out the shoe ends: that is one game. With a continuous shuffler, a game is 50 rounds.',
    ),
  ];
}
