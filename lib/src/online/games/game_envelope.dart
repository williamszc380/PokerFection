/// The "m" of a game message (`{t:"g", game, gv, m}`, see protocol.dart's
/// GameMessage and ServerGameMessage): the kinds every game other than
/// Hold'em shares. Pure Dart, read strictly: every reader throws
/// [FormatException] when anything is off (protocol.dart turns it into a
/// ProtocolError).
///
/// From a device: a seat's [EnvelopeMove], the host's [EnvelopeBotMove]
/// for a bot, [EnvelopeReady] for the next round. To a device: its full
/// view of the round ([EnvelopeState], never a diff) and, on the host's
/// device only, a bot's turn ([EnvelopeBotRequest]). A view is the game's
/// own JSON (its view codec reads it); it never holds the deck, the shoe
/// order, undealt cards or a seed.
///
/// Every seat in these messages is a **hand seat**: the round's own
/// numbering, 0 to the number of players - 1 (the runner's, see
/// GameRunner). [EnvelopeState.seats] gives the room seat of each.
library;

/// The longest move read (the longest Fight the Landlord play, 20 cards in
/// `"<seat>:<encode>|<ids>"`, is about 95 characters).
const maxMoveLength = 256;

/// Why a move was made: the player's (or for a bot, the host's device's),
/// the room's when time ran out, the player was away or had left, or the
/// host was away; or a deal thrown in and dealt again ([redeal]).
enum EnvelopeCause { act, timeout, away, left, hostAway, redeal }

/// One "m" of a game message.
sealed class EnvelopeBody {
  const EnvelopeBody();

  Map<String, Object?> toJson();
}

// -----------------------------------------------------------------------------
// From a device
// -----------------------------------------------------------------------------

/// A seat's [move] at turn [turnId] of round [round], in the game's move
/// notation.
final class EnvelopeMove extends EnvelopeBody {
  const EnvelopeMove({required this.round, required this.turnId, required this.move});

  final int round;
  final int turnId;
  final String move;

  @override
  Map<String, Object?> toJson() => {'k': 'move', 'r': round, 'turnId': turnId, 'mv': move};
}

/// The host's device plays the bot in hand seat [seat].
final class EnvelopeBotMove extends EnvelopeBody {
  const EnvelopeBotMove({required this.round, required this.turnId, required this.seat, required this.move});

  final int round;
  final int turnId;
  final int seat;
  final String move;

  @override
  Map<String, Object?> toJson() => {'k': 'botMove', 'r': round, 'turnId': turnId, 's': seat, 'mv': move};
}

/// The device has shown the last round: round [round] can be dealt.
final class EnvelopeReady extends EnvelopeBody {
  const EnvelopeReady(this.round);
  final int round;

  @override
  Map<String, Object?> toJson() => {'k': 'ready', 'r': round};
}

// -----------------------------------------------------------------------------
// To a device
// -----------------------------------------------------------------------------

/// Whose turn it is: hand seat [seat], turn [turnId], [ms] to decide once
/// [waitMs] of the last move has been shown (null: no limit).
final class EnvelopeTurn {
  const EnvelopeTurn({required this.seat, required this.turnId, required this.ms, required this.waitMs});

  final int seat;
  final int turnId;
  final int? ms;
  final int waitMs;

  Map<String, Object?> toJson() => {'s': seat, 'turnId': turnId, 'ms': ms, 'waitMs': waitMs};

  factory EnvelopeTurn.fromJson(Object? json) {
    final m = _Strict(json);
    return EnvelopeTurn(
      seat: m.seat('s'),
      turnId: m.integer('turnId', min: 1),
      ms: m.has('ms') ? m.integer('ms', min: 0) : null,
      waitMs: m.integer('waitMs', min: 0),
    );
  }
}

/// The move just made: by hand seat [seat], why ([cause]).
final class EnvelopeLast {
  const EnvelopeLast({required this.seat, required this.move, required this.cause});

  final int seat;
  final String move;
  final EnvelopeCause cause;

  Map<String, Object?> toJson() => {'s': seat, 'mv': move, 'cause': cause.name};

  factory EnvelopeLast.fromJson(Object? json) {
    final m = _Strict(json);
    return EnvelopeLast(seat: m.seat('s'), move: m.move('mv'), cause: m.named('cause', EnvelopeCause.values));
  }
}

/// A round just ended: the game's [result] (its own JSON) and what each
/// seat scored, by the lineup's order.
final class EnvelopeOver {
  const EnvelopeOver({required this.result, required this.scores});

  final Map<String, Object?> result;
  final List<num> scores;

  Map<String, Object?> toJson() => {'result': result, 'scores': scores};

  factory EnvelopeOver.fromJson(Object? json) {
    final m = _Strict(json);
    return EnvelopeOver(result: m.object('result'), scores: m.numbers('scores'));
  }
}

/// A member's full view of round [round] ([seq]: the round's messages so
/// far, so a device drops anything older): for hand seat [you], or the
/// spectators' view ([you] null, the same for every spectator, with
/// [coachSeed]: a fresh random number per round, unrelated to the deal).
/// [seats]: the room seat of each hand seat (the round's lineup).
final class EnvelopeState extends EnvelopeBody {
  const EnvelopeState({
    required this.round,
    required this.seq,
    required this.you,
    required this.turn,
    required this.last,
    required this.view,
    this.seats = const [],
    this.over,
    this.coachSeed,
  });

  final int round;
  final int seq;
  final int? you;

  /// The room seat of each hand seat, in order (the room seats taken when
  /// the round was dealt).
  final List<int> seats;
  final EnvelopeTurn? turn;
  final EnvelopeLast? last;
  final Map<String, Object?> view;
  final EnvelopeOver? over;
  final int? coachSeed;

  @override
  Map<String, Object?> toJson() => {
    'k': 'state',
    'r': round,
    'seq': seq,
    'you': you,
    'turn': turn?.toJson(),
    'last': last?.toJson(),
    'view': view,
    if (seats.isNotEmpty) 'seats': seats,
    if (over != null) 'over': over!.toJson(),
    'coachSeed': ?coachSeed,
  };
}

/// To the host's device only: the bot in hand seat [seat] acts at turn
/// [turnId], at [level], seeing [view] (that seat's own view).
final class EnvelopeBotRequest extends EnvelopeBody {
  const EnvelopeBotRequest({
    required this.round,
    required this.turnId,
    required this.seat,
    required this.level,
    required this.view,
  });

  final int round;
  final int turnId;
  final int seat;
  final String level;
  final Map<String, Object?> view;

  @override
  Map<String, Object?> toJson() => {'k': 'bot', 'r': round, 'turnId': turnId, 's': seat, 'level': level, 'view': view};
}

/// The bots' levels in these games.
const envelopeBotLevels = ['easy', 'medium', 'hard'];

/// The "m" of a game message from a device: a move, a bot's move or ready.
EnvelopeBody readClientBody(Object? json) {
  final m = _Strict(json);
  return switch (m.string('k')) {
    'move' => EnvelopeMove(round: m.integer('r', min: 1), turnId: m.integer('turnId', min: 1), move: m.move('mv')),
    'botMove' => EnvelopeBotMove(
      round: m.integer('r', min: 1),
      turnId: m.integer('turnId', min: 1),
      seat: m.seat('s'),
      move: m.move('mv'),
    ),
    'ready' => EnvelopeReady(m.integer('r', min: 1)),
    final kind => throw FormatException('Unknown game message $kind'),
  };
}

/// The "m" of a game message to a device: a view, or a bot's turn.
EnvelopeBody readServerBody(Object? json) {
  final m = _Strict(json);
  return switch (m.string('k')) {
    'state' => EnvelopeState(
      round: m.integer('r', min: 1),
      seq: m.integer('seq', min: 0),
      you: m.has('you') ? m.seat('you') : null,
      turn: m.has('turn') ? EnvelopeTurn.fromJson(m['turn']) : null,
      last: m.has('last') ? EnvelopeLast.fromJson(m['last']) : null,
      view: m.object('view'),
      seats: m.has('seats') ? m.seats('seats') : const [],
      over: m.has('over') ? EnvelopeOver.fromJson(m['over']) : null,
      coachSeed: m.has('coachSeed') ? m.integer('coachSeed', min: 0, max: (1 << 31) - 1) : null,
    ),
    'bot' => EnvelopeBotRequest(
      round: m.integer('r', min: 1),
      turnId: m.integer('turnId', min: 1),
      seat: m.seat('s'),
      level: m.level('level'),
      view: m.object('view'),
    ),
    final kind => throw FormatException('Unknown game message $kind'),
  };
}

/// A JSON object read strictly (as protocol.dart's reader, which is
/// private there): every getter throws [FormatException].
extension type _Strict._(Map<String, Object?> _m) {
  factory _Strict(Object? json) {
    if (json is! Map) throw const FormatException('Expected an object');
    final m = <String, Object?>{};
    for (final MapEntry(:key, :value) in json.entries) {
      if (key is! String) throw const FormatException('Keys must be strings');
      m[key] = value;
    }
    return _Strict._(m);
  }

  Object? operator [](String key) => _m[key];

  bool has(String key) => _m[key] != null;

  int integer(String key, {int? min, int? max}) {
    final value = switch (_m[key]) {
      final int i => i,
      // On the web JSON numbers may be doubles: only whole ones count.
      final double d when d == d.roundToDouble() && d.abs() < 1e15 => d.toInt(),
      _ => throw FormatException('Expected a whole number: $key'),
    };
    if ((min != null && value < min) || (max != null && value > max)) throw FormatException('Out of range: $key');
    return value;
  }

  int seat(String key) => integer(key, min: 0, max: 7);

  /// Up to 8 distinct room seats, rising.
  List<int> seats(String key) {
    final v = _m[key];
    if (v is! List || v.length > 8) throw FormatException('Expected up to 8 seats: $key');
    final seats = [
      for (final s in v) _Strict({'s': s}).seat('s'),
    ];
    for (var i = 1; i < seats.length; i++) {
      if (seats[i] <= seats[i - 1]) throw FormatException('Seats out of order: $key');
    }
    return List.unmodifiable(seats);
  }

  String string(String key, {int maxLength = 64}) {
    final v = _m[key];
    if (v is! String || v.length > maxLength) throw FormatException('Expected a short text: $key');
    return v;
  }

  String move(String key) => string(key, maxLength: maxMoveLength);

  String level(String key) {
    final v = _m[key];
    return v is String && envelopeBotLevels.contains(v) ? v : throw FormatException('No such level: $key');
  }

  T named<T extends Enum>(String key, List<T> values) {
    final v = _m[key];
    for (final value in values) {
      if (value.name == v) return value;
    }
    throw FormatException('Unknown $key');
  }

  Map<String, Object?> object(String key) => _Strict(_m[key])._m;

  List<num> numbers(String key) {
    final v = _m[key];
    if (v is! List || v.length > 8) throw FormatException('Expected up to 8 numbers: $key');
    return List.unmodifiable([
      for (final n in v)
        if (n is num && n.isFinite) n else throw FormatException('Expected a number: $key'),
    ]);
  }
}
