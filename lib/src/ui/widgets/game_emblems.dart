import 'dart:math';

import 'package:flutter/material.dart';

import '../../engine/cards.dart';
import 'card_view.dart';
import 'gomoku_board.dart';

// The small pictures of the games on Home and on their menus, all drawn
// in code, each in a size by size square. The cards and the board follow
// the player's looks (Settings).

/// Hold'em: two hole cards, A♠ K♥.
class HoldemEmblem extends StatelessWidget {
  const HoldemEmblem({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => _Fan(size: size, cards: ['As', 'Kh'], spread: 0.4);
}

/// Big Two: the four 2s, the game's best cards (♦ ♣ ♥ ♠, the best last).
class BigTwoEmblem extends StatelessWidget {
  const BigTwoEmblem({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => _Fan(size: size, cards: ['2d', '2c', '2h', '2s'], spread: 0.26);
}

/// Fight the Landlord: the landlord's three hidden cards under a crown.
class LandlordEmblem extends StatelessWidget {
  const LandlordEmblem({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              top: size * 0.16,
              child: Center(child: _Fan(size: size * 0.84, cards: [null, null, null], spread: 0.3)),
            ),
            Positioned(
              left: size * 0.32,
              right: size * 0.32,
              top: 0,
              height: size * 0.22,
              child: const CustomPaint(painter: _CrownPainter()),
            ),
          ],
        ),
      );
}

/// Gomoku: a corner of a board, with black about to make five.
class GomokuEmblem extends StatelessWidget {
  const GomokuEmblem({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Padding(
          padding: EdgeInsets.all(size * 0.06),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.08),
            child: const GomokuBoard(
              lines: 7,
              stones: {
                (1, 5): Stone.black,
                (2, 4): Stone.black,
                (3, 3): Stone.black,
                (4, 2): Stone.black,
                (2, 3): Stone.white,
                (3, 2): Stone.white,
                (4, 3): Stone.white,
              },
              lastMove: (4, 2),
            ),
          ),
        ),
      );
}

/// Blackjack: a blackjack as the dealer lays it on the table, a face card
/// with an ace overlapping it (J♠ A♠), slightly askew, not held in a fan
/// like Hold'em's cards.
class BlackjackEmblem extends StatelessWidget {
  const BlackjackEmblem({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final width = size * 0.46;
    Widget card(String name, double angle, Offset offset) => Transform.translate(
          offset: offset,
          child: Transform.rotate(angle: angle, child: CardView(width: width, card: PlayingCard.parse(name))),
        );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          card('Js', -0.14, Offset(-size * 0.13, -size * 0.04)),
          card('As', 0.1, Offset(size * 0.13, size * 0.05)),
        ],
      ),
    );
  }
}

/// Cards held in a fan ([spread]: the angle between two cards), face down
/// where a card is null.
class _Fan extends StatelessWidget {
  const _Fan({required this.size, required this.cards, required this.spread});

  final double size;
  final List<String?> cards;
  final double spread;

  @override
  Widget build(BuildContext context) {
    final width = size * 0.46, height = width * cardAspectRatio;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (final (i, card) in cards.indexed)
            Transform.rotate(
              angle: (i - (cards.length - 1) / 2) * spread,
              // Turned around a point below the cards, like a hand of cards.
              origin: Offset(0, height * 0.9),
              child: Transform.translate(
                offset: Offset(0, size * 0.06),
                child: CardView(
                  width: width,
                  card: card == null ? null : PlayingCard.parse(card),
                  faceUp: card != null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small gold crown.
class _CrownPainter extends CustomPainter {
  const _CrownPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final crown = Path()
      ..moveTo(0, h * 0.3)
      ..lineTo(w * 0.28, h * 0.58)
      ..lineTo(w * 0.5, h * 0.1)
      ..lineTo(w * 0.72, h * 0.58)
      ..lineTo(w, h * 0.3)
      ..lineTo(w * 0.86, h)
      ..lineTo(w * 0.14, h)
      ..close();
    canvas.drawPath(
      crown,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE082), Color(0xFFFFB300)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.75, w * 0.04)
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF8D6E00),
    );
    for (final x in [0.0, 0.5, 1.0]) {
      canvas.drawCircle(
        Offset(w * x, x == 0.5 ? h * 0.1 : h * 0.3),
        max(1.0, w * 0.06),
        Paint()..color = const Color(0xFFFFE082),
      );
    }
  }

  @override
  bool shouldRepaint(_CrownPainter old) => false;
}
