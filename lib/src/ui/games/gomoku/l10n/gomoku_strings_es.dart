import '../../../../games/gomoku/gomoku.dart';
import 'gomoku_strings.dart';

/// Gomoku in Spanish.
class GomokuStringsEs extends GomokuStrings {
  const GomokuStringsEs();

  @override
  String get pickLabel => 'Mejor jugada';

  @override
  String get you => 'Jugador';

  @override
  String color(Stone stone) => switch (stone) {
    Stone.black => 'Negras',
    Stone.white => 'Blancas',
  };

  @override
  String get place => 'Colocar';

  @override
  String get pass => 'Pasar';

  @override
  String winsIn(int moves) => 'Gana en $moves';

  @override
  String losesIn(int moves) => 'Pierde en $moves';

  @override
  String reason(MoveReason reason) => switch (reason) {
    MoveReason.makesFive => 'Cinco',
    MoveReason.makesOpenFour => 'Cuatro abierto',
    MoveReason.makesDoubleFour => 'Doble cuatro',
    MoveReason.makesFourThree => 'Cuatro-tres',
    MoveReason.makesFour => 'Cuatro',
    MoveReason.makesDoubleThree => 'Doble tres',
    MoveReason.makesOpenThree => 'Tres abierto',
    MoveReason.blocksFour => 'Bloquea su cuatro',
    MoveReason.blocksOpenThree => 'Bloquea su tres abierto',
    MoveReason.blocksFourThree => 'Ocupa su punto de cuatro-tres',
    MoveReason.blocksDoubleThree => 'Ocupa su punto de doble tres',
    MoveReason.startsForcedWin => 'Victoria forzada',
    MoveReason.missesForcedWin => 'Pierde una victoria forzada',
    MoveReason.allowsForcedWin => 'Permite una victoria forzada',
    MoveReason.ignoresFour => 'Ignora su cuatro',
    MoveReason.ignoresOpenThree => 'Ignora su tres abierto',
    MoveReason.mustPass => 'Hay que pasar',
  };

  @override
  String get rule => 'Regla';

  @override
  String get board => 'Tablero';

  @override
  String get random => 'Al azar';

  @override
  String ruleName(WinRule rule) => switch (rule) {
    WinRule.freestyle => 'Libre',
    WinRule.standard => 'Estándar',
    WinRule.renju => 'Renju',
  };

  @override
  String get threats => 'Amenazas';

  @override
  String figureTitle(GomokuFigure figure) => switch (figure) {
    GomokuFigure.five => 'Cinco',
    GomokuFigure.openFour => 'Cuatro abierto',
    GomokuFigure.four => 'Cuatro',
    GomokuFigure.openThree => 'Tres abierto',
    GomokuFigure.brokenThree => 'Tres roto',
    GomokuFigure.fourThree => 'Cuatro-tres',
    GomokuFigure.doubleThree => 'Doble tres',
    GomokuFigure.doubleFour => 'Doble cuatro',
    GomokuFigure.vcf => 'VCF',
    GomokuFigure.forbiddenThree => 'Prohibida: doble tres',
    GomokuFigure.forbiddenFour => 'Prohibida: doble cuatro',
    GomokuFigure.forbiddenOverline => 'Prohibida: línea larga',
  };

  @override
  String figureCaption(GomokuFigure figure) => switch (figure) {
    GomokuFigure.five => 'Cinco en línea gana.',
    GomokuFigure.openFour => 'Dos formas de hacer cinco (los puntos): no se puede parar.',
    GomokuFigure.four => 'Una forma de hacer cinco (el punto): hay que bloquearla ya.',
    GomokuFigure.openThree => 'Cualquiera de los puntos hace un cuatro abierto: bloquea un extremo ya.',
    GomokuFigure.brokenThree => 'Un tres abierto con un hueco: el punto hace un cuatro abierto.',
    GomokuFigure.fourThree =>
      'Blancas deben bloquear el cuatro en el punto; luego el tres se vuelve un cuatro abierto.',
    GomokuFigure.doubleThree => 'Dos tres abiertos a la vez: Blancas solo pueden bloquear uno.',
    GomokuFigure.doubleFour => 'Dos cuatros a la vez (los puntos): Blancas solo pueden bloquear uno.',
    GomokuFigure.vcf =>
      'Negras ganan solo con cuatros: cada uno obliga a responder a Blancas (2, 4, 6) hasta que 7 hace cinco.',
    GomokuFigure.forbiddenThree => 'Renju: Negras no pueden jugar en × (dos tres abiertos).',
    GomokuFigure.forbiddenFour => 'Renju: Negras no pueden jugar en × (dos cuatros).',
    GomokuFigure.forbiddenOverline => 'Renju: Negras no pueden jugar en × (seis en línea).',
  };

  @override
  String term(GomokuTerm term) => switch (term) {
    GomokuTerm.bestMove => 'Mejor jugada',
    GomokuTerm.provenWin => 'Gana en N',
    GomokuTerm.five => 'Cinco',
    GomokuTerm.openFour => 'Cuatro abierto',
    GomokuTerm.four => 'Cuatro',
    GomokuTerm.openThree => 'Tres abierto',
    GomokuTerm.brokenThree => 'Tres roto',
    GomokuTerm.fourThree => 'Cuatro-tres',
    GomokuTerm.doubleThree => 'Doble tres',
    GomokuTerm.doubleFour => 'Doble cuatro',
    GomokuTerm.vcf => 'VCF',
    GomokuTerm.overline => 'Línea larga',
    GomokuTerm.forbiddenMove => 'Jugada prohibida',
    GomokuTerm.freestyle => 'Libre',
    GomokuTerm.standard => 'Estándar',
    GomokuTerm.renju => 'Renju',
    GomokuTerm.firstMove => 'Ventaja de negras',
  };

  @override
  String definition(GomokuTerm term) => switch (term) {
    GomokuTerm.bestMove => 'La elección del coach: la jugada que valora más. Una victoria demostrada va siempre primero. En el tablero, sus mejores jugadas llevan número.',
    GomokuTerm.provenWin => 'El coach ha demostrado una victoria forzada: cinco en N de tus jugadas, haga lo que haga el rival. «Pierde en N»: el rival tiene una.',
    GomokuTerm.five => 'Cinco piedras en línea, en horizontal, vertical o diagonal: victoria.',
    GomokuTerm.openFour => 'Cuatro en línea con los dos extremos libres. No se puede parar: luego viene el cinco.',
    GomokuTerm.four => 'Cuatro piedras que hacen cinco con una jugada más. El rival debe bloquear ese punto ya.',
    GomokuTerm.openThree => 'Tres en línea que puede volverse un cuatro abierto. Hay que responder, o gana.',
    GomokuTerm.brokenThree => 'Un tres abierto con un hueco. Llenar el hueco hace un cuatro abierto.',
    GomokuTerm.fourThree => 'Una jugada que hace un cuatro y un tres abierto. Al bloquear el cuatro, el tres se vuelve un cuatro abierto: victoria.',
    GomokuTerm.doubleThree => 'Una jugada que hace dos tres abiertos. Prohibida para Negras en Renju.',
    GomokuTerm.doubleFour =>
      'Una jugada que hace dos cuatros: solo se puede bloquear uno. Prohibida para Negras en Renju.',
    GomokuTerm.vcf =>
      'Victoria por cuatros continuos: una victoria hecha solo de cuatros, cada uno obliga a bloquear, hasta el cinco.',
    GomokuTerm.overline => 'Seis o más en línea. Gana en Libre, pero no en Estándar, ni para Negras en Renju.',
    GomokuTerm.forbiddenMove => 'Renju: un punto donde Negras harían un doble tres, un doble cuatro o una línea larga. Negras no pueden jugar ahí, salvo que hagan cinco. Marcado ×.',
    GomokuTerm.freestyle => 'Cinco o más en línea gana, para los dos jugadores.',
    GomokuTerm.standard => 'Gana exactamente cinco en línea. Una línea larga no gana y la partida sigue.',
    GomokuTerm.renju => 'Las reglas de torneo: Negras tienen jugadas prohibidas y necesitan exactamente cinco; Blancas ganan con cinco o más.',
    GomokuTerm.firstMove => 'Negras juegan primero, una gran ventaja: en Libre, con juego perfecto siempre ganan Negras. Blancas es el lado difícil. Las jugadas prohibidas de Renju la reducen, pero Negras siguen con ventaja.',
  };

  @override
  List<(String, String)> get rulesSections => const [
    (
      'La partida',
      'Dos jugadores colocan por turnos una piedra en un punto libre; empiezan Negras. '
          'Las piedras nunca se mueven ni se capturan.',
    ),
    ('Ganar', 'Gana el primero que pone cinco en línea, en horizontal, vertical o diagonal.'),
    ('Libre', 'Cinco o más en línea gana.'),
    ('Estándar', 'Gana exactamente cinco. Seis o más en línea (línea larga) no gana y la partida sigue.'),
    (
      'Renju',
      'Negras necesitan exactamente cinco y no pueden hacer un doble tres, un doble cuatro ni una línea larga: '
          'esos puntos están prohibidos (×), salvo que la jugada haga cinco. Blancas no tienen jugadas prohibidas '
          'y ganan con cinco o más. Si todos los puntos libres están prohibidos, Negras deben pasar.',
    ),
    ('Empate', 'Si el tablero se llena sin cinco, es empate.'),
    ('Coordenadas', 'Las columnas son letras desde la izquierda y las filas números desde abajo: h8 es el centro.'),
  ];
}
