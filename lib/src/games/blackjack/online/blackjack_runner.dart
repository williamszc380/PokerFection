/// Blackjack in a room (see online_games.dart): 1 to 7 seats, the host
/// picks how many, and each seat taken plays its own hands against the
/// dealer, who plays by the rules inside the runner (on the host's device).
/// A round is one deal; every seat bets 1, as in the solo game, and what a
/// round wins or loses (1.5 for a blackjack at 3:2) is added to the seat's
/// score.
///
/// The shoe lasts from round to round until its cut card comes out, as at
/// a casino table, and every shuffle draws from the room's secure Random
/// (Shoe's `random`): there is no seed anywhere, so the cards seen can't be
/// used to work out the ones to come. No view holds the shoe's order or the
/// face-down hole card (the spectators see it only with the host's switch:
/// it counts as the bots'). Pure Dart: it imports only the engine (its move
/// notation included) and its view codec, nothing of the kit or the app.
library;

import 'dart:math';

import '../../../online/games/game_runner.dart';
import '../blackjack.dart';
import '../moves.dart';
import 'blackjack_view_codec.dart';

/// Blackjack's online support. Nullable as online_games.dart expects of
/// every game's (a game without one yet is null there).
// ignore: unnecessary_nullable_for_final_variable_declarations
final OnlineGame? blackjackOnline = BlackjackOnline();

/// Blackjack's rules, seats and bots in a room.
class BlackjackOnline implements OnlineGame {
  const BlackjackOnline();

  /// The game's key (GameKeys.blackjack).
  @override
  String get key => 'blackjack';

  @override
  int get gv => blackjackOnlineGv;

  /// The solo game's default table (Standard: 6 decks, S17, 3:2).
  @override
  Map<String, Object?> get defaultRules => const BlackjackRules().toJson();

  /// [json] read strictly: every key one of the rules' own, every value of
  /// its type and in range (BlackjackRules.fromJson), and written back in
  /// full, so every device plays exactly the same table.
  @override
  Map<String, Object?> readRules(Object? json) {
    if (json is! Map || json.keys.any((k) => k is! String || !_ruleKeys.contains(k))) {
      throw const FormatException('Not blackjack rules');
    }
    return BlackjackRules.fromJson(json).toJson();
  }

  static final _ruleKeys = const BlackjackRules().toJson().keys.toSet();

  /// 1 to 7 seats, as at a casino table; the round is dealt to the seats
  /// taken.
  @override
  SeatRange seatsFor(Map<String, Object?> rules) => const SeatRange(1, 7, hostPicks: true, everySeat: false);

  @override
  List<String> get botLevels => const ['easy', 'medium', 'hard'];

  /// A round is quick: 3 s to see how it ended, the next dealt within 10 s.
  @override
  Duration get betweenRounds => const Duration(seconds: 3);
  @override
  Duration get maxBetweenRounds => const Duration(seconds: 10);

  @override
  GameRunner newRunner(OnlineSetup setup, Random random) =>
      BlackjackRunner(BlackjackRules.fromJson(setup.rules), random);
}

/// The rounds of blackjack played at one room's table, Start to End game,
/// from one shoe (shuffled again whenever its cut card has come out).
class BlackjackRunner implements GameRunner {
  BlackjackRunner(this.rules, this._random);

  final BlackjackRules rules;

  /// The room's secure Random: the shoe's only source.
  final Random _random;

  Shoe? _shoe;
  BlackjackRound? _round;
  int _roundNo = 0;

  /// What the last act brought to the table, for its playback: cards dealt,
  /// and whether the hole card turned over.
  int _lastCards = 0;
  bool _lastTurned = false;

  /// The shoe (null before the first deal). Its order is the secret: tests
  /// read it to check no message holds a card still to come.
  Shoe? get shoe => _shoe;

  /// The round being played, or the last one.
  BlackjackRound? get round => _round;

  @override
  void startRound(int round, List<bool> isBot) {
    if (isBot.isEmpty || isBot.length > 7) throw ArgumentError('1 to 7 seats, not ${isBot.length}');
    // The first deal makes the shoe, so its shuffle is that deal's draw.
    final shoe = _shoe ??= Shoe.forRules(rules, random: _random);
    _roundNo = round;
    _round = BlackjackRound.deal(rules, shoe, List.filled(isBot.length, 1));
    _lastCards = 0;
    _lastTurned = false;
  }

  @override
  bool get roundOver => _round?.isOver ?? true;

  @override
  int? get seatToAct => _round?.turn?.seat;

  @override
  bool get redealt => false;

  static final _notation = RegExp(r'^[0-3]:[HSDPRINK]$');

  @override
  String? check(int seat, String move) {
    final round = _round;
    if (round == null || round.isOver) return 'the round is over';
    final turn = round.turn!;
    if (seat != turn.seat) return 'not their turn';
    // Only the solo game's notation, exactly ("0:H"): no spaces, no
    // leading zeros, nothing else.
    final parsed = _notation.hasMatch(move) ? parseHandMove(move) : null;
    if (parsed == null) return 'not a decision';
    if (parsed.hand != turn.hand) return 'not the hand to play';
    if (!round.legalActions().contains(parsed.action)) return 'not allowed now';
    return null;
  }

  @override
  void act(int seat, String move) {
    if (check(seat, move) case final reason?) throw ArgumentError(reason);
    final round = _round!;
    final before = round.shoe.dealt.length;
    final wasHidden = round.holeCardHidden;
    round.apply(parseHandMove(move)!.action);
    // A mid-round reshuffle of the discards restarts the count of dealt
    // cards; then at least one card came.
    final after = round.shoe.dealt.length;
    _lastCards = after >= before ? after - before : 1;
    _lastTurned = wasHidden && !round.holeCardHidden;
  }

  /// No who-goes-first step: the seats play in order.
  @override
  int get openingMs => 0;

  /// Stand, or turning down an offer (No insurance, Keep playing): always
  /// legal, never a risk taken for someone who isn't there.
  @override
  String autoMove(int seat, {bool absent = false}) {
    final round = _round!;
    final legal = round.legalActions();
    final action = const [
      BlackjackAction.stand,
      BlackjackAction.noInsurance,
      BlackjackAction.keepPlaying,
    ].firstWhere(legal.contains, orElse: () => legal.first);
    return handMove(round.turn!.hand, action);
  }

  /// A moment for the move, then the time for its cards to fly in one
  /// after another (BlackjackDealing.gap) and the hole card to turn over.
  @override
  int playbackMs(String move) => 300 + 230 * _lastCards + (_lastTurned ? 400 : 0);

  Map<String, Object?> get _public => blackjackPublicView(_round!, roundNo: _roundNo);

  @override
  Map<String, Object?> seatView(int seat) => {..._public, 'you': seat};

  /// With the host's switch on, the face-down hole card too (the dealer's
  /// card counts as the bots').
  @override
  Map<String, Object?> spectatorView({required bool seesBots}) {
    final round = _round!;
    return {..._public, if (seesBots && round.holeCardHidden) 'hole': cardText(round.dealerCards[1])};
  }

  /// `{"nets": [...]}`: what each seat won or lost, insurance included.
  @override
  Map<String, Object?> roundResult() => {'nets': roundScores};

  @override
  List<num> get roundScores {
    final round = _round;
    if (round == null || !round.isOver) return const [];
    return [for (var s = 0; s < round.seats.length; s++) wireNumber(round.result(s).net)];
  }
}
