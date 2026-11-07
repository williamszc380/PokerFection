import 'package:flutter/material.dart';

import '../../../games/doudizhu/app/doudizhu_grading.dart';
import '../../../games/doudizhu/app/doudizhu_record.dart';
import '../../../games/doudizhu/doudizhu.dart';
import '../../kit/coach_panel.dart';
import '../../kit/help.dart';
import '../../kit/l10n/game_strings.dart';
import 'doudizhu_cards.dart';
import 'doudizhu_controller.dart';
import 'l10n/doudizhu_strings.dart';

/// A record move or move key in words: "Pair 77", "Trio 999 + 4", "Bid 2",
/// "Pass", "Rocket". The move is read under [rules], the game's own.
String ddzMoveLabel(LandlordStrings s, String move, DdzRules rules) {
  final DdzMove m;
  try {
    m = ddzParseMove(move, rules).move;
  } on FormatException {
    return move;
  }
  return switch (m) {
    DdzBid(:final points) => points == 0 ? s.noBid : s.bid(points),
    DdzCall(:final yes) => yes ? s.call : s.noCall,
    DdzRob(:final yes) => yes ? s.rob : s.noRob,
    DdzPass() => s.pass,
    DdzPlay(:final play) => ddzPlayLabel(s, play),
  };
}

/// A play in words: its kind and its cards ("Straight 34567"); a single
/// joker by its name, the rocket by its kind alone.
String ddzPlayLabel(LandlordStrings s, Play play) {
  if (play.type == PlayType.rocket) return s.kind(play.type);
  if (play.type == PlayType.solo && play.rank >= Rank.littleJoker) return s.joker(big: play.rank == Rank.bigJoker);
  String cards(List<int> ranks) {
    final labels = [for (final r in ranks) r >= Rank.littleJoker ? s.joker(big: r == Rank.bigJoker) : Rank.label(r)];
    // "77" reads fine; "10 10" and the jokers' names need spaces.
    return labels.any((l) => l.length > 1) ? labels.join(' ') : labels.join();
  }

  final kickers = play.kickers;
  final main = cards(play.mainRanks);
  return '${s.kind(play.type)} ${kickers.isEmpty ? main : '$main + ${cards(kickers)}'}';
}

/// How the coach list and the grade card show Fight the Landlord's moves:
/// plays as their kind and small cards, bids and passes as words, the
/// coach's reasons as a few words, proofs as "Sure win". Moves are read
/// under [rules] (the game's own), and a play's cards are drawn in the
/// suits of [cards] where it can (the player's hand). [onHover], [onSelect]
/// and [onPlay]: the game's hover preview, single tap (select) and double
/// tap (play); [selected]: the row lit. The review has none of them.
CoachLook ddzLook(
  LandlordStrings s, {
  required DdzRules rules,
  required List<int> Function() cards,
  void Function(String? move)? onHover,
  void Function(String move)? onSelect,
  void Function(String move)? onPlay,
  String? selected,
}) => CoachLook(
  moveText: (move) => ddzMoveLabel(s, move, rules),
  moveWidget: (context, move) => _MoveCell(strings: s, rules: rules, cards: cards(), move: move),
  reasonText: (code) => switch (DdzReason.values.asNameMap()[code]) {
    final reason? => s.reason(reason),
    null => null,
  },
  proofText: (proof) => switch (proof) {
    ddzSureWin => s.sureWin,
    ddzSureLoss => s.sureLoss,
    _ => null,
  },
  onHover: onHover,
  onSelect: onSelect,
  onPlay: onPlay,
  selected: selected,
);

/// The game's look: rows in the player's own suits (the hand, then the
/// cards already played, for the grade card's move); hovering a row dims
/// every other card of the hand. A single tap selects the row's move (a
/// play's cards pop up; Pass or a bid lights its button), never playing
/// it; a double tap plays it. The row of the picked cards' play is lit
/// (or, with no cards picked, the choice lit: GameScaffold).
CoachLook landlordLook(LandlordController controller, LandlordStrings s) => ddzLook(
  s,
  rules: controller.rules,
  cards: () {
    if (!controller.started) return const [];
    final game = controller.game;
    return [
      ...game.hands[LandlordController.you],
      for (final a in game.history.reversed)
        if (a.seat == LandlordController.you) ...a.cardIds,
    ];
  },
  onHover: (move) => controller.preview = move,
  onSelect: controller.selectMove,
  onPlay: controller.playFromRow,
  selected: controller.selectedKey,
);

/// A coach row's move: the kind of play and its cards, or the bid's words.
class _MoveCell extends StatelessWidget {
  const _MoveCell({required this.strings, required this.rules, required this.cards, required this.move});

  final LandlordStrings strings;
  final DdzRules rules;
  final List<int> cards;
  final String move;

  @override
  Widget build(BuildContext context) {
    final DdzMove m;
    try {
      m = ddzParseMove(move, rules).move;
    } on FormatException {
      return Text(move);
    }
    const style = TextStyle(fontWeight: FontWeight.w600);
    if (m is! DdzPlay) return Text(ddzMoveLabel(strings, move, rules), style: style, maxLines: 1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.kind(m.play.type), style: style, maxLines: 1),
        const SizedBox(width: 6),
        DdzMiniCards(
          ids: ddzIdsForRanks(m.play.ranks, preferred: cards),
          width: 18,
          play: m.play,
        ),
      ],
    );
  }
}

/// The card counter: how many of each rank are still in the other hands
/// (or the kitty during the auction), from the player's own view. Ranks
/// all gone are greyed; four left (a bomb may be out there) and both
/// jokers left (a rocket) stand out.
class LandlordCardCounter extends StatelessWidget {
  const LandlordCardCounter({super.key, required this.count, required this.strings, required this.help});

  final DdzCardCount count;
  final LandlordStrings strings;

  /// The entries its "?" opens.
  final List<GameTerm> help;

  @override
  Widget build(BuildContext context) {
    const order = [14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0];
    final rocket = count.rocketOut;
    Widget label(int r) => r >= Rank.littleJoker
        ? Text('★', style: TextStyle(fontSize: 12, color: r == Rank.bigJoker ? const Color(0xFFFF6B6B) : Colors.white))
        : Text(Rank.label(r), style: const TextStyle(fontSize: 12, color: Colors.white70));
    Widget number(int r) {
      final n = count.unseen[r];
      final hot = (r <= Rank.two && n == 4) || (r >= Rank.littleJoker && rocket);
      return Text(
        '$n',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: n == 0 ? Colors.white24 : (hot ? const Color(0xFFFFB74D) : Colors.white),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    return Padding(
      key: const ValueKey('card counter'),
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 3, 0, 3),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(8)),
        // The ranks and their counts, with the "?" (which names it) beside them.
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (final r in order)
                    Expanded(
                      child: Column(
                        children: [
                          FittedBox(child: label(r)),
                          FittedBox(child: number(r)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            TermsHelpButton(title: strings.cardCounter, terms: help),
          ],
        ),
      ),
    );
  }
}

/// The peasants' team line: the partner and their cards left, and the
/// coach's teamwork advice for this turn when it has some ("Your partner
/// wins the trick", "Leads low for your partner").
class LandlordTeamLine extends StatelessWidget {
  const LandlordTeamLine({super.key, required this.controller, required this.strings});

  final LandlordController controller;
  final LandlordStrings strings;

  static const teamwork = {DdzReason.partnerWinning, DdzReason.leadsSmallForPartner};

  @override
  Widget build(BuildContext context) {
    final game = controller.game;
    final lord = game.landlord;
    if (lord == null || lord == LandlordController.you || game.phase != DdzPhase.playing) {
      return const SizedBox.shrink();
    }
    final partner = 3 - lord - LandlordController.you;
    final advice = controller.training && controller.coachVisible ? controller.advice : null;
    final tip = advice == null || advice.lines.isEmpty
        ? null
        : advice.lines.first.reasons.where(teamwork.contains).firstOrNull;
    return Padding(
      key: const ValueKey('team line'),
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.handshake_outlined, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              [
                '${strings.partner}: ${controller.seatName(partner)} · ${strings.cardsLeft(game.handSize(partner))}',
                if (tip != null) strings.reason(tip),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
