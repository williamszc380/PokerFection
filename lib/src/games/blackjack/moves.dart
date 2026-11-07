/// The decisions' move notation, shared by the solo game's record and the
/// room's runner: `"<hand>:<letter>"`, a decision for the seat's hand number
/// `<hand>` (0 before any split), the letter one of H S D P R (Hit, Stand,
/// Double, sPlit, suRrender), I N (Insurance, No insurance) or K (Keep
/// playing, turning down early surrender). Pure Dart with no kit imports,
/// so the room's server can use it.
library;

import 'action.dart';

/// The letter of each decision in the move notation.
const Map<BlackjackAction, String> actionLetters = {
  BlackjackAction.hit: 'H',
  BlackjackAction.stand: 'S',
  BlackjackAction.double: 'D',
  BlackjackAction.split: 'P',
  BlackjackAction.surrender: 'R',
  BlackjackAction.insurance: 'I',
  BlackjackAction.noInsurance: 'N',
  BlackjackAction.keepPlaying: 'K',
};

/// The move for [action] on the player's hand number [hand].
String handMove(int hand, BlackjackAction action) => '$hand:${actionLetters[action]}';

/// A hand move read back: its hand and decision; null for anything else
/// (the deal move included).
({int hand, BlackjackAction action})? parseHandMove(String move) {
  final colon = move.indexOf(':');
  if (colon < 1) return null;
  final hand = int.tryParse(move.substring(0, colon));
  final letter = move.substring(colon + 1);
  if (hand == null || hand < 0) return null;
  for (final MapEntry(key: action, value: l) in actionLetters.entries) {
    if (l == letter) return (hand: hand, action: action);
  }
  return null;
}
