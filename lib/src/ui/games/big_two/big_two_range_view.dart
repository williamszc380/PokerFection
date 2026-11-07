import 'package:flutter/material.dart' hide Card;

import '../../../app/app_settings.dart';
import '../../../games/big_two/big_two.dart';
import '../../kit/range_sheet.dart';
import '../../widgets/card_view.dart' show SuitIcon;
import 'big_two_coach_view.dart';
import 'l10n/big_two_strings.dart';

/// How the range sheet names Big Two's ranks and combinations (see
/// big_two_range.dart for the kinds and how the job writes each instance):
/// the ranks as the cards show them ("10", not "T"), each kind by the
/// combination's own name ("Pair", "Full house"; "2s: 1+" for the 2s), and
/// each instance drawn: rank chips for pairs, runs and full houses, the
/// suit for a flush, the cards themselves for straight flushes and the 2s.
RangeLook bigTwoRangeLook(BigTwoStrings strings) => RangeLook(
  rankLabel: bigTwoRankLabel,
  comboLabel: (kind) => bigTwoComboLabel(strings, kind),
  comboText: bigTwoComboText,
  comboWidget: (context, combo) => BigTwoComboView(combo: combo),
  terms: [
    for (final term in const [
      BigTwoTerm.pair,
      BigTwoTerm.triple,
      BigTwoTerm.straight,
      BigTwoTerm.flush,
      BigTwoTerm.fullHouse,
      BigTwoTerm.fourOfAKind,
      BigTwoTerm.straightFlush,
    ])
      strings.entry(term),
  ],
);

/// A rank as the job writes it ('3' .. 'T' .. '2') as the cards show it.
String bigTwoRankLabel(String rank) {
  final i = Ranks.chars.indexOf(rank);
  return i < 0 ? rank : Ranks.labels[i];
}

/// A kind of combination by its name in the player's language.
String bigTwoComboLabel(BigTwoStrings strings, String kind) => switch (kind) {
  'pair' => strings.kind(PlayKind.pair),
  'triple' => strings.kind(PlayKind.triple),
  'straight' => strings.kind(PlayKind.straight),
  'flush' => strings.kind(PlayKind.flush),
  'fullHouse' => strings.kind(PlayKind.fullHouse),
  'quads' => strings.kind(PlayKind.fourOfAKind),
  'straightFlush' => strings.kind(PlayKind.straightFlush),
  _ when kind.startsWith('twos:') => strings.twosHeld(int.tryParse(kind.substring(5)) ?? 1),
  _ => kind,
};

/// An instance as text: "7 7", "3 4 5 6 7", "♠ ×5", "2♥ 2♠".
String bigTwoComboText(String combo) {
  if (combo.startsWith('flush:')) {
    final suit = Suit.values.where((s) => s.letter == combo.substring(6)).firstOrNull;
    return '${suit?.symbol ?? '?'} ×5';
  }
  return combo
      .split('-')
      .map((part) => part.length == 2 ? _cardOf(part)?.label ?? part : bigTwoRankLabel(part))
      .join(' ');
}

Card? _cardOf(String code) {
  try {
    return Card.parse(code);
  } on FormatException {
    return null;
  }
}

/// One instance of a combination, drawn small: plain rank chips ("7 7",
/// a run), the suit for a flush ("♠ ×5"), real cards when the suits matter
/// (a straight flush, which 2s).
class BigTwoComboView extends StatelessWidget {
  const BigTwoComboView({super.key, required this.combo, this.height = 20});

  final String combo;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (combo.startsWith('flush:')) {
      final suit = Suit.values.where((s) => s.letter == combo.substring(6)).firstOrNull;
      if (suit == null) return Text(combo);
      final style = AppSettings.of(context).cardFaces;
      final face = bigTwoFace(Card.of(0, suit)).suit;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Chip(
            height: height,
            color: style.face(face),
            child: SuitIcon(suit: face, size: height * 0.6, color: style.ink(face)),
          ),
          Text(
            ' ×5',
            style: TextStyle(fontSize: height * 0.6, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    final parts = combo.split('-');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final part in parts)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: switch (part.length == 2 ? _cardOf(part) : null) {
              final card? => MiniCard(card: card, height: height),
              null => _Chip(
                height: height,
                color: const Color(0xFFE8E8E8),
                child: Text(
                  bigTwoRankLabel(part),
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: height * 0.6,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            },
          ),
      ],
    );
  }
}

/// A small rounded chip like MiniCard's, for a rank alone or a suit alone.
class _Chip extends StatelessWidget {
  const _Chip({required this.height, required this.color, required this.child});

  final double height;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    constraints: BoxConstraints(minWidth: height * 0.8),
    padding: EdgeInsets.symmetric(horizontal: height * 0.12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height * 0.18),
      border: Border.all(color: Colors.black26, width: 0.5),
    ),
    child: child,
  );
}
