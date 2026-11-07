import 'kit_strings.dart';

class KitStringsEs extends KitStrings {
  const KitStringsEs();

  @override
  String get trainingMode => 'Entrenamiento';
  @override
  String get lastGame => 'Última partida';
  @override
  String get thinkLonger => 'Pensar más';
  @override
  String get yourTurn => 'Tu turno';
  @override
  String get youWin => 'Ganas';
  @override
  String get youLose => 'Pierdes';
  @override
  String get draw => 'Empate';
  @override
  String wins(String name) => 'Gana $name';
  @override
  String get nextDeal => 'Siguiente mano';
  @override
  String get deal => 'Repartir';
  @override
  String get newShoe => 'Nuevo mazo';
  @override
  String get level => 'Nivel';
  @override
  String kitLevel(KitLevel level) => switch (level) {
        KitLevel.easy => 'Fácil',
        KitLevel.medium => 'Medio',
        KitLevel.hard => 'Difícil',
      };
  @override
  String get bots => 'Bots';
  @override
  String get custom => 'Personalizado';
  @override
  String get coach => 'Coach';
  @override
  String winChance(String pct) => 'Gana $pct';
  @override
  String pointsValue(String x) => '$x pts';
  @override
  String betsValue(String x) => '$x apuestas';
  @override
  String net(String x) => 'Neto $x';
  @override
  String moveNumber(int n) => 'Jugada $n';
  @override
  String get pass => 'Paso';
  @override
  String trick(int n) => 'Baza $n';
  @override
  String get allCards => 'Todas las cartas';
  @override
  String handOrder(HandOrder order) => switch (order) {
        HandOrder.rank => 'Valor',
        HandOrder.suit => 'Palo',
        HandOrder.own => 'Ordenar',
      };
  @override
  String get showCards => 'Mostrar cartas';
  @override
  String get visibleToAll => 'Todos ven esta carta';
  @override
  String rangeTitle(String name, int cards) => '$name · $cards ${cards == 1 ? 'carta' : 'cartas'}';
  @override
  String get rangeRanks => 'Cartas que puede tener';
  @override
  String get rangeCombos => 'Combinaciones posibles';
  @override
  String get rangeWorking => 'Calculando…';
  @override
  String get rangeFailed => 'No se pudo calcular. Toca el asiento otra vez.';
  @override
  String get rangeNone => 'Ahora no hay rango que calcular.';
  @override
  String rangeSamples(int n) => 'De $n repartos posibles, solo con lo que has visto.';
  @override
  String get playTo => 'Jugar a';
  @override
  String get noLimit => 'Sin límite';
  @override
  String get scaleWithPlayers => 'Según jugadores';
  @override
  String get scores => 'Puntos';
  @override
  String get total => 'Suma';
  @override
  String get newMatch => 'Nueva partida';
  @override
  String dealNumber(int n) => 'Mano $n';
  @override
  String target(int points) => 'A $points';
  @override
  String get youWinMatch => 'Ganas la partida';
  @override
  String winsMatch(String name) => '$name gana la partida';
  @override
  String matchTie(List<String> names) => 'Empate: ${names.join(' y ')}';
  @override
  String term(KitTerm term) => switch (term) {
        KitTerm.training => 'Entrenamiento',
        KitTerm.freePlay => 'Juego libre',
        KitTerm.coach => 'Coach',
        KitTerm.grades => 'Notas',
        KitTerm.score => 'Puntuación',
        KitTerm.level => 'Nivel',
        KitTerm.lastGame => 'Última partida',
        KitTerm.showCards => 'Mostrar cartas',
        KitTerm.range => 'Rango',
        KitTerm.playTo => 'Jugar a',
      };
  @override
  String definition(KitTerm term) => switch (term) {
        KitTerm.training => 'Cada jugada tuya se califica frente al coach, con una puntuación. '
            'Se elige antes de la partida.',
        KitTerm.freePlay => 'Juega sin notas ni coach. Se elige antes de la partida.',
        KitTerm.coach => 'Muestra las mejores jugadas en tu posición y cuánto vale cada una. '
            'Su botón de arriba lo muestra u oculta.',
        KitTerm.grades => 'Óptimo, Bueno, Imprecisión, Error, Error grave: cuánto pierde una jugada '
            'frente a la mejor del coach.',
        KitTerm.score => 'De 0 a 100 por cada jugada calificada: 100 si no pierde nada. '
            'El panel muestra tu media.',
        KitTerm.level => 'Lo bien que juegan los bots.',
        KitTerm.lastGame => 'Tu partida más reciente, guardada tras cada jugada, para repasarla jugada a jugada.',
        KitTerm.showCards => 'Solo en Entrenamiento: las cartas de los rivales boca arriba, para aprender. '
            'El coach y tus notas nunca las usan. Está en el menú.',
        KitTerm.range => 'Lo que un rival puede tener, según lo que has visto: la probabilidad de cada carta '
            '(1+, 2+, 3+ o las 4 de un valor) y de cada combinación. Toca su asiento para verlo.',
        KitTerm.playTo => 'Una partida son varias manos; los puntos se suman hasta que alguien llega a este total. '
            'Según jugadores lo sube en una mesa más grande (y lo baja en una más pequeña), '
            'para que con más jugadores la partida no acabe antes.',
      };
}
