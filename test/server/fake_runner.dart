/// "High card": a fake game for testing the rooms' runner framework (and
/// the runner harness) before any real card game is online. Each hand seat
/// is dealt one hidden card; then, from a first seat that moves round by
/// round, each plays `"<seat>:raise"` or `"<seat>:fold"` once. The highest
/// card among those who raised wins one point from each other raiser. It
/// has hidden cards, bots (their level is ignored), turns, a result and
/// scores: the whole room path, leaks included.
///
/// Pure Dart like a real runner: its deal draws from the room's Random.
library;

import 'dart:math';

import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/protocol.dart' show botLevelNames;

/// The 52 cards as two characters: rank then suit ("Td", "As").
final highCardDeck = [
  for (final r in '23456789TJQKA'.split(''))
    for (final s in 'cdhs'.split('')) '$r$s',
];

/// [card]'s rank, 0 (a two) to 12 (an ace).
int highCardRank(String card) => '23456789TJQKA'.indexOf(card[0]);

/// High card's online support. [key] must be a GameKeys key (the envelope
/// reads only those): Gomoku's by default. [seats] defaults to 2 or 3 seats
/// picked by the host, starting with 2. Rules: `{}`, or `{"pad": n}` to add
/// n characters to every view (for size checks).
class HighCardGame implements OnlineGame {
  HighCardGame({
    this.key = 'gomoku',
    this.gv = 1,
    this.seats = const SeatRange(2, 3, hostPicks: true, start: 2),
    this.betweenRounds = const Duration(seconds: 2),
    this.maxBetweenRounds = const Duration(seconds: 6),
    this.openingMs = 0,
  });

  /// The opening step each round's first clock waits for (ms), as Big
  /// Two's and Fight the Landlord's who-goes-first step.
  final int openingMs;

  @override
  final String key;
  @override
  final int gv;
  final SeatRange seats;
  @override
  final Duration betweenRounds;
  @override
  final Duration maxBetweenRounds;

  /// Every runner made, newest last (tests look inside).
  final List<HighCardRunner> runners = [];

  @override
  Map<String, Object?> get defaultRules => const {};

  @override
  Map<String, Object?> readRules(Object? json) => switch (json) {
    {'pad': final int n} when json.length == 1 && n >= 0 && n <= 20000 => {'pad': n},
    final Map<Object?, Object?> m when m.isEmpty => const {},
    _ => throw const FormatException('Not High card rules'),
  };

  @override
  SeatRange seatsFor(Map<String, Object?> rules) => seats;

  @override
  List<String> get botLevels => botLevelNames;

  @override
  GameRunner newRunner(OnlineSetup setup, Random random) {
    final runner = HighCardRunner(random, pad: (setup.rules['pad'] as int?) ?? 0, openingMs: openingMs);
    runners.add(runner);
    return runner;
  }
}

/// One game of High card in a room.
class HighCardRunner implements GameRunner {
  HighCardRunner(this._random, {this.pad = 0, this.openingMs = 0});

  final Random _random;

  /// Characters added to every view.
  final int pad;

  int _round = 0;
  List<bool> _isBot = const [];
  List<String> _cards = const [];
  List<String?> _acts = const [];
  int _first = 0;
  int? _toAct;

  int get players => _isBot.length;

  /// The round being played (or the last), and every move played in this
  /// game, with its seat.
  int get round => _round;
  final List<(int, String)> moves = [];

  @override
  void startRound(int round, List<bool> isBot) {
    _round = round;
    _isBot = List.unmodifiable(isBot);
    // A secure deal: every card drawn from the room's Random.
    final deck = [...highCardDeck];
    for (var i = deck.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final t = deck[i];
      deck[i] = deck[j];
      deck[j] = t;
    }
    _cards = deck.take(isBot.length).toList();
    _acts = List.filled(isBot.length, null);
    _first = (round - 1) % isBot.length;
    _toAct = _first;
  }

  @override
  bool get roundOver => _toAct == null;

  @override
  int? get seatToAct => _toAct;

  @override
  bool get redealt => false;

  @override
  String? check(int seat, String move) {
    if (_toAct == null) return 'the round is over';
    if (seat != _toAct) return 'not their turn';
    if (move != '$seat:raise' && move != '$seat:fold') return 'not a move';
    return null;
  }

  @override
  void act(int seat, String move) {
    if (check(seat, move) case final reason?) throw ArgumentError(reason);
    _acts[seat] = move.endsWith('raise') ? 'raise' : 'fold';
    moves.add((seat, move));
    final next = (seat + 1) % players;
    _toAct = next == _first ? null : next;
  }

  @override
  String autoMove(int seat, {bool absent = false}) {
    autoMoves.add((seat, absent));
    return '$seat:fold';
  }

  /// Each auto move asked for: the seat, and whether nobody was playing it.
  final List<(int, bool)> autoMoves = [];

  @override
  final int openingMs;

  @override
  int playbackMs(String move) => 300;

  Map<String, String> get _shown => {for (var s = 0; s < players; s++) '$s': _cards[s]};

  Map<String, Object?> _public() => {'n': players, 'round': _round, 'first': _first, 'acts': _acts, 'toAct': _toAct};

  @override
  Map<String, Object?> seatView(int seat) => {
    ..._public(),
    'you': seat,
    'card': _cards[seat],
    if (roundOver) 'shown': _shown,
    if (pad > 0) 'pad': 'x' * pad,
  };

  @override
  Map<String, Object?> spectatorView({required bool seesBots}) => {
    ..._public(),
    'hands': {
      for (var s = 0; s < players; s++)
        if (seesBots || !_isBot[s] || roundOver) '$s': _cards[s],
    },
    if (roundOver) 'shown': _shown,
    if (pad > 0) 'pad': 'x' * pad,
  };

  /// The winner: the highest card among those who raised (null if nobody
  /// raised).
  int? get winner {
    int? best;
    for (var s = 0; s < players; s++) {
      if (_acts[s] != 'raise') continue;
      if (best == null || highCardRank(_cards[s]) > highCardRank(_cards[best])) best = s;
    }
    return best;
  }

  @override
  Map<String, Object?> roundResult() => {'winner': winner, 'cards': _cards};

  @override
  List<num> get roundScores {
    final w = winner;
    final raisers = _acts.where((a) => a == 'raise').length;
    return [
      for (var s = 0; s < players; s++)
        if (w == null || _acts[s] != 'raise') 0 else if (s == w) raisers - 1 else -1,
    ];
  }
}

/// High card's view codec, as a game's `<key>_view_codec.dart` has it: the
/// acting seat's view rebuilt from the spectators' view (null when that
/// seat's card isn't in it: a bot with the host's switch off).
Map<String, Object?>? highCardSeatViewFrom(Map<String, Object?> spectatorView, int seat) {
  final hands = spectatorView['hands'];
  if (hands is! Map || hands['$seat'] is! String) return null;
  return {
    for (final key in ['n', 'round', 'first', 'acts', 'toAct']) key: spectatorView[key],
    'you': seat,
    'card': hands['$seat'],
    'shown': ?spectatorView['shown'],
    'pad': ?spectatorView['pad'],
  };
}

/// The cards nobody may see in [runner]'s round (the rest of the deck), as
/// they appear in JSON (quoted).
Set<String> highCardUndealt(HighCardRunner runner) => {
  for (final c in highCardDeck)
    if (!runner._cards.contains(c)) '"$c"',
};

/// The hidden part of hand seat [seat]'s view while the round goes on: its
/// card, as it appears in JSON (quoted). Nothing once the round is over
/// (every card is shown then).
Set<String> highCardSecrets(Map<String, Object?> seatView, int seat) =>
    seatView['shown'] != null ? const {} : {'"${seatView['card']}"'};

/// A legal move for [seat] seeing [seatView]: raise with a ten or better,
/// else raise or fold at random.
String highCardPick(Map<String, Object?> seatView, int seat, Random random) {
  final card = seatView['card']! as String;
  final raise = highCardRank(card) >= 8 || random.nextBool();
  return '$seat:${raise ? 'raise' : 'fold'}';
}
