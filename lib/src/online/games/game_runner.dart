/// What a game other than Hold'em gives the room to be played online: its
/// [OnlineGame] (registered in online_games.dart) and a [GameRunner] per
/// game played. Pure Dart: the room runs on a host's device, in a browser
/// or in bin/server.dart, so a runner imports only its engine and its
/// record codec (never lib/src/kit/jobs/, Flutter or lib/src/ui).
///
/// Every deal comes straight from the room's `Random.secure()` (the
/// `random` given to [OnlineGame.newRunner]): a runner never hands an
/// engine a seed (a seed can be searched from one's own cards), and no view
/// holds the deck, the shoe order, undealt cards or any seed.
library;

import 'dart:math';

import '../timing.dart';

/// How many seats a game has under some rules: [min] to [max], whether
/// the host picks the count ([hostPicks]; else it is [max]), how many a
/// newly picked game starts with ([start]; null: [max]), and whether a
/// round needs every seat ([everySeat]: Gomoku, Big Two, Fight the
/// Landlord) or is dealt to the seats taken, at least [min] (Blackjack).
class SeatRange {
  const SeatRange(this.min, this.max, {this.hostPicks = false, this.start, this.everySeat = true});

  final int min, max;
  final bool hostPicks;

  /// The seats a game starts with when the host picks it (Big Two: 2, so a
  /// room starts with a two-player game); null: [max].
  final int? start;

  /// Every seat must be taken (by someone who can play) for a round to be
  /// dealt; false: the seats taken play, at least [min] of them.
  final bool everySeat;

  bool allows(int seats) => seats >= min && seats <= max && (hostPicks || seats == max);

  /// The seats a new game of these rules has.
  int get first => (hostPicks ? (start ?? max) : max).clamp(min, max);

  /// How many must play for a round to be dealt, with [seats] seats.
  int needed(int seats) => everySeat ? seats : min;
}

/// What the host chose for a game: its [rules] (the game's own JSON), the
/// number of [seats], and the seconds per move ([turnLimit], one of
/// [OnlineTiming.turnLimits]; 0: no limit).
class OnlineSetup {
  const OnlineSetup({required this.rules, required this.seats, this.turnLimit = 0});

  final Map<String, Object?> rules;
  final int seats;
  final int turnLimit;

  Map<String, Object?> toJson() => {'seats': seats, 'turnLimit': turnLimit, 'rules': rules};

  /// [json] read strictly for [game]: its rules by [OnlineGame.readRules],
  /// a number of seats the rules allow, a known time limit. Throws
  /// [FormatException] when anything is off.
  static OnlineSetup fromJson(Object? json, OnlineGame game) {
    if (json is! Map) throw const FormatException('Expected a setup');
    final keys = json.keys.toSet();
    if (keys.any((k) => k is! String) || !keys.every(const {'seats', 'turnLimit', 'rules'}.contains)) {
      throw const FormatException('Unknown setup keys');
    }
    final rules = game.readRules(json['rules']);
    final seats = json['seats'], turnLimit = json['turnLimit'] ?? 0;
    if (seats is! int || !game.seatsFor(rules).allows(seats)) throw const FormatException('Not a number of seats');
    if (turnLimit is! int || !OnlineTiming.turnLimits.contains(turnLimit)) {
      throw const FormatException('No such time limit');
    }
    return OnlineSetup(rules: rules, seats: seats, turnLimit: turnLimit);
  }

  /// The setup a game starts with: its default rules, and the seats its
  /// range starts with ([SeatRange.first]: the most, unless it says).
  static OnlineSetup defaultFor(OnlineGame game) =>
      OnlineSetup(rules: game.defaultRules, seats: game.seatsFor(game.defaultRules).first);
}

/// One game's online support, registered in online_games.dart.
abstract interface class OnlineGame {
  /// The game's GameKeys key.
  String get key;

  /// The version of its view and move notation (devices with another one
  /// watch nothing: "Update the app to watch").
  int get gv;

  Map<String, Object?> get defaultRules;

  /// [json] read strictly as this game's rules; throws [FormatException].
  Map<String, Object?> readRules(Object? json);

  /// The seats under [rules] (Big Two: its players; Blackjack: 1 to 7, the
  /// host picks).
  SeatRange seatsFor(Map<String, Object?> rules);

  /// The bots' levels (`easy`, `medium`, `hard`).
  List<String> get botLevels;

  /// The least time to see a round's result before the next is dealt
  /// (Gomoku 5 s, the card games 4 s, Blackjack 3 s), and when it is dealt
  /// at the latest (Blackjack 10 s, the others 15 s).
  Duration get betweenRounds;
  Duration get maxBetweenRounds;

  /// The game itself, for one game played with [setup]. [random] is the
  /// room's `Random.secure()`: every shuffle draws from it directly.
  GameRunner newRunner(OnlineSetup setup, Random random);
}

/// One game played in a room (Blackjack keeps its shoe across rounds). The
/// room calls it from one synchronous event at a time.
///
/// Its seats are the round's **hand seats**, 0 to the number of players - 1:
/// the room seats taken when the round is dealt, in order (as poker's hand
/// seats; the room tells devices which room seat each one is, see
/// EnvelopeState.seats). Views, moves and results all use hand seats.
abstract interface class GameRunner {
  /// Deals round [round] (1, 2, …) to [isBot].length hand seats (the
  /// lineup, in room seat order; [isBot] says which are bots). The same
  /// runner plays every round of one game (Start to the game's end).
  void startRound(int round, List<bool> isBot);

  bool get roundOver;

  /// Null only when the round is over. After any act someone acts or the
  /// round is over: a deal thrown in (Fight the Landlord, everyone passes
  /// under the redeal rule) is dealt again inside [act].
  int? get seatToAct;

  /// Null if [move] is legal for [seat] now, else a short reason (logged,
  /// never shown). [move] is whatever a member sent (up to 256 characters,
  /// maybe junk): return a reason for anything unreadable rather than
  /// throw. (The room refuses a move whose check or act throws anyway, so
  /// one member can never close the room, but the harness's
  /// expectJunkRefused should pass without it.)
  String? check(int seat, String move);

  /// Plays [move] (the dealer's play happens inside); throws
  /// [ArgumentError] if it is illegal.
  void act(int seat, String move);

  /// Whether the last [act] dealt the round again inside it (Fight the
  /// Landlord: everyone passed under the redeal rule): the move goes out
  /// with the cause "redeal". False for games that never do.
  bool get redealt;

  /// A legal move for [seat], cheap (well under 20 ms on a phone, no
  /// search): time ran out, or the player is away.
  ///
  /// [absent]: nobody is there to play the seat (its player is away or
  /// left, or it is a bot while the host is away). False when the clock
  /// just ran out on someone at the table (a person past their time, or a
  /// bot the host's device answered late for), who should get the move a
  /// player at the table would make by doing nothing.
  String autoMove(int seat, {bool absent = false});

  /// The time to show [move] before the next clock starts (ms).
  int playbackMs(String move);

  /// The time the devices take to show a round's opening (ms) before its
  /// first clock starts and its first bot is asked: the who-goes-first
  /// step at Normal speed (Big Two, Fight the Landlord), 0 for a game
  /// without one. Read right after [startRound].
  int get openingMs;

  /// [seat]'s view: its own hidden cards, nobody else's, and never the
  /// deck, a kitty not yet turned, a dealer's hole card or the shoe's next
  /// card (a game's runner test gives the harness these as `undealt`).
  Map<String, Object?> seatView(int seat);

  /// The spectators' view: every person's hidden cards, the bots' only when
  /// [seesBots]. Never the deck, the shoe order, undealt cards or a seed.
  Map<String, Object?> spectatorView({required bool seesBots});

  /// Each seat's outcome of the round just over (the game's own JSON).
  Map<String, Object?> roundResult();

  /// What each seat scored in the round just over (added to its session
  /// score), by the lineup's order.
  List<num> get roundScores;
}
