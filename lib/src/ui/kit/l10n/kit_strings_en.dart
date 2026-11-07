import 'kit_strings.dart';

class KitStringsEn extends KitStrings {
  const KitStringsEn();

  @override
  String get trainingMode => 'Training';
  @override
  String get lastGame => 'Last game';
  @override
  String get thinkLonger => 'Think longer';
  @override
  String get yourTurn => 'Your turn';
  @override
  String get youWin => 'You win';
  @override
  String get youLose => 'You lose';
  @override
  String get draw => 'Draw';
  @override
  String wins(String name) => '$name wins';
  @override
  String get nextDeal => 'Next deal';
  @override
  String get deal => 'Deal';
  @override
  String get newShoe => 'New shoe';
  @override
  String get level => 'Level';
  @override
  String kitLevel(KitLevel level) => switch (level) {
        KitLevel.easy => 'Easy',
        KitLevel.medium => 'Medium',
        KitLevel.hard => 'Hard',
      };
  @override
  String get bots => 'Bots';
  @override
  String get custom => 'Custom';
  @override
  String get coach => 'Coach';
  @override
  String winChance(String pct) => 'Win $pct';
  @override
  String pointsValue(String x) => '$x pts';
  @override
  String betsValue(String x) => '$x bets';
  @override
  String net(String x) => 'Net $x';
  @override
  String moveNumber(int n) => 'Move $n';
  @override
  String get pass => 'Pass';
  @override
  String trick(int n) => 'Trick $n';
  @override
  String get allCards => 'All cards';
  @override
  String handOrder(HandOrder order) => switch (order) {
        HandOrder.rank => 'Rank',
        HandOrder.suit => 'Suit',
        HandOrder.own => 'Sort',
      };
  @override
  String get showCards => 'Show cards';
  @override
  String get visibleToAll => 'Everyone can see this card';
  @override
  String rangeTitle(String name, int cards) => '$name · $cards ${cards == 1 ? 'card' : 'cards'}';
  @override
  String get rangeRanks => 'Cards they may hold';
  @override
  String get rangeCombos => 'Combos they may make';
  @override
  String get rangeWorking => 'Working it out…';
  @override
  String get rangeFailed => "Couldn't work it out. Tap the seat again.";
  @override
  String get rangeNone => 'No range to work out now.';
  @override
  String rangeSamples(int n) => 'From $n possible deals, using only what you have seen.';
  @override
  String get playTo => 'Play to';
  @override
  String get noLimit => 'No limit';
  @override
  String get scaleWithPlayers => 'Scale with players';
  @override
  String get scores => 'Scores';
  @override
  String get total => 'Total';
  @override
  String get newMatch => 'New match';
  @override
  String dealNumber(int n) => 'Deal $n';
  @override
  String target(int points) => 'To $points';
  @override
  String get youWinMatch => 'You win the match';
  @override
  String winsMatch(String name) => '$name wins the match';
  @override
  String matchTie(List<String> names) => 'Tie: ${names.join(' and ')}';
  @override
  String term(KitTerm term) => switch (term) {
        KitTerm.training => 'Training',
        KitTerm.freePlay => 'Free Play',
        KitTerm.coach => 'Coach',
        KitTerm.grades => 'Grades',
        KitTerm.score => 'Score',
        KitTerm.level => 'Level',
        KitTerm.lastGame => 'Last game',
        KitTerm.showCards => 'Show cards',
        KitTerm.range => 'Range',
        KitTerm.playTo => 'Play to',
      };
  @override
  String definition(KitTerm term) => switch (term) {
        KitTerm.training => 'Each of your moves is graded against the coach, with a score. Chosen before the game.',
        KitTerm.freePlay => 'Play without grades or coach. Chosen before the game.',
        KitTerm.coach => 'Shows the best moves where you are and what each is worth. '
            'Its button at the top shows or hides it.',
        KitTerm.grades => 'Best, Good, Inaccuracy, Mistake, Blunder: how much a move gave up '
            "compared with the coach's best.",
        KitTerm.score => 'From 0 to 100 for each graded move: 100 when it gives up nothing. '
            'The panel shows your average.',
        KitTerm.level => 'How well the bots play.',
        KitTerm.lastGame => 'Your most recent game, saved after every move, to look back through move by move.',
        KitTerm.showCards => "Training only: the opponents' cards face up, to learn from. "
            "The coach and your grades never use them. It's in the menu.",
        KitTerm.range => 'What an opponent could hold, from what you have seen: the chance of each card '
            '(1+, 2+, 3+ or all 4 of a rank) and of each combo. Tap their seat to see it.',
        KitTerm.playTo => 'A match is deal after deal, the points adding up, until someone reaches this total. '
            'Scale with players raises it at a bigger table (and lowers it at a smaller one), '
            "so the match isn't over sooner with more players.",
      };
}
