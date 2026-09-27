import '../bots/bot.dart';
import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/positions.dart';
import '../game/table_session.dart';

/// What one seat looks like on screen right now. This lags behind the engine
/// while animations play.
class SeatView {
  SeatView({required this.info, required this.stack});

  final PlayerInfo info;

  /// The bot's actual style (random ones resolved); null for the user.
  BotStyle? style;
  int stack;

  /// Chips in front of the player on this street.
  int bet = 0;
  Position? position;

  /// Cards whose faces we know (the user's own, or revealed at showdown).
  List<PlayingCard> cards = const [];

  /// How many cards (0-2) are in front of the player.
  int cardsHeld = 0;
  bool faceUp = false;
  bool folded = false;
  bool allIn = false;

  /// The action shown by the seat (until the street's bets are collected).
  ActionTaken? action;
  ActionKind? lastAction;

  /// Chips won this hand, shown as a highlight.
  int won = 0;

  void resetForHand(int newStack, Position? newPosition) {
    stack = newStack;
    position = newPosition;
    bet = 0;
    cards = const [];
    cardsHeld = 0;
    faceUp = false;
    folded = false;
    allIn = false;
    action = null;
    lastAction = null;
    won = 0;
  }
}

class TableViewState {
  TableViewState(this.seats);

  final List<SeatView> seats;
  int? buttonSeat;
  int? actingSeat;
  final List<PlayingCard> board = [];

  /// Collected pots, main pot first. Zero once paid out.
  List<int> pots = const [];

  /// Every pot paid, to show as a line like "Bob wins 12 BB · Two Pair, Ks and 7s".
  final List<PotResult> results = [];

  /// The user's result for the hand that just finished.
  int? heroResult;
}

enum AnchorKind { seat, seatCards, bet, pot, deck, board }

/// A named spot on the table. The table widget turns it into screen
/// coordinates, so animations follow the layout when the window is resized.
class Anchor {
  const Anchor(this.kind, [this.index = 0]);
  const Anchor.seat(int seat) : this(AnchorKind.seat, seat);
  const Anchor.seatCards(int seat) : this(AnchorKind.seatCards, seat);
  const Anchor.bet(int seat) : this(AnchorKind.bet, seat);
  const Anchor.pot() : this(AnchorKind.pot);
  const Anchor.deck() : this(AnchorKind.deck);
  const Anchor.board(int slot) : this(AnchorKind.board, slot);

  final AnchorKind kind;
  final int index;
}

/// Chips or a card moving from one spot to another.
class FlyingItem {
  FlyingItem({
    required this.from,
    required this.to,
    required this.duration,
    this.chips = 0,
    this.card,
    this.faceUp = false,
    this.fadeOut = false,
  }) : id = _nextId++;

  static int _nextId = 0;

  final int id;
  final Anchor from;
  final Anchor to;
  final Duration duration;

  /// Chips being moved; 0 for a card.
  final int chips;
  final PlayingCard? card;
  final bool faceUp;

  /// Fade away while moving (folded cards going to the muck).
  final bool fadeOut;

  bool get isCard => chips == 0;
}

/// A pot that was paid, and whether the hand had side pots (so the main
/// pot is named as such).
class PotResult {
  const PotResult(this.award, {required this.sidePots});

  final PotAwarded award;
  final bool sidePots;
}
