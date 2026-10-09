import '../bots/bot.dart';
import '../engine/events.dart';
import '../engine/hand_evaluator.dart';
import '../engine/rules.dart';
import '../gto/preflop/preflop_charts.dart';
import '../gto/hand_read.dart';
import '../gto/spot_strategy.dart';
import '../online/protocol.dart' show CloseReason, JoinError;
import '../online/room_host.dart' show InternetAccess;
import '../ui/table_controller.dart' show OnlineNotice, PlaybackSpeed;
import 'strings.dart';

class StringsEs extends S {
  const StringsEs();

  @override
  String get play => 'Jugar';
  @override
  String get settings => 'Ajustes';

  @override
  String get handRankings => 'Ranking de manos';
  @override
  String oneIn(String x) => '1 de cada $x';
  @override
  String get rankingOddsNote => 'Probabilidad de terminar con cada mano usando 7 cartas: tus 2 y las 5 de la mesa.';
  @override
  String get invite => 'Invitar';
  @override
  String get copyInviteLink => 'Copiar enlace de invitación';
  @override
  String get noInvite => 'No hay invitación ni código de sala en el portapapeles.';
  @override
  String get inviteThisComputer => 'Este servidor está en esta computadora, así que solo ella puede unirse.';
  @override
  String get pasteBlocked => 'Esta página no puede leer el portapapeles: pega en la casilla (Ctrl+V).';
  @override
  String get roomCodeOrLink => 'Código de sala o invitación';
  @override
  String get emptyToCreate => 'Déjalo vacío para crear una sala.';
  @override
  String get joinRoom => 'Unirse';
  @override
  String get notACode => 'Eso no es un código de sala ni una invitación.';
  @override
  String get royalFlush => 'Escalera real';
  @override
  String handCategory(HandCategory category) => switch (category) {
        HandCategory.highCard => 'Carta alta',
        HandCategory.pair => 'Pareja',
        HandCategory.twoPair => 'Doble pareja',
        HandCategory.trips => 'Trío',
        HandCategory.straight => 'Escalera',
        HandCategory.flush => 'Color',
        HandCategory.fullHouse => 'Full',
        HandCategory.quads => 'Póker',
        HandCategory.straightFlush => 'Escalera de color',
      };

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
  String get simple => 'Simple';
  @override
  String get advanced => 'Avanzado';
  @override
  String get freePlay => 'Juego libre';
  @override
  String get editTable => 'Editar mesa';
  @override
  String get solo => 'Solo';
  @override
  String get multiplayer => 'Multijugador';
  @override
  String get guides => 'Guías';
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
  String get preflop => 'Preflop';
  @override
  String get postflop => 'Postflop';
  @override
  String get cancel => 'Cancelar';
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
  String get checkFold => 'Pasar/Retirarse';
  @override
  String get callAny => 'Igualar cualquiera';
  @override
  String get playsAtYourTurn => 'Se juega en tu turno';
  @override
  String get potWord => 'bote';

  @override
  String potOdds(int percent) => 'Pot odds $percent%';
  @override
  String get showGto => 'Ver GTO';
  @override
  String get approxMultiway => 'Respuesta aproximada: bote multiway';
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
  String mistakeReason(MistakeKind kind, SpotActionKind gto, String amount) {
    final move = switch (gto) {
      SpotActionKind.fold => 'se retira',
      SpotActionKind.check => 'pasa',
      SpotActionKind.call => 'iguala',
      SpotActionKind.raise => 'sube a $amount',
      SpotActionKind.allIn => 'va all-in',
    };
    return switch (kind) {
      MistakeKind.tooTight => 'Demasiado conservador: GTO $move aquí.',
      MistakeKind.tooLoose => 'Demasiado suelto: GTO $move aquí.',
      MistakeKind.tooPassive => 'Demasiado pasivo: GTO $move aquí.',
      MistakeKind.tooAggressive => 'Demasiado agresivo: GTO $move aquí.',
      MistakeKind.wrongSize => 'Bien la jugada, mal el tamaño: GTO $move.',
    };
  }
  @override
  String mistakeWhy(Reason r, String hand) => switch (r.kind) {
        ReasonKind.behind =>
          'El ${r.percent}% de sus manos te gana${r.threat == null ? '' : ', sobre todo ${_threats(r.threat!)}'}.',
        ReasonKind.ahead => 'Tu mano gana al ${r.percent}% de las suyas.',
        ReasonKind.potOdds =>
          'Para igualar basta ganar el ${r.odds}% de las veces, y ganas al ${r.percent}% de sus manos.',
        ReasonKind.potOddsPreflop => 'Para igualar basta ganar el ${r.odds}% de las veces.',
        ReasonKind.flushDraw => 'Tienes proyecto de color.',
        ReasonKind.straightDraw => 'Tienes proyecto de escalera.',
        ReasonKind.bluff => 'De farol: una subida hace retirarse a manos mejores.',
        ReasonKind.keepWorseIn => 'Las manos peores se retirarían ante una subida; así siguen en la mano.',
        ReasonKind.strongStart => '$hand está entre el ${r.percent}% de mejores manos iniciales.',
        ReasonKind.weakStart => '$hand está entre el ${r.percent}% de peores manos iniciales.',
      };

  static String _threats(HandCategory c) => switch (c) {
        HandCategory.highCard => 'cartas más altas',
        HandCategory.pair => 'parejas mejores',
        HandCategory.twoPair => 'dobles parejas',
        HandCategory.trips => 'tríos',
        HandCategory.straight => 'escaleras',
        HandCategory.flush => 'colores',
        HandCategory.fullHouse => 'fulls',
        HandCategory.quads => 'póqueres',
        HandCategory.straightFlush => 'escaleras de color',
      };
  @override
  String unavailable(Unavailable reason) => switch (reason) {
        Unavailable.checkIsFree => 'Puedes pasar gratis',
        Unavailable.raisingNotAllowed => 'No se puede subir',
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
  String get playOnline => 'Jugar en línea';
  @override
  String get yourName => 'Tu nombre';
  @override
  String get enterName => 'Escribe un nombre';
  @override
  String get createRoom => 'Crear sala';
  @override
  String get roomCode => 'Código de sala';
  @override
  String get join => 'Unirse';
  @override
  String get server => 'Servidor';
  @override
  String get serverHint => 'Vacío: las salas van en el dispositivo del anfitrión.';
  @override
  String get startingRoom => 'Abriendo la sala…';
  @override
  String get cantStartRoom => 'No se puede abrir una sala en este dispositivo.';
  @override
  String get cantHostInBrowser => 'Las salas se crean en la app (Windows, Android, iPhone). Aquí puedes unirte a una.';
  @override
  String get websiteCantJoin =>
      'Este sitio web no puede llegar a una sala en el dispositivo de otra persona: abre la dirección para navegador de la invitación.';
  @override
  String get roomNotNearby => 'No hay ninguna sala con ese código en esta red: pide la invitación al anfitrión.';
  @override
  String sameWifi(bool yes) => yes ? 'Misma Wi-Fi: sí' : 'Misma Wi-Fi: sin red';
  @override
  String internetStatus(InternetAccess access) => switch (access) {
        InternetAccess.checking => 'Internet: comprobando…',
        InternetAccess.ready => 'Internet: lista',
        _ => 'Internet: no disponible',
      };
  @override
  String get internetByHand => 'Internet: puesta a mano';
  @override
  String internetHelp({
    required InternetAccess access,
    required int port,
    String? address,
    String? byHand,
    required bool windows,
    required bool phone,
  }) =>
      [
        switch (access) {
          InternetAccess.checking => 'La app le está pidiendo a tu router que deje entrar a amigos desde internet.',
          InternetAccess.ready => 'Tu router abrió el puerto $port: tus amigos en internet pueden unirse con la '
              'invitación.',
          InternetAccess.noRouter => 'Ningún router respondió a la configuración automática (UPnP está apagado o el '
              'router no lo tiene).',
          InternetAccess.refused => 'Tu router no quiso abrir el puerto.',
          InternetAccess.notPublic => 'Tu router no tiene una dirección pública propia: tu proveedor de internet la '
              'comparte (CGNAT) o hay otro router delante.',
          InternetAccess.byHand => 'En iPhone y iPad la app no puede configurar el router.',
        },
        if (access != InternetAccess.ready)
          'Para abrirlo a mano: en la configuración del router, redirige el puerto TCP $port a '
              '${address ?? 'este dispositivo'}. Luego escribe la IP pública del router en Dirección pública, en la '
              'sala: las invitaciones la llevan.',
        if (byHand != null)
          'Puesta a mano: las invitaciones llevan $byHand. La app no puede comprobarla: pide a un amigo de fuera '
              'que abra http://$byHand/health.',
        'En la misma Wi-Fi siempre funciona.',
        if (windows) 'La primera vez, el Firewall de Windows pregunta si PokerFection puede usar la red: permítelo.',
        'Algunos proveedores de internet (direcciones compartidas, CGNAT) y los datos móviles hacen imposible jugar por '
            'internet sin un servidor externo.',
        if (phone)
          'Mantén la app abierta en pantalla mientras eres anfitrión: la sala se detiene si la app se cierra o pasa a '
              'segundo plano. Con datos móviles, los amigos en internet casi nunca pueden unirse.',
      ].join('\n\n');
  @override
  String get publicAddress => 'Dirección pública';
  @override
  String get notPublicAddress => 'Escribe tu IP pública, como 203.0.113.7';
  @override
  String publicAddressHelp({required int port, String? address, required bool windows}) => [
        'Para un router que no abre el puerto solo (UPnP apagado). Ábrelo a mano una vez: en la página de '
            'configuración o la app del router, busca Redirección de puertos y redirige el puerto TCP $port a '
            '${windows ? 'esta computadora' : 'este dispositivo'}${address == null ? '' : ', $address'}.',
        'Luego escribe aquí tu IP pública. La app o la página de estado del router la muestra (dirección IP WAN o '
            'de Internet), o busca "cuál es mi IP". Si el router lleva otro puerto de fuera al $port, añádelo: '
            '203.0.113.7:47500.',
        'Entonces las invitaciones la llevan, y el enlace para navegador también. La app no puede comprobarla: '
            'pide a un amigo de fuera que abra http://<IP pública>:$port/health. Casi todas las IP públicas cambian '
            'de vez en cuando: revísala antes de jugar.',
      ].join('\n\n');
  @override
  String get connecting => 'Conectando…';
  @override
  String joinError(JoinError? error) => switch (error) {
        JoinError.upgrade => 'Actualiza la app para jugar',
        JoinError.roomNotFound => 'Sala no encontrada',
        JoinError.tableFull => 'Mesa llena',
        JoinError.rateLimited => 'Demasiados intentos: espera un minuto',
        JoinError.serverFull => 'Servidor lleno: prueba más tarde',
        JoinError.internal => 'Error del servidor',
        JoinError.roomGone => 'La sala se cerró',
        JoinError.seatGone => 'Estuviste fuera demasiado: vuelve a unirte',
        JoinError.removed => 'El anfitrión te expulsó de la sala',
        null => 'No se puede conectar al servidor',
      };
  @override
  String room(String code) => 'Sala $code';
  @override
  String get copied => 'Copiado';
  @override
  String get shareCode => 'En la misma Wi-Fi basta el código; a los demás mándales la invitación.';
  @override
  String get host => 'Anfitrión';
  @override
  String get botBadge => 'Bot';
  @override
  String get awayBadge => 'Ausente';
  @override
  String get leftBadge => 'Se fue';
  @override
  String get nextHandBadge => 'Próxima mano';
  @override
  String get help => 'Ayuda';
  @override
  String get noHelp => 'Ninguna';
  @override
  String get timeLimit => 'Tiempo';
  @override
  String turnLimit(int seconds) => seconds == 0 ? 'Sin límite' : '$seconds s';
  @override
  String secondsLeft(int seconds) => '$seconds s';
  @override
  String get waitingForHost => 'Esperando al anfitrión…';
  @override
  String get joinNextHand => 'Te sientas en la próxima mano.';
  @override
  String nextHandIn(int seconds) => 'Próxima mano en $seconds s';
  @override
  String onlineNotice(OnlineNotice notice) => switch (notice) {
        OnlineNotice.timesUp => 'Se acabó el tiempo',
        OnlineNotice.refused => 'No permitido: elige otra vez',
        OnlineNotice.outOfSync => 'Desincronizado',
      };
  @override
  String get hostAway => 'El anfitrión está ausente: los bots pasan o se retiran.';
  @override
  String get connectionLost => 'Conexión perdida';
  @override
  String get reconnecting => 'Reconectando…';
  @override
  String rejoinRoom(String code) => 'Volver a la sala $code';
  @override
  String closed(CloseReason? reason) => switch (reason) {
        CloseReason.roomClosed => 'El anfitrión cerró la sala.',
        CloseReason.serverRestart => 'El servidor se reinició.',
        CloseReason.replaced => 'Tu asiento pasó a otra ventana.',
        CloseReason.roomError => 'La sala se cerró por un error.',
        CloseReason.idle => 'La sala se cerró: hacía mucho que no se repartía.',
        CloseReason.removed => 'El anfitrión te expulsó de la sala.',
        null => 'La sala se cerró.',
      };
  @override
  String get closeRoom => 'Cerrar sala';
  @override
  String get tableSettings => 'Mesa';
  @override
  String get fromNextHand => 'Los cambios valen desde la próxima mano.';
  @override
  String get leave => 'Salir';
  @override
  String get leaveTable => '¿Dejar la mesa?';
  @override
  String leaveWarning({required bool host}) =>
      host ? 'La sala se cierra para todos.' : 'Tu asiento queda libre desde la próxima mano.';
  @override
  String get seats => 'Asientos';
  @override
  String get emptySeat => 'Asiento libre';
  @override
  String get addBot => 'Añadir bot';
  @override
  String get removeBot => 'Quitar';
  @override
  String get leavingBadge => 'Se va la próxima mano';
  @override
  String get needPlayers => 'Una mano necesita 2 jugadores: invita a un amigo o añade un bot.';
  @override
  String get waitingForPlayers => 'Esperando jugadores (hacen falta 2)';
  @override
  String get allowSeeCards => 'Se pueden ver las cartas de otros';
  @override
  String get seeCards => 'Ver cartas';
  @override
  String seeCardsQuestion(String name) => '¿Ver las cartas de $name? Todos se enteran.';
  @override
  String get showMyCards => 'Mostrar mis cartas';
  @override
  String showNotice(String? name, String cards) => name == null ? 'Muestras $cards' : '$name muestra $cards';
  @override
  String helpNotice(String? name) => name == null ? 'Usaste la ayuda GTO' : '$name usó la ayuda GTO';
  @override
  String peekNotice(String? name, String? target) => switch ((name, target)) {
        (null, final t?) => 'Miraste las cartas de $t',
        (final n?, null) => '$n miró tus cartas',
        (final n?, final t?) => '$n miró las cartas de $t',
        (null, null) => 'Miraste tus cartas',
      };
  @override
  String get rulesChanged => 'El anfitrión cambió las reglas (desde la próxima mano).';
  @override
  String get rebuys => 'Recompras';
  @override
  String get outBadge => 'Fuera';
  @override
  String outOfChips({required bool rebuys}) =>
      rebuys ? 'Te quedaste sin fichas.' : 'Te quedaste sin fichas: miras hasta que acabe la partida.';
  @override
  String rebuy(String stack) => 'Recomprar $stack';
  @override
  String get lobby => 'Sala';
  @override
  String get watch => 'Mirar';
  @override
  String gameOver(String? winner, {bool you = false}) =>
      you ? '¡Fin de la partida: ganas tú!' : (winner == null ? 'Fin de la partida' : 'Fin de la partida: gana $winner');
  @override
  String get sitOut => 'Ausentarse';
  @override
  String get imBack => 'Estoy de vuelta';
  @override
  String get sittingOutBadge => 'No juega';
  @override
  String get sitOutNextHand => 'Te ausentas desde la próxima mano.';
  @override
  String get youSitOut => 'Te has ausentado: no te reparten cartas.';
  @override
  String get removePlayer => 'Expulsar';
  @override
  String removePlayerQuestion(String name) => '¿Expulsar a $name?';
  @override
  String get removePlayerWarning => 'No podrá volver a unirse a esta sala. Si está en una mano, se va cuando termine.';
  @override
  String removedNotice(String name) => 'Expulsaron a $name';
  @override
  String get chat => 'Chat';
  @override
  String get chatHint => 'Mensaje';
  @override
  String get send => 'Enviar';
  @override
  String get noMessages => 'Todavía no hay mensajes';
  @override
  String get chatTooFast => 'Demasiado rápido: espera un momento';
  @override
  String get drills => 'Ejercicios';
  @override
  String drillsDue(int due) => due == 0 ? 'Ejercicios' : 'Ejercicios (${_pending(due)})';
  @override
  String savedToDrills(String wait, {required bool again}) =>
      again ? 'Ya está en tus ejercicios: vuelve en $wait' : 'Guardado en tus ejercicios: primer repaso en $wait';
  @override
  String drillQueued(String wait, {required bool? right}) => switch (right) {
        true => '✓ Próximo repaso en $wait',
        false => 'Vuelve en $wait',
        null => 'Sin calificar: próximo repaso en $wait',
      };
  @override
  String drillSpot(String grade, int due) => 'Jugada guardada ($grade) · ${_pending(due)}';

  /// "1 pendiente", "3 pendientes".
  static String _pending(int due) => due == 1 ? '1 pendiente' : '$due pendientes';
  @override
  String randomHands(String? next) => next == null
      ? 'Aún no hay errores guardados. Repartiendo manos al azar.'
      : '¡Todo al día! Próximo repaso en $next. Repartiendo manos al azar.';
  @override
  String get noSavedMistakes => 'Aún no hay errores guardados';
  @override
  String get playRandomHands => 'Jugar manos al azar';
  @override
  String get savedSpots => 'Jugadas guardadas';
  @override
  String get dueNow => 'Ya toca';
  @override
  String reviewIn(String wait) => 'En $wait';
  @override
  String waitTime(int count, WaitUnit unit) => switch (unit) {
        WaitUnit.minutes => '$count min',
        WaitUnit.hours => '$count h',
        WaitUnit.days => count == 1 ? '1 día' : '$count días',
        WaitUnit.weeks => count == 1 ? '1 semana' : '$count semanas',
        WaitUnit.months => count == 1 ? '1 mes' : '$count meses',
        WaitUnit.years => count == 1 ? '1 año' : '$count años',
      };

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
        GlossarySection.online => 'En línea',
      };

  @override
  String term(GlossaryTerm term) => positionTerms[term] ?? switch (term) {
        GlossaryTerm.training => 'Entrenamiento GTO',
        GlossaryTerm.play => 'Juego libre',
        GlossaryTerm.drills => 'Ejercicios',
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
        GlossaryTerm.preActions => 'Acciones anticipadas',
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
        GlossaryTerm.roomCode => 'Código de sala',
        GlossaryTerm.host => 'Anfitrión',
        GlossaryTerm.hosting => 'Alojar la sala',
        GlossaryTerm.onlineBots => 'Bots',
        GlossaryTerm.timeLimit => 'Tiempo',
        GlossaryTerm.helpLevel => 'Ayuda',
        GlossaryTerm.seeCards => 'Ver cartas',
        GlossaryTerm.rebuys => 'Recompras',
        GlossaryTerm.sitOut => 'Ausentarse',
        GlossaryTerm.chat => 'Chat',
        GlossaryTerm.away => 'Ausente',
        _ => term.name,
      };

  @override
  String definition(GlossaryTerm term) => switch (term) {
        GlossaryTerm.training => 'Juega contra los bots y aprende de GTO. Simple: juega con normalidad; tras un '
            'Error o un Error grave verás la respuesta GTO, y Ver GTO la muestra cuando quieras. Avanzado: en cada '
            'decisión indica con qué frecuencia crees que GTO se retira, iguala o sube (y cuánto), y verás la '
            'respuesta GTO y tu puntuación. Elígelo al preparar la partida. En el preflop los bots juegan GTO; sus '
            'estilos cuentan después del flop.',
        GlossaryTerm.play => 'Juega contra los bots sin puntuaciones, como en una partida real.',
        GlossaryTerm.drills => 'Cada Error o Error grave que cometes en el Entrenamiento GTO (Simple o Avanzado) se '
            'guarda como jugada: la misma mano, hasta esa decisión. Ejercicios (menú principal) vuelve a repartir las '
            'jugadas pendientes, primero las más atrasadas, y califica tu juego como el entrenamiento Simple; Ver GTO '
            'espera a que hayas jugado. Si la juegas bien (Bueno o mejor), vuelve cada vez más tarde: en 1 h, 1 día, '
            '3 días, 1 semana y luego unas 2,5 veces más. Si la juegas mal (o repites el error al entrenar), vuelve '
            'en 10 min. Las jugadas se quedan aunque ya las domines, hasta 256: entonces se van primero las que mejor '
            'conoces. Sin nada pendiente, Ejercicios reparte manos al azar en mesas al azar, y sus errores se suman a '
            'tus ejercicios. ☰ > Jugadas guardadas las muestra todas.',
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
        GlossaryTerm.betSizes => 'Tus opciones de subida siguen una sola regla, antes y después del flop: los '
            'números de Fibonacci en ciegas grandes, 1, 2, 3, 5, 8, 13, 21, 34, 55 BB y así (el total al que '
            'subes), desde la subida mínima hasta el all-in. Con 100 BB y primero en hablar: 2, 3, 5, 8, 13, 21, '
            '34, 55 y 89 BB, más All-in. El all-in cuenta lo que alguien que sigue en la mano puede igualar. Cada '
            'tamaño también se muestra como × la apuesta antes del flop y × bote después.',
        GlossaryTerm.fold => 'Abandonar la mano y las fichas que ya están en el bote.',
        GlossaryTerm.check => 'Pasar sin apostar (solo si nadie ha apostado).',
        GlossaryTerm.call => 'Igualar la apuesta actual.',
        GlossaryTerm.betRaise => 'Poner fichas el primero (apostar) o más que la apuesta actual (subir).',
        GlossaryTerm.open => 'La primera subida antes del flop.',
        GlossaryTerm.limp => 'Igualar la ciega grande antes del flop en lugar de subir.',
        GlossaryTerm.threeBet => 'Las siguientes subidas antes del flop: la ciega grande cuenta como la primera '
            'apuesta y el open como la segunda, así que la resubida es el 3-bet, y así sucesivamente.',
        GlossaryTerm.preActions => 'Mientras otro jugador actúa, marca tu jugada por adelantado: Pasar/Retirarse '
            '(pasa si es gratis; si no, se retira), Pasar (se cancela si alguien apuesta), Igualar la cantidad '
            'indicada (se cancela si cambia la apuesta) o Igualar cualquiera. Se juega en cuanto llega tu turno; '
            'tócala otra vez para cancelarla. Vale hasta que termina la calle. En el entrenamiento Simple la jugada '
            'se sigue puntuando; el Avanzado no las tiene (necesita porcentajes). En línea hacen la partida más '
            'rápida.',
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
        GlossaryTerm.score => 'De 0 a 100. Simple: cada jugada vale 100, menos un punto por cada 0,01 BB que '
            'pierde. Avanzado: la mitad por la coincidencia y la mitad por perder poco EV; cuenta cuánto te '
            'retiras, pasas o igualas, y subes, y los tamaños de subida cuentan solo un 10%. En el historial, un '
            'borde blanco marca las manos en Avanzado.',
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
        GlossaryTerm.roomCode => 'Cinco letras que identifican una sala en línea. Tus amigos se unen con ellas desde '
            'Jugar en línea.',
        GlossaryTerm.host => 'Quien creó la sala: va en su dispositivo. Prepara la mesa, la ayuda y el tiempo, empieza '
            'la partida y juega los bots. El anfitrión puede expulsar a un jugador: toca su asiento en la sala o en '
            '☰ > Editar mesa, y luego Expulsar. Se va enseguida (si está en una mano, cuando termine) y no puede volver '
            'a unirse a la sala. Si el anfitrión se va, la sala se cierra.',
        GlossaryTerm.hosting => 'Crear sala abre la sala en tu dispositivo: se juega a través de la app del anfitrión, '
            'sin servidor externo. Los amigos en la misma Wi-Fi se unen con el código o la invitación; los de fuera, con '
            'la invitación cuando tu router los deja entrar (la app intenta configurarlo: mira Internet en la sala). '
            'Quien no tiene la app abre en el navegador la dirección de la invitación (si la app trae la versión web). '
            'La sala termina cuando el anfitrión se va o cierra la app. La versión del navegador no puede alojar una '
            'sala, solo unirse.',
        GlossaryTerm.onlineBots => 'Una sala nueva solo tiene al anfitrión: los demás asientos están libres. Los amigos '
            'que se unen toman un asiento libre, y el anfitrión puede añadir bots (cada uno con su estilo) o quitarlos. '
            'Cada mano se reparte a los asientos ocupados, así que hacen falta al menos 2 jugadores; con menos, la '
            'partida espera. Unirse, irse, añadir o quitar un bot durante la partida vale desde la próxima mano, y '
            'quien se va deja su asiento libre.',
        GlossaryTerm.timeLimit => 'Cuánto tiene cada jugador para decidir. Si se acaba, el servidor pasa si es gratis '
            'y si no se retira. Sin límite: no hay tiempo máximo.',
        GlossaryTerm.helpLevel => 'La ayuda que recibe toda la mesa, elegida por el anfitrión: Ninguna (como Juego '
            'libre), Simple o Avanzado (como Entrenamiento GTO). En línea, las cartas de los demás quedan ocultas. '
            'Tus opciones salen enseguida y la respuesta de GTO se suma al resolverse (Resolviendo…). Las jugadas se '
            'envían al elegirlas: la puntuación se ve sin detener la mesa, y una jugada hecha antes de la respuesta se '
            'puntúa cuando llega. Todos se enteran cuando un jugador pulsa Ver GTO.',
        GlossaryTerm.seeCards => 'Si el anfitrión lo permite, toca el asiento de otro jugador durante una mano y elige '
            'Ver cartas: sus cartas se ven boca arriba para ti hasta que acabe la mano. Toda la mesa se entera de '
            'quién miró las cartas de quién.',
        GlossaryTerm.rebuys => 'Qué pasa con un jugador que pierde todas sus fichas; lo decide el anfitrión. Con '
            'recompras: elige Recomprar (otra vez el stack inicial, desde la próxima mano) o Salir; los bots recompran '
            'solos. Sin recompras: queda fuera (su asiento dice Fuera) y mira la partida, desde la mesa o la Sala, o '
            'se va. Cuando solo un jugador tiene fichas y nadie puede recomprar, la partida termina: todos vuelven a la '
            'sala, y el anfitrión pulsa Empezar para una partida nueva con stacks nuevos. Con Reiniciar stacks cada '
            'mano nadie se queda sin fichas.',
        GlossaryTerm.sitOut => '☰ > Ausentarse: desde la próxima mano no te reparten cartas, pero conservas tu asiento y '
            'tus fichas y miras la mesa. ☰ > Estoy de vuelta te vuelve a repartir desde la próxima mano. Si reciben '
            'cartas menos de 2 jugadores, la partida espera. A quien se le corta la conexión durante toda una mano se '
            'le ausenta hasta que vuelve.',
        GlossaryTerm.chat => 'Todos en la sala pueden chatear: antes de empezar, y durante la partida desde ☰ > Chat '
            '(también sin fichas). Los mensajes nuevos se ven un momento arriba de la mesa y luego se desvanecen; '
            '☰ > Chat tiene toda la conversación y los mensajes rápidos (un toque envía uno). Hasta 256 caracteres '
            'por mensaje, y como mucho 4 mensajes cada 8 segundos. La sala guarda los últimos 64 mensajes: quien se '
            'une o vuelve los ve.',
        GlossaryTerm.away => 'Si a un jugador se le corta la conexión, conserva su asiento 2 minutos. Mientras, el '
            'servidor pasa o se retira por él a los 3 s (tras una mano entera fuera, queda ausentado hasta que vuelve), y '
            'la partida espera si pueden jugar menos de 2. Su app se '
            'reconecta sola y se pone al día con la mano; si se cerró, puede volver desde Jugar en línea. Mientras el '
            'anfitrión está ausente, los bots pasan o se retiran; si pasa 2 minutos fuera (o cierra la app), la sala '
            'se cierra.',
      };
}
