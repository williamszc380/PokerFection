/// One shoe of blackjack as a game record, and the game played back from
/// it: what the most recent game keeps, and (cut down) what the coach and
/// bot jobs get.
///
/// One shoe is one record. Its moves are, in order:
/// - `"d"`: deal a round, the player betting 1;
/// - `"<hand>:<letter>"`: a decision for the player's hand number `<hand>`
///   (0 before any split), the letter one of H S D P R (Hit, Stand, Double,
///   sPlit, suRrender), I N (Insurance, No insurance) or K (Keep playing,
///   turning down early surrender).
///
/// The dealer draws inside the engine, so the dealer has no moves. The
/// shoe is stored as its seed (the engine's random generator gives the same
/// shuffle everywhere), so replaying the moves rebuilds every card.
library;

import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../blackjack.dart';
import '../moves.dart';

export '../moves.dart';

/// The record codec's version; a saved shoe of another version is ignored.
const blackjackRecordVersion = 1;

/// The move that deals the next round.
const dealMove = 'd';

/// With a continuous shuffler the cut card never comes out, so a "shoe"
/// ends after this many rounds.
const continuousShuffleRounds = 50;

/// The player's seat: the only one (one player, betting 1 per round).
const playerSeat = 0;

/// The dealer, as a seat in the record, so the shoe's result can say who
/// won ("Dealer wins"). The dealer never has a move.
const dealerSeat = 1;

/// The record of a new shoe: [rules], the [seed] that shuffles it, the
/// player and the dealer (named [dealerName] in the player's language),
/// and the setup's choices in [extra].
GameRecord newBlackjackRecord({
  required BlackjackRules rules,
  required int seed,
  required String playerName,
  required String dealerName,
  Map<String, Object?> extra = const {},
}) => GameRecord(
  game: GameKeys.blackjack,
  version: blackjackRecordVersion,
  seed: seed,
  rules: rules.toJson(),
  seats: [
    SeatSpec(human: true, name: playerName),
    SeatSpec(human: false, name: dealerName),
  ],
  deal: {'shoeSeed': seed},
  extra: extra,
);

/// A shoe being played: the table, the round on it, and the player's
/// winnings. Built from the rules and the shoe's seed, then moved on with
/// [apply]; [BlackjackPlay.replay] rebuilds it from a record.
class BlackjackPlay {
  /// A fresh shoe for [rules], shuffled by [shoeSeed].
  BlackjackPlay(this.rules, {required int shoeSeed}) : table = BlackjackTable(rules, seed: shoeSeed);

  /// The shoe in [record] after all its moves. Throws if the record is
  /// broken or a move is illegal.
  factory BlackjackPlay.replay(GameRecord record) {
    final play = BlackjackPlay(BlackjackRules.fromJson(record.rules), shoeSeed: record.deal['shoeSeed']! as int);
    for (final move in record.moves) {
      play.apply(move);
    }
    return play;
  }

  /// The shoe a job's input describes (a record's `jobJson`). Throws if
  /// it isn't a blackjack record of this version.
  factory BlackjackPlay.fromJobJson(Object? json) => BlackjackPlay.replay(
    GameRecord.fromJson(json, game: GameKeys.blackjack, version: blackjackRecordVersion) ??
        (throw const FormatException('not a blackjack record')),
  );

  final BlackjackRules rules;
  final BlackjackTable table;

  /// The round being played, or the last one (shown until the next deal);
  /// null before the first deal.
  BlackjackRound? round;

  /// Rounds dealt so far.
  int rounds = 0;

  /// What each finished round won or lost, in bets.
  final List<double> roundNets = [];

  /// The player's winnings over the finished rounds, in bets.
  double get net => roundNets.fold(0.0, (a, b) => a + b);

  /// No round is being played: the next move is a deal (or the shoe is over).
  bool get betweenRounds => round == null || round!.isOver;

  /// The shoe is finished: the cut card came out (with a continuous
  /// shuffler, [continuousShuffleRounds] were played) and the last round
  /// is over. A new shoe is a new game.
  bool get shoeOver {
    if (rounds == 0 || !betweenRounds) return false;
    return rules.continuousShuffle ? rounds >= continuousShuffleRounds : table.shoe.needsShuffle;
  }

  /// The player's turn in the round: their hand to play (0 for the offers
  /// before play), or null between rounds.
  int? get handToPlay {
    final r = round;
    if (r == null || r.isOver) return null;
    return r.turn?.hand;
  }

  /// The moves the player may make now.
  List<String> legalMoves() {
    if (shoeOver) return const [];
    if (betweenRounds) return const [dealMove];
    final r = round!;
    final hand = r.turn!.hand;
    return [for (final a in r.legalActions()) handMove(hand, a)];
  }

  /// Plays [move] (see the library comment). Throws if it isn't legal now,
  /// and then nothing changes.
  void apply(String move) {
    if (shoeOver) throw StateError('the shoe is over');
    if (move == dealMove) {
      if (!betweenRounds) throw StateError('a round is being played');
      round = table.deal(const [1]);
      rounds++;
      _settle();
      return;
    }
    final parsed = parseHandMove(move);
    final r = round;
    if (parsed == null || r == null || r.isOver || r.turn?.hand != parsed.hand) {
      throw StateError('$move is not legal now');
    }
    r.apply(parsed.action);
    _settle();
  }

  /// Books a round that just ended (a deal can end at once: a blackjack).
  void _settle() {
    final r = round!;
    if (r.isOver && roundNets.length < rounds) roundNets.add(r.result(playerSeat).net);
  }

  /// What the player knows now (only during a round).
  BlackjackView view() => round!.viewFor(playerSeat);
}

/// Whether [record] plays back: the check a saved shoe passes before the
/// setup, the menu's Last game or the review use it (a broken shoe, or one
/// an older engine dealt differently, throws on replay).
bool blackjackReplays(GameRecord record) {
  try {
    BlackjackPlay.replay(record);
    return true;
  } on Object {
    return false;
  }
}

/// Whether move [index] of [record] answers an even-money offer: the
/// player's blackjack against the dealer's ace, where insurance is called
/// "Even money". Insurance and No insurance answer both kinds of offer, so
/// only the shoe up to that move can tell which one it was.
bool evenMoneyAtMove(GameRecord record, int index) {
  final round = BlackjackPlay.replay(record.upTo(index)).round;
  return round != null && round.phase == RoundPhase.insurance && round.viewFor(playerSeat).offersEvenMoney;
}
