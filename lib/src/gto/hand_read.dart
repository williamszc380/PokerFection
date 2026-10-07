import 'dart:math';
import 'dart:typed_data';

import '../engine/cards.dart';
import '../engine/hand_evaluator.dart';
import 'combos.dart';
import 'spot_strategy.dart';

/// A quick read of the user's hand against one opponent's range, to say why
/// a play was a mistake.
class HandRead {
  const HandRead({required this.beaten, this.threat, this.flushDraw = false, this.straightDraw = false});

  /// How much of their range (by weight) beats the user's hand right now (0-1).
  final double beaten;

  /// What most of the hands that beat it are; null if none does.
  final HandCategory? threat;

  /// The user has four cards to a flush, or an open-ended straight draw,
  /// with cards still to come.
  final bool flushDraw;
  final bool straightDraw;
}

/// Reads [hole] on [board] (flop, turn or river) against [range]: weights per
/// two-card combination (0-1325). Null without a board or a range.
HandRead? readHand(List<PlayingCard> hole, List<PlayingCard> board, Float64List range) {
  if (board.length < 3) return null;
  final boardCards = [for (final c in board) c.index];
  final dead = {for (final c in hole) c.index, ...boardCards};
  final mine = evaluateIndices([for (final c in hole) c.index, ...boardCards]);
  var total = 0.0, beaten = 0.0;
  final threats = <HandCategory, double>{};
  for (var c = 0; c < comboCount; c++) {
    final w = range[c];
    if (w <= 0 || dead.contains(comboLow[c]) || dead.contains(comboHigh[c])) continue;
    total += w;
    final theirs = evaluateIndices([comboLow[c], comboHigh[c], ...boardCards]);
    if (theirs <= mine) continue;
    beaten += w;
    final category = HandValue(theirs).category;
    threats[category] = (threats[category] ?? 0) + w;
  }
  if (total == 0) return null;
  final threat = threats.entries.fold<MapEntry<HandCategory, double>?>(
      null, (best, e) => best == null || e.value > best.value ? e : best)?.key;

  // Draws, only with cards to come and short of a made flush or straight.
  final made = HandValue(mine).category.index;
  final toCome = board.length < 5;
  final all = [...hole, ...board];
  var flushDraw = false, straightDraw = false;
  if (toCome && made < HandCategory.straight.index) {
    for (var suit = 0; suit < 4; suit++) {
      final suited = all.where((c) => c.suit == suit);
      if (suited.length == 4 && hole.any((c) => c.suit == suit)) flushDraw = true;
    }
    // Four ranks in a row with a card free at both ends, using a hole card.
    final ranks = {for (final c in all) c.rank};
    for (var low = 1; low + 3 < 12; low++) {
      final run = [for (var r = low; r < low + 4; r++) r];
      if (run.every(ranks.contains) && hole.any((c) => run.contains(c.rank))) straightDraw = true;
    }
  }
  return HandRead(beaten: beaten / total, threat: threat, flushDraw: flushDraw, straightDraw: straightDraw);
}

/// Why a play was a mistake, in plain words: the reason behind GTO's choice.
enum ReasonKind {
  /// Many of their hands beat the user's ([percent]%, mostly [threat]).
  behind,

  /// The user's hand beats [percent]% of their range.
  ahead,

  /// Calling needs only [odds]% (and the user beats [percent]% of their range).
  potOdds,

  /// Calling needs only [odds]% (before the flop).
  potOddsPreflop,
  flushDraw,
  straightDraw,

  /// GTO raises as a bluff: better hands fold to it.
  bluff,

  /// GTO doesn't raise a strong hand: worse hands would fold.
  keepWorseIn,

  /// Before the flop: the hand is in the top [percent]% of starting hands.
  strongStart,

  /// Before the flop: the hand is in the bottom [percent]% of starting hands.
  weakStart,
}

typedef Reason = ({ReasonKind kind, int percent, int odds, HandCategory? threat});

/// The reason to give for a [mistake] (see [mistakeOf]): from [read] after
/// the flop, from the hand's [percentile] before it (0 = the best starting
/// hand, 1 = the worst), and the pot odds when facing a bet ([odds], the
/// share of the time a call must win). Null when there is nothing simple to
/// say (a wrong size, say).
Reason? reasonFor(MistakeKind mistake, {HandRead? read, double? percentile, double? odds}) {
  Reason make(ReasonKind kind, {double share = 0, HandCategory? threat}) =>
      (kind: kind, percent: (share * 100).round(), odds: ((odds ?? 0) * 100).round(), threat: threat);
  if (mistake == MistakeKind.wrongSize) return null;
  if (read == null) {
    if (percentile == null) return null;
    final top = max(1, (percentile * 100).ceil());
    return switch (mistake) {
      MistakeKind.tooTight when odds != null && top > 50 => make(ReasonKind.potOddsPreflop),
      MistakeKind.tooTight || MistakeKind.tooPassive => make(ReasonKind.strongStart, share: top / 100),
      MistakeKind.tooAggressive when top <= 10 => make(ReasonKind.keepWorseIn),
      _ => make(ReasonKind.weakStart, share: max(1, 100 - top + 1) / 100),
    };
  }
  final ahead = 1 - read.beaten;
  return switch (mistake) {
    MistakeKind.tooTight when odds != null => make(ReasonKind.potOdds, share: ahead),
    MistakeKind.tooTight when ahead >= 0.5 => make(ReasonKind.ahead, share: ahead),
    MistakeKind.tooTight when read.flushDraw => make(ReasonKind.flushDraw),
    MistakeKind.tooTight when read.straightDraw => make(ReasonKind.straightDraw),
    MistakeKind.tooLoose || MistakeKind.tooAggressive when read.beaten >= 0.4 =>
      make(ReasonKind.behind, share: read.beaten, threat: read.threat),
    MistakeKind.tooAggressive => make(ReasonKind.keepWorseIn),
    MistakeKind.tooPassive when read.beaten <= 0.4 => make(ReasonKind.ahead, share: ahead),
    MistakeKind.tooPassive => make(ReasonKind.bluff),
    _ => null,
  };
}
