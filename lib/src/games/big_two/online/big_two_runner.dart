/// Big Two in a room (see online_games.dart): 2 to 4 seats, the host
/// picking how many (a room starts at 2), the setup's rules, and the deals
/// played as a match to a target, carried from deal to deal.
///
/// Pure Dart: it imports only the engine, its rules and match code and the
/// view codec (not the record's, which reaches the app's grading). Every deal is shuffled with the room's `Random.secure()`
/// directly and dealt with [BigTwoState.fromHands]: no seed exists that a
/// player could search from their own cards.
library;

import 'dart:math';

import '../../../kit/game_keys.dart';
import '../../../kit/match.dart';
import '../../../online/games/game_runner.dart';
import '../app/big_two_match.dart';
import '../app/big_two_rules_codec.dart';
import '../big_two.dart';
import 'big_two_view_codec.dart';

/// Big Two's online support, registered in online_games.dart (which lists
/// every game's as nullable: a game is online once its part is filled in).
// ignore: unnecessary_nullable_for_final_variable_declarations
final OnlineGame? bigTwoOnline = BigTwoOnline();

/// A room's Big Two rules, as the room's setup carries them:
/// `{"rules": <the engine's rules JSON>, "cards2": 13 | 17 | 21, "match": {"points": 100 | null, "scale": bool}}`.
///
/// - `rules` are the engine's, written for four players (the room's seat
///   count decides the real number: [rulesFor]);
/// - `cards2` is how many cards each player gets when two play (three get
///   17 and four 13, always);
/// - `match` is the setup's "Play to" (MatchTarget's JSON): a target, or
///   null for No limit, scaled with the players when asked.
class BigTwoRoomRules {
  const BigTwoRoomRules({required this.rules, this.cards2 = 17, this.match = defaultMatch});

  /// The rules, for four players (see [rulesFor]).
  final BigTwoRules rules;

  /// Cards each in a two-player game.
  final int cards2;

  /// The match's target as chosen.
  final MatchTarget match;

  /// A room's first choice: the standard target, scaled with the players
  /// (so a two-player match doesn't last twice as many deals).
  static const defaultMatch = MatchTarget(points: 100, scale: true);

  /// The standard rules, 17 cards each at two players, the standard match.
  static final standard = BigTwoRoomRules(rules: BigTwoRules.standard());

  /// The straight orders a room accepts (the setup's).
  static const straights = BigTwoRulesCodec.straights;

  /// The rules for [seats] players: their deal size (17 or 13 each, or
  /// [cards2] with two).
  BigTwoRules rulesFor(int seats) =>
      rules.copyWith(players: seats, cardsEach: seats == 2 ? cards2 : BigTwoRulesCodec.cardsEachFor(seats).first);

  /// The target a match at [seats] players plays to; null: No limit.
  int? targetFor(int seats) => bigTwoMatchTarget(match, rulesFor(seats));

  BigTwoRoomRules copyWith({BigTwoRules? rules, int? cards2, MatchTarget? match}) => BigTwoRoomRules(
    rules: rules == null ? this.rules : rules.copyWith(players: 4),
    cards2: cards2 ?? this.cards2,
    match: match ?? this.match,
  );

  Map<String, Object?> toJson() => {
    'rules': BigTwoRulesCodec.encode(rules.copyWith(players: 4)),
    'cards2': cards2,
    'match': match.toJson(),
  };

  /// [json] read strictly: exactly these keys, rules the engine accepts
  /// with one of the setup's straight orders, a two-player deal size the
  /// engine allows, a target that is No limit or a positive number. Throws
  /// [FormatException] otherwise.
  static BigTwoRoomRules read(Object? json) {
    if (json is! Map || json.length != 3 || !json.keys.every(const {'rules', 'cards2', 'match'}.contains)) {
      throw const FormatException('Not Big Two room rules');
    }
    final rules = BigTwoRulesCodec.decode(json['rules']);
    if (!straights.contains(rules.straights)) throw const FormatException('Not a straight order the setup offers');
    final cards2 = json['cards2'];
    if (cards2 is! int || !BigTwoRulesCodec.cardsEachFor(2).contains(cards2)) {
      throw const FormatException('Not a two-player deal');
    }
    final match = json['match'];
    if (match is! Map || match.length != 2 || match['scale'] is! bool || !match.containsKey('points')) {
      throw const FormatException('Not a match target');
    }
    final points = match['points'];
    if (points != null && (points is! int || points <= 0 || points > 100000)) {
      throw const FormatException('Not a match target');
    }
    return BigTwoRoomRules(
      rules: rules.copyWith(players: 4),
      cards2: cards2,
      match: MatchTarget(points: points as int?, scale: match['scale']! as bool),
    );
  }
}

/// Big Two's online game: its rules, seats (2 to 4, the host picks; a room
/// starts with 2), bot levels and pauses between deals.
class BigTwoOnline implements OnlineGame {
  @override
  String get key => GameKeys.bigTwo;

  @override
  int get gv => 2;

  @override
  Map<String, Object?> get defaultRules => BigTwoRoomRules.standard.toJson();

  @override
  Map<String, Object?> readRules(Object? json) => BigTwoRoomRules.read(json).toJson();

  @override
  SeatRange seatsFor(Map<String, Object?> rules) => const SeatRange(2, 4, hostPicks: true, start: 2);

  @override
  List<String> get botLevels => const ['easy', 'medium', 'hard'];

  @override
  Duration get betweenRounds => const Duration(seconds: 4);

  @override
  Duration get maxBetweenRounds => const Duration(seconds: 15);

  @override
  GameRunner newRunner(OnlineSetup setup, Random random) =>
      BigTwoRunner(BigTwoRoomRules.read(setup.rules), random, seats: setup.seats);
}

/// One game of Big Two in a room: one deal a round, the deals adding up to
/// a match (when the rules have a target). When a match is won the next
/// deal starts a new one. A seat's match total stays with the seat, so a
/// person who takes a bot's seat between deals carries on from its total.
class BigTwoRunner implements GameRunner {
  BigTwoRunner(this.roomRules, this._random, {required this.seats}) : rules = roomRules.rulesFor(seats);

  final BigTwoRoomRules roomRules;
  final int seats;

  /// The rules at this table ([seats] players).
  final BigTwoRules rules;
  final Random _random;

  BigTwoState? _state;
  int _deal = 0;
  List<bool> _isBot = const [];

  /// The match being played (null: No limit), and the one the last deal
  /// finished, if it did.
  MatchScore? _match;
  bool _settled = false;

  /// The cards no seat was dealt this deal (two players: 52 minus the
  /// hands), for tests: no view may hold one.
  List<Card> undealt = const [];

  /// The deal being played (or the last one).
  BigTwoState get state => _state ?? (throw StateError('No deal yet'));

  /// The match as it stands (after the last deal once it is over).
  MatchScore? get match => _match;

  @override
  void startRound(int round, List<bool> isBot) {
    if (isBot.length != seats) throw ArgumentError('${isBot.length} seats dealt, the game has $seats');
    _deal = round;
    _isBot = List.unmodifiable(isBot);
    final match = _match;
    if (match == null || match.isOver) _match = bigTwoStartMatch(roomRules.match, rules);
    // A secure deal: the 52 cards shuffled with the room's Random, each
    // seat's cards taken in turn (with three players the last card is the
    // face-up one), then the engine deals from those hands.
    final deck = [...fullDeck];
    for (var i = deck.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final t = deck[i];
      deck[i] = deck[j];
      deck[j] = t;
    }
    final each = rules.cardsEach;
    final hands = [for (var s = 0; s < seats; s++) deck.sublist(s * each, (s + 1) * each)];
    final extra = seats == 3 ? deck[51] : null;
    undealt = seats == 2 ? deck.sublist(2 * each) : const [];
    _state = BigTwoState.fromHands(rules, hands, extra: extra);
    _settled = false;
    // A dealt dragon wins before anyone plays.
    _settle();
  }

  @override
  bool get roundOver => _state?.isOver ?? true;

  @override
  int? get seatToAct => roundOver ? null : state.toMove;

  @override
  bool get redealt => false;

  @override
  String? check(int seat, String move) {
    final state = _state;
    if (state == null || state.isOver) return 'the deal is over';
    if (seat != state.toMove) return 'not their turn';
    try {
      final (seat: who, :play) = bigTwoReadMove(rules, move);
      if (who != seat) return 'another seat\'s move';
      // One play, one spelling (the coach's lines and the moves compare as text).
      if (bigTwoMove(seat, play) != move) return 'not written the usual way';
      if (!state.isLegal(play)) return 'not a legal play now';
      return null;
    } on Object {
      return 'not a move';
    }
  }

  @override
  void act(int seat, String move) {
    if (check(seat, move) case final reason?) throw ArgumentError(reason);
    state.apply(bigTwoReadMove(rules, move).play);
    _settle();
  }

  /// Once the deal is over, its points go to the match (once).
  void _settle() {
    final state = this.state;
    if (!state.isOver || _settled) return;
    _settled = true;
    _match = _match?.add(bigTwoDealPoints(rules, state.result));
  }

  /// The who-starts step every deal opens with (BigTwoOpening: two seconds
  /// at Normal, 1.2 s for a chosen leader), and a little more; none for a
  /// deal a dealt dragon won.
  @override
  int get openingMs {
    final opening = _state == null ? null : BigTwoOpening.of(state);
    return opening == null ? 0 : opening.normalLength.inMilliseconds + openingMargin;
  }

  /// Time on top of the step at Normal for the network and a slow frame.
  static const openingMargin = 200;

  /// Pass when it is allowed; else the smallest play (the fewest cards,
  /// then the lowest): cheap, and it never throws a hand away.
  @override
  String autoMove(int seat, {bool absent = false}) {
    final legal = state.legalMoves();
    if (legal.contains(Play.pass)) return bigTwoMove(seat, Play.pass);
    final plays = [...legal]..sort((a, b) => a.size != b.size ? a.size.compareTo(b.size) : a.key.compareTo(b.key));
    return bigTwoMove(seat, plays.first);
  }

  /// A pass shows briefly; a play as long as its cards take to fly to the
  /// pile (one after the other).
  @override
  int playbackMs(String move) => move.endsWith(':pass') ? 350 : 450 + 45 * bigTwoMoveCardsOf(move).length;

  @override
  Map<String, Object?> seatView(int seat) => bigTwoSeatView(state, seat, deal: _deal, match: _match);

  @override
  Map<String, Object?> spectatorView({required bool seesBots}) => bigTwoSpectatorView(
    state,
    visible: {
      for (var s = 0; s < seats; s++)
        if (seesBots || !_isBot[s]) s,
    },
    deal: _deal,
    match: _match,
  );

  /// The winner, each seat's points this deal (the winner collecting what
  /// the losers pay, or under Pusoy Dos scoring the winner's points), the
  /// match's points this deal and its totals (when there is a target),
  /// the cards each seat had left, whether a dealt dragon won, and the
  /// match's winners once it is over.
  @override
  Map<String, Object?> roundResult() {
    final result = state.result;
    final match = _match;
    return {
      'winner': result.winner,
      'scores': result.scores,
      'cardsLeft': result.cardsLeft,
      if (result.dragon) 'dragon': true,
      if (match != null) ...{
        'points': match.deals.last,
        'totals': match.totals,
        'target': match.target,
        if (match.isOver) 'matchWinners': match.leaders,
      },
    };
  }

  /// Each seat's points this deal, as the solo game's session counts them:
  /// under penalty scoring the winner collects every loser's penalty (they
  /// add up to 0); under Pusoy Dos scoring only the winner scores.
  @override
  List<num> get roundScores => state.result.scores;
}
