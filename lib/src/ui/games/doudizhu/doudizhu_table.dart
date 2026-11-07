import 'dart:math';

import 'package:flutter/material.dart';

import '../../../games/doudizhu/doudizhu.dart';
import '../../../l10n/strings.dart';
import '../../kit/card_flights.dart';
import '../../kit/cards.dart';
import '../../kit/felt.dart';
import '../../kit/fit_text.dart';
import '../../kit/help.dart';
import '../../kit/table_pile.dart';
import 'doudizhu_cards.dart';
import 'doudizhu_coach_view.dart';
import 'doudizhu_controller.dart';
import 'doudizhu_opening.dart';
import 'l10n/doudizhu_strings.dart';

/// The deal's turns as the table's pile and its history take them, in the
/// game's order (one per entry of [DdzGame.history], so turn i of the deal
/// is pile play i, where its card flights land): the bids as words, each
/// play with its cards in reading order ([ddzPlayOrder]) and its kind, each
/// pass. The bids are not a trick: the history puts them under a heading of
/// their own ("Bidding"), then "Trick 1" over the first play; each trick
/// after it starts with the play that follows two passes.
List<PilePlay> ddzPilePlays(DdzGame game, LandlordStrings strings) {
  final out = <PilePlay>[];
  var trick = 0, played = false, passes = 0;
  for (final a in game.history) {
    switch (a.move) {
      case DdzPlay(:final play):
        if (played && passes == 2) trick++;
        played = true;
        passes = 0;
        out.add(
          PilePlay(
            seat: a.seat,
            cards: [for (final id in ddzPlayOrder(a.cardIds, play)) ddzFace(id)],
            label: strings.kind(play.type),
            trick: trick,
          ),
        );
      case DdzPass():
        passes++;
        out.add(PilePlay(seat: a.seat, pass: true, trick: trick));
      case final move:
        out.add(
          PilePlay(
            seat: a.seat,
            label: ddzMoveLabel(strings, '${a.seat}:${move.encode()}', game.rules),
            heading: strings.bidding,
          ),
        );
    }
  }
  return out;
}

/// What the felt shows: a deal at one moment, seen from the player's seat
/// (seat 0). The game screen makes one from its controller
/// ([LandlordFelt.of]); the review from the saved deal at each step.
class LandlordFelt {
  const LandlordFelt({
    required this.game,
    required this.names,
    this.toAct,
    this.over = false,
    this.winners = const [],
    this.allCards = false,
    this.showCards = false,
    this.seed = 0,
    this.bottomName,
    this.faceUpSeats = const {},
    this.bottomHand = false,
    this.kittyUp,
    this.note,
    this.playerSpot = false,
    this.scores = const [],
    this.dealing,
  });

  /// The game as it stands, as the controller has it; while the deal's
  /// first step runs, the cards dealt so far, the first bidder outlined
  /// once named.
  factory LandlordFelt.of(LandlordController c) => LandlordFelt(
    game: c.dealing?.game ?? c.game,
    dealing: c.dealing,
    names: [for (var s = 0; s < 3; s++) c.seatName(s)],
    toAct: switch (c.dealing) {
      final d? => d.landed ? d.order.firstBidder : null,
      null => c.isOver ? null : (c.seatToAct ?? c.thinkingSeat),
    },
    over: c.isOver,
    winners: c.winners,
    showCards: c.showOpponentCards,
    seed: c.record.seed,
  );

  final DdzGame game;

  /// The bots' names by seat (the player's own seat is always "Player", in
  /// the app's language).
  final List<String> names;

  /// The seat whose turn it is, outlined; null: nobody's (the deal is over).
  final int? toAct;

  /// The deal is over: the winners are outlined and the bots' last cards
  /// are turned up.
  final bool over;
  final List<int> winners;

  /// The review's All cards: the bots' hands and the kitty face up.
  final bool allCards;

  /// Training's Show cards: the bots' hands face up (on the screen only:
  /// the coach never sees them; the kitty keeps to the rules).
  final bool showCards;

  /// Whether the bots' hands are face up: after the deal, in the review's
  /// All cards, or with Training's Show cards.
  bool get handsUp => over || allCards || showCards;

  /// The deal's seed: how the plays lie on the pile (each deal its own way,
  /// the same on every redraw and in the review).
  final int seed;

  // What a room's table changes (lib/src/ui/games/doudizhu/online/): the
  // seat at the bottom is the player's, or for a spectator someone's whose
  // cards may show; the solo game leaves them all as they are.

  /// The bottom seat's name; null: the player's ("Player" in the app's
  /// language).
  final String? bottomName;

  /// Seats whose hands are face up besides [handsUp]'s (a spectator sees
  /// every person's hand, and the bots' with the host's switch).
  final Set<int> faceUpSeats;

  /// The bottom seat's hand on the felt, under its badge, as the bots' are
  /// (a spectator has no hand fan of their own).
  final bool bottomHand;

  /// Whether the kitty is face up; null: once taken, if the rules show it
  /// or the player is the landlord.
  final bool? kittyUp;

  /// A few words beside the kitty's name (the multiplier, "×4").
  final String? note;

  /// The bottom seat's badge is where its plays fly from (a room: the hand
  /// fan is outside the table's flights).
  final bool playerSpot;

  /// Each seat's total in a room ("12", "−4"), on its badge; empty (the
  /// solo game) or null for a seat: none (the solo game keeps its match in
  /// the scoreboard).
  final List<String?> scores;

  /// The step that opens the deal, while it runs (doudizhu_opening.dart):
  /// [game] is then the cards dealt so far, the rest in the stack in the
  /// middle. Null: the deal is dealt.
  final LandlordDealing? dealing;
}

/// The felt: the two bots at the top corners (seat 2 on the left, seat 1 on
/// the right, the next to play) with the kitty between them, the player's
/// badge at the bottom right (clear of the hand's Sort button), and the
/// deal's plays piled up a little messily in the middle (TablePile: the
/// latest on top, the one to beat; a tap opens the deal's history, the bids
/// included). Roles show on the seats once the landlord is known.
///
/// Under each bot's badge, its hand: a small fan of card backs (SeatHand,
/// up to six; the badge says how many), turned face up after the deal, in
/// the review's All cards and with Training's Show cards. A bot that went
/// out has nothing left to show. The cards everyone has seen
/// (DdzGame.visibleIn: the face-up card that decided the first bidder, the
/// shown kitty in the landlord's hand) show face up among the backs, with
/// the kit's eye on the corner and "Everyone can see this card" under the
/// mouse or on a long press; among faces they carry the eye where they
/// are. None once the deal is over: every hand is face up then. In Training a bot's seat opens its range
/// when tapped ([seatTap], RangeTap).
///
/// Every deal opens with who bids first (LandlordFelt.dealing, see
/// doudizhu_opening.dart): the cards go round from a stack in the middle,
/// the face-up card flies from it face up to its holder's seat, and then
/// the middle names the first bidder ("Ana bids first", with a "?" on the
/// face-up card) until the first bid. The review's first step and a game
/// at Instant show those words alone.
///
/// Plays fly in from the hand or the bots' seats, and the kitty flies to
/// the landlord: the controller launches the flights, the places are here
/// ([kittyTag], [lordCardTag], [deckTag], [faceUpTag] and the bots'
/// seats).
class LandlordTable extends StatelessWidget {
  const LandlordTable({super.key, required this.felt, required this.strings, this.seatTap});

  final LandlordFelt felt;
  final LandlordStrings strings;

  /// Wraps a bot's seat (its badge and hand) to open its range on a tap
  /// (the game: RangeTap); null: the seats are only shown (the review).
  final Widget Function(int seat, Widget child)? seatTap;

  /// Kitty card [k] (as the kitty shows them, highest first): where its
  /// flight to the landlord starts.
  static Object kittyTag(int k) => ('kitty', k);

  /// Where kitty card [k] lands on a bot landlord's badge (the player's
  /// land in the hand, at HandFan.flightTag).
  static Object lordCardTag(int seat, int k) => ('lord card', seat, k);

  /// The top of the stack the deal's first step deals from: where the
  /// face-up card's flight starts.
  static const Object deckTag = ('ddz deck',);

  /// Where the face-up card lands in a seat drawn without a hand fan (a
  /// bot's, a spectator's bottom seat), at the end of its cards; the
  /// player's lands in the fan, at HandFan.flightTag.
  static Object faceUpTag(int seat) => ('face-up card', seat);

  @override
  Widget build(BuildContext context) {
    final game = felt.game;
    final player = S.of(context).you;
    final names = [for (var s = 0; s < 3; s++) s == LandlordController.you ? felt.bottomName ?? player : felt.names[s]];
    return FeltArea(
      child: LayoutBuilder(
        builder: (context, box) {
          // Cards under the badges and in the kitty grow with the felt,
          // within reason.
          final cardWidth = (min(box.maxHeight * 0.2, box.maxWidth * 0.08)).clamp(16.0, 56.0);
          // A badge too wide for its room gets its role under it (it would
          // shrink, then cut its words, by itself: SeatBadge).
          Widget seat(int s, Alignment align) => LayoutBuilder(
            builder: (context, room) {
              final name = names[s];
              final role = _role(s);
              final under =
                  role != null && _badgeWidth(context, name, role, game.handSize(s), _score(s)) > room.maxWidth;
              final start = align.x < 0;
              final bot = s != LandlordController.you;
              // A bot's hand under its badge: backs, or faces (see
              // LandlordFelt.handsUp). Nothing once it went out.
              final count = game.handSize(s);
              final hand = (bot || felt.bottomHand) && count > 0;
              final up = hand && (felt.handsUp || felt.faceUpSeats.contains(s));
              final visible = felt.over ? const <int>[] : game.visibleIn(s);
              // While the deal opens, the face-up card's seat keeps room for
              // it from the start, so nothing jumps when it lands.
              final opening = felt.dealing?.order;
              final marked = visible.isNotEmpty || (opening?.faceUp != null && s == opening!.firstBidder);
              // Faces are bigger than backs: their corners must read. A
              // visible card among the backs is a face too, so the backs
              // grow to the faces' least size with it.
              final face = (cardWidth * 0.8).clamp(18.0, 44.0);
              final small = (cardWidth * 0.7).clamp(marked ? 18.0 : 14.0, 30.0);
              final handWidth = up
                  ? _BotFaces.widthFor(count, face, room.maxWidth)
                  : _backsWidth(count, visible.length, small);
              // A role under the badge shares the cards' line when the
              // cards still read there (the pile keeps its room), else it
              // gets its own line.
              final beside = under && hand && room.maxWidth - _RoleChip.width(context, role) - 4 >= handWidth;
              final column = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: start ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  _seatBadge(s, name, under ? null : role),
                  if (under && !beside) Padding(padding: const EdgeInsets.only(top: 2), child: _RoleChip(role)),
                  if (hand)
                    Padding(
                      // The eye rises above a visible card's corner: room
                      // for it, so it doesn't cover the badge or the role.
                      padding: EdgeInsets.only(
                        top: marked ? max(3.0, GameCardView.markRise(up ? face : small) - 1) : 3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        textDirection: start ? TextDirection.ltr : TextDirection.rtl,
                        children: [
                          if (beside) ...[_RoleChip(role), const SizedBox(width: 4)],
                          Flexible(
                            child: _landingPlace(
                              s,
                              up ? face : small,
                              up
                                ? _BotFaces(
                                    key: ValueKey(felt.over ? 'left $s' : 'hand $s'),
                                    ids: ddzSorted(game.hands[s]),
                                    visible: {...visible},
                                    cardWidth: face,
                                    alignEnd: !start,
                                  )
                                : SeatHand(
                                    key: ValueKey('backs $s'),
                                    count: count,
                                    cardWidth: small,
                                    maxBacks: _maxBacks,
                                    visibleToAll: [for (final id in ddzSorted(visible)) ddzFace(id)],
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
              final tap = seatTap;
              return Align(alignment: align, child: bot && tap != null ? tap(s, column) : column);
            },
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The bots at the corners, the kitty between them (where the
              // Chinese apps show the landlord's three cards).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: seat(2, Alignment.topLeft)),
                  const SizedBox(width: 8),
                  // Smaller rather than cut when the seats take the room.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * 0.3),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: _Kitty(
                        game: game,
                        faceUp: felt.allCards,
                        up: felt.kittyUp,
                        note: felt.note,
                        cardWidth: (cardWidth * 0.75).clamp(14.0, 34.0),
                        strings: strings,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: seat(1, Alignment.topRight)),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, middle) {
                    // As big as the room between the seats allows: the
                    // pile's card and its words, with a little room to
                    // stray up and down (a pile with less than its full
                    // room strays less, see TablePile). On a sideways phone
                    // this room is short, and bigger cards read better than
                    // a wider mess.
                    final pileCard = min(
                      (middle.maxHeight - 18) / (cardAspectRatio + 0.45),
                      middle.maxWidth / 5,
                    ).clamp(16.0, 60.0);
                    final pile = TablePile(
                      key: const ValueKey('table pile'),
                      plays: ddzPilePlays(game, strings),
                      names: names,
                      cardWidth: pileCard,
                      // Once two passes end the trick, its last play is
                      // no longer the one to beat (its maker leads).
                      toBeat: game.phase != DdzPhase.playing || game.current != null,
                      passLabel: strings.pass,
                      seed: felt.seed,
                    );
                    final opening = _opening(names, pileCard, middle);
                    return Center(
                      child: opening == null ? pile : Stack(alignment: Alignment.center, children: [pile, opening]),
                    );
                  },
                ),
              ),
              // The player's badge at the bottom right, kept clear of the
              // bottom left: there the hand's Sort button rises over the
              // felt when the hand has no room above its cards (a sideways
              // phone, a low window). A badge too wide for the rest gets its
              // role under it.
              Padding(
                padding: EdgeInsets.only(left: _sortRoom(context)),
                child: seat(LandlordController.you, Alignment.bottomRight),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The middle of the felt while the deal opens: the stack the cards are
  /// dealt from, and once the face-up card has landed, who bids first.
  /// After the step, those words alone until the first bid (the result,
  /// also at Instant and in the review's first step). Null: neither.
  Widget? _opening(List<String> names, double cardWidth, BoxConstraints room) {
    final game = felt.game, dealing = felt.dealing;
    final named = dealing != null
        ? dealing.landed && game.faceUp != null
        : game.phase == DdzPhase.bidding && game.history.isEmpty && game.faceUp != null;
    final words = named
        ? _FirstBidder(text: strings.firstToBid(names[game.firstBidder], game.rules.bidding), strings: strings)
        : null;
    final stack = dealing != null && !dealing.allOut ? _DealStack(cards: dealing.inStack, cardWidth: cardWidth) : null;
    if (stack == null) return words;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: room.maxWidth, maxHeight: room.maxHeight),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [stack, ?words]),
      ),
    );
  }

  /// While the deal opens, a seat drawn without a fan gets an empty card's
  /// place at the end of its cards for the face-up card to fly to
  /// ([faceUpTag]); otherwise [cards] as they are.
  Widget _landingPlace(int seat, double width, Widget cards) {
    if (felt.dealing == null) return cards;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        cards,
        Positioned(
          right: 0,
          top: 0,
          child: IgnorePointer(
            child: FlightSlot(
              tag: faceUpTag(seat),
              child: SizedBox(width: width, height: width * cardAspectRatio),
            ),
          ),
        ),
      ],
    );
  }

  /// The most card backs a bot's fan shows (its badge gives the count).
  static const _maxBacks = 6;

  /// How wide SeatHand draws [count] cards of which [visible] are face up,
  /// at [width] each: the backs first (at most [_maxBacks]), then the faces,
  /// each card but the last showing a share of itself (a back 0.32, a face
  /// its corner, 0.45).
  static double _backsWidth(int count, int visible, double width) {
    final n = min(count - visible, _maxBacks) + visible;
    final backs = n - visible;
    var spread = 0.0;
    for (var i = 0; i < n - 1; i++) {
      spread += i < backs ? 0.32 : 0.45;
    }
    return width * (1 + spread);
  }

  /// The width the hand's Sort button may take over the felt's bottom left:
  /// its widest words, at the size it has where it rises (HandSortButton).
  static double _sortRoom(BuildContext context) =>
      HandOrder.values.map((order) => HandSortButton.sizeFor(context, order, height: 30).width).reduce(max) + 6;

  /// The seat's total in a room, if any.
  String? _score(int seat) => seat < felt.scores.length ? felt.scores[seat] : null;

  /// The seat's role once the landlord is known.
  String? _role(int seat) {
    final lord = felt.game.landlord;
    return lord == null ? null : (seat == lord ? strings.landlord : strings.peasant);
  }

  /// A seat's badge. A bot's is where its plays fly from, and where the
  /// kitty lands when it becomes the landlord.
  Widget _seatBadge(int seat, String name, String? role) {
    final badge = SeatBadge(
      key: ValueKey('seat $seat'),
      name: name,
      cardsLeft: felt.game.handSize(seat),
      toAct: felt.toAct == seat,
      role: role,
      winner: felt.over && felt.winners.contains(seat),
      score: _score(seat),
    );
    if (seat == LandlordController.you && !felt.playerSpot) return badge;
    return FlightSpot(
      tag: CardFlights.seatTag(seat),
      child: Stack(
        alignment: Alignment.center,
        children: [
          badge,
          // Three card-sized places, invisible, for the kitty to land in.
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Stack(
                  children: [
                    for (var k = 0; k < 3; k++)
                      FlightSlot(
                        tag: lordCardTag(seat, k),
                        child: const SizedBox(width: 14, height: 14 * cardAspectRatio),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// How wide a badge with [role] is at full size: its words, chips and
  /// padding. Wider than its room, the role goes under it, so every badge
  /// keeps one size instead of some shrinking (SeatBadge) and others not.
  static double _badgeWidth(BuildContext context, String name, String role, int cards, String? score) {
    const chrome = 2 * 8 + 2 * 2 + 6 + 2 * 5 + 6 + 14 + 2 + 2;
    final words =
        textWidth(context, name, const TextStyle(fontWeight: FontWeight.w600)) +
        textWidth(context, role, const TextStyle(fontSize: 11)) +
        textWidth(context, '$cards', const TextStyle(fontSize: 12)) +
        (score == null ? 0 : 6 + textWidth(context, score, const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)));
    return chrome + words;
  }
}

/// A bot's hand face up (after the deal, All cards, Show cards): highest
/// first, as players hold their cards, each showing its corner. When one
/// row would squeeze the cards past reading, they take two rows, the second
/// over the lower part of the first (the corners stay in view); past that,
/// SeatHand squeezes them.
class _BotFaces extends StatelessWidget {
  const _BotFaces({
    super.key,
    required this.ids,
    required this.cardWidth,
    this.visible = const {},
    this.alignEnd = false,
  });

  final List<int> ids;
  final double cardWidth;

  /// The cards everyone has seen (ids), marked with the eye.
  final Set<int> visible;

  /// The right-hand bot's cards line up on the right, under its badge.
  final bool alignEnd;

  /// The share of each card in view: its whole corner.
  static const _showing = 0.45;

  /// How far down the first row the second starts: the corners stay in view.
  static const _rowStep = 0.55;

  /// Cards a row of [room] holds at [width] each, every corner in view.
  static int _perRow(double width, double room) =>
      room.isFinite ? max(1, ((room - width) / (width * _showing)).floor() + 1) : 1 << 20;

  /// The rows [n] cards take: one, or two when one would squeeze them.
  static int _rows(int n, double width, double room) => n > _perRow(width, room) ? 2 : 1;

  /// The width [n] cards take in [room].
  static double widthFor(int n, double width, double room) {
    final perRow = (n / _rows(n, width, room)).ceil();
    return min(room, width + width * _showing * (perRow - 1));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, room) {
      final n = ids.length;
      final rows = _rows(n, cardWidth, room.maxWidth);
      final perRow = (n / rows).ceil();
      final height = cardWidth * cardAspectRatio;
      final align = alignEnd ? Alignment.centerRight : Alignment.centerLeft;
      Widget row(List<int> part) => SeatHand(
        count: part.length,
        faces: [for (final id in part) ddzFace(id)],
        cardWidth: cardWidth,
        visibleToAll: [
          for (final id in part)
            if (visible.contains(id)) ddzFace(id),
        ],
      );
      if (rows == 1) return Align(alignment: align, widthFactor: 1, child: row(ids));
      final width = widthFor(n, cardWidth, room.maxWidth);
      return SizedBox(
        width: width,
        height: height * (1 + _rowStep),
        child: Stack(
          children: [
            for (var r = 0; r < rows; r++)
              Positioned(
                top: r * height * _rowStep,
                left: 0,
                width: width,
                child: Align(alignment: align, child: row(ids.sublist(r * perRow, min(n, (r + 1) * perRow)))),
              ),
          ],
        ),
      );
    },
  );
}

/// A seat's role on its own line, under a badge too narrow for it (the
/// badge's own role chip, see SeatBadge).
class _RoleChip extends StatelessWidget {
  const _RoleChip(this.role);

  final String role;

  static const _style = TextStyle(fontSize: 11);

  /// How wide the chip is drawn.
  static double width(BuildContext context, String role) => textWidth(context, role, _style) + 2 * 5;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('role $role'),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(6),
    ),
    // Smaller rather than cut on a felt too narrow for the word
    // ("Terrateniente" on a 512 px wide phone).
    child: FittedBox(fit: BoxFit.scaleDown, child: Text(role, maxLines: 1, softWrap: false, style: _style)),
  );
}

/// The three kitty cards: face down until the landlord takes them, then
/// face up if the rules show them (or the player is the landlord).
class _Kitty extends StatelessWidget {
  const _Kitty({
    required this.game,
    required this.cardWidth,
    required this.strings,
    this.faceUp = false,
    this.up,
    this.note,
  });

  final DdzGame game;
  final double cardWidth;

  /// Face up whatever the rules (the review's All cards).
  final bool faceUp;

  /// Face up or down, as a room's view has it (null: by the rules).
  final bool? up;

  /// Words beside the kitty's name (LandlordFelt.note).
  final String? note;
  final LandlordStrings strings;

  @override
  Widget build(BuildContext context) {
    final lord = game.landlord;
    final up = faceUp || (this.up ?? (lord != null && (game.rules.kittyShown || lord == LandlordController.you)));
    return Column(
      key: ValueKey(up ? 'kitty up' : 'kitty down'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (k, id) in ddzSorted(game.kitty).indexed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: GameCardView(
                  width: cardWidth,
                  face: up ? ddzFace(id) : null,
                  faceUp: up,
                  flightTag: LandlordTable.kittyTag(k),
                ),
              ),
          ],
        ),
        // Named, so it isn't taken for a play.
        Text(
          note == null ? strings.kitty : '${strings.kitty} · $note',
          maxLines: 1,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }
}

/// The player's hand, fanned under the table (up to the landlord's 20 within
/// the table's width, never under the panel), in the order the player
/// chose (see LandlordController.hand); its cards are where the player's
/// plays fly from. A tap picks or unpicks a card; dragging one moves it to
/// a new place ([onReorder]), and the Sort button just above the hand's
/// left end ([sortOrder], [onSort]) sorts it by rank or by suit again.
/// While the mouse is over a coach row, every card that row's play doesn't
/// use is dimmed. The review shows it without [onToggle], the cards of the
/// move made there picked, and its Sort button greyed out. The cards
/// everyone has seen ([visible]: the face-up card, the shown kitty) carry
/// the kit's eye, and say so under the mouse or on a long press.
class LandlordHand extends StatelessWidget {
  const LandlordHand({
    super.key,
    required this.cards,
    this.visible = const {},
    this.selected = const {},
    this.preview = const {},
    this.onToggle,
    this.onReorder,
    this.sortOrder,
    this.onSort,
  });

  /// The game's hand, as the screen shows it (nothing before the deal).
  /// Once the deal is over, nothing in it moves.
  static Widget of(LandlordController c) {
    if (!c.started) return const SizedBox.shrink();
    // Nothing in it moves while the cards are still being dealt.
    final live = !c.isOver && c.dealing == null;
    return LandlordHand(
      cards: c.hand,
      visible: c.visibleInHand,
      selected: c.selected,
      preview: c.previewCards,
      onToggle: live ? c.toggle : null,
      onReorder: live ? c.reorder : null,
      sortOrder: c.arrangement.order,
      onSort: live ? c.sortTap : null,
    );
  }

  /// The card ids in hand, left to right as they are shown.
  final List<int> cards;

  /// The cards in hand everyone at the table has seen (ids); empty once the
  /// deal is over.
  final Set<int> visible;

  /// The picked cards (raised).
  final Set<int> selected;

  /// The cards of the coach row under the mouse; the others are dimmed.
  /// Empty: nothing dimmed.
  final Set<int> preview;

  /// Picks or unpicks a card (by id); null: the hand can't be touched.
  final ValueChanged<int>? onToggle;

  /// The card at [from] in [cards] was dragged to [to]; null: the cards
  /// can't be moved.
  final void Function(int from, int to)? onReorder;

  /// The order the hand is in, on its Sort button; null: no button.
  final HandOrder? sortOrder;

  /// A tap on the Sort button; null: the button is greyed out.
  final VoidCallback? onSort;

  /// The least share of each card in view, enough for a corner's whole
  /// "10" (it reaches about 45% across the card; at the kit's 18% a 10 read
  /// as "1" and a Q's tail was hidden), as in Big Two: the cards get
  /// smaller rather than overlap more.
  static const showing = 0.46;

  @override
  Widget build(BuildContext context) {
    final ids = cards;
    final toggle = onToggle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: HandFan(
        key: const ValueKey('hand'),
        cards: [for (final id in ids) ddzFace(id)],
        visibleToAll: {
          for (final (i, id) in ids.indexed)
            if (visible.contains(id)) i,
        },
        selected: {
          for (final (i, id) in ids.indexed)
            if (selected.contains(id)) i,
        },
        dimmed: preview.isEmpty
            ? const {}
            : {
                for (final (i, id) in ids.indexed)
                  if (!preview.contains(id)) i,
              },
        onToggle: toggle == null ? null : (i) => toggle(ids[i]),
        onReorder: onReorder,
        sortOrder: sortOrder,
        onSort: onSort,
        showing: showing,
      ),
    );
  }
}

/// The stack the deal's first step deals from, in the middle of the felt:
/// a few backs a little apart, fewer as it goes down; its top card is
/// where the face-up card flies from ([LandlordTable.deckTag]).
class _DealStack extends StatelessWidget {
  const _DealStack({required this.cards, required this.cardWidth});

  /// The cards still in it.
  final int cards;
  final double cardWidth;

  /// How far each card of the stack lies from the one under it.
  static const _step = 1.5;

  @override
  Widget build(BuildContext context) {
    final layers = (cards / 12).ceil().clamp(1, 5);
    return SizedBox(
      key: const ValueKey('deal stack'),
      width: cardWidth + _step * 4,
      height: cardWidth * cardAspectRatio + _step * 4,
      child: Stack(
        children: [
          for (var i = 0; i < layers; i++)
            Positioned(
              left: _step * i,
              top: _step * (4 - i),
              child: GameCardView(
                width: cardWidth,
                face: null,
                faceUp: false,
                flightTag: i == layers - 1 ? LandlordTable.deckTag : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Who opens the auction ("Ana bids first"), in the middle of the felt,
/// with a "?" on the face-up card that decided it.
class _FirstBidder extends StatelessWidget {
  const _FirstBidder({required this.text, required this.strings});

  final String text;
  final LandlordStrings strings;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Container(
      key: const ValueKey('first bidder'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          TermsHelpButton(
            title: strings.term(LandlordTerm.faceUpCard),
            terms: [strings.entry(LandlordTerm.faceUpCard)],
            all: strings.glossary,
          ),
        ],
      ),
    ),
  );
}
