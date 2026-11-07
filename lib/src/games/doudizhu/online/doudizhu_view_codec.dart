/// Fight the Landlord's online notation: the views the room sends, the
/// moves the devices send back, and the way a device turns a view back
/// into a game it can draw, check moves on and hand to its bot or coach.
///
/// Pure Dart (the room runs on a host's device, in a browser or in
/// bin/server.dart): it reads only the engine's cards, plays, rules and
/// game.
///
/// **Cards** travel as two characters, rank then suit ("Tc", "3d"), and the
/// jokers as "B" (little, black) and "R" (big, red): [ddzCardCode]. As
/// strings, a hidden card can be told apart from every number in a view,
/// which is how the runner test looks for leaks.
///
/// **A seat's view**, in this key order:
/// - `rules`: the deal's DdzRules.toJson;
/// - `first`: the seat that opened the auction;
/// - `faceUp`: the card dealt face up to that seat, which made it the first
///   to bid (Pagat). Everyone sees it, every seat and the spectators, the
///   bots' seats included, whatever the host's switch says: it stays shown
///   in that hand until it is played;
/// - `redeals`: the deals thrown in this round so far (everyone passed);
/// - `lord`: the landlord, once the auction made one;
/// - `you`: the seat, and `hand`: its cards;
/// - `kitty`: the three kitty cards, when this seat may see them (the
///   landlord always; everyone once taken, if the rules show it);
/// - `moves`: the deal so far, each `[seat, move]` with the move as
///   DdzMove.encode, a play with its cards: `[2, "xpair:77", ["7c", "7d"]]`;
/// - `left`: once the deal is over, every hand's last cards (all are shown).
///
/// **The spectators' view** has `hands` (seat → cards: every person's, the
/// bots' only with the host's switch) in place of `you` and `hand`, and the
/// kitty once taken when the rules show it or the spectators see the
/// landlord's hand (which holds it). Neither ever holds a kitty not yet
/// taken, the cards of a deal thrown in, or anything about the shuffle.
///
/// Legal moves are never sent: a device replays the moves ([DdzWireView]
/// and its replay) and asks the engine.
///
/// **A move** is the game record's move text: `"<seat>:<move>"`, and for a
/// play the card ids after a bar, `"1:xpair:77|20,23"` (see
/// doudizhu_record.dart, whose functions read it too).
library;

import '../cards.dart';
import '../game.dart';
import '../plays.dart';
import '../rules.dart';

/// The version of these views and moves (OnlineGame.gv): 2 since the views
/// carry the face-up card.
const ddzOnlineVersion = 2;

/// The most cards a play can have (the landlord's whole hand).
const _maxPlayCards = 20;

/// Card [id] on the wire: "Tc", "3d", "2s", "B" (little joker), "R" (big
/// joker).
String ddzCardCode(int id) => DdzCard(id).toString();

/// The card [code] names ([ddzCardCode]), or null when it names none.
int? ddzCardOf(Object? code) {
  if (code is! String) return null;
  if (code == 'B') return 52;
  if (code == 'R') return 53;
  if (code.length != 2) return null;
  final rank = Rank.chars.indexOf(code[0]);
  final suit = 'cdhs'.indexOf(code[1]);
  if (rank < 0 || rank > Rank.two || suit < 0) return null;
  return rank * 4 + suit;
}

/// [ids] on the wire, lowest id first.
List<String> ddzCardCodes(Iterable<int> ids) => [
  for (final id in [...ids]..sort()) ddzCardCode(id),
];

/// One move of the record notation, read back.
typedef DdzOnlineMove = ({int seat, DdzMove move, List<int>? cardIds});

/// [seat] making [move] (with [cardIds] for a play) as the devices send it.
String ddzOnlineMoveText(int seat, DdzMove move, [List<int> cardIds = const []]) =>
    '$seat:${move.encode()}${move is DdzPlay && cardIds.isNotEmpty ? '|${cardIds.join(',')}' : ''}';

/// Reads a move a member sent ([ddzOnlineMoveText]) under [rules]. Throws
/// [FormatException] for anything else; it never reads more than a play's
/// worth of cards, so a long junk string costs nothing.
DdzOnlineMove ddzReadOnlineMove(String text, DdzRules rules) {
  if (text.length < 3 || text[1] != ':') throw FormatException('Not a move', text);
  final seat = '012'.indexOf(text[0]);
  if (seat < 0) throw FormatException('Not a seat', text);
  final bar = text.indexOf('|');
  final body = text.substring(2, bar < 0 ? null : bar);
  // A play's ranks after "x<kind>:" are at most a hand's worth.
  if (body.length > 40) throw FormatException('Too long', text);
  final move = DdzMove.decode(body, rules);
  List<int>? ids;
  if (bar >= 0) {
    final parts = text.substring(bar + 1).split(',');
    if (move is! DdzPlay || parts.length > _maxPlayCards) throw FormatException('Not the cards of a play', text);
    ids = [
      for (final part in parts)
        switch (int.tryParse(part)) {
          final id? when id >= 0 && id < 54 && part.length <= 2 => id,
          _ => throw FormatException('Not a card', text),
        },
    ];
  }
  return (seat: seat, move: move, cardIds: ids);
}

/// The deal's moves as the views carry them.
List<List<Object>> _movesOf(DdzGame game) => [
  for (final a in game.history) [a.seat, a.move.encode(), if (a.move is DdzPlay) ddzCardCodes(a.cardIds)],
];

/// Every hand's last cards, once the deal is over (null before).
List<List<String>>? _leftOf(DdzGame game) =>
    game.phase == DdzPhase.finished ? [for (final h in game.hands) ddzCardCodes(h)] : null;

/// A seat's view, from its parts (one builder for the runner and the
/// codec, so a view rebuilt from the spectators' is the same JSON).
Map<String, Object?> _seatView({
  required Object? rules,
  required Object? first,
  required Object? faceUp,
  required Object? redeals,
  required Object? lord,
  required int you,
  required Object? hand,
  required Object? kitty,
  required Object? moves,
  required Object? left,
}) => {
  'rules': rules,
  'first': first,
  'faceUp': ?faceUp,
  'redeals': redeals,
  'lord': ?lord,
  'you': you,
  'hand': hand,
  'kitty': ?kitty,
  'moves': moves,
  'left': ?left,
};

/// The card dealt face up on the wire, or null for a deal with none (a
/// set-up deal; the room's always have one).
String? _faceUpOf(DdzGame game) => switch (game.faceUp) {
  final id? => ddzCardCode(id),
  null => null,
};

/// Whether [seat] may see [game]'s kitty: once the landlord took it, the
/// landlord always and the others when the rules show it; everyone once
/// the deal is over.
bool _seesKitty(DdzGame game, int seat) {
  final lord = game.landlord;
  if (game.phase == DdzPhase.finished) return true;
  return lord != null && (game.rules.kittyShown || seat == lord);
}

/// What hand seat [seat] sees of [game] ([redeals]: deals thrown in this
/// round before it).
Map<String, Object?> ddzSeatView(DdzGame game, int seat, {required int redeals}) => _seatView(
  rules: game.rules.toJson(),
  first: game.firstBidder,
  faceUp: _faceUpOf(game),
  redeals: redeals,
  lord: game.landlord,
  you: seat,
  hand: ddzCardCodes(game.hands[seat]),
  kitty: _seesKitty(game, seat) ? ddzCardCodes(game.kitty) : null,
  moves: _movesOf(game),
  left: _leftOf(game),
);

/// What the spectators see of [game]: the hands of the seats in [shown]
/// (every person's; the bots' too with the host's switch), the kitty once
/// taken if the rules show it or [shown] has the landlord, and every card
/// once the deal is over.
Map<String, Object?> ddzSpectatorView(DdzGame game, {required Set<int> shown, required int redeals}) {
  final lord = game.landlord;
  final over = game.phase == DdzPhase.finished;
  final kitty = over || (lord != null && (game.rules.kittyShown || shown.contains(lord)));
  return {
    'rules': game.rules.toJson(),
    'first': game.firstBidder,
    'faceUp': ?_faceUpOf(game),
    'redeals': redeals,
    'lord': ?lord,
    if (!over)
      'hands': {
        for (var s = 0; s < 3; s++)
          if (shown.contains(s)) '$s': ddzCardCodes(game.hands[s]),
      },
    if (kitty) 'kitty': ddzCardCodes(game.kitty),
    'moves': _movesOf(game),
    'left': ?_leftOf(game),
  };
}

/// Hand seat [seat]'s view rebuilt from the spectators' view (the coach's
/// and the runner test's): exactly what the room sends that seat, or null
/// when the spectators don't see its hand (a bot, the host's switch off).
Map<String, Object?>? ddzSeatViewFrom(Map<String, Object?> spectatorView, int seat) {
  if (seat < 0 || seat > 2) return null;
  final left = spectatorView['left'];
  final Object? hand;
  if (left is List && left.length == 3) {
    hand = left[seat];
  } else {
    final hands = spectatorView['hands'];
    hand = hands is Map ? hands['$seat'] : null;
  }
  if (hand is! List) return null;
  final lord = spectatorView['lord'];
  final rules = spectatorView['rules'];
  final shown = rules is Map && rules['kittyShown'] != false;
  // The spectators see the kitty whenever this seat does: it is this
  // seat's (the landlord's) or shown to all, or the deal is over.
  final kitty = left != null || (lord != null && (shown || lord == seat)) ? spectatorView['kitty'] : null;
  return _seatView(
    rules: rules,
    first: spectatorView['first'],
    faceUp: spectatorView['faceUp'],
    redeals: spectatorView['redeals'],
    lord: lord,
    you: seat,
    hand: hand,
    kitty: kitty,
    moves: spectatorView['moves'],
    left: left,
  );
}

/// A view (a seat's or the spectators'), read: what a device draws and
/// replays. Seats here are the round's hand seats.
class DdzWireView {
  const DdzWireView({
    required this.rules,
    required this.first,
    this.faceUp,
    required this.redeals,
    required this.lord,
    required this.you,
    required this.hands,
    required this.kitty,
    required this.moves,
    required this.over,
  });

  /// Reads a view; throws [FormatException] when it isn't one.
  factory DdzWireView.read(Map<String, Object?> json) {
    final rulesJson = json['rules'];
    if (rulesJson is! Map) throw const FormatException('No rules');
    final rules = DdzRules.fromJson(rulesJson.cast<String, Object?>());
    int seatOf(Object? s) => s is int && s >= 0 && s < 3 ? s : throw FormatException('Not a seat', s);
    List<int> cards(Object? list) => list is List
        ? [for (final code in list) ddzCardOf(code) ?? (throw FormatException('Not a card', code))]
        : throw FormatException('Not cards', list);
    final hands = <int, List<int>>{};
    final left = json['left'];
    final you = json['you'] == null ? null : seatOf(json['you']);
    if (left is List) {
      if (left.length != 3) throw const FormatException('Not three hands');
      for (var s = 0; s < 3; s++) {
        hands[s] = cards(left[s]);
      }
    } else if (you != null) {
      hands[you] = cards(json['hand']);
    } else if (json['hands'] case final Map<Object?, Object?> shown) {
      for (final MapEntry(:key, :value) in shown.entries) {
        hands[seatOf(int.tryParse('$key'))] = cards(value);
      }
    }
    final moves = <DdzOnlineMove>[];
    for (final m in json['moves'] as List? ?? (throw const FormatException('No moves'))) {
      if (m is! List || m.length < 2 || m[1] is! String) throw FormatException('Not a move', m);
      final move = DdzMove.decode(m[1] as String, rules);
      moves.add((seat: seatOf(m[0]), move: move, cardIds: m.length > 2 ? cards(m[2]) : null));
    }
    final faceUp = json['faceUp'];
    return DdzWireView(
      rules: rules,
      first: seatOf(json['first']),
      faceUp: faceUp == null ? null : ddzCardOf(faceUp) ?? (throw FormatException('Not a card', faceUp)),
      redeals: json['redeals'] is int ? json['redeals']! as int : 0,
      lord: json['lord'] == null ? null : seatOf(json['lord']),
      you: you,
      hands: hands,
      kitty: json['kitty'] == null ? null : cards(json['kitty']),
      moves: moves,
      over: left != null,
    );
  }

  final DdzRules rules;
  final int first;

  /// The card dealt face up to [first] (null in a view without one).
  final int? faceUp;

  /// Deals thrown in this round before this one.
  final int redeals;
  final int? lord;

  /// The seat whose view this is; null: the spectators'.
  final int? you;

  /// The hands this view holds, by seat (their current cards).
  final Map<int, List<int>> hands;
  final List<int>? kitty;
  final List<DdzOnlineMove> moves;

  /// The deal is over (every hand is shown).
  final bool over;

  /// This view with every seat moved back by [base] (seat [base] becomes
  /// 0): the table draws the player's own seat at the bottom, as seat 0.
  /// Play goes 0 → 1 → 2, so turning keeps the order.
  DdzWireView rotated(int base) {
    if (base % 3 == 0) return this;
    int turn(int seat) => (seat - base) % 3;
    return DdzWireView(
      rules: rules,
      first: turn(first),
      faceUp: faceUp,
      redeals: redeals,
      lord: lord == null ? null : turn(lord!),
      you: you == null ? null : turn(you!),
      hands: {for (final MapEntry(:key, :value) in hands.entries) turn(key): value},
      kitty: kitty,
      moves: [for (final m in moves) (seat: turn(m.seat), move: m.move, cardIds: m.cardIds)],
      over: over,
    );
  }

  /// The deal replayed: a game whose hands this view holds are the real
  /// ones and whose other cards (in hands it doesn't hold, a kitty it
  /// doesn't see) are stand-ins, the cards nobody here can see, given out
  /// in id order. Everything public (whose turn, the play to beat, the
  /// multiplier, the result) and the legal moves of a seat whose hand it
  /// holds are the real game's; the stand-ins are never to be shown or
  /// told to anyone (a seat's DdzGame.viewFor holds only its own hand and
  /// a kitty it may see, so the bots and the coach never meet them). Null
  /// when the view doesn't replay (it can't happen with the room's).
  DdzGame? replay() {
    try {
      // The auction never reads the cards: play it on any deal to learn the landlord.
      final auction = DdzGame.fromCards(
        rules: rules,
        hands: [
          for (var s = 0; s < 3; s++) [for (var i = 0; i < 17; i++) s * 17 + i],
        ],
        kitty: const [51, 52, 53],
        firstBidder: first,
      );
      for (final m in moves) {
        if (auction.phase != DdzPhase.bidding) break;
        if (m.seat != auction.toAct) return null;
        auction.act(m.move);
      }
      final lord = auction.landlord;
      final played = [<int>[], <int>[], <int>[]];
      for (final m in moves) {
        played[m.seat].addAll(m.cardIds ?? const []);
      }
      // The face-up card is known to all: it stays in the first bidder's
      // hand (the stand-ins never take its place) until it is played.
      final faceUp = this.faceUp;
      final known = <int>{for (final h in hands.values) ...h, ...?kitty, for (final p in played) ...p, ?faceUp};
      final faceUpHeld = faceUp != null && !hands.containsKey(first) && !played[first].contains(faceUp);
      final unseen = [
        for (var id = 0; id < 54; id++)
          if (!known.contains(id)) id,
      ];
      var next = 0;
      List<int> standIns(int n) {
        if (n < 0 || next + n > unseen.length) throw const FormatException('The cards don\'t add up');
        return unseen.sublist(next, next += n);
      }

      // A landlord's hand known without its kitty can't be split.
      if (kitty == null && lord != null && hands.containsKey(lord)) return null;
      var kittyIds = kitty;
      final dealt = <List<int>>[];
      for (var s = 0; s < 3; s++) {
        if (s != lord) {
          final cards = [...?hands[s], ...played[s], if (s == first && faceUpHeld) faceUp];
          if (!hands.containsKey(s)) cards.addAll(standIns(17 - cards.length));
          dealt.add(cards);
          continue;
        }
        // The landlord's 20: the 17 dealt and the kitty. A kitty this view
        // doesn't see is any three of them (played ones too: it went into
        // the hand), the stand-ins first.
        final all = {...?hands[s], ...played[s], ...?kitty, if (s == first && faceUpHeld) faceUp}.toList();
        // The face-up card was dealt to this hand, never in the kitty: kept
        // out of the three an unseen kitty is taken from.
        if (faceUp != null && all.remove(faceUp)) all.insert(0, faceUp);
        if (!hands.containsKey(s)) all.addAll(standIns(20 - all.length));
        if (all.length != 20) return null;
        final taken = kittyIds ??= all.sublist(17);
        if (!taken.every(all.contains)) return null;
        dealt.add([
          for (final id in all)
            if (!taken.contains(id)) id,
        ]);
      }
      kittyIds ??= standIns(3);
      if (next != unseen.length || dealt.any((cards) => cards.length != 17)) return null;
      final game = DdzGame.fromCards(rules: rules, hands: dealt, kitty: kittyIds, firstBidder: first, faceUp: faceUp);
      for (final m in moves) {
        if (game.phase != DdzPhase.bidding && game.phase != DdzPhase.playing) return null;
        if (m.seat != game.toAct) return null;
        game.act(m.move, cardIds: m.cardIds);
      }
      for (final MapEntry(key: s, value: cards) in hands.entries) {
        if (([...cards]..sort()).join(',') != game.hands[s].join(',')) return null;
      }
      return game;
    } on Object {
      return null;
    }
  }
}

/// The cheap legal move an absent player makes (time ran out, or they are
/// away): declining in the auction (no bid, no call, no rob), passing when
/// following, and leading the lowest single card. No search: a few
/// microseconds.
///
/// One exception, with [standIn] (the room plays a seat nobody is
/// playing, or a table where nobody acts; see DoudizhuRunner.autoMove):
/// under the default rule (Pagat: "If everyone passes the hand is thrown
/// in and there is a new deal"), the auction's last chance bids 1 (or
/// calls) instead of declining. Declining there throws the deal in within
/// the same round, so a table where every seat is away (idle, gone or out
/// of time) would redeal forever: the round would never end, and End game,
/// which waits for a round's end, would never take effect. Taking the
/// landlord at the lowest stake is what the other rule does too
/// ([AllPassRule.firstBidderLandlord]); the deal is then played out as
/// usual. Without [standIn] it declines, as a player at the table who does
/// nothing does.
String ddzAutoMove(DdzGame game, {bool standIn = false}) {
  final seat = game.toAct;
  if (game.phase == DdzPhase.bidding) {
    if (standIn && game.rules.allPass == AllPassRule.redeal && game.isLastChance) {
      final take = switch (game.rules.bidding) {
        BiddingStyle.points => const DdzBid(1),
        BiddingStyle.callRob => const DdzCall(true),
      };
      return ddzOnlineMoveText(seat, take);
    }
    final decline = switch (game.rules.bidding) {
      BiddingStyle.points => const DdzBid(0),
      BiddingStyle.callRob => game.isRobbing ? const DdzRob(false) : const DdzCall(false),
    };
    return ddzOnlineMoveText(seat, decline);
  }
  if (game.current != null) return ddzOnlineMoveText(seat, const DdzPass());
  // Hands are kept sorted by id, and ids go up with the rank.
  final low = game.hands[seat].first;
  final play = Play.decode('solo:${Rank.chars[rankOfId(low)]}', game.rules);
  return ddzOnlineMoveText(seat, DdzPlay(play), [low]);
}
