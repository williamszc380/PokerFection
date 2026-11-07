import '../../../../games/gomoku/gomoku.dart';
import 'gomoku_strings.dart';

/// Gomoku in English.
class GomokuStringsEn extends GomokuStrings {
  const GomokuStringsEn();

  @override
  String get pickLabel => 'Best move';

  @override
  String get you => 'Player';

  @override
  String color(Stone stone) => switch (stone) {
    Stone.black => 'Black',
    Stone.white => 'White',
  };

  @override
  String get place => 'Place';

  @override
  String get pass => 'Pass';

  @override
  String winsIn(int moves) => 'Wins in $moves';

  @override
  String losesIn(int moves) => 'Loses in $moves';

  @override
  String reason(MoveReason reason) => switch (reason) {
    MoveReason.makesFive => 'Five',
    MoveReason.makesOpenFour => 'Open four',
    MoveReason.makesDoubleFour => 'Double four',
    MoveReason.makesFourThree => 'Four-three',
    MoveReason.makesFour => 'Four',
    MoveReason.makesDoubleThree => 'Double three',
    MoveReason.makesOpenThree => 'Open three',
    MoveReason.blocksFour => 'Blocks their four',
    MoveReason.blocksOpenThree => 'Blocks their open three',
    MoveReason.blocksFourThree => 'Takes their four-three point',
    MoveReason.blocksDoubleThree => 'Takes their double-three point',
    MoveReason.startsForcedWin => 'Forced win',
    MoveReason.missesForcedWin => 'Misses a forced win',
    MoveReason.allowsForcedWin => 'Allows a forced win',
    MoveReason.ignoresFour => 'Ignores their four',
    MoveReason.ignoresOpenThree => 'Ignores their open three',
    MoveReason.mustPass => 'Must pass',
  };

  @override
  String get rule => 'Rule';

  @override
  String get board => 'Board';

  @override
  String get random => 'Random';

  @override
  String ruleName(WinRule rule) => switch (rule) {
    WinRule.freestyle => 'Freestyle',
    WinRule.standard => 'Standard',
    WinRule.renju => 'Renju',
  };

  @override
  String get threats => 'Threats';

  @override
  String figureTitle(GomokuFigure figure) => switch (figure) {
    GomokuFigure.five => 'Five',
    GomokuFigure.openFour => 'Open four',
    GomokuFigure.four => 'Four',
    GomokuFigure.openThree => 'Open three',
    GomokuFigure.brokenThree => 'Broken three',
    GomokuFigure.fourThree => 'Four-three',
    GomokuFigure.doubleThree => 'Double three',
    GomokuFigure.doubleFour => 'Double four',
    GomokuFigure.vcf => 'VCF',
    GomokuFigure.forbiddenThree => 'Forbidden: double three',
    GomokuFigure.forbiddenFour => 'Forbidden: double four',
    GomokuFigure.forbiddenOverline => 'Forbidden: overline',
  };

  @override
  String figureCaption(GomokuFigure figure) => switch (figure) {
    GomokuFigure.five => 'Five in a row wins.',
    GomokuFigure.openFour => 'Two ways to make five (the dots): it can\'t be stopped.',
    GomokuFigure.four => 'One way to make five (the dot): it must be blocked at once.',
    GomokuFigure.openThree => 'Either dot makes an open four: block one end now.',
    GomokuFigure.brokenThree => 'An open three with a gap: the dot makes an open four.',
    GomokuFigure.fourThree => 'White must block the four at the dot; then the three becomes an open four.',
    GomokuFigure.doubleThree => 'Two open threes at once: White can block only one.',
    GomokuFigure.doubleFour => 'Two fours at once (the dots): White can block only one.',
    GomokuFigure.vcf => 'Black wins with fours only: each forces White\'s reply (2, 4, 6) until 7 makes five.',
    GomokuFigure.forbiddenThree => 'Renju: Black may not play × (two open threes).',
    GomokuFigure.forbiddenFour => 'Renju: Black may not play × (two fours).',
    GomokuFigure.forbiddenOverline => 'Renju: Black may not play × (six in a row).',
  };

  @override
  String term(GomokuTerm term) => switch (term) {
    GomokuTerm.bestMove => 'Best move',
    GomokuTerm.provenWin => 'Wins in N',
    GomokuTerm.five => 'Five',
    GomokuTerm.openFour => 'Open four',
    GomokuTerm.four => 'Four',
    GomokuTerm.openThree => 'Open three',
    GomokuTerm.brokenThree => 'Broken three',
    GomokuTerm.fourThree => 'Four-three',
    GomokuTerm.doubleThree => 'Double three',
    GomokuTerm.doubleFour => 'Double four',
    GomokuTerm.vcf => 'VCF',
    GomokuTerm.overline => 'Overline',
    GomokuTerm.forbiddenMove => 'Forbidden move',
    GomokuTerm.freestyle => 'Freestyle',
    GomokuTerm.standard => 'Standard',
    GomokuTerm.renju => 'Renju',
    GomokuTerm.firstMove => 'Black\'s edge',
  };

  @override
  String definition(GomokuTerm term) => switch (term) {
    GomokuTerm.bestMove => 'The coach\'s pick: the move it rates highest. A proven win always comes first. On the board, the coach\'s top moves are numbered.',
    GomokuTerm.provenWin => 'The coach has proven a forced win: five within N of your moves, whatever the opponent does. "Loses in N": the opponent has one.',
    GomokuTerm.five => 'Five stones in a row, across, down or diagonally: a win.',
    GomokuTerm.openFour => 'Four in a row with both ends free. It can\'t be stopped: five comes next.',
    GomokuTerm.four => 'Four stones that make five with one more move. The opponent must block that point at once.',
    GomokuTerm.openThree => 'Three in a row that can become an open four. It must be answered, or it wins.',
    GomokuTerm.brokenThree => 'An open three with a gap in it. Filling the gap makes an open four.',
    GomokuTerm.fourThree =>
      'One move that makes a four and an open three. Blocking the four leaves the three to become an open four: a win.',
    GomokuTerm.doubleThree => 'One move that makes two open threes. Forbidden for Black in Renju.',
    GomokuTerm.doubleFour => 'One move that makes two fours: only one can be blocked. Forbidden for Black in Renju.',
    GomokuTerm.vcf => 'Victory by continuous fours: a win made of fours only, each forcing a block, until five.',
    GomokuTerm.overline => 'Six or more in a row. It wins in Freestyle, but not in Standard, nor for Black in Renju.',
    GomokuTerm.forbiddenMove => 'Renju: a point where Black would make a double three, a double four or an overline. Black can\'t play there, unless it makes five. Marked ×.',
    GomokuTerm.freestyle => 'Five or more in a row wins, for both players.',
    GomokuTerm.standard => 'Exactly five in a row wins. An overline doesn\'t, and the game goes on.',
    GomokuTerm.renju =>
      'The tournament rules: Black has forbidden moves and needs exactly five; White wins with five or more.',
    GomokuTerm.firstMove => 'Black moves first, a big edge: in Freestyle, perfect play always wins for Black. White is the harder side. Renju\'s forbidden moves cut it, but Black still has the edge.',
  };

  @override
  List<(String, String)> get rulesSections => const [
    (
      'The game',
      'Two players take turns placing a stone on an empty point, Black first. '
          'Stones never move and are never taken.',
    ),
    ('Winning', 'The first to get five in a row, across, down or diagonally, wins.'),
    ('Freestyle', 'Five or more in a row wins.'),
    ('Standard', 'Exactly five wins. Six or more in a row (an overline) doesn\'t win, and the game goes on.'),
    (
      'Renju',
      'Black needs exactly five and may not make a double three, a double four or an overline: '
          'those points are forbidden (×), unless the move makes five. White has no forbidden moves '
          'and wins with five or more. If every free point is forbidden, Black must pass.',
    ),
    ('Draw', 'A full board with no five is a draw.'),
    ('Coordinates', 'Columns are letters from the left, rows numbers from the bottom: h8 is the center.'),
  ];
}
