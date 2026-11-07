import '../../../../games/big_two/big_two.dart';
import 'big_two_strings.dart';

/// Big Two in Spanish.
class BigTwoStringsEs extends BigTwoStrings {
  const BigTwoStringsEs();

  @override
  String get pickLabel => 'GTO';

  @override
  String get play => 'Jugar';
  @override
  String get pass => 'Paso';
  @override
  String get cantBeat => 'No puedo';
  @override
  String starts(String name, String? card) => 'Sale $name${card == null ? '' : ': $card'}';
  @override
  String get whoStarts => '¿Quién sale?';
  @override
  String get clear => 'Borrar';
  @override
  String get cardCounter => 'Contador de cartas';
  @override
  String get stillOut => 'Por salir';
  @override
  String get highestOut => 'Más alta fuera';
  @override
  String get handPlan => 'Plan de mano';
  @override
  String planSummary(int plays, int unbeatable) => '$plays jugadas · $unbeatable imbatibles';
  @override
  String kind(PlayKind kind) => switch (kind) {
    PlayKind.pass => 'Paso',
    PlayKind.single => 'Carta suelta',
    PlayKind.pair => 'Pareja',
    PlayKind.triple => 'Trío',
    PlayKind.straight => 'Escalera',
    PlayKind.flush => 'Color',
    PlayKind.fullHouse => 'Full',
    PlayKind.fourOfAKind => 'Póquer',
    PlayKind.straightFlush => 'Escalera de color',
  };
  @override
  String reason(CoachReason reason) => switch (reason) {
    CoachReason.goesOut => 'Te quedas sin cartas',
    CoachReason.sureWin => 'Victoria segura',
    CoachReason.cantBeBeaten => 'Nadie la supera',
    CoachReason.shedsFive => 'Suelta cinco cartas',
    CoachReason.shedsLowest => 'Suelta tu carta más baja',
    CoachReason.keepsTwo => 'Guarda tus 2',
    CoachReason.usesTwo => 'Gasta un 2',
    CoachReason.breaksPair => 'Rompe una pareja',
    CoachReason.breaksTriple => 'Rompe un trío',
    CoachReason.breaksFour => 'Rompe un póquer',
    CoachReason.followsPlan => 'Sigue tu plan',
    CoachReason.addsPlays => 'Suma jugadas para acabar',
    CoachReason.blocksLastCard => 'Frena la última carta',
    CoachReason.lastCardDanger => 'Puede dejar salir la última carta',
    CoachReason.passKeepsHand => 'Mantiene tu mano entera',
    CoachReason.opponentNearlyOut => 'Alguien casi termina',
  };
  @override
  String get sureWin => 'Victoria segura';

  @override
  String preset(BigTwoPreset preset) => switch (preset) {
    BigTwoPreset.standard => 'Estándar',
    BigTwoPreset.hongKong => 'Hong Kong',
    BigTwoPreset.taiwan => 'Taiwán',
    BigTwoPreset.pusoyDos => 'Pusoy Dos',
  };
  @override
  String get cardsEach => 'Cartas por jugador';
  @override
  String get straights => 'Escaleras';
  @override
  String straightName(StraightRule rule) => switch (rule.name) {
    'hongKong' => 'Hong Kong',
    'taiwan' => 'Taiwán',
    'twoHigh' => 'J-Q-K-A-2',
    _ => 'Estándar',
  };
  @override
  String get flushes => 'Colores';
  @override
  String flushOrder(FlushOrder order) => switch (order) {
    FlushOrder.suitFirst => 'Palo primero',
    FlushOrder.rankFirst => 'Número primero',
    FlushOrder.allRanks => 'Como en póquer',
  };
  @override
  String get bombs => 'Bombas';
  @override
  String get sameFiveType => 'Igualar tipo de 5';
  @override
  String get passLockout => 'Pasar te deja fuera';
  @override
  String get lastCardRule => 'Regla de última carta';
  @override
  String get dragonWins => 'Dragón gana';
  @override
  String get noTopTwoFinish => 'No acabar con el 2 más alto';
  @override
  String get scoring => 'Puntuación';
  @override
  String scoringName(BigTwoScoring scoring) => switch (scoring) {
    BigTwoScoring.penalty => 'Penalización',
    BigTwoScoring.pusoyDos => 'Pusoy Dos',
  };
  @override
  String get doubleTwosLeft => 'Doble por cada 2 en mano';
  @override
  String get doubleBombLeft => 'Doble por bomba en mano';
  @override
  String get customizeSeats => 'Personalizar asientos';
  @override
  String scaledTarget(int points) => 'En esta mesa: a $points';
  @override
  String twosHeld(int n) => 'Doses: $n+';

  @override
  String get handRanks => 'Jugadas';
  @override
  String get suitsLowToHigh => 'Palos, de menor a mayor';
  @override
  String get ranksLowToHigh => 'Números, de menor a mayor';
  @override
  String get smallPlays => 'Cartas sueltas, parejas, tríos';
  @override
  String get fiveCardHands => 'Jugadas de cinco, de menor a mayor';
  @override
  String kindHint(PlayKind kind) => switch (kind) {
    PlayKind.pass => 'Sin cartas este turno.',
    PlayKind.single => 'Cualquier carta. Primero el número, luego el palo.',
    PlayKind.pair => 'Dos del mismo número. Decide la carta más alta.',
    PlayKind.triple => 'Tres del mismo número.',
    PlayKind.straight => 'Cinco números seguidos, palos mezclados.',
    PlayKind.flush => 'Cinco cartas del mismo palo.',
    PlayKind.fullHouse => 'Un trío y una pareja. Decide el trío.',
    PlayKind.fourOfAKind => 'Cuatro del mismo número y una carta cualquiera. Deciden las cuatro.',
    PlayKind.straightFlush => 'Cinco seguidas, todas del mismo palo.',
  };
  @override
  String get lowestStraight => 'Escalera más baja';
  @override
  String get highestStraight => 'Escalera más alta';
  @override
  String flushHint(FlushOrder order) => switch (order) {
    FlushOrder.suitFirst => 'Dos colores: gana el palo más alto, luego la carta más alta.',
    FlushOrder.rankFirst => 'Dos colores: gana la carta más alta, luego su palo.',
    FlushOrder.allRanks => 'Dos colores: se comparan las cartas de arriba abajo, como en póquer; el palo al final.',
  };
  @override
  String get bombsHint =>
      'Bombas: el póquer y la escalera de color también ganan a cualquier carta suelta, '
      'pareja o trío.';
  @override
  String get sameTypeHint => 'Una jugada de cinco solo se supera con una más alta del mismo tipo, o con una bomba.';

  @override
  String term(BigTwoTerm term) => switch (term) {
    BigTwoTerm.single => 'Carta suelta',
    BigTwoTerm.pair => 'Pareja',
    BigTwoTerm.triple => 'Trío',
    BigTwoTerm.fiveCard => 'Jugada de cinco',
    BigTwoTerm.straight => 'Escalera',
    BigTwoTerm.flush => 'Color',
    BigTwoTerm.fullHouse => 'Full',
    BigTwoTerm.fourOfAKind => 'Póquer',
    BigTwoTerm.straightFlush => 'Escalera de color',
    BigTwoTerm.bomb => 'Bomba',
    BigTwoTerm.sameType => sameFiveType,
    BigTwoTerm.pass => 'Paso',
    BigTwoTerm.lead => 'Salida',
    BigTwoTerm.startingCard => 'Carta de salida',
    BigTwoTerm.suitOrder => 'Orden de palos',
    BigTwoTerm.lastCard => 'Regla de última carta',
    BigTwoTerm.lockout => 'Pasar te deja fuera',
    BigTwoTerm.dragon => 'Dragón',
    BigTwoTerm.topTwo => 'No acabar con el 2 más alto',
    BigTwoTerm.penalty => 'Puntuación por penalización',
    BigTwoTerm.pusoyScoring => 'Puntuación Pusoy Dos',
    BigTwoTerm.doubling => 'Doblar',
    BigTwoTerm.handPlan => 'Plan de mano',
    BigTwoTerm.unbeatable => 'Imbatible',
    BigTwoTerm.cardCounter => 'Contador de cartas',
    BigTwoTerm.match => 'Partida',
  };
  @override
  String definition(BigTwoTerm term) => switch (term) {
    BigTwoTerm.single => 'Una carta. La supera una carta más alta: primero el número, luego el palo.',
    BigTwoTerm.pair => 'Dos cartas del mismo número. Gana la pareja con la carta más alta.',
    BigTwoTerm.triple => 'Tres cartas del mismo número. Gana el número más alto.',
    BigTwoTerm.fiveCard =>
      'Escalera, color, full, póquer (más una carta) o escalera de color, de menor a '
          'mayor. Solo otra jugada de cinco la supera.',
    BigTwoTerm.straight =>
      'Cinco números seguidos, no todos del mismo palo. Qué escaleras valen, y su '
          'orden, dependen de las reglas (Escaleras en la preparación).',
    BigTwoTerm.flush =>
      'Cinco cartas del mismo palo, no seguidas. Cómo se comparan dos colores depende de '
          'las reglas (Colores en la preparación).',
    BigTwoTerm.fullHouse => 'Un trío y una pareja. Decide el número del trío.',
    BigTwoTerm.fourOfAKind =>
      'Cuatro cartas del mismo número y una quinta cualquiera. Cuatro cartas solas '
          'no son una jugada.',
    BigTwoTerm.straightFlush => 'Cinco números seguidos del mismo palo: la jugada de cinco más alta.',
    BigTwoTerm.bomb =>
      'Con Bombas, el póquer y la escalera de color también ganan a cualquier carta '
          'suelta, pareja o trío.',
    BigTwoTerm.sameType => sameTypeHint,
    BigTwoTerm.pass =>
      'No jugar cartas este turno. Puedes volver a jugar en tu próximo turno, salvo con '
          'Pasar te deja fuera.',
    BigTwoTerm.lead =>
      'Cuando todos los demás pasan, el último que jugó empieza otra ronda con cualquier '
          'jugada.',
    BigTwoTerm.startingCard =>
      'La carta más baja repartida (el 3 de diamantes en el juego estándar). Quien la tiene sale '
          'primero, y esa primera jugada debe incluirla. Todos la ven hasta que se juega. Con dos jugadores se cantan '
          'las cartas desde la más baja hasta que alguien tenga una, así que el otro no tiene ninguna más baja.',
    BigTwoTerm.suitOrder =>
      'Los palos desempatan números iguales. Estándar: diamantes < tréboles < corazones < '
          'picas. Taiwán: tréboles < diamantes < corazones < picas. Pusoy Dos: tréboles < picas < corazones < diamantes.',
    BigTwoTerm.lastCard =>
      'Si el siguiente jugador tiene una sola carta, la carta suelta que juegues debe '
          'ser la más alta que tengas. Puedes pasar o jugar dos o más cartas.',
    BigTwoTerm.lockout => 'Después de pasar, no puedes volver a jugar hasta que empiece otra ronda.',
    BigTwoTerm.dragon =>
      'Una carta de cada número, del 3 al 2, en una mano de 13. Con Dragón gana, gana '
          'la mano en el acto.',
    BigTwoTerm.topTwo => 'No puedes terminar jugando sola la carta más alta (el 2 de picas en el juego estándar).',
    BigTwoTerm.penalty =>
      'Cada perdedor paga 1 punto por carta si le quedan hasta 9, 2 por carta con 10 o '
          'más, 3 por carta si no jugó ninguna. El ganador se lo lleva todo.',
    BigTwoTerm.pusoyScoring => 'Solo puntúa el ganador: 1 punto, doblado por cada 2 de su última jugada.',
    BigTwoTerm.doubling =>
      'Con penalización, lo que paga un perdedor puede doblarse por cada 2 que le '
          'quede, y otra vez si le queda un póquer o una escalera de color.',
    BigTwoTerm.handPlan =>
      'Las menos jugadas que vacían tu mano. Cada jugada que nadie supera te devuelve '
          'la salida; cada una de las otras necesita una salida tuya.',
    BigTwoTerm.unbeatable =>
      'Ninguna carta que no hayas visto puede superar esta jugada, así que después '
          'vuelves a salir.',
    BigTwoTerm.cardCounter =>
      'Los 2, ases y reyes que aún no has visto jugar, y la carta más alta que '
          'queda fuera.',
    BigTwoTerm.match =>
      'Las manos se suman hasta que alguien llega al objetivo. Con penalización, cada perdedor suma su '
          'penalización y gana el total más bajo (se suele jugar a 100). Con Pusoy Dos, el ganador suma sus '
          'puntos y gana el total más alto. Ajustar a los jugadores: el objetivo cambia con la mesa, para que '
          'la partida dure más o menos las mismas manos que con cuatro jugadores (unas 20).',
  };

  @override
  List<(String, String)> get rulesSections => const [
    ('Objetivo', 'Ser el primero en jugar todas tus cartas.'),
    (
      'Cartas',
      'Números de menor a mayor: 3 4 5 6 7 8 9 10 J Q K A 2. Los palos desempatan: en el juego estándar '
          'diamantes < tréboles < corazones < picas, así que el 3 de diamantes es la carta más baja y el 2 de picas la más alta.',
    ),
    (
      'Reparto',
      'Con cuatro jugadores, 13 cartas cada uno. Con tres, 17 cada uno, y la última se reparte boca arriba: '
          'se la queda quien tiene la carta más baja, y todos saben quién la tiene. Con dos, 17 cada uno (o 13 '
          'o 21) y el resto no se usa.',
    ),
    (
      'Salida',
      'Quien tiene la carta más baja repartida (el 3 de diamantes si se reparten todas) juega primero, '
          'y esa jugada debe incluirla. Todos la ven hasta que se juega. Con dos jugadores se cantan las cartas '
          'desde la más baja hasta que alguien tenga una.',
    ),
    (
      'Jugadas',
      'Carta suelta, pareja, trío o una jugada de cinco: escalera, color, full, póquer (más una carta) y '
          'escalera de color, de menor a mayor.',
    ),
    (
      'Turnos',
      'Se juega hacia la derecha. Supera la última jugada con otra más alta del mismo número de cartas, o '
          'pasa. Cuando todos los demás pasan, el último que jugó empieza otra ronda con lo que quiera.',
    ),
    (
      'Puntuación',
      'Penalización: cada perdedor paga 1 punto por carta si le quedan hasta 9, 2 por carta con 10 o más, '
          '3 por carta si no jugó ninguna; el ganador se lo lleva todo. Pusoy Dos: el ganador suma 1, '
          'doblado por cada 2 de su última jugada.',
    ),
    (
      'Partida',
      'Las manos se suman hasta que alguien llega al objetivo: con penalización gana el total más bajo, '
          'con Pusoy Dos el más alto.',
    ),
    (
      'Variantes',
      'Hong Kong: A-2-3-4-5 es la escalera más alta, los colores se comparan por número, un dragón '
          'repartido gana y nadie termina con el 2 de picas solo. Taiwán: sale el 3 de tréboles, las bombas ganan a todo y '
          'las jugadas de cinco deben ser del mismo tipo. Pusoy Dos: sale el 3 de tréboles, palos tréboles < picas < corazones < diamantes, solo '
          'puntúa el ganador.',
    ),
  ];

  @override
  String presetTerm(BigTwoPreset preset) => switch (preset) {
    BigTwoPreset.standard => 'Reglas estándar',
    BigTwoPreset.hongKong => 'Reglas de Hong Kong',
    BigTwoPreset.taiwan => 'Reglas de Taiwán',
    BigTwoPreset.pusoyDos => 'Reglas Pusoy Dos',
  };
  @override
  String presetIntro(BigTwoPreset preset) => switch (preset) {
    BigTwoPreset.standard => 'El Big Two de Pagat.',
    BigTwoPreset.hongKong => 'Choh Dai Di (锄大地), como se juega en Hong Kong.',
    BigTwoPreset.taiwan => 'Da Lao Er (大老二), como se juega en Taiwán. Las fuentes no coinciden en sus escaleras.',
    BigTwoPreset.pusoyDos => 'El juego filipino.',
  };
  @override
  String suitsLine(String suits) => 'Palos: $suits.';
  @override
  String startLine(String card, {required bool mustPlay}) => mustPlay
      ? 'Sale la carta más baja repartida (el $card si se reparten todas), y debe ir en la primera jugada.'
      : 'Sale quien tenga la carta más baja repartida (el $card si se reparten todas), con cualquier jugada.';
  @override
  String straightsLine(String lowest, String highest) => 'Escaleras: $lowest la más baja, $highest la más alta.';
  @override
  String get noBombs => 'Sin bombas.';
  @override
  String get lockoutOn => 'Si pasas, quedas fuera hasta la siguiente salida.';
  @override
  String get lockoutOff => 'Pasar nunca te deja fuera.';
  @override
  String get lastCardOn => 'Regla de última carta.';
  @override
  String get dragonOn => 'Un dragón repartido gana al instante.';
  @override
  String topTwoOn(String card) => 'Nadie puede terminar con el $card solo.';
  @override
  String scoringLine(String name) => 'Puntuación: $name.';
  @override
  String straightTerm(StraightRule rule) => switch (rule.name) {
    'hongKong' => 'Escaleras de Hong Kong',
    'taiwan' => 'Escaleras de Taiwán',
    'twoHigh' => 'Escaleras J-Q-K-A-2',
    _ => 'Escaleras estándar',
  };
  @override
  String runsLowToHigh(String runs) => 'De menor a mayor: $runs.';
  @override
  String notStraights(String runs) => 'No son escalera: $runs.';
  @override
  String straightTie(StraightTieBreak tieBreak, {required String card, required String run}) => switch (tieBreak) {
    StraightTieBreak.sequenceTop =>
      'Escaleras iguales: gana el palo de la carta más alta de la serie (el $card en $run).',
    StraightTieBreak.highestCard => 'Escaleras iguales: gana el palo de la carta más alta (el $card en $run).',
  };
  @override
  String flushTerm(FlushOrder order) => switch (order) {
    FlushOrder.suitFirst => 'Colores: palo primero',
    FlushOrder.rankFirst => 'Colores: número primero',
    FlushOrder.allRanks => 'Colores: como en póquer',
  };
  @override
  String usedBy(List<String> presets) => 'Variantes: ${presets.join(', ')}.';
  @override
  String get noPreset => 'Ninguna variante la usa.';
  @override
  String get byPreset => 'Por variante';
  @override
  String get on => 'Sí';
  @override
  String get off => 'No';
  @override
  String labelled(String label, String value) => '$label: $value';
  @override
  String source(List<String> names) => '${names.length > 1 ? 'Fuentes' : 'Fuente'}: ${names.join('; ')}.';
  @override
  String sourceName(BigTwoSource source) => switch (source) {
    BigTwoSource.pagat => 'Pagat, Big Two',
    BigTwoSource.pagatHongKong => 'Pagat, Big Two (Hong Kong)',
    BigTwoSource.pagatPhilippines => 'Pagat, Big Two (Filipinas)',
    BigTwoSource.pagatIndonesia => 'Pagat, Big Two (Indonesia)',
    BigTwoSource.wikipedia => 'Wikipedia en inglés, Big two',
    BigTwoSource.zhWikipedia => 'Wikipedia en chino, 大老二',
    BigTwoSource.charlesworth => 'Charlesworth, arXiv:1808.10442',
    BigTwoSource.denexa => 'Denexa, Big Two',
    BigTwoSource.wikipediaPusoy => 'Wikipedia, Pusoy dos',
  };
  @override
  String get presetsCompared => 'Variantes comparadas';
  @override
  String get sourcesTitle => 'Fuentes';
}
