/// Fight the Landlord in a room: three seats (people or bots), one deal a
/// round, the points of each deal added to the seats' scores. Pure Dart:
/// it reads only the engine and its online notation
/// (doudizhu_view_codec.dart, where the views and moves are described).
///
/// - Each deal is shuffled straight from the room's Random, and one of the
///   cards dealt to the hands is turned face up: its holder opens the
///   auction (Pagat), and every seat and spectator sees it until it is
///   played.
/// - When everyone passes in the auction and the rules redeal, the cards are
///   dealt again inside the round (from the same Random, with a new face-up
///   card), and the move goes out as a redeal. A round ends only when
///   someone goes out.
/// - Nobody is ever sent cards they may not see: their own hand, how many
///   the others hold (the moves tell), the kitty once taken (per the rules),
///   the plays; every card once the deal is over. The spectators see every
///   person's hand, and the bots' only with the host's switch.
/// - The room adds up each deal's points (the landlord's twice a peasant's)
///   as the seats' scores across the game, as a match in the solo game adds
///   them.
library;

import 'dart:math';

import '../../../online/games/game_runner.dart';
import '../cards.dart';
import '../game.dart';
import '../rules.dart';
import 'doudizhu_view_codec.dart';

/// Fight the Landlord's online support (see online_games.dart).
// ignore: unnecessary_nullable_for_final_variable_declarations
final OnlineGame? doudizhuOnline = DoudizhuOnline();

/// The game as a room offers it: three seats, Easy to Hard bots, the solo
/// game's rule switches.
class DoudizhuOnline implements OnlineGame {
  @override
  String get key => 'doudizhu';

  @override
  int get gv => ddzOnlineVersion;

  @override
  Map<String, Object?> get defaultRules => DdzRules.standard.toJson();

  /// The multiplier caps a room may pick (null: none), as the setup offers.
  static const caps = <int?>[null, 8, 16, 32, 64];

  /// [json] read strictly as rules (DdzRules.toJson): only its keys, each of
  /// its type; a key left out keeps the standard rule. The rules come back
  /// whole, so every device reads the same.
  @override
  Map<String, Object?> readRules(Object? json) {
    if (json is! Map) throw const FormatException('Expected rules');
    const switches = {'fourWithTwo', 'rocketAsKickers', 'kittyShown', 'bombsDouble', 'springDoubles'};
    for (final MapEntry(:key, :value) in json.entries) {
      final ok = switch (key) {
        'bidding' => BiddingStyle.values.asNameMap().containsKey(value),
        'allPass' => AllPassRule.values.asNameMap().containsKey(value),
        'maxMultiplier' => caps.contains(value),
        final String s when switches.contains(s) => value is bool,
        _ => false,
      };
      if (!ok) throw FormatException('Not a Fight the Landlord rule', '$key');
    }
    return DdzRules.fromJson(json.cast<String, Object?>()).toJson();
  }

  @override
  SeatRange seatsFor(Map<String, Object?> rules) => const SeatRange(3, 3);

  @override
  List<String> get botLevels => const ['easy', 'medium', 'hard'];

  @override
  Duration get betweenRounds => const Duration(seconds: 4);

  @override
  Duration get maxBetweenRounds => const Duration(seconds: 15);

  @override
  GameRunner newRunner(OnlineSetup setup, Random random) => DoudizhuRunner(DdzRules.fromJson(setup.rules), random);
}

/// One game of Fight the Landlord in a room: its rounds, one deal each
/// (plus any thrown in). Seats are hand seats 0, 1, 2, in the order of
/// play.
class DoudizhuRunner implements GameRunner {
  DoudizhuRunner(this.rules, this._random);

  final DdzRules rules;
  final Random _random;

  DdzGame? _game;
  List<bool> _isBot = const [false, false, false];
  int _redeals = 0;
  bool _redealt = false;

  /// The auto move just given (to tell, in [act], the room's moves from
  /// the players'), whether every auction move of this deal was the
  /// room's so far, and how many deals in a row were thrown in that way.
  String? _autoGiven;
  bool _idleDeal = true;
  int _idleThrowIns = 0;

  /// The deal being played (tests look inside: the runner test's undealt
  /// cards are its kitty during the auction).
  DdzGame get game => _game ?? (throw StateError('No round dealt'));

  /// The deals thrown in this round so far.
  int get redeals => _redeals;

  @override
  void startRound(int round, List<bool> isBot) {
    if (isBot.length != 3) throw ArgumentError('Fight the Landlord has three seats');
    _isBot = List.unmodifiable(isBot);
    _redeals = 0;
    _redealt = false;
    _idleThrowIns = 0;
    _deal();
  }

  /// A new deal, shuffled from the room's Random; the face-up card's holder
  /// opens the auction.
  void _deal() {
    _game = DdzGame.deal(rules: rules, random: _random);
    _idleDeal = true;
    _autoGiven = null;
  }

  @override
  bool get roundOver => game.phase == DdzPhase.finished;

  @override
  int? get seatToAct => roundOver ? null : game.toAct;

  @override
  bool get redealt => _redealt;

  @override
  String? check(int seat, String move) {
    try {
      final g = game;
      if (g.phase != DdzPhase.bidding && g.phase != DdzPhase.playing) return 'the round is over';
      if (seat != g.toAct) return 'not their turn';
      final (seat: mover, move: m, :cardIds) = ddzReadOnlineMove(move, rules);
      if (mover != seat) return "another seat's move";
      if (!g.isLegal(m)) return 'not legal now';
      if (m is DdzPlay && cardIds != null) {
        final ranks = (cardIds.map(rankOfId).toList()..sort()).join(',');
        if (cardIds.length != m.play.size ||
            cardIds.toSet().length != cardIds.length ||
            ranks != m.play.ranks.join(',') ||
            !cardIds.every(g.hands[seat].contains)) {
          return 'not the cards of the play';
        }
      }
      return null;
    } on Object {
      return 'unreadable';
    }
  }

  @override
  void act(int seat, String move) {
    if (check(seat, move) case final reason?) throw ArgumentError(reason);
    final (seat: _, move: m, :cardIds) = ddzReadOnlineMove(move, rules);
    final g = game;
    final auto = move == _autoGiven;
    _autoGiven = null;
    if (!auto && g.phase == DdzPhase.bidding) _idleDeal = false;
    g.act(m, cardIds: cardIds);
    _redealt = g.phase == DdzPhase.thrownIn;
    if (_redealt) {
      // Everyone passed: the cards are dealt again, a new card face up.
      _idleThrowIns = _idleDeal ? _idleThrowIns + 1 : 0;
      _redeals++;
      _deal();
    }
  }

  /// [ddzAutoMove]. It takes the landlord at the auction's last chance
  /// (instead of declining, which throws the deal in) only for a seat
  /// nobody is playing, or once a deal was thrown in with every auction
  /// move the room's (a table where everyone lets the clock run out). A
  /// player at the table whose time ran out otherwise declines, as doing
  /// nothing means: Pagat, "If everyone passes the hand is thrown in".
  @override
  String autoMove(int seat, {bool absent = false}) {
    final move = ddzAutoMove(game, standIn: absent || _idleThrowIns > 0);
    _autoGiven = move;
    return move;
  }

  /// The who-bids-first step every deal opens with, as after a redeal.
  @override
  int get openingMs => redealMs;

  /// Long enough to see a play land (a bomb a moment longer), short for a
  /// bid or a pass. A deal thrown in is dealt again, and the devices show
  /// the new deal's first step (who bids first, about two seconds at
  /// Normal: LandlordDealClock) before the next clock starts.
  @override
  int playbackMs(String move) {
    if (_redealt) return redealMs;
    final at = move.indexOf(':');
    final body = at < 0 ? '' : move.substring(at + 1);
    if (body.startsWith('xbomb') || body.startsWith('xrocket')) return 1100;
    return body.startsWith('x') ? 700 : 400;
  }

  /// How long a deal dealt again is shown before its first clock: the
  /// step that opens it at Normal (51 cards at 26 ms, then 650 ms; see
  /// doudizhu_opening.dart, which this pure-Dart file can't import), and
  /// a little more.
  static const redealMs = 2200;

  @override
  Map<String, Object?> seatView(int seat) => ddzSeatView(game, seat, redeals: _redeals);

  @override
  Map<String, Object?> spectatorView({required bool seesBots}) => ddzSpectatorView(
    game,
    shown: {
      for (var s = 0; s < 3; s++)
        if (seesBots || !_isBot[s]) s,
    },
    redeals: _redeals,
  );

  @override
  Map<String, Object?> roundResult() {
    final r = game.result;
    if (r == null) return const {};
    return {
      'landlord': r.landlord,
      'winner': r.winner,
      'stake': r.stake,
      'multiplier': r.multiplier,
      'bombs': r.bombs,
      if (r.spring) 'spring': true,
      if (r.antiSpring) 'antiSpring': true,
      'points': r.points,
      if (_redeals > 0) 'redeals': _redeals,
    };
  }

  @override
  List<num> get roundScores => game.result?.points ?? const [0, 0, 0];
}
