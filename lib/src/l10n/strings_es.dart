import '../bots/bot.dart';
import '../engine/events.dart';
import '../engine/hand_evaluator.dart';
import '../engine/rules.dart';
import '../gto/preflop/preflop_charts.dart';
import '../gto/spot_strategy.dart';
import '../ui/table_controller.dart' show PlaybackSpeed;
import 'strings.dart';

class StringsEs extends S {
  const StringsEs();

  @override
  String get play => 'Jugar';
  @override
  String get settings => 'Ajustes';

  @override
  String get preflopCharts => 'Tablas preflop';
  @override
  String get spot => 'Situación';
  @override
  String chartSpot(ChartSpot spot) => switch (spot) {
        ChartSpot.open => 'Abrir',
        ChartSpot.vsOpen => 'vs apertura',
        ChartSpot.vs3bet => 'vs 3-bet',
      };
  @override
  String chartVillain(ChartSpot spot) => spot == ChartSpot.vs3bet ? 'Quien hace 3-bet' : 'Quien abre';
  @override
  String get callWord => 'Igualar';
  @override
  String inRange(int percent) => 'En rango: $percent%';
  @override
  String get glossary => 'Glosario';
  @override
  String get animations => 'Animaciones';
  @override
  String get sound => 'Sonido';
  @override
  String get cardBack => 'Reverso';
  @override
  String get cardFaces => 'Cartas';
  @override
  String get twoColors => '2 colores';
  @override
  String get fourColors => '4 colores';
  @override
  String get coloredCards => 'De colores';
  @override
  String get tableColor => 'Mesa';
  @override
  String speed(PlaybackSpeed speed) => switch (speed) {
        PlaybackSpeed.normal => 'Normal',
        PlaybackSpeed.fast => 'Rápida',
        PlaybackSpeed.instant => 'Instantánea',
      };

  @override
  String get newGame => 'Nueva partida';
  @override
  String get training => 'Entrenamiento GTO';
  @override
  String get freePlay => 'Juego libre';
  @override
  String get players => 'Jugadores';
  @override
  String get stack => 'Stack';
  @override
  String get opponentStyles => 'Estilos de los rivales';
  @override
  String get random => 'Aleatorio';
  @override
  String style(BotStyle style) => switch (style) {
        BotStyle.tag => 'TAG',
        BotStyle.lag => 'LAG',
        BotStyle.station => 'Station',
        BotStyle.nit => 'Nit',
        BotStyle.gto => 'GTO',
      };
  @override
  String get showStyles => 'Mostrar estilos de juego';
  @override
  String get showCards => 'Mostrar cartas';
  @override
  String get customizeSeats => 'Personalizar rivales';
  @override
  String get you => 'Jugador';
  @override
  String get position => 'Posición';
  @override
  String get rotate => 'Rotar';
  @override
  String get resetStacks => 'Reiniciar stacks cada mano';
  @override
  String get betSizes => 'Tamaños de apuesta';
  @override
  String get preflop => 'Preflop';
  @override
  String get postflop => 'Postflop';
  @override
  String get add => 'Añadir';
  @override
  String get resetDefaults => 'Restablecer';
  @override
  String get cancel => 'Cancelar';
  @override
  String get preflopSizePrompt => 'Tamaño de subida (× la apuesta)';
  @override
  String get postflopSizePrompt => 'Tamaño de subida (× el bote)';
  @override
  String between(String low, String high) => 'De $low a $high';
  @override
  String get rules => 'Reglas';
  @override
  String get minRaise => 'Subida mínima';
  @override
  String raiseRule(RaiseRule rule) => switch (rule) {
        RaiseRule.standard => 'Estándar',
        RaiseRule.bigBlind => '1 BB (regla de la casa)',
      };
  @override
  String get ante => 'Ante';
  @override
  String get noAnte => 'Ninguno';
  @override
  String get start => 'Empezar';

  @override
  String handsPlayed(int hands) => hands == 1 ? '1 mano' : '$hands manos';
  @override
  String get showAllCards => 'Mostrar cartas';
  @override
  String get hideAllCards => 'Ocultar cartas';
  @override
  String get ranges => 'Rangos';
  @override
  String get history => 'Historial';
  @override
  String get shuffleStyles => 'Mezclar estilos de juego';
  @override
  String get newStylesDealt => 'Nuevos estilos de juego aleatorios.';
  @override
  String get mainMenu => 'Menú principal';
  @override
  String get showRange => 'Rango';
  @override
  String get changeStyle => 'Estilo de juego';
  @override
  String get showTheirCards => 'Mostrar cartas';
  @override
  String get hideTheirCards => 'Ocultar cartas';

  @override
  String get fold => 'Retirarse';
  @override
  String get check => 'Pasar';
  @override
  String call(String amount) => 'Igualar $amount';
  @override
  String raiseTo(String amount, String? size) => 'Subir a $amount${size == null ? '' : ' ($size)'}';
  @override
  String allIn(String amount) => 'All-in $amount';
  @override
  String get allInBadge => 'All-in';
  @override
  String get raiseAnySize => 'Subir';
  @override
  String get potWord => 'bote';

  @override
  String potOdds(int percent) => 'Pot odds $percent%';
  @override
  String get showGto => 'Ver GTO';
  @override
  String get randomize => 'RNG';
  @override
  String get playRandomized => 'Jugar RNG';
  @override
  String get continueHand => 'Continuar';
  @override
  String score(int score) => 'Puntuación $score';
  @override
  String evLossAndMatch(String evLoss, int match) => 'Pérdida de EV $evLoss · Coincidencia $match%';
  @override
  String youPlay(String action) => action;
  @override
  String randomized(String action) => 'RNG: $action';
  @override
  String solvingTable(int percent) => 'Resolviendo… $percent%';
  @override
  String get solvingDecision => 'Resolviendo…';
  @override
  String thinking(String name) => '$name…';
  @override
  String get nextHand => 'Siguiente mano';
  @override
  String get evenHand => '±0 BB';
  @override
  String noAnswer(NoAnswer? reason) => switch (reason) {
        NoAnswer.multiway => 'Sin respuesta GTO: bote multijugador',
        NoAnswer.leftSolvedLines => 'Sin respuesta GTO: fuera de las líneas resueltas',
        NoAnswer.solveFailed => 'Sin respuesta GTO: falló el solver',
        null => 'Sin respuesta GTO',
      };
  @override
  String unavailable(Unavailable reason) => switch (reason) {
        Unavailable.checkIsFree => 'Puedes pasar gratis',
        Unavailable.raisingNotAllowed => 'No se puede subir',
        Unavailable.belowMinBet => 'Menos que la apuesta mínima',
        Unavailable.belowMinRaise => 'Menos que la subida mínima',
        Unavailable.nearlyAllIn => 'Casi all-in: usa All-in',
        Unavailable.sameAmount => 'Igual que un tamaño menor',
        Unavailable.notSolved => 'No está en el juego resuelto',
      };
  @override
  String grade(DecisionGrade grade) => switch (grade) {
        DecisionGrade.best => 'Óptimo',
        DecisionGrade.good => 'Bueno',
        DecisionGrade.inaccuracy => 'Imprecisión',
        DecisionGrade.mistake => 'Error',
        DecisionGrade.blunder => 'Error grave',
      };
  @override
  String get columnYou => 'Jugador';
  @override
  String get columnGto => 'GTO';
  @override
  String get columnEvLoss => 'Pérd. EV';

  @override
  String get average => 'Media';
  @override
  String get all => 'Todo';
  @override
  String get noScoresYet => 'Aún no hay puntuaciones.';
  @override
  String get decisions => 'Decisiones';
  @override
  String get averageScore => 'Puntuación media';
  @override
  String get evLoss => 'Pérdida de EV';
  @override
  String get net => 'Neto';
  @override
  String handNumber(int number) => '#$number';
  @override
  String street(Street street) => switch (street) {
        Street.preflop => 'Preflop',
        Street.flop => 'Flop',
        Street.turn => 'Turn',
        Street.river => 'River',
      };
  @override
  String get close => 'Cerrar';
  @override
  String get ok => 'Aceptar';
  @override
  String get fullGlossary => 'Glosario';

  @override
  String get yourRange => 'Tu rango';
  @override
  String get shareOfRange => 'Peso en el rango';
  @override
  String get frequency => 'Frecuencia';
  @override
  String get noRange => 'Sin rango aquí.';

  @override
  String wins(String name, String amount, {required bool you}) => you ? 'Ganas $amount' : '$name gana $amount';
  @override
  String split(String names, String amount) => '$names se reparten $amount';
  @override
  String get mainPot => 'Bote principal';
  @override
  String sidePot(int number) => 'Bote secundario $number';
  @override
  String listNames(List<String> names) =>
      names.length < 2 ? names.join() : '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
  @override
  String hand(HandValue value) {
    final r0 = rankSymbols[value.rankAt(0)], r1 = rankSymbols[value.rankAt(1)];
    return switch (value.category) {
      HandCategory.straightFlush => value.rankAt(0) == 12 ? 'Escalera real' : 'Escalera de color al $r0',
      HandCategory.quads => 'Póker de $r0',
      HandCategory.fullHouse => 'Full de $r0 y $r1',
      HandCategory.flush => 'Color al $r0',
      HandCategory.straight => 'Escalera al $r0',
      HandCategory.trips => 'Trío de $r0',
      HandCategory.twoPair => 'Doble pareja de $r0 y $r1',
      HandCategory.pair => 'Pareja de $r0',
      HandCategory.highCard => 'Carta alta $r0',
    };
  }

  @override
  String section(GlossarySection section) => switch (section) {
        GlossarySection.modes => 'Modos',
        GlossarySection.positions => 'Posiciones',
        GlossarySection.amounts => 'Cantidades',
        GlossarySection.actions => 'Acciones',
        GlossarySection.hand => 'La mano',
        GlossarySection.strategy => 'Estrategia',
        GlossarySection.scoring => 'Puntuación',
        GlossarySection.rules => 'Reglas',
        GlossarySection.styles => 'Estilos de juego',
      };

  @override
  String term(GlossaryTerm term) => positionTerms[term] ?? switch (term) {
        GlossaryTerm.training => 'Entrenamiento GTO',
        GlossaryTerm.play => 'Juego libre',
        GlossaryTerm.inPosition => 'IP / OOP',
        GlossaryTerm.headsUp => 'Heads-up',
        GlossaryTerm.bigBlinds => 'BB',
        GlossaryTerm.ante => 'Ante',
        GlossaryTerm.pot => 'Bote',
        GlossaryTerm.stack => 'Stack',
        GlossaryTerm.allIn => 'All-in',
        GlossaryTerm.raiseTo => 'Subir a',
        GlossaryTerm.betSizes => 'Tamaños de apuesta',
        GlossaryTerm.fold => 'Retirarse',
        GlossaryTerm.check => 'Pasar',
        GlossaryTerm.call => 'Igualar',
        GlossaryTerm.betRaise => 'Apostar / Subir',
        GlossaryTerm.open => 'Open',
        GlossaryTerm.limp => 'Limp',
        GlossaryTerm.threeBet => '3-bet / 4-bet',
        GlossaryTerm.holeCards => 'Cartas propias',
        GlossaryTerm.preflop => 'Preflop',
        GlossaryTerm.streets => 'Flop / Turn / River',
        GlossaryTerm.board => 'Board',
        GlossaryTerm.showdown => 'Showdown',
        GlossaryTerm.gto => 'GTO',
        GlossaryTerm.solver => 'Solver',
        GlossaryTerm.range => 'Rango',
        GlossaryTerm.rangeGrid => 'Tabla de rangos',
        GlossaryTerm.charts => 'Tablas preflop',
        GlossaryTerm.equity => 'Equity',
        GlossaryTerm.ev => 'EV',
        GlossaryTerm.mixedStrategy => 'Estrategia mixta',
        GlossaryTerm.rng => 'RNG',
        GlossaryTerm.potOdds => 'Pot odds',
        GlossaryTerm.evLoss => 'Pérdida de EV',
        GlossaryTerm.mixMatch => 'Coincidencia',
        GlossaryTerm.score => 'Puntuación',
        GlossaryTerm.grades => 'Calificaciones',
        GlossaryTerm.noLimit => 'No-Limit',
        GlossaryTerm.minBet => 'Apuesta mínima',
        GlossaryTerm.minRaise => 'Subida mínima',
        GlossaryTerm.houseRule => 'Regla de la casa',
        GlossaryTerm.incompleteRaise => 'Subida incompleta',
        GlossaryTerm.reopen => 'Reabrir la acción',
        GlossaryTerm.splitPot => 'Bote dividido',
        GlossaryTerm.styleGto => 'GTO',
        GlossaryTerm.tag => 'TAG',
        GlossaryTerm.lag => 'LAG',
        GlossaryTerm.station => 'Station',
        GlossaryTerm.nit => 'Nit',
        _ => term.name,
      };

  @override
  String definition(GlossaryTerm term) => switch (term) {
        GlossaryTerm.training => 'En cada decisión, indica con qué frecuencia crees que GTO se retira, iguala o '
            'sube (y cuánto), marca lo que vas a jugar y verás la respuesta GTO y tu puntuación. En el preflop los '
            'bots juegan GTO, así tus situaciones vienen de un juego GTO; sus estilos cuentan después del flop.',
        GlossaryTerm.play => 'Juega contra los bots sin puntuaciones, como en una partida real.',
        GlossaryTerm.utg => 'Under the gun: el primero en hablar antes del flop.',
        GlossaryTerm.utg1 => 'El asiento después de UTG.',
        GlossaryTerm.lj => 'Lojack: tres asientos antes del botón.',
        GlossaryTerm.hj => 'Hijack: dos asientos antes del botón.',
        GlossaryTerm.co => 'Cutoff: el asiento justo antes del botón.',
        GlossaryTerm.btn => 'Botón (el repartidor): habla el último después del flop, el mejor asiento. En '
            'heads-up, el botón pone también la ciega pequeña.',
        GlossaryTerm.sb => 'Ciega pequeña: pone media ciega grande antes del reparto; habla la primera después '
            'del flop.',
        GlossaryTerm.bb => 'Ciega grande: pone una ciega grande antes del reparto; habla la última antes del flop.',
        GlossaryTerm.inPosition => 'En posición (IP): hablas después de tu rival tras el flop. Fuera de '
            'posición (OOP): hablas antes. Hablar el último es una ventaja.',
        GlossaryTerm.headsUp => 'Solo dos jugadores, en la mesa o en el bote.',
        GlossaryTerm.bigBlinds => 'Ciegas grandes, la unidad de stacks y apuestas: un stack de 100 BB son 100 '
            'ciegas grandes.',
        GlossaryTerm.ante => 'Una pequeña apuesta obligatoria que pone cada jugador antes del reparto.',
        GlossaryTerm.pot => 'Todas las fichas apostadas hasta ahora. Una subida de "0.5× bote" es la mitad del bote.',
        GlossaryTerm.stack => 'Las fichas de un jugador. Entre dos jugadores solo se puede ganar el stack menor '
            '(el stack efectivo).',
        GlossaryTerm.allIn => 'Apostar todas tus fichas.',
        GlossaryTerm.raiseTo => 'Tu apuesta total tras la subida, incluido lo que ya habías puesto.',
        GlossaryTerm.betSizes => 'Tus opciones de apuesta y subida, las mismas en cada decisión. En el preflop '
            'son múltiplos de la apuesta que enfrentas: si eres el primero, 2× es subir a 2 BB; contra un open a '
            '2,5 BB, 3× es subir a 7,5 BB. En el postflop son múltiplos del bote: 0.5× bote es la mitad '
            '(del bote tras igualar, si enfrentas una apuesta). Los tamaños no permitidos aparecen en gris; uno que es casi all-in lo cubre All-in. Más '
            'tamaños tardan más en resolverse.',
        GlossaryTerm.fold => 'Abandonar la mano y las fichas que ya están en el bote.',
        GlossaryTerm.check => 'Pasar sin apostar (solo si nadie ha apostado).',
        GlossaryTerm.call => 'Igualar la apuesta actual.',
        GlossaryTerm.betRaise => 'Poner fichas el primero (apostar) o más que la apuesta actual (subir).',
        GlossaryTerm.open => 'La primera subida antes del flop.',
        GlossaryTerm.limp => 'Igualar la ciega grande antes del flop en lugar de subir.',
        GlossaryTerm.threeBet => 'Las siguientes subidas antes del flop: la ciega grande cuenta como la primera '
            'apuesta y el open como la segunda, así que la resubida es el 3-bet, y así sucesivamente.',
        GlossaryTerm.holeCards => 'Tus dos cartas privadas.',
        GlossaryTerm.preflop => 'Las apuestas antes de repartir cartas comunitarias.',
        GlossaryTerm.streets => 'Las cartas comunitarias: tres a la vez, luego una y luego otra, cada una con '
            'una ronda de apuestas.',
        GlossaryTerm.board => 'Las cartas comunitarias de la mesa.',
        GlossaryTerm.showdown => 'Tras la última apuesta, los jugadores que quedan muestran sus cartas; gana la '
            'mejor mano.',
        GlossaryTerm.gto => 'Game Theory Optimal (teoría de juegos óptima): una estrategia imbatible a largo plazo, '
            'hagan lo que hagan los rivales. Los solvers la encuentran (o se acercan).',
        GlossaryTerm.solver => 'Un programa que calcula estrategias GTO. El de esta app es casi GTO: simplifica '
            'algunas partes, como las apuestas de las calles siguientes.',
        GlossaryTerm.range => 'Todas las manos que un jugador puede tener en una situación, y la probabilidad de '
            'cada una.',
        GlossaryTerm.rangeGrid => 'Las 169 clases de manos iniciales en una tabla de 13 × 13: parejas en la '
            'diagonal, manos del mismo palo encima y de distinto palo debajo. Peso en el rango: las casillas más '
            'claras forman más parte del rango. Frecuencia: con qué frecuencia se juega así cada mano.',
        GlossaryTerm.charts => 'Lo que hace GTO con cada mano inicial antes del flop cuando los demás se '
            'retiran: primero en actuar (Abrir), ante una subida (vs apertura) o ante una resubida tras abrir '
            '(vs 3-bet). Los colores reparten cada mano entre Subir, Igualar y Retirarse; una mano oscura nunca '
            'llega ahí y una a medio llenar, solo a veces. Toca una mano para ver sus números.',
        GlossaryTerm.equity => 'Tu parte del bote si se repartieran todas las cartas restantes sin más apuestas.',
        GlossaryTerm.ev => 'Valor esperado: cuántas BB gana o pierde una acción de media.',
        GlossaryTerm.mixedStrategy => 'Jugar la misma mano de distintas formas, como igualar el 60% y subir el '
            '40%. GTO lo hace a menudo para ser impredecible.',
        GlossaryTerm.rng => 'Generador de números aleatorios: deja que el azar elija tu acción según tus '
            'porcentajes, como mezcla GTO.',
        GlossaryTerm.potOdds => 'Lo que debes igualar comparado con el bote que puedes ganar. Igualar compensa '
            'si tu equity es mayor que esa proporción.',
        GlossaryTerm.evLoss => 'Cuántas BB pierden tus porcentajes frente a la mezcla de GTO. La columna Pérd. EV compara cada acción con la mejor.',
        GlossaryTerm.mixMatch => 'Cuánto se parecen tus porcentajes a los de GTO: 100% es idéntico.',
        GlossaryTerm.score => 'De 0 a 100: la mitad por la coincidencia y la mitad por perder poco EV. Cuenta '
            'cuánto te retiras, pasas o igualas, y subes; los tamaños de subida cuentan solo un 10%.',
        GlossaryTerm.grades => 'Según la pérdida de EV (los tamaños de subida cuentan un 10%): Óptimo (hasta 0,02 BB), Bueno (0,08), Imprecisión (0,25), '
            'Error (0,75), Error grave (más).',
        GlossaryTerm.noLimit => 'Las apuestas que se usan aquí: puedes apostar o subir cualquier cantidad, hasta '
            'todas tus fichas.',
        GlossaryTerm.minBet => 'La apuesta más pequeña permitida: una ciega grande.',
        GlossaryTerm.minRaise => 'La subida más pequeña permitida. Estándar: al menos el tamaño de la última '
            'apuesta o subida de la calle (ante una apuesta de 10, sube a 20 o más; si 10 se sube a 30, la '
            'siguiente subida es a 50 como mínimo).',
        GlossaryTerm.houseRule => 'Una regla que acuerda una mesa en lugar de la estándar, como permitir '
            'cualquier subida de al menos 1 BB.',
        GlossaryTerm.incompleteRaise => 'Un all-in por menos de una subida mínima completa. Está permitido, pero '
            'no reabre la acción: quienes ya hablaron solo pueden igualar o retirarse.',
        GlossaryTerm.reopen => 'Una subida completa permite volver a subir a todos los que ya hablaron en la calle.',
        GlossaryTerm.splitPot => 'Las manos empatadas se reparten el bote. Si no se divide exacto, la ficha '
            'sobrante va al primer ganador a la izquierda del botón.',
        GlossaryTerm.styleGto => 'Juega la estrategia casi óptima del solver.',
        GlossaryTerm.tag => 'Tight-agresivo: juega pocas manos, pero las apuesta y sube con fuerza.',
        GlossaryTerm.lag => 'Loose-agresivo: juega muchas manos y mete mucha presión.',
        GlossaryTerm.station => 'Calling station: iguala demasiado y casi nunca sube.',
        GlossaryTerm.nit => 'Muy tight: espera manos premium.',
      };
}
