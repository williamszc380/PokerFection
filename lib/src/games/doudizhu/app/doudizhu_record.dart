/// Fight the Landlord's game record: one deal as the kit's GameRecord, in
/// the engine's own notation, so the most recent game, the coach and bot
/// jobs (and later the online host) share one codec.
///
/// - `rules`: [DdzRules.toJson].
/// - `deal`: [DdzGame.toJson] without its rules and moves: the hands as
///   dealt, the kitty, the first bidder and the card dealt face up
///   (`faceUp`, which decided the first bidder; older records have none).
/// - `moves`: `"<seat>:<move>"`, the move as [DdzMove.encode], and for a
///   play `"|<card ids>"` after it, e.g. `"2:xpair:77|20,23"`. The ids keep
///   the suits the player picked (the engine's notation has ranks only).
///
/// Replaying a record is [DdzGame.fromJson] on that deal, then each move,
/// checked to be made by the seat whose turn it is.
library;

import 'dart:math';

import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../doudizhu.dart';

/// The record format's version; a saved record of another one is ignored.
const ddzRecordVersion = 1;

/// One move of a record, read back.
typedef DdzRecordMove = ({int seat, DdzMove move, List<int>? cardIds});

/// The record's text for [seat] making [move] with [cardIds] (plays only).
String ddzMoveText(int seat, DdzMove move, [List<int> cardIds = const []]) =>
    '$seat:${move.encode()}${move is DdzPlay && cardIds.isNotEmpty ? '|${cardIds.join(',')}' : ''}';

/// Reads [ddzMoveText]. Throws [FormatException] for anything else.
DdzRecordMove ddzParseMove(String text, [DdzRules rules = DdzRules.standard]) {
  final colon = text.indexOf(':');
  final seat = colon < 0 ? null : int.tryParse(text.substring(0, colon));
  if (seat == null || seat < 0 || seat > 2) throw FormatException('Not a move', text);
  final bar = text.indexOf('|');
  final move = DdzMove.decode(text.substring(colon + 1, bar < 0 ? null : bar), rules);
  List<int>? ids;
  if (bar >= 0) {
    ids = [
      for (final part in text.substring(bar + 1).split(','))
        int.tryParse(part) ?? (throw FormatException('Not a card id', text)),
    ];
  }
  return (seat: seat, move: move, cardIds: ids);
}

/// The seat that made a record move: the number before its colon. It
/// reads nothing else, so it needs no rules. Throws [FormatException] when
/// there is no seat.
int ddzParseSeat(String text) {
  final colon = text.indexOf(':');
  final seat = colon < 0 ? null : int.tryParse(text.substring(0, colon));
  if (seat == null || seat < 0 || seat > 2) throw FormatException('Not a move', text);
  return seat;
}

/// Whether a move's text (or key) is an auction move: a bid, a call or a
/// rob. It reads only the move's letter, so it needs no rules: a play
/// that is legal only under the game's own variants (both jokers as
/// kickers) still answers false instead of failing to decode.
bool ddzIsAuctionMove(String text) {
  final colon = text.indexOf(':');
  if (colon < 0 || colon + 1 >= text.length) return false;
  return const {'b', 'c', 'r'}.contains(text[colon + 1]);
}

/// The part of a move's text that says what was played, without the card
/// ids: the coach rates plays by rank, so a pair of 7s is the same move
/// whichever two 7s the player picked. Coach lines use it, and grading
/// compares by it.
String ddzMoveKey(String text) {
  final bar = text.indexOf('|');
  return bar < 0 ? text : text.substring(0, bar);
}

/// The lowest-suited cards of [hand] that make [play] (what the engine
/// takes when it isn't told which): bots and the coach's "select" use it.
List<int> ddzCardsFor(List<int> hand, Play play) {
  final left = [...hand]..sort();
  final ids = <int>[];
  for (final r in play.ranks) {
    final i = left.indexWhere((id) => rankOfId(id) == r);
    if (i < 0) throw StateError('No ${Rank.label(r)} left for $play');
    ids.add(left.removeAt(i));
  }
  return ids;
}

/// The text a move made on [game] by its seat to act gets in the record
/// (the cards are the lowest suits when [cardIds] is null).
String ddzMoveTextFor(DdzGame game, DdzMove move, [List<int>? cardIds]) => ddzMoveText(
      game.toAct,
      move,
      move is DdzPlay ? cardIds ?? ddzCardsFor(game.hands[game.toAct], move.play) : const [],
    );

/// A new deal's record: the cards shuffled from [seed] (the game seed);
/// one of the 51 dealt to the hands is turned face up, and its holder
/// opens the auction (Pagat). Given a [firstBidder], that seat opens it,
/// with one of its own cards face up.
GameRecord ddzNewRecord({
  required int seed,
  required DdzRules rules,
  required List<SeatSpec> seats,
  int? firstBidder,
  Map<String, Object?> extra = const {},
}) {
  final game = DdzGame.deal(rules: rules, random: Random(seed), firstBidder: firstBidder);
  return GameRecord(
    game: GameKeys.doudizhu,
    version: ddzRecordVersion,
    seed: seed,
    rules: rules.toJson(),
    seats: seats,
    deal: ddzDealOf(game),
    extra: extra,
  );
}

/// [game]'s cards as dealt (its toJson without rules and moves).
Map<String, Object?> ddzDealOf(DdzGame game) => {...game.toJson()}
  ..remove('rules')
  ..remove('moves');

/// [record] in the engine's own JSON (what [DdzGame.toJson] gives for the
/// same deal and moves).
Map<String, Object?> ddzEngineJson(GameRecord record) {
  final rules = ddzRulesOf(record);
  return {
    'rules': record.rules,
    ...record.deal,
    'moves': [
      for (final text in record.moves)
        if (ddzParseMove(text, rules) case (seat: _, :final move, :final cardIds)) [move.encode(), ?cardIds],
    ],
  };
}

/// The rules of [record].
DdzRules ddzRulesOf(GameRecord record) => DdzRules.fromJson(record.rules);

/// The game [record] describes, with its moves played (the first [upTo]
/// only, when given). Throws on a record that doesn't replay: a move out of
/// turn, an illegal move or cards the seat doesn't hold.
DdzGame ddzReplay(GameRecord record, {int? upTo}) {
  final rules = ddzRulesOf(record);
  final game = DdzGame.fromJson({...record.deal, 'rules': record.rules, 'moves': const []});
  final moves = upTo == null || upTo >= record.moves.length ? record.moves : record.moves.sublist(0, upTo);
  for (final text in moves) {
    ddzApply(game, text, rules);
  }
  return game;
}

/// Plays one record move on [game]: the seat must be the one to act.
/// Throws (and changes nothing) otherwise.
void ddzApply(DdzGame game, String text, [DdzRules? rules]) {
  final (:seat, :move, :cardIds) = ddzParseMove(text, rules ?? game.rules);
  final open = game.phase == DdzPhase.bidding || game.phase == DdzPhase.playing;
  if (!open || seat != game.toAct) throw StateError('Seat $seat moved out of turn: $text');
  game.act(move, cardIds: cardIds);
}

/// [json] (a saved record or a job's input) as a Fight the Landlord record,
/// or null when it isn't one.
GameRecord? ddzRecordFromJson(Object? json) =>
    GameRecord.fromJson(json, game: GameKeys.doudizhu, version: ddzRecordVersion);

/// Whether [record] replays (LastGames.load's check).
bool ddzReplays(GameRecord record) {
  try {
    ddzReplay(record);
    return true;
  } on Object {
    return false;
  }
}
