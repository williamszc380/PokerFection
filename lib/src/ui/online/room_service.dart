/// The room the app is in, for the app's whole life rather than one
/// screen's: its connection, the hosting (on this device), and the running
/// game's controller, which keeps playing (the host's bots, its Ready)
/// whether or not the table is on screen. Screens show the room; none owns
/// it, so leaving a screen never takes anyone out of the room.
library;

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/app_settings.dart';
import '../../app/keep_awake.dart';
import '../../gto/gto_solutions.dart';
import '../../kit/jobs/jobs.dart';
import '../../l10n/strings.dart';
import '../../online/games/game_envelope.dart';
import '../../online/online_client.dart';
import '../../online/protocol.dart';
import '../../online/room_host.dart';
import '../kit/kit_scope.dart';
import '../table_controller.dart';
import 'online_game_ui.dart';
import 'online_game_uis.dart';
import 'room_lobby_screen.dart';
import 'room_scope.dart';
import 'room_shell.dart';
import 'runner_client.dart';

/// Where the app is with its room (one at a time).
enum RoomStage {
  /// In no room.
  none,

  /// In a room.
  open,

  /// The room closed, or the connection was lost: the room's card says
  /// why until OK ([RoomService.dismiss]).
  ended,
}

/// The app's room: created once by the app, above its Navigator (see
/// RoomScope), so it outlives every screen.
///
/// - Play Online opens the connection and hands it over ([enter]); the
///   room then stays until Leave Room or Close Room ([leave]), or until it
///   ends ([RoomStage.ended], then [dismiss]).
/// - While hosting on this device it keeps the screen on, hears the Wi-Fi's
///   room searches, and closes the room properly when the app quits.
/// - The host picks games on Home ([hostPick]); when the room's game
///   changes, everyone follows: the room's table opens (RoomGamePage: the
///   game's seats, then the game itself), over whatever is open.
/// - When a game starts it makes the game's controller (poker's table
///   controller, or for the other games a [RunnerClient]) and takes
///   everyone not at the room's table there. The controller lives here, so
///   the host's bots keep playing while the host is on another screen; off
///   screen it makes no sound and the spectator's coach rests. When the
///   game is over its end shows for [gameOverShown], then the room's table
///   shows the seats again and the room takes the connection back.
class RoomService extends ChangeNotifier {
  RoomService({required this.settings, this.solutions, Map<String, OnlineGameUi>? gameUis, this._newJobs})
    : gameUis = gameUis ?? onlineGameUis;

  /// The playback speed (and language) for the table.
  final AppSettings settings;

  /// Where the table's solves come from (the app-wide cache by default;
  /// tests give a fast one).
  final GtoSolutions? solutions;

  /// The games other than Hold'em this app shows online (onlineGameUis;
  /// tests give their own).
  final Map<String, OnlineGameUi> gameUis;

  /// Background jobs for a game other than Hold'em (its bots on the host's
  /// device, a spectator's coach): the app's (KitScope) by default.
  final Jobs Function()? _newJobs;

  /// How long the game-over banner shows before the table closes.
  static const gameOverShown = Duration(seconds: 4);

  /// The app's Navigator (MaterialApp.navigatorKey).
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey();

  /// The app's snack bars (MaterialApp.scaffoldMessengerKey).
  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey();

  /// Follows the app's routes (MaterialApp.navigatorObservers).
  late final NavigatorObserver observer = _TopPageObserver(this);

  /// Keeps the app's screens (their Navigator) when the room appears,
  /// goes or changes its layout (RoomShell).
  final GlobalKey appKey = GlobalKey();

  /// Lights up the docked panel's header for a moment (Home's room button
  /// when the panel is already in view): counts up each time.
  final ValueNotifier<int> flash = ValueNotifier(0);

  /// How the shell shows the room now (set by RoomShell as it lays out).
  RoomShellMode shellMode = RoomShellMode.none;

  /// What the user is typing in the room's chat: one draft for every chat
  /// box of the room (the docked panel, the rail's or bar's, the Room tab),
  /// so it stays as the room's screens change (the dock stepping aside, the
  /// seats turning into the game, the panel closing when the game starts).
  final TextEditingController chatDraft = TextEditingController();

  /// The tab the room's table shows (0: Game, 1: Room), kept as the table
  /// turns from the seats into the game and back.
  int frameTab = 0;

  OnlineClient? _client;
  RoomStage _stage = RoomStage.none;
  OnlineTableController? _table;
  RunnerClient? _runner;
  Route<Object?>? _gameRoute;
  Route<Object?>? _panelRoute;
  bool _leaving = false;
  int? _lastSeat;

  /// The room's game when last seen (its key): a new one opens its table.
  String? _lastGame;
  int _seenChat = 0;
  StreamSubscription<void>? _changes;
  AppLifecycleListener? _lifecycle;
  Timer? _gameOver;

  /// The app's routes, bottom first (from the observer), and those that
  /// show the room themselves (see [claim]).
  final List<Route<Object?>> _stack = [];

  /// How many widgets claim each route (the room's table changes in place: the next screen claims before
  /// the last one lets go).
  final Map<Route<Object?>, int> _claimed = {};

  /// The room's connection; null in no room.
  OnlineClient? get client => _client;

  RoomStage get stage => _stage;
  RoomState? get room => _client?.room;

  /// The shell shows the room (an ended one too, with why).
  bool get inRoom => _stage != RoomStage.none;
  bool get isHost => _client?.isHost ?? false;

  /// Poker's game while one runs.
  OnlineTableController? get table => _table;

  /// Another game's, while one runs.
  RunnerClient? get runner => _runner;

  bool get gameRunning => _table != null || _runner != null;

  /// The running game's room has ended (closed, or the connection lost).
  bool get _gameEnded => (_table?.ended ?? false) || (_runner?.ended ?? false);

  /// The top screen shows the room itself (the game's two tabs).
  bool get gameOnScreen {
    final top = _topPage;
    return top != null && _claimed.containsKey(top);
  }

  /// The room's table is open (on top or under another).
  bool get gameOpen => _gameRoute?.isActive ?? false;

  /// The room plays a game (picked, running or not): its table can open.
  bool get hasGame => _client?.room?.game != null;

  /// The rail's or bar's panel is open over the screen.
  bool get panelOpen => _panelRoute?.isActive ?? false;

  /// Others' chat messages since the chat was last on screen.
  int get unreadChat => _client?.chat.where((line) => line.n > _seenChat && !line.you).length ?? 0;

  /// Where dialogs from the docked panel go: over the app's screens.
  BuildContext? get dialogContext => navigatorKey.currentState?.overlay?.context;

  Route<Object?>? get _topPage {
    for (final route in _stack.reversed) {
      if (route is PageRoute) return route;
    }
    return null;
  }

  NavigatorState? get _nav => navigatorKey.currentState;

  /// Takes the room [client] is in (it opened: created, joined or back),
  /// from Play Online. One room at a time.
  void enter(OnlineClient client) {
    assert(_stage == RoomStage.none, 'already in a room');
    _client = client;
    _stage = RoomStage.open;
    _leaving = false;
    chatDraft.clear();
    frameTab = 0;
    _seenChat = client.chat.lastOrNull?.n ?? 0;
    _lastGame = client.room?.game?.key;
    _changes = client.changes.listen((_) => _onChanges());
    // After this frame: Play Online goes first; then the room's game, if it has one, opens its table.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_client != client || _stage != RoomStage.open) return;
      if (!gameRunning) client.attach(_onMessage);
      if (hasGame) _follow();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
    // Back on screen, a dropped connection is tried again at once.
    _lifecycle = AppLifecycleListener(onResume: client.reconnectNow);
    if (client.host case final host?) _whileHosting(host);
    notifyListeners();
  }

  /// Leave Room (a guest) or Close Room (the host: the room ends for
  /// everyone). Asks nothing: the screens ask first.
  Future<void> leave() async {
    final client = _client;
    if (client == null) return;
    _leaving = true;
    _closePanel();
    _endGameView(pop: true);
    unawaited(_changes?.cancel());
    // Out at once (the room's views go); the connection closes meanwhile, the host's room with it.
    _reset();
    notifyListeners();
    await client.close(leave: true);
  }

  /// OK on the ended room's card: in no room again.
  void dismiss() {
    if (_stage != RoomStage.ended) return;
    _closePanel();
    _endGameView(pop: true);
    unawaited(_changes?.cancel());
    _reset();
    notifyListeners();
  }

  /// To the room's table: back to it when it is under others (History, the
  /// glossary), else opened.
  void watch() {
    _closePanel();
    final nav = _nav, route = _gameRoute;
    if (nav == null || !hasGame) return;
    if (route != null && route.isActive) {
      nav.popUntil((r) => r == route);
    } else {
      _pushGame();
    }
  }

  /// Start was pressed (the host) or a seat asked for. Nothing more to do
  /// since v2.1: when the game starts everyone goes to its table anyway.
  void expectGame() {}

  /// The host picked [key]'s game the usual way (Home, the game's Play or
  /// Hold'em's setup): it becomes the room's game, with [setup] (another
  /// game's) or [holdem] (Hold'em's rules), and its table opens. Everyone
  /// else follows when the room says so. Only in the lobby (between games).
  void hostPick(String key, {RoomSettings? holdem, Map<String, Object?>? setup}) {
    final client = _client, room = client?.room;
    if (client == null || room == null || !client.isHost || room.phase != RoomPhase.lobby) return;
    final same = room.game?.key == key;
    if (!same || (setup != null && key != holdemKey)) {
      client.send(ChooseGame(game: key, setup: key == holdemKey ? null : setup));
    }
    if (key == holdemKey && holdem != null) client.send(ChangeSettings(settings: holdem));
    // The same game: its table now; a new one opens for everyone (this app too) when the room says so.
    if (same) watch();
  }

  /// Home's room button, the rail and the bar: the room over the screen
  /// (once); docked, where it already is, its header lights up.
  void openPanel() {
    if (!inRoom) return;
    switch (shellMode) {
      case RoomShellMode.docked:
        flash.value++;
      case RoomShellMode.rail || RoomShellMode.bar:
        final nav = _nav;
        if (nav == null || panelOpen) return;
        final route = RoomPanelRoute(rooms: this, fromBottom: shellMode == RoomShellMode.bar);
        _panelRoute = route;
        unawaited(nav.push(route));
        markChatSeen();
      case RoomShellMode.none:
        break;
    }
  }

  /// The chat was on screen: what came so far is seen.
  void markChatSeen() {
    final last = _client?.chat.lastOrNull?.n ?? _seenChat;
    if (last == _seenChat) return;
    _seenChat = last;
    _notifySoon();
  }

  /// [route] shows the room itself ([on]; RoomTabHost), so the shell hides
  /// its dock while it is the top screen; or no longer.
  void claim(Route<Object?> route, bool on) {
    final before = _claimed[route] ?? 0;
    final after = on ? before + 1 : (before > 0 ? before - 1 : 0);
    if (after == 0) {
      _claimed.remove(route);
    } else {
      _claimed[route] = after;
    }
    final changed = (before > 0) != (after > 0);
    if (changed) _notifySoon();
  }

  // ---------------------------------------------------------------------------
  // The room's messages, and the game's screen
  // ---------------------------------------------------------------------------

  void _onChanges() {
    final client = _client;
    if (client == null) return;
    final over = client.status == OnlineStatus.closed || client.status == OnlineStatus.lost;
    if (over && !_leaving && _stage == RoomStage.open) {
      _stage = RoomStage.ended;
      _gameOver?.cancel();
      _gameOver = null;
      // The table says so itself, and its OK closes it: then the controller goes.
      if (!gameOpen) _dropTable();
    }
    // The host picked a game (or another): everyone goes to its table.
    final game = client.room?.game?.key;
    if (_stage == RoomStage.open && game != null && game != _lastGame) {
      _lastGame = game;
      _follow();
    }
    _lastGame = game ?? _lastGame;
    // Seated while the table isn't open (queued from the panel on another screen): to the table, or the
    // hand would wait for this player's turns with nothing on screen to play them.
    if (gameRunning && _stage == RoomStage.open) {
      final seat = client.mySeat;
      if (_lastSeat == null && seat != null && !gameOpen) {
        _closePanel();
        _pushGame();
      }
      _lastSeat = seat;
    }
    notifyListeners();
  }

  /// What the room says while no game's controller holds the connection.
  void _onMessage(ServerMessage message) {
    final client = _client;
    if (client == null || _stage != RoomStage.open) return;
    final s = S.forLanguage(settings.language);
    final NextHand lineup;
    switch (message) {
      case NextHand():
        lineup = message;
      case Snapshot(hand: final hand?):
        lineup = hand.lineup;
      case Snapshot(next: final next?):
        lineup = next;
      case GameOver(:final seat, :final name):
        _snack(s.gameOver(name, you: seat != null && seat == client.mySeat));
        return;
      case PlayerRemoved(:final name):
        _snack(s.removedNotice(name));
        return;
      case ServerGameMessage(:final game, :final gv, body: final EnvelopeState state):
        // Another game's first view: played here if this app shows it (else the room says to update).
        final ui = gameUis[game];
        if (ui == null || ui.gv != gv) return;
        client.detach();
        final runner = RunnerClient(client, ui: ui, newJobs: _jobs, start: state);
        _runner = runner;
        _lastSeat = client.mySeat;
        runner.addListener(_onGame);
        _land();
        notifyListeners();
        return;
      default:
        return;
    }
    client.detach();
    final table = OnlineTableController(
      client,
      lineup,
      start: message is Snapshot ? message : null,
      speed: settings.speed,
      solutions: solutions,
    );
    _table = table;
    _lastSeat = client.mySeat;
    table.addListener(_onGame);
    _land();
    notifyListeners();
  }

  /// A new Jobs for another game's controller: the app's (KitScope above
  /// the Navigator), or the test's.
  Jobs _jobs() {
    if (_newJobs case final make?) return make();
    final context = navigatorKey.currentContext;
    return context == null ? Jobs.inline() : KitScope.of(context).newJobs();
  }

  void _snack(String text) => messengerKey.currentState?.showSnackBar(SnackBar(content: Text(text)));

  /// The game started (or the user came into it): everyone follows the
  /// host to the room's table, over whatever is open (a solo game stays
  /// under it); one already there stays (the table turns into the game).
  void _land() {
    _closePanel();
    _pushGame();
  }

  /// The room's game changed (or the user came into a room with one):
  /// to its table, closing what is over it, or opening it.
  void _follow() => watch();

  void _pushGame() {
    final nav = _nav;
    if (nav == null || !hasGame || gameOpen) return;
    final route = MaterialPageRoute<void>(
      settings: const RouteSettings(arguments: RoomRoute.game),
      builder: (_) => RoomGamePage(rooms: this),
    );
    _gameRoute = route;
    unawaited(nav.push(route));
  }

  /// The game is over (poker: its GameOver; another game: the room back in
  /// its lobby): its end shows a moment, then the room's table shows the
  /// seats again and the room takes the connection back (a new game's
  /// first round may be waiting in it already).
  void _onGame() {
    final table = _table, runner = _runner;
    final Object game;
    if (table != null) {
      if (table.ended || table.gameOver == null) return;
      game = table;
    } else if (runner != null) {
      if (runner.ended || !runner.gameOver) return;
      game = runner;
    } else {
      return;
    }
    if (_gameOver != null) return;
    _gameOver = Timer(gameOverShown, () {
      _gameOver = null;
      if ((_table ?? _runner) != game || _gameEnded) return;
      // What was opened over the table (History, the glossary) closes; the table shows the seats again.
      final nav = _nav, route = _gameRoute;
      if (nav != null && route != null && route.isActive) nav.popUntil((r) => r == route);
      _dropTable();
      final client = _client;
      if (client != null && _stage == RoomStage.open) client.attach(_onMessage);
      notifyListeners();
    });
  }

  /// Closes the game's screen ([pop]: with whatever is open over it) and
  /// lets its controller go, keeping the connection.
  void _endGameView({required bool pop}) {
    _gameOver?.cancel();
    _gameOver = null;
    final nav = _nav, route = _gameRoute;
    if (pop && nav != null && route != null && route.isActive) {
      nav.popUntil((r) => r == route);
      nav.pop();
    }
    if (pop) _gameRoute = null;
    _dropTable(route);
  }

  /// The game's controller hands the connection back and goes, once its
  /// screen is gone: after the route's closing animation when [route] is
  /// being popped (it is drawn until then), or after the next frame when
  /// the room's table stays and shows the seats instead.
  void _dropTable([Route<Object?>? route]) {
    final table = _table, runner = _runner;
    if (table == null && runner == null) return;
    _table = null;
    _runner = null;
    _lastSeat = null;
    table?.removeListener(_onGame);
    runner?.removeListener(_onGame);
    table?.handBack();
    runner?.handBack();
    void dispose() {
      table?.dispose();
      runner?.dispose();
    }

    if (route is TransitionRoute<Object?> && !route.isActive) {
      unawaited(route.completed.then((_) => dispose(), onError: (Object _) => dispose()));
    } else if (route == null && !gameOpen) {
      dispose();
    } else {
      // The room's table rebuilds without the game's screen first.
      SchedulerBinding.instance.addPostFrameCallback((_) => dispose());
      SchedulerBinding.instance.ensureVisualUpdate();
    }
  }

  /// Closes the rail's or bar's panel, with any dialog opened over it.
  void _closePanel() {
    final nav = _nav, route = _panelRoute;
    _panelRoute = null;
    if (nav == null || route == null || !route.isActive) return;
    nav.popUntil((r) => r == route);
    nav.removeRoute(route);
  }

  void _reset() {
    _gameOver?.cancel();
    _gameOver = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _changes = null;
    _client = null;
    _table = null;
    _runner = null;
    _gameRoute = null;
    _lastGame = null;
    _stage = RoomStage.none;
    _leaving = false;
    _lastSeat = null;
    chatDraft.clear();
    frameTab = 0;
  }

  /// While [host] serves the room: the screen stays on and the Wi-Fi's
  /// broadcasts are heard (phones), and closing the app closes the room
  /// properly (everyone is told, the room's name at the meeting service is
  /// given back, the router's port closes).
  void _whileHosting(RoomHost host) {
    unawaited(keepScreenOn(true));
    unawaited(hearRoomSearches(true));
    final exit = AppLifecycleListener(
      onExitRequested: () async {
        try {
          await host.stop().timeout(const Duration(seconds: 2));
        } on Object {
          // Closing anyway.
        }
        return AppExitResponse.exit;
      },
    );
    unawaited(
      host.stopped.whenComplete(() {
        exit.dispose();
        unawaited(keepScreenOn(false));
        unawaited(hearRoomSearches(false));
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // The app's routes
  // ---------------------------------------------------------------------------

  bool _notifying = false;

  /// Tells the shell after this frame (routes change during builds).
  void _notifySoon() {
    if (_notifying) return;
    _notifying = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifying = false;
      notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _gone(Route<Object?> route) {
    _stack.remove(route);
    _claimed.remove(route);
    if (route == _panelRoute) _panelRoute = null;
    if (route == _gameRoute) {
      _gameRoute = null;
      // The table's own OK after the room ended: the controller goes now.
      if (_stage != RoomStage.open || _gameEnded) _dropTable(route);
    }
    _notifySoon();
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _gameOver?.cancel();
    _lifecycle?.dispose();
    flash.dispose();
    super.dispose();
  }
}

/// Follows the app's Navigator for [RoomService]: which page is on top.
class _TopPageObserver extends NavigatorObserver {
  _TopPageObserver(this.rooms);

  final RoomService rooms;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    rooms._stack.add(route);
    rooms._notifySoon();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => rooms._gone(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => rooms._gone(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : rooms._stack.indexOf(oldRoute);
    if (oldRoute != null) rooms._gone(oldRoute);
    if (newRoute != null) {
      if (i >= 0 && i <= rooms._stack.length) {
        rooms._stack.insert(i, newRoute);
      } else {
        rooms._stack.add(newRoute);
      }
    }
    rooms._notifySoon();
  }
}
