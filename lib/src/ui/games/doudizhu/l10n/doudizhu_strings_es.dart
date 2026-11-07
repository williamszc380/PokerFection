import '../../../../games/doudizhu/doudizhu.dart';
import 'doudizhu_strings.dart';

/// Fight the Landlord in Spanish ("El terrateniente", as Spanish guides
/// translate 斗地主; plays named as in the Spanish card-game words).
class LandlordStringsEs extends LandlordStrings {
  const LandlordStringsEs();

  @override
  String get pickLabel => 'GTO';

  @override
  String get landlord => 'Terrateniente';
  @override
  String get peasant => 'Campesino';
  @override
  String get kitty => 'Monte';
  @override
  String get cantBeat => 'No puedo';
  @override
  String get everyonePassed => 'Todos pasan';
  @override
  String firstToBid(String name, BiddingStyle style) =>
      style == BiddingStyle.callRob ? '$name pide primero' : '$name puja primero';
  @override
  String get spring => 'Primavera';
  @override
  String get antiSpring => 'Primavera inversa';
  @override
  String cardsLeft(int n) => n == 1 ? '1 carta' : '$n cartas';

  @override
  String get play => 'Jugar';
  @override
  String get pass => 'Paso';
  @override
  String get clear => 'Borrar';
  @override
  String get noBid => 'No pujo';
  @override
  String bid(int points) => 'Puja $points';
  @override
  String get call => 'Pedir';
  @override
  String get noCall => 'No pedir';
  @override
  String get rob => 'Robar';
  @override
  String get noRob => 'No robar';

  @override
  String kind(PlayType type) => switch (type) {
    PlayType.solo => 'Carta suelta',
    PlayType.pair => 'Pareja',
    PlayType.trio => 'Trío',
    PlayType.trioSolo => 'Trío + 1',
    PlayType.trioPair => 'Trío + pareja',
    PlayType.straight => 'Escalera',
    PlayType.pairStraight => 'Escalera de parejas',
    PlayType.airplane => 'Avión',
    PlayType.airplaneSolos => 'Avión + cartas',
    PlayType.airplanePairs => 'Avión + parejas',
    PlayType.fourTwoSolos => 'Cuatro + 2',
    PlayType.fourTwoPairs => 'Cuatro + 2 parejas',
    PlayType.bomb => 'Bomba',
    PlayType.rocket => 'Cohete',
  };

  @override
  String joker({required bool big}) => big ? 'Comodín grande' : 'Comodín chico';

  @override
  String jokerShort({required bool big}) => big ? 'CG' : 'CC';

  @override
  String rangeKind(String kind) => switch (kind) {
    'pair' => 'Parejas',
    'trio' => 'Tríos',
    'straight' => 'Escaleras',
    'pairs' => 'Escaleras de parejas',
    'airplane' => 'Aviones',
    'bomb' => 'Bombas',
    'rocket' => 'Cohete',
    _ => kind,
  };

  @override
  String rangeKindInfo(String kind) => switch (kind) {
    'pair' => 'Dos cartas del mismo valor. Una bomba también se puede partir en parejas.',
    'trio' => 'Tres cartas del mismo valor, solas o con una carta o una pareja.',
    'straight' => '5 o más valores seguidos, del 3 al A. Se muestran por sus 5 primeras cartas.',
    'pairs' => '3 o más parejas seguidas, del 3 al A. Se muestran por sus 3 primeras parejas.',
    'airplane' => '2 o más tríos seguidos, del 3 al A. Se muestran por sus 2 primeros tríos.',
    'bomb' => 'Cuatro iguales. Gana a cualquier otra jugada y dobla la apuesta.',
    'rocket' => 'Los dos comodines (CC y CG). Gana a todo y dobla la apuesta.',
    _ => kind,
  };

  @override
  String reason(DdzReason reason) => switch (reason) {
    DdzReason.goesOut => 'Te quedas sin cartas',
    DdzReason.finishesNext => 'Terminas en el próximo turno',
    DdzReason.partnerWinning => 'Tu compañero gana la baza',
    DdzReason.keepsBomb => 'Guardas tu bomba',
    DdzReason.breaksBomb => 'Rompes tu bomba',
    DdzReason.usesBomb => 'Bomba: dobla la apuesta',
    DdzReason.usesRocket => 'Cohete: dobla la apuesta',
    DdzReason.leadsSmallForPartner => 'Sales baja para tu compañero',
    DdzReason.opponentsCantBeat => 'Nadie la supera',
    DdzReason.keepsHighCards => 'Guardas tus 2 y comodines',
    DdzReason.breaksGroup => 'Rompes una combinación',
    DdzReason.shedsMany => 'Sueltas muchas cartas',
    DdzReason.stopsOpponent => 'Frenas a un rival que acaba',
    DdzReason.opponentCanFollow => 'Un rival puede seguir',
    DdzReason.takesLead => 'Tomas la mano',
    DdzReason.leadsWeakGroup => 'Sueltas lo más flojo',
    DdzReason.waits => 'Esperas',
    DdzReason.strongHand => 'Mano fuerte',
    DdzReason.weakHand => 'Mano floja',
    DdzReason.holdsRocket => 'Tienes el cohete',
    DdzReason.holdsBomb => 'Tienes una bomba',
  };

  @override
  String get sureWin => 'Gana seguro';
  @override
  String get sureLoss => 'Pierde seguro';
  @override
  String get cardCounter => 'Contador de cartas';
  @override
  String get partner => 'Compañero';

  @override
  String presetName(String preset) => switch (preset) {
    'standard' => 'Estándar',
    'app' => 'Pedir y robar',
    'beginner' => 'Principiante',
    _ => preset,
  };
  @override
  String get bidding => 'Subasta';
  @override
  String biddingStyle(BiddingStyle style) => switch (style) {
    BiddingStyle.points => 'Puntos',
    BiddingStyle.callRob => 'Pedir y robar',
  };
  @override
  String get allPass => 'Si todos pasan';
  @override
  String allPassRule(AllPassRule rule) => switch (rule) {
    AllPassRule.redeal => 'Repartir',
    AllPassRule.firstBidderLandlord => 'El primero',
  };
  @override
  String get fourWithTwo => 'Cuatro con dos';
  @override
  String get fourWithTwoInfo => 'Cuatro iguales con 2 cartas sueltas o 2 parejas. No es bomba.';
  @override
  String get rocketAsKickers => 'Cohete como acompañante';
  @override
  String get rocketAsKickersInfo =>
      'Los dos comodines pueden ser las 2 cartas sueltas de un cuatro con dos o de un avión.';
  @override
  String get kittyShown => 'Monte visible';
  @override
  String get bombsDouble => 'Las bombas doblan';
  @override
  String get springDoubles => 'La primavera dobla';
  @override
  String get maxMultiplier => 'Multiplicador máximo';
  @override
  String get noLimit => 'Sin límite';
  @override
  String get customizeSeats => 'Elegir por asiento';

  @override
  String get combinations => 'Combinaciones';
  @override
  String get beats => 'Gana a';
  @override
  String get example => 'Ejemplo';
  @override
  String kindRule(PlayType type) => switch (type) {
    PlayType.solo => 'Una carta más baja. Los comodines son las más altas.',
    PlayType.pair => 'Una pareja más baja. Los dos comodines no son pareja.',
    PlayType.trio => 'Un trío más bajo.',
    PlayType.trioSolo => 'Un trío + 1 más bajo. Solo cuenta el trío.',
    PlayType.trioPair => 'Un trío + pareja más bajo. Solo cuenta el trío.',
    PlayType.straight => 'Una escalera más baja del mismo largo. 5 o más, del 3 al A.',
    PlayType.pairStraight => 'Una más baja del mismo largo. 3 parejas o más.',
    PlayType.airplane => 'Un avión más bajo del mismo largo. 2 tríos o más.',
    PlayType.airplaneSolos => 'Uno más bajo del mismo largo. Una carta por trío.',
    PlayType.airplanePairs => 'Uno más bajo del mismo largo. Una pareja por trío.',
    PlayType.fourTwoSolos => 'Un cuatro + 2 más bajo. No es bomba.',
    PlayType.fourTwoPairs => 'Un cuatro + 2 parejas más bajo. No es bomba.',
    PlayType.bomb => 'Todo salvo una bomba más alta o el cohete. Dobla la apuesta.',
    PlayType.rocket => 'Todo. Dobla la apuesta.',
  };

  @override
  String term(LandlordTerm term) => switch (term) {
    LandlordTerm.landlord => 'Terrateniente',
    LandlordTerm.peasants => 'Campesinos',
    LandlordTerm.kitty => 'Monte',
    LandlordTerm.faceUpCard => 'Carta descubierta',
    LandlordTerm.bidding => 'Subasta',
    LandlordTerm.callRob => 'Pedir y robar',
    LandlordTerm.multiplier => 'Multiplicador',
    LandlordTerm.bomb => 'Bomba',
    LandlordTerm.rocket => 'Cohete',
    LandlordTerm.spring => 'Primavera',
    LandlordTerm.cardCounter => 'Contador de cartas',
    LandlordTerm.match => 'Partida',
  };

  @override
  String definition(LandlordTerm term) => switch (term) {
    LandlordTerm.landlord =>
      'Quien gana la subasta. Se queda el monte, sale primero y juega solo '
          'contra los otros dos. Gana o pierde el doble.',
    LandlordTerm.peasants =>
      'Los dos jugadores contra el terrateniente. Ganan juntos cuando uno de ellos '
          'se queda sin cartas.',
    LandlordTerm.kitty => 'Las 3 cartas que sobran del reparto. El terrateniente las suma a su mano.',
    LandlordTerm.faceUpCard =>
      'Una carta se reparte boca arriba. Quien la recibe puja primero. Todos la ven hasta que se juega.',
    LandlordTerm.bidding =>
      'Puja 1, 2 o 3, o pasa. Quien puja más es terrateniente y la puja es la apuesta. '
          'Una puja de 3 cierra la subasta.',
    LandlordTerm.callRob =>
      'La subasta de la mayoría de apps: al primero que pide se lo pueden robar los otros, '
          'una vez cada uno. Cada robo dobla la apuesta; el último que roba es terrateniente.',
    LandlordTerm.multiplier =>
      'Por cuánto se multiplica la apuesta: ×2 por cada bomba o cohete jugado, '
          'y ×2 por una primavera.',
    LandlordTerm.bomb => 'Cuatro iguales. Gana a cualquier otra jugada y dobla la apuesta.',
    LandlordTerm.rocket => 'Los dos comodines juntos. Gana a todo y dobla la apuesta.',
    LandlordTerm.spring =>
      'El terrateniente acaba antes de que ningún campesino juegue, o los campesinos '
          'ganan cuando el terrateniente jugó una sola vez. Dobla la apuesta.',
    LandlordTerm.cardCounter => 'Cuántas cartas de cada valor quedan en las otras manos.',
    LandlordTerm.match =>
      'Los puntos de cada mano se suman: la apuesta por el multiplicador para cada campesino, '
          'el doble para el terrateniente. El primero que llega a la meta termina la partida y gana el total más alto. '
          'Siempre son 3 jugadores, así que la meta no cambia.',
  };

  @override
  List<(String, String)> get rulesSections => const [
    (
      'Objetivo',
      'Tres jugadores: un terrateniente contra dos campesinos. El primero que juega todas sus cartas '
          'gana para su bando.',
    ),
    (
      'Reparto',
      'Una baraja con dos comodines: 17 cartas cada uno y 3 boca abajo, el monte. '
          'Una carta se reparte boca arriba: quien la recibe puja primero. '
          'Valores de menor a mayor: 3 4 5 6 7 8 9 10 J Q K A 2, comodín chico, comodín grande. '
          'Los palos no cuentan.',
    ),
    (
      'Subasta',
      'Por turnos, puja más que la última puja (1, 2 o 3) o pasa. Una puja de 3, o dos pases tras una puja, '
          'la cierran. Quien puja más es terrateniente y se queda el monte, que ven todos. '
          'Si todos pasan, se reparte de nuevo.',
    ),
    (
      'Juego',
      'El terrateniente sale con cualquier combinación. Cada siguiente jugador juega una del mismo tipo y '
          'largo, más alta, o pasa. Las bombas y el cohete ganan a otros tipos. Tras dos pases seguidos, '
          'el último que jugó sale de nuevo. Pasar no impide jugar después.',
    ),
    (
      'Puntos',
      'Cada campesino gana o pierde la puja por el multiplicador; el terrateniente, el doble. '
          'Cada bomba o cohete lo dobla, y también una primavera. '
          'Los puntos se suman mano tras mano: el primero que llega a la meta (Jugar a) termina la partida, '
          'y gana el total más alto.',
    ),
    (
      'Variantes',
      'Antes de jugar se puede elegir: subasta de pedir y robar, qué pasa si todos pasan, cuatro con dos, '
          'el cohete como acompañante, el monte oculto y un límite al multiplicador.',
    ),
  ];
}
