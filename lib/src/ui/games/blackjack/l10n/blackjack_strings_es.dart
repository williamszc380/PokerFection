import '../../../../games/blackjack/app/blackjack_grading.dart';
import '../../../../games/blackjack/blackjack.dart';
import 'blackjack_strings.dart';

/// Blackjack in Spanish, with the words of the casino table.
class BlackjackStringsEs extends BlackjackStrings {
  const BlackjackStringsEs();

  @override
  String get pickLabel => 'Estrategia básica';

  @override
  String? tagLabel(String tag) => tag == 'count' ? 'Conteo' : null;

  @override
  String get dealer => 'Crupier';
  @override
  String get dealerSeat => 'la banca';

  @override
  String action(BlackjackAction action) => switch (action) {
    BlackjackAction.hit => 'Pedir',
    BlackjackAction.stand => 'Plantarse',
    BlackjackAction.double => 'Doblar',
    BlackjackAction.split => 'Separar',
    BlackjackAction.surrender => 'Rendirse',
    BlackjackAction.insurance => 'Seguro',
    BlackjackAction.noInsurance => 'Sin seguro',
    BlackjackAction.keepPlaying => 'Seguir',
  };

  @override
  String get evenMoney => 'Pago 1:1';
  @override
  String softTotal(int total) => '$total blando';
  @override
  String get bust => 'Pasado';
  @override
  String get blackjackHand => 'Blackjack';
  @override
  String totalsFromTo(int low, int high) => '$low–$high';
  @override
  String totalOrLess(int total) => '$total o menos';

  @override
  String outcome(HandOutcome outcome) => switch (outcome) {
    HandOutcome.pending => 'En juego',
    HandOutcome.blackjack => 'Blackjack',
    HandOutcome.win => 'Gana',
    HandOutcome.push => 'Empate',
    HandOutcome.lose => 'Pierde',
    HandOutcome.bust => 'Pasado',
    HandOutcome.dealerBlackjack => 'Blackjack del crupier',
    HandOutcome.surrender => 'Rendida',
  };

  @override
  String get insured => 'Asegurado';
  @override
  String get countToggle => 'Conteo';
  @override
  String runningCount(String count) => 'Conteo $count';
  @override
  String trueCount(String count) => 'Real $count';
  @override
  String cardsLeft(int cards) => 'Quedan $cards';
  @override
  String round(int n) => 'Mano $n';

  @override
  String get presetLabel => 'Mesa';
  @override
  String preset(BlackjackPreset preset) => switch (preset) {
    BlackjackPreset.standard => 'Estándar',
    BlackjackPreset.vegasStrip => 'Vegas Strip',
    BlackjackPreset.downtown => 'Downtown',
    BlackjackPreset.atlanticCity => 'Atlantic City',
    BlackjackPreset.european => 'Europea',
    BlackjackPreset.singleDeck => 'Una baraja',
  };
  @override
  String get decks => 'Barajas';
  @override
  String get dealerHitsSoft17 => 'Crupier pide con 17 blando';
  @override
  String get blackjackPays => 'Blackjack paga';
  @override
  String get doubleLabel => 'Doblar';
  @override
  String doubleRule(DoubleRule rule) => switch (rule) {
    DoubleRule.anyTwo => 'Cualquiera',
    DoubleRule.nineToEleven => '9–11',
    DoubleRule.tenToEleven => '10–11',
  };
  @override
  String get doubleAfterSplit => 'Doblar tras separar';
  @override
  String get surrenderLabel => 'Rendirse';
  @override
  String surrenderRule(Surrender rule) => switch (rule) {
    Surrender.none => 'No',
    Surrender.late => 'Tardía',
    Surrender.early => 'Temprana',
  };
  @override
  String get holeCard => 'Carta oculta';
  @override
  String get noHoleCardLossLabel => 'Blackjack del crupier';
  @override
  String noHoleCardLoss(NoHoleCardLoss rule) => switch (rule) {
    NoHoleCardLoss.allBets => 'Todas las apuestas',
    NoHoleCardLoss.originalBetsOnly => 'Solo la inicial',
  };
  @override
  String get resplitAces => 'Volver a separar ases';
  @override
  String get continuousShuffle => 'Barajado continuo';
  @override
  String get penetration => 'Penetración';
  @override
  String coachMode(CoachMode mode) => switch (mode) {
    CoachMode.fresh => 'Zapato nuevo',
    CoachMode.seen => 'Cartas vistas',
  };

  @override
  String get hardTotals => 'Totales duros';
  @override
  String get softTotals => 'Totales blandos';
  @override
  String get pairs => 'Pares';
  @override
  String get dealerShows => 'Crupier';
  @override
  String chartLetter(ChartCode code) => switch (code) {
    ChartCode.hit => 'P',
    ChartCode.stand => 'Pl',
    ChartCode.doubleOrHit => 'D',
    ChartCode.doubleOrStand => 'Dp',
    ChartCode.split => 'S',
    ChartCode.surrenderOrHit => 'R',
    ChartCode.surrenderOrStand => 'Rp',
    ChartCode.surrenderOrSplit => 'Rs',
  };
  @override
  String chartMeaning(ChartCode code) => switch (code) {
    ChartCode.hit => 'Pedir',
    ChartCode.stand => 'Plantarse',
    ChartCode.doubleOrHit => 'Doblar; si no, pedir',
    ChartCode.doubleOrStand => 'Doblar; si no, plantarse',
    ChartCode.split => 'Separar',
    ChartCode.surrenderOrHit => 'Rendirse; si no, pedir',
    ChartCode.surrenderOrStand => 'Rendirse; si no, plantarse',
    ChartCode.surrenderOrSplit => 'Rendirse; si no, separar',
  };
  @override
  String get chartFailed => 'No se pudo hacer la tabla.';

  @override
  String reason(CoachReason r) {
    final up = BlackjackStrings.upcard(r.upcard);
    final hand = r.soft ? '${r.total} blando' : '${r.total}';
    final pct = BlackjackStrings.percent(r.chance ?? 0);
    final play = r.action == null ? '' : action(r.action!);
    final chart = r.basicAction == null ? '' : action(r.basicAction!);
    return switch (r.kind) {
      ReasonKind.standMadeHand => '17 o más: plantarse',
      ReasonKind.cantBust => '11 o menos: no te pasas',
      ReasonKind.dealerBustsOften => 'El $up del crupier se pasa a menudo',
      ReasonKind.dealerStrong => 'El $up del crupier suele llegar a 17+',
      ReasonKind.doubleStrong => '$hand contra $up: doblar',
      ReasonKind.doubleSoft => '$hand contra $up: doblar',
      ReasonKind.splitAces => 'Separa siempre los ases',
      ReasonKind.splitEights => 'Separa siempre los ochos',
      ReasonKind.neverSplitTens => 'Nunca separes dieces',
      ReasonKind.neverSplitFives => 'Nunca separes cincos',
      ReasonKind.splitVsWeak => 'Separa contra un $up débil',
      ReasonKind.noSplitVsStrong => 'No separes contra un $up',
      ReasonKind.surrenderSaves => 'Gana muy poco: rendirse',
      ReasonKind.softCantBust => 'Mano blanda: no te pasas',
      ReasonKind.softStand => 'Buen total blando: plantarse',
      ReasonKind.insuranceBad => 'Dieces $pct: el seguro pierde',
      ReasonKind.insuranceGood => 'Dieces $pct: el seguro gana',
      ReasonKind.countDeviation =>
        'Real ${BlackjackStrings.signed(r.trueCount ?? 0, decimals: 1)}: $play (tabla: $chart)',
      ReasonKind.exactCardsPlay => 'Con estas cartas: $play (tabla: $chart)',
      ReasonKind.bustRisk => 'Te pasas el $pct de las veces',
      ReasonKind.tooRisky => 'Demasiado arriesgado contra un $up',
      ReasonKind.dealerBustsLess => 'El $up del crupier se pasa menos de lo que parece',
      ReasonKind.betterPlay => 'Mejor: $play',
    };
  }

  @override
  String term(BlackjackTerm term) => switch (term) {
    BlackjackTerm.blackjack => 'Blackjack',
    BlackjackTerm.hit => 'Pedir',
    BlackjackTerm.stand => 'Plantarse',
    BlackjackTerm.double => 'Doblar',
    BlackjackTerm.split => 'Separar',
    BlackjackTerm.surrender => 'Rendirse',
    BlackjackTerm.insurance => 'Seguro',
    BlackjackTerm.evenMoney => 'Pago 1:1',
    BlackjackTerm.soft => 'Mano blanda',
    BlackjackTerm.bust => 'Pasarse',
    BlackjackTerm.push => 'Empate',
    BlackjackTerm.holeCard => 'Carta oculta',
    BlackjackTerm.dealerStart => 'Dos cartas del crupier',
    BlackjackTerm.noHoleCardLoss => 'Blackjack del crupier',
    BlackjackTerm.soft17 => '17 blando',
    BlackjackTerm.doubleAfterSplit => 'Doblar tras separar',
    BlackjackTerm.resplitAces => 'Volver a separar ases',
    BlackjackTerm.shoe => 'Zapato',
    BlackjackTerm.penetration => 'Penetración',
    BlackjackTerm.continuousShuffle => 'Barajado continuo',
    BlackjackTerm.basicStrategy => 'Estrategia básica',
    BlackjackTerm.runningCount => 'Conteo',
    BlackjackTerm.trueCount => 'Conteo real',
    BlackjackTerm.freshShoe => 'Zapato nuevo',
    BlackjackTerm.cardsSeen => 'Cartas vistas',
    BlackjackTerm.bets => 'Apuestas',
  };

  @override
  String definition(BlackjackTerm term) => switch (term) {
    BlackjackTerm.blackjack => 'Un as y una carta de valor diez como primeras dos cartas. Paga 3 a 2 (6 a 5 en algunas mesas), salvo que el crupier también tenga blackjack.',
    BlackjackTerm.hit => 'Pedir una carta más.',
    BlackjackTerm.stand => 'Quedarte con la mano; juega la siguiente mano o el crupier.',
    BlackjackTerm.double => 'Doblar la apuesta y recibir exactamente una carta más.',
    BlackjackTerm.split => 'Convertir una pareja en dos manos, cada una con su apuesta. Cada mano recibe una segunda carta y se juega por separado.',
    BlackjackTerm.surrender => 'Abandonar la mano y recuperar la mitad de la apuesta. La tardía es después de que el crupier mire si tiene blackjack; la temprana, antes.',
    BlackjackTerm.insurance => 'Una apuesta aparte de media apuesta cuando el crupier muestra un as. Paga 2 a 1 si el crupier tiene blackjack. Solo compensa si más de un tercio de las cartas que quedan son dieces.',
    BlackjackTerm.evenMoney =>
      'El seguro sobre tu propio blackjack en una mesa 3:2: cobras 1 a 1 tenga lo que tenga el crupier.',
    BlackjackTerm.soft =>
      'Una mano con un as que cuenta 11, como A-6 (17 blando). Una carta más no puede pasarla: el as vuelve a valer 1.',
    BlackjackTerm.bust => 'Más de 21. La mano pierde enseguida, aunque luego el crupier se pase.',
    BlackjackTerm.push => 'Empate con el crupier: recuperas la apuesta.',
    BlackjackTerm.holeCard => 'La carta boca abajo del crupier. Con un diez o un as a la vista, el crupier mira si tiene blackjack antes de que juegues. Sin carta oculta (mesas europeas), su segunda carta llega después de que juegues.',
    BlackjackTerm.dealerStart => 'Lo que suman la carta visible y la carta oculta del crupier. 17–21: el crupier se planta (con 17 blando pide en las mesas donde así se juega). 12–16: tiene que pedir, y con un total duro puede pasarse. 11 o menos: pide y no puede pasarse con la siguiente carta. En Entrenamiento, toca al crupier para ver las probabilidades, calculadas con las cartas que has visto.',
    BlackjackTerm.noHoleCardLoss => 'Sin carta oculta, el crupier puede sacar blackjack después de que hayas doblado o dividido. Casi todas las mesas se llevan entonces todas tus apuestas; algunas solo la apuesta inicial, y doblar o dividir contra un diez o un as arriesga menos.',
    BlackjackTerm.soft17 => 'Un 17 con un as que cuenta 11. En algunas mesas el crupier pide con él, lo que cuesta al jugador un 0,2% de cada apuesta.',
    BlackjackTerm.doubleAfterSplit => 'Puedes doblar en las manos que salen de separar.',
    BlackjackTerm.resplitAces => 'Si un as separado recibe otro as, puedes volver a separar.',
    BlackjackTerm.shoe => 'La caja de la que se reparten las cartas: de 1 a 8 barajas mezcladas.',
    BlackjackTerm.penetration =>
      'Cuánto del zapato se reparte antes de que salga la carta de corte y se baraje. Aquí un zapato es una partida.',
    BlackjackTerm.continuousShuffle =>
      'Una máquina devuelve las cartas tras cada mano, así que recordar cartas no sirve. Una partida son 50 manos.',
    BlackjackTerm.basicStrategy => 'La mejor jugada para cada total contra cada carta del crupier, con las reglas de la mesa y un zapato completo. Es la jugada del coach y la tabla de las guías.',
    BlackjackTerm.runningCount => 'Conteo de cartas (Hi-Lo): +1 por cada 2 a 6 visto, −1 por cada diez o as. Un conteo alto indica que quedan muchos dieces y ases, lo que te favorece.',
    BlackjackTerm.trueCount => 'El conteo dividido entre las barajas que quedan: el que cambia las jugadas.',
    BlackjackTerm.freshShoe => 'El coach supone un zapato completo menos las cartas de esta mano: la estrategia básica. Se te evalúa con la tabla.',
    BlackjackTerm.cardsSeen => 'El coach usa todas las cartas vistas desde el barajado, como un contador perfecto. Su mejor jugada lleva la etiqueta Conteo cuando difiere de la tabla, y se te evalúa con ella.',
    BlackjackTerm.bets => 'Los números del coach: lo que gana o pierde cada jugada de media, en apuestas. −0,05 es perder un 5% de la apuesta a la larga.',
  };

  @override
  List<(String, String)> get rulesSections => const [
    (
      'Objetivo',
      'Gana al crupier: acaba más cerca de 21 que él sin pasarte. Juegas solo contra el crupier y apuestas 1 en cada mano.',
    ),
    (
      'Valor de las cartas',
      'Del 2 al 10 valen su número; J, Q y K valen 10, y el as vale 11 o 1. Una mano con un as que vale 11 es blanda.',
    ),
    (
      'El reparto',
      'Tú y el crupier recibís dos cartas; una del crupier va boca abajo (la carta oculta). Con un diez o un as a la vista, el crupier mira si tiene blackjack antes de que juegues. Sin carta oculta, su segunda carta llega después.',
    ),
    (
      'Tus jugadas',
      'Pedir: otra carta. Plantarse: quedarte con la mano. Doblar: doblar la apuesta y recibir una sola carta. Separar: una pareja se convierte en dos manos, cada una con su apuesta. Rendirse: abandonar la mano y recuperar la mitad, si la mesa lo permite.',
    ),
    (
      'Seguro',
      'Cuando el crupier muestra un as puedes comprar un seguro por media apuesta; paga 2 a 1 si tiene blackjack. Con tu propio blackjack en una mesa 3:2 es pago 1:1: cobras 1 a 1 pase lo que pase.',
    ),
    (
      'El crupier',
      'El crupier pide hasta 16 y se planta con 17. En las mesas donde pide con 17 blando, también pide con un 17 blando.',
    ),
    (
      'Pagos',
      'Ganar paga 1 a 1. El blackjack paga 3 a 2 (6 a 5 en algunas mesas). Un empate devuelve la apuesta. Una mano de más de 21 pierde enseguida.',
    ),
    (
      'El zapato',
      'Las cartas salen de un zapato de 1 a 8 barajas. Cuando sale la carta de corte, el zapato termina: eso es una partida. Con barajado continuo, una partida son 50 manos.',
    ),
  ];
}
