/// Big Two's game record: one deal as the kit's GameRecord, so the most
/// recent game, the coach and bot jobs (and later the online host) share
/// one codec.
///
/// - `rules`: [BigTwoRulesCodec.encode] (the engine's own JSON).
/// - `deal`: `{"hands": ["3d 4c …", …]}`, each seat's cards as dealt in
///   [Card.short] notation; with three players also `"extra"`, the face-up
///   52nd card (it goes to the holder of the lowest card, as the engine
///   deals it); `"leader"` when a chosen seat leads instead of the holder of
///   the starting card.
/// - `moves`: `"<seat>:<cards>"`, the cards lowest first under the rules,
///   space separated (`"2:7c 7h"`), or `"<seat>:pass"`. One play has one
///   spelling, so the coach's lines and the player's moves compare as text.
///
/// Replaying is the engine dealt from those hands, then each move, checked
/// to be legal and made by the seat whose turn it is.
library;

import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../big_two.dart';
import 'big_two_rules_codec.dart';

/// The record format's version; a saved record of another one is ignored.
const bigTwoRecordVersion = 1;

/// One move of a record, read back.
typedef BigTwoRecordMove = ({int seat, Play play});

/// The record's text for [seat] making [play].
String bigTwoMoveText(int seat, Play play) =>
    '$seat:${play.isPass ? 'pass' : [for (final card in play.cards) card.short].join(' ')}';

/// Reads [bigTwoMoveText] under [rules]. Throws [FormatException] when the
/// text isn't a move or its cards make no combination.
BigTwoRecordMove bigTwoParseMove(BigTwoRules rules, String text) {
  final colon = text.indexOf(':');
  final seat = colon < 0 ? null : int.tryParse(text.substring(0, colon));
  if (seat == null || seat < 0 || seat >= rules.players) throw FormatException('Not a move', text);
  final rest = text.substring(colon + 1);
  if (rest == 'pass') return (seat: seat, play: Play.pass);
  final List<Card> cards;
  try {
    cards = parseCards(rest);
  } on FormatException {
    throw FormatException('Not a move', text);
  }
  final play = rules.classify(cards);
  if (play == null) throw FormatException('Not a combination', text);
  return (seat: seat, play: play);
}

/// The seat of a move's text (without reading its cards).
int bigTwoMoveSeat(String text) => int.parse(text.substring(0, text.indexOf(':')));

/// The cards of a move's text, as written (empty for a pass).
List<Card> bigTwoMoveCards(String text) {
  final rest = text.substring(text.indexOf(':') + 1);
  return rest == 'pass' ? const [] : parseCards(rest);
}

/// Making, reading and replaying Big Two records.
abstract final class BigTwoRecord {
  /// A new deal's record (no moves yet), the cards shuffled from [seed]
  /// (the game seed). [leader]: a chosen seat leads instead of the holder
  /// of the starting card.
  static GameRecord deal({
    required BigTwoRules rules,
    required List<SeatSpec> seats,
    required int seed,
    int? leader,
    Map<String, Object?> extra = const {},
  }) {
    final state = BigTwoState.deal(rules, seed: seed, leader: leader);
    return GameRecord(
      game: GameKeys.bigTwo,
      version: bigTwoRecordVersion,
      seed: seed,
      rules: BigTwoRulesCodec.encode(rules),
      seats: seats,
      deal: dealOf(state, leader: leader),
      extra: extra,
    );
  }

  /// The `deal` of a record for [state] before its first move.
  static Map<String, Object?> dealOf(BigTwoState state, {int? leader}) {
    final rules = state.rules;
    final extra = state.extraCode >= 0 ? rules.cardOf(state.extraCode) : null;
    return {
      'hands': [
        for (var seat = 0; seat < state.players; seat++)
          [
            for (final card in state.handOf(seat))
              if (!(seat == state.extraSeat && card == extra)) card.short,
          ].join(' '),
      ],
      'extra': ?extra?.short,
      'leader': ?leader,
    };
  }

  /// The rules of [record]. Throws [FormatException] if they are broken.
  static BigTwoRules rulesOf(GameRecord record) => BigTwoRulesCodec.decode(record.rules);

  /// The deal of [record] played up to its last move, with its history.
  /// Throws if anything in it is broken or illegal.
  static BigTwoState replay(GameRecord record) => replayJson(record.jobJson());

  /// [replay] for a record's JSON (a job's input carries
  /// GameRecord.jobJson): `rules`, `deal` and `moves`.
  static BigTwoState replayJson(Map<String, Object?> json) {
    final rules = BigTwoRulesCodec.decode(json['rules']);
    final deal = (json['deal']! as Map).cast<String, Object?>();
    final hands = [for (final hand in deal['hands']! as List) parseCards(hand as String)];
    final extra = deal['extra'] as String?;
    final state = BigTwoState.fromHands(
      rules,
      hands,
      extra: extra == null ? null : Card.parse(extra),
      leader: deal['leader'] as int?,
    );
    for (final text in json['moves']! as List) {
      final (:seat, :play) = bigTwoParseMove(rules, text as String);
      if (seat != state.toMove) throw FormatException('Not seat $seat\'s turn', text);
      state.apply(play);
    }
    return state;
  }

  /// Whether [record] replays (LastGames.load's check).
  static bool validate(GameRecord record) {
    try {
      final state = replay(record);
      return record.seats.length == state.players && record.seats.first.human;
    } on Object {
      return false;
    }
  }

  /// The result kept in a finished deal's record: the winner, each seat's
  /// points and cards left, and whether a dealt dragon won.
  static Map<String, Object?> resultOf(BigTwoState state) {
    final result = state.result;
    return {
      'winners': [result.winner],
      'scores': result.scores,
      'cardsLeft': result.cardsLeft,
      if (result.dragon) 'dragon': true,
    };
  }
}
