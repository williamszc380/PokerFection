/// A game other than Hold'em, played in the room on this device: the latest
/// view the room sent (a seat's own, or the spectators'), the player's
/// moves, Ready after each round, the bots the host's device plays, and a
/// spectator's coach. It lives in the app's room (RoomService) while the
/// game runs, whether or not its screen is open.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../kit/coach_answer.dart';
import '../../kit/jobs/jobs.dart';
import '../../kit/jobs/jobs_core.dart';
import '../../kit/seats.dart';
import '../../online/games/game_envelope.dart';
import '../../online/online_client.dart';
import '../../online/protocol.dart';
import 'online_game_ui.dart';

/// One game other than Hold'em in the room, on this device ([ui]: the
/// game's online part).
///
/// - Every view comes whole from the room ([state], newest by round and
///   seq). A seat's view holds its own hidden cards; the spectators' view
///   every person's (the bots' only with the host's switch).
/// - The seated player plays with [move], once per turn.
/// - Once a round is over, a seated player's device says it is ready for
///   the next one.
/// - On the host's device it plays the bots: each bot's turn comes with
///   that bot's own view, which is kept apart (never drawn, never given to
///   the coach); the game's bot job answers it (seeded with a secret of
///   this device's, so nobody else can work its choices out), shown no sooner than
///   [botMinDelay] after the turn opened, or the game's fallback move when
///   the job fails.
/// - A spectator's coach (off until [setCoach]) works out the acting
///   seat's best moves from the view rebuilt from the spectators' view,
///   only while the screen is open ([onScreen]); "—" ([coachHidden]) when
///   that seat's cards are hidden.
/// - When the room goes back to its lobby (the host ended the game) it is
///   over ([gameOver]): nothing more is played here, and the room takes
///   the connection back ([handBack]).
class RunnerClient extends ChangeNotifier {
  RunnerClient(
    this.client, {
    required this.ui,
    required Jobs Function() newJobs,
    EnvelopeState? start,
    int? botSalt,
  }) : _jobs = newJobs(),
       _botSalt = botSalt ?? freshGameSeed() {
    _statusChanges = client.changes.listen((_) => _onChanges());
    if (start != null) _onState(start);
    client.attach(_receive);
  }

  final OnlineClient client;
  final OnlineGameUi ui;
  final Jobs _jobs;
  late final StreamSubscription<void> _statusChanges;

  /// A secret drawn once on this device (the host's), mixed into every
  /// bot's seed. Round, turn and seat are sent to every member, so a seed
  /// made of them alone could be rebuilt by the other players, who could
  /// then replay a bot's choice for each hand it might hold.
  final int _botSalt;

  /// The least time between a bot's turn opening and its move.
  static const botMinDelay = Duration(milliseconds: 600);

  /// The latest view of the round.
  EnvelopeState? state;

  /// The room went back to its lobby: the game is over.
  bool gameOver = false;

  bool _handedBack = false;
  bool _disposed = false;

  /// The turn this device has moved at (once per turn).
  int? _movedAt;

  /// The round this device said it is ready for.
  int _readyFor = 0;

  // The host's device: the bot's turn being played (never drawn).
  EnvelopeBotRequest? _botRequest;
  JobHandle<Object?>? _botJob;
  Timer? _botTimer;

  // A spectator's coach.
  bool _coachOn = false;
  bool _onScreen = false;
  JobHandle<Object?>? _coachJob;

  /// The coach's answer for the acting seat (null: none yet, or none).
  CoachAnswer? coach;

  /// The coach is working on an answer.
  bool coachThinking = false;

  /// The acting seat's cards are hidden from this device: the coach shows
  /// "—".
  bool coachHidden = false;

  /// The coach was turned on, on this device (off by default: the best
  /// play is shown only when asked for).
  bool get coachOn => _coachOn;

  /// The game's screen is open: the coach works only then.
  bool get onScreen => _onScreen;
  set onScreen(bool on) {
    if (_onScreen == on) return;
    _onScreen = on;
    _coach();
    _notify();
  }

  void setCoach(bool on) {
    if (_coachOn == on) return;
    _coachOn = on;
    _coach();
    _notify();
  }

  // ---------------------------------------------------------------------------
  // What the screens read
  // ---------------------------------------------------------------------------

  /// This device's hand seat in the round; null: it watches.
  int? get you => state?.you;

  /// Watching (no seat in this round, or only waiting for one).
  bool get spectating => you == null;

  /// Plays in the round on screen and still has the seat (one who gave it
  /// up at the round's end holds that round's seat view until the next).
  bool get seated => you != null && client.mySeat != null;

  /// The view: the game's own JSON.
  Map<String, Object?>? get view => state?.view;

  /// The room seat of each hand seat.
  List<int> get lineup => state?.seats ?? const [];

  EnvelopeTurn? get turn => state?.over == null ? state?.turn : null;
  EnvelopeOver? get over => state?.over;
  int get round => state?.round ?? 0;

  /// It is this player's turn, and they haven't moved yet.
  bool get myTurn {
    final t = turn, me = you;
    return !ended && !gameOver && t != null && me != null && t.seat == me && _movedAt != t.turnId;
  }

  /// The connection ended (the room closed, or was lost).
  bool get ended => client.status == OnlineStatus.closed || client.status == OnlineStatus.lost;
  bool get reconnecting => client.status == OnlineStatus.reconnecting;
  bool get isHost => client.isHost;
  String get roomCode => client.room?.code ?? client.welcome?.code ?? '';

  /// The host's connection dropped (the bots move after a moment meanwhile).
  bool get hostAway {
    final room = client.room;
    final host = room?.members.where((m) => m.id == room.host).firstOrNull;
    return host != null && host.status == SeatStatus.away && !client.isHost;
  }

  /// The room seat of hand seat [seat] as the room shows it (name, score,
  /// away); null if the room doesn't list it.
  SeatInfo? seatInfo(int seat) {
    final seats = client.room?.seats ?? const <SeatInfo>[];
    final at = seat < lineup.length ? lineup[seat] : -1;
    return at >= 0 && at < seats.length ? seats[at] : null;
  }

  /// The name of whoever has hand seat [seat].
  String nameOf(int seat) {
    final info = seatInfo(seat);
    if (info != null && !info.isEmpty) return info.name;
    final at = seat < lineup.length ? lineup[seat] : seat;
    return kitBotNames[at % kitBotNames.length];
  }

  // ---------------------------------------------------------------------------
  // What the player does
  // ---------------------------------------------------------------------------

  /// Plays [move] at this player's turn (once).
  void move(String move) {
    final s = state, t = turn;
    if (!myTurn || s == null || t == null) return;
    _movedAt = t.turnId;
    client.send(
      GameMessage(
        game: ui.key,
        gv: ui.gv,
        body: EnvelopeMove(round: s.round, turnId: t.turnId, move: move),
      ),
    );
    _notify();
  }

  /// Join game: a seat from the next round (a bot's if none is free).
  void joinGame() {
    if (!ended) client.send(const TakeSeat());
  }

  /// Gives up the seat waited for, or (playing) the seat once the round
  /// ends.
  void leaveSeat() {
    if (!ended) client.send(const LeaveSeat());
  }

  /// The game is over: the room takes the connection back (messages not
  /// handled here wait in it, in order).
  OnlineClient handBack() {
    _handedBack = true;
    client.detach();
    return client;
  }

  // ---------------------------------------------------------------------------
  // What the room says
  // ---------------------------------------------------------------------------

  void _receive(ServerMessage m) {
    if (_disposed || gameOver) return;
    switch (m) {
      case ServerGameMessage(:final game, :final gv, :final body) when game == ui.key && gv == ui.gv:
        switch (body) {
          case EnvelopeState():
            _onState(body);
          case EnvelopeBotRequest():
            _onBot(body);
          default:
            break;
        }
      case RoomState():
        _onRoom(m);
      case Rejected(:final turnId?) when turnId == _movedAt && m.reason == Rejection.illegal:
        // A move the room refused: the player may choose again.
        _movedAt = null;
        _notify();
      default:
        _notify();
    }
  }

  void _onChanges() {
    if (_disposed) return;
    _maybeReady();
    _notify();
  }

  void _onState(EnvelopeState s) {
    final old = state;
    if (old != null && (s.round < old.round || (s.round == old.round && s.seq < old.seq))) return;
    state = s;
    if (s.turn?.turnId != old?.turn?.turnId) _movedAt = null;
    // A bot's turn is over once the room moved on.
    final request = _botRequest;
    if (request != null && (s.round != request.round || s.turn?.turnId != request.turnId)) _dropBot();
    _maybeReady();
    _coach();
    _notify();
  }

  /// The room's lobby again (the host ended the game, or another game is
  /// picked): over. What comes next waits in the connection for the room.
  void _onRoom(RoomState room) {
    if (state != null && (room.phase == RoomPhase.lobby || room.game?.key != ui.key)) {
      gameOver = true;
      client.detach();
      _dropBot();
      _coachJob?.cancel();
      coachThinking = false;
      _notify();
      return;
    }
    _maybeReady();
    _notify();
  }

  /// A round is over: a seated player's device is ready for the next (the
  /// room shows the result for a while anyway).
  void _maybeReady() {
    final s = state;
    if (s == null || s.over == null || gameOver || _readyFor > s.round) return;
    if (client.mySeat == null && client.queuedSeat == null) return;
    _readyFor = s.round + 1;
    client.send(GameMessage(game: ui.key, gv: ui.gv, body: EnvelopeReady(s.round + 1)));
  }

  // ---------------------------------------------------------------------------
  // The host's bots
  // ---------------------------------------------------------------------------

  void _onBot(EnvelopeBotRequest r) {
    _dropBot();
    _botRequest = r;
    final opened = DateTime.now();
    final seed = mixSeed(mixSeed(_botSalt, r.round, r.turnId), r.seat, 0);
    final JobHandle<Object?> job;
    try {
      job = ui.botJob(r.view, r.level, seed: seed).start(_jobs, lane: JobLane.bot, kind: JobKind.bot);
    } on Object {
      _sendBot(r, ui.fallbackMove(r.view, seed: seed), opened);
      return;
    }
    _botJob = job;
    unawaited(
      job.result.then(
        (output) => _sendBot(r, ui.botMove(output), opened),
        onError: (Object error) {
          if (error is! JobCancelled) _sendBot(r, ui.fallbackMove(r.view, seed: seed), opened);
        },
      ),
    );
  }

  /// Sends the bot's [move] once [botMinDelay] has passed since its turn
  /// opened ([opened]), if it is still that turn.
  void _sendBot(EnvelopeBotRequest r, String move, DateTime opened) {
    if (_disposed || _botRequest != r) return;
    final wait = botMinDelay - DateTime.now().difference(opened);
    void send() {
      if (_disposed || _botRequest != r) return;
      _botRequest = null;
      client.send(
        GameMessage(
          game: ui.key,
          gv: ui.gv,
          body: EnvelopeBotMove(round: r.round, turnId: r.turnId, seat: r.seat, move: move),
        ),
      );
    }

    if (wait <= Duration.zero) {
      send();
    } else {
      _botTimer = Timer(wait, send);
    }
  }

  void _dropBot() {
    _botRequest = null;
    _botTimer?.cancel();
    _botTimer = null;
    _botJob?.cancel();
    _botJob = null;
  }

  // ---------------------------------------------------------------------------
  // A spectator's coach
  // ---------------------------------------------------------------------------

  /// The coach for whoever acts now: from the view this device may see,
  /// rebuilt for that seat (never from a bot's turn the host's device was
  /// sent); nothing while off, off screen, seated or between turns.
  void _coach() {
    _coachJob?.cancel();
    _coachJob = null;
    final s = state, t = turn;
    if (!_coachOn || !_onScreen || !spectating || gameOver || s == null || t == null) {
      coach = null;
      coachThinking = false;
      coachHidden = false;
      return;
    }
    final seatView = ui.seatViewFrom(s.view, t.seat);
    if (seatView == null) {
      coach = null;
      coachThinking = false;
      coachHidden = true;
      return;
    }
    coachHidden = false;
    coachThinking = true;
    final JobHandle<Object?> job;
    try {
      job = ui
          .coachJob(seatView, seed: mixSeed(s.coachSeed ?? 0, s.seq, 99))
          .start(_jobs, lane: JobLane.coach, kind: JobKind.coach);
    } on Object {
      coachThinking = false;
      return;
    }
    _coachJob = job;
    unawaited(
      job.result.then(
        (output) {
          if (_disposed || _coachJob != job) return;
          coach = ui.toAnswer(output);
          coachThinking = false;
          _notify();
        },
        onError: (Object _) {
          if (_disposed || _coachJob != job) return;
          coachThinking = false;
          _notify();
        },
      ),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_statusChanges.cancel());
    _dropBot();
    _coachJob?.cancel();
    _jobs.dispose();
    if (!_handedBack) {
      client.detach();
      unawaited(client.close());
    }
    super.dispose();
  }
}
