/// One deal of Fight the Landlord: the bidding, the play and the score.
///
/// Rules follow Pagat (https://www.pagat.com/climbing/doudizhu.html) unless
/// a [DdzRules] switch says otherwise:
/// - 17 cards each, 3 face down (the kitty). One of the 51 cards dealt to
///   the hands is turned face up ([DdzGame.faceUp]): whoever gets it bids
///   first, and everyone sees it in that hand until it is played.
/// - Players act in seat order
///   0 → 1 → 2 → 0 (Pagat plays counter-clockwise; seat numbers follow the
///   order of play, whatever direction the app draws).
/// - The auction picks the landlord, who adds the kitty to their hand
///   (shown to all by default) and leads. The other two are a team.
/// - Each player beats the last play or passes; "passing does not prevent
///   you from playing on a future turn". After two passes in a row the
///   last player to play leads anything. The first hand to empty wins for
///   its side.
library;

import 'dart:math';

import 'cards.dart';
import 'play_gen.dart';
import 'plays.dart';
import 'rules.dart';
import 'view.dart';

/// Where a deal is.
enum DdzPhase {
  /// Choosing the landlord.
  bidding,

  /// Playing cards.
  playing,

  /// Someone went out; [DdzGame.result] has the score.
  finished,

  /// Everyone passed and the rules say redeal: deal a new game.
  thrownIn,
}

/// Something a player can do.
sealed class DdzMove {
  const DdzMove();

  /// A short string for online messages and saved games: `b2` (bid 2),
  /// `b0` (pass the auction), `c1`/`c0` (call or not), `r1`/`r0` (rob or
  /// not), `p` (pass in play) or `x` and a play (see [Play.encode]).
  String encode();

  /// Reads [encode]. Throws [FormatException] for anything else.
  static DdzMove decode(String text, [DdzRules rules = DdzRules.standard]) {
    if (text == 'p') return const DdzPass();
    if (text.length == 2) {
      // Only the digits a real move can carry: a bid of 0 to 3, a yes (1)
      // or no (0). Anything else is a corrupt save or a bad message, and
      // must not quietly turn into a decline.
      final n = int.tryParse(text[1]);
      switch (text[0]) {
        case 'b' when n != null && n >= 0 && n <= 3:
          return DdzBid(n);
        case 'c' when n == 0 || n == 1:
          return DdzCall(n == 1);
        case 'r' when n == 0 || n == 1:
          return DdzRob(n == 1);
      }
    }
    if (text.startsWith('x')) return DdzPlay(Play.decode(text.substring(1), rules));
    throw FormatException('Not a move', text);
  }
}

/// A bid in the points auction: 1, 2 or 3, or 0 to pass.
class DdzBid extends DdzMove {
  const DdzBid(this.points);
  final int points;
  bool get isPass => points == 0;
  @override
  String encode() => 'b$points';
  @override
  bool operator ==(Object other) => other is DdzBid && other.points == points;
  @override
  int get hashCode => points;
  @override
  String toString() => isPass ? 'no bid' : 'bid $points';
}

/// Calling the landlord (or declining) in the call-and-rob auction.
class DdzCall extends DdzMove {
  const DdzCall(this.yes);
  final bool yes;
  @override
  String encode() => yes ? 'c1' : 'c0';
  @override
  bool operator ==(Object other) => other is DdzCall && other.yes == yes;
  @override
  int get hashCode => yes ? 11 : 10;
  @override
  String toString() => yes ? 'call' : 'no call';
}

/// Robbing the landlord seat (or not) in the call-and-rob auction.
class DdzRob extends DdzMove {
  const DdzRob(this.yes);
  final bool yes;
  @override
  String encode() => yes ? 'r1' : 'r0';
  @override
  bool operator ==(Object other) => other is DdzRob && other.yes == yes;
  @override
  int get hashCode => yes ? 21 : 20;
  @override
  String toString() => yes ? 'rob' : 'no rob';
}

/// Playing cards.
class DdzPlay extends DdzMove {
  const DdzPlay(this.play);
  final Play play;
  @override
  String encode() => 'x${play.encode()}';
  @override
  bool operator ==(Object other) => other is DdzPlay && other.play == play;
  @override
  int get hashCode => play.hashCode;
  @override
  String toString() => play.toString();
}

/// Passing during play.
class DdzPass extends DdzMove {
  const DdzPass();
  @override
  String encode() => 'p';
  @override
  bool operator ==(Object other) => other is DdzPass;
  @override
  int get hashCode => 1;
  @override
  String toString() => 'pass';
}

/// One entry of the public history: who did what. For plays, [cardIds] are
/// the exact cards, so the app can show suits.
class DdzAction {
  const DdzAction(this.seat, this.move, [this.cardIds = const []]);
  final int seat;
  final DdzMove move;
  final List<int> cardIds;
  @override
  String toString() => '$seat:$move';
}

/// How a deal ended and what everyone scores.
class DdzResult {
  const DdzResult({
    required this.landlord,
    required this.winner,
    required this.stake,
    required this.multiplier,
    required this.bombs,
    required this.spring,
    required this.antiSpring,
    required this.points,
  });

  /// The landlord's seat.
  final int landlord;

  /// The seat that went out first.
  final int winner;

  /// The bid (points auction) or 2 to the number of robs (call and rob).
  final int stake;

  /// 2 for each bomb or rocket, and for a spring or anti-spring (capped by
  /// [DdzRules.maxMultiplier]).
  final int multiplier;

  /// Bombs and rockets played.
  final int bombs;

  /// The landlord won before either peasant played a card.
  final bool spring;

  /// The peasants won after the landlord played only one combination.
  final bool antiSpring;

  /// Points won (or lost, when negative) by each seat. Each peasant wins or
  /// loses [stake] × [multiplier]; the landlord twice that (Pagat: each
  /// opponent pays the landlord, or is paid by him).
  final List<int> points;

  bool get landlordWon => winner == landlord;

  /// Whether [seat]'s side won.
  bool wonBy(int seat) => (seat == landlord) == landlordWon;

  @override
  String toString() =>
      'winner $winner (${landlordWon ? 'landlord' : 'peasants'}), stake $stake x$multiplier, points $points';
}

/// The multiplier from bombs and spring, as the rules count it.
int ddzMultiplier(DdzRules rules, int bombs, bool spring) {
  var m = 1;
  if (rules.bombsDouble) {
    for (var i = 0; i < bombs; i++) {
      m *= 2;
    }
  }
  if (spring && rules.springDoubles) m *= 2;
  final cap = rules.maxMultiplier;
  return cap != null && m > cap ? cap : m;
}

/// The points each seat wins when [winner] goes out.
List<int> ddzPoints(int landlord, int winner, int stake, int multiplier) {
  final each = stake * multiplier;
  final sign = winner == landlord ? 1 : -1;
  return [for (var s = 0; s < 3; s++) s == landlord ? 2 * each * sign : -each * sign];
}

/// A deal in progress. Mutable: [act] changes it; [copy] makes an
/// independent one (bots and the coach never touch the real game).
class DdzGame {
  // [removed] is worked out from the hands only at the start of a deal; a
  // copy passes the original's on, since by then cards have been played
  // and the kitty may sit in the landlord's hand (both would be miscounted).
  DdzGame._(this.rules, this.firstBidder, this.hands, this.kitty, this.faceUp, [List<int>? removed])
      : toAct = firstBidder,
        _callDeclined = List.filled(3, false),
        removed = removed ?? _removedFrom(hands, kitty) {
    if (rules.players != 3) throw UnsupportedError('Only the 3-player game is supported');
  }

  static List<int> _removedFrom(List<List<int>> hands, List<int> kitty) {
    final dealt = countsOfIds([...hands.expand((h) => h), ...kitty]);
    return [for (var r = 0; r < Rank.count; r++) deckCountOf(r) - dealt[r]];
  }

  /// Shuffles and deals with [random], and turns one card face up: its
  /// holder opens the auction.
  ///
  /// Pagat: "One card is turned face up and inserted somewhere near the
  /// middle of the stack", and "The player who drew the face up card ... is
  /// the first to bid". Baidu Baike's 明牌 is the same card: "拿到明牌的玩家
  /// 有先叫地主的权利". It lies near the middle, so it always goes to a hand,
  /// never to the kitty: one of the 51 cards dealt to the hands, at random.
  ///
  /// The face-up card is drawn after the shuffle, so a seed deals the same
  /// hands as it did before there was one. Given a [firstBidder] (tests, a
  /// set opening), the face-up card is one of that seat's cards instead.
  factory DdzGame.deal({DdzRules rules = DdzRules.standard, required Random random, int? firstBidder}) {
    final deck = shuffledDeck(random);
    final hands = [deck.sublist(0, 17), deck.sublist(17, 34), deck.sublist(34, 51)];
    final int faceUp;
    final int first;
    if (firstBidder == null) {
      final i = random.nextInt(51);
      faceUp = deck[i];
      first = i ~/ 17;
    } else {
      faceUp = hands[firstBidder][random.nextInt(17)];
      first = firstBidder;
    }
    return DdzGame.fromCards(rules: rules, hands: hands, kitty: deck.sublist(51), firstBidder: first, faceUp: faceUp);
  }

  /// A deal with chosen cards. Pass [landlord] (and [stake]) to skip the
  /// auction: that seat takes the kitty and leads at once. [faceUp], when
  /// given, is the card dealt face up, which must be one of [firstBidder]'s
  /// (a set-up deal, a puzzle or an old save may have none).
  factory DdzGame.fromCards({
    DdzRules rules = DdzRules.standard,
    required List<List<int>> hands,
    required List<int> kitty,
    int firstBidder = 0,
    int? faceUp,
    int? landlord,
    int stake = 1,
  }) {
    final all = {...hands.expand((h) => h), ...kitty};
    if (all.length != hands.fold<int>(0, (n, h) => n + h.length) + kitty.length) {
      throw ArgumentError('A card is dealt twice');
    }
    // Checked before a preset landlord takes the kitty into the hand.
    if (faceUp != null && !hands[firstBidder].contains(faceUp)) {
      throw ArgumentError('The face-up card $faceUp is not one of the first bidder\'s');
    }
    final g = DdzGame._(rules, firstBidder, [for (final h in hands) [...h]..sort()], [...kitty]..sort(), faceUp);
    if (landlord != null) {
      g._presetLandlord = landlord;
      g._makeLandlord(landlord, stake);
    }
    return g;
  }

  /// Reads [toJson]: deals the saved cards and replays every move, so a
  /// saved game comes back exactly (and a corrupt one throws).
  factory DdzGame.fromJson(Map<String, Object?> json) {
    List<int> ints(Object? o) => [for (final x in o! as List) x as int];
    final g = DdzGame.fromCards(
      rules: DdzRules.fromJson((json['rules']! as Map).cast<String, Object?>()),
      hands: [for (final h in json['hands']! as List) ints(h)],
      kitty: ints(json['kitty']),
      firstBidder: json['firstBidder']! as int,
      faceUp: json['faceUp'] as int?,
      landlord: json['landlord'] as int?,
      stake: json['stake'] as int? ?? 1,
    );
    for (final m in json['moves']! as List) {
      final entry = m as List;
      final ids = entry.length > 1 ? ints(entry[1]) : null;
      g.act(DdzMove.decode(entry[0] as String, g.rules), cardIds: ids);
    }
    return g;
  }

  /// A deal from rank text, for tests: hands like `"33344455"` (see
  /// [parseRanks]). Suits are given out in order.
  factory DdzGame.fromRanks({
    DdzRules rules = DdzRules.standard,
    required List<String> hands,
    String kitty = '',
    int firstBidder = 0,
    int? landlord,
    int stake = 1,
  }) {
    final taken = <int>{};
    final ids = [for (final h in hands) idsForRanks(parseRanks(h), taken: taken)];
    final kittyIds = idsForRanks(parseRanks(kitty), taken: taken);
    return DdzGame.fromCards(
        rules: rules, hands: ids, kitty: kittyIds, firstBidder: firstBidder, landlord: landlord, stake: stake);
  }

  /// The rule switches of this deal.
  final DdzRules rules;

  /// The seat that opened the auction: the one dealt [faceUp].
  final int firstBidder;

  /// The card dealt face up (an id, one of [firstBidder]'s as dealt): its
  /// holder bids first, and everyone sees it until it is played. Null for a
  /// set-up deal (a test, a puzzle) or a game saved before there was one.
  final int? faceUp;

  /// Each seat's cards (ids, sorted). The landlord's include the kitty.
  final List<List<int>> hands;

  /// The three kitty cards (ids).
  final List<int> kitty;

  /// Rank counts of cards left out of the deal: none in a real deal; a
  /// set-up position (a puzzle, a test) may leave cards out, and everyone
  /// knows which.
  final List<int> removed;

  DdzPhase phase = DdzPhase.bidding;

  /// The seat whose turn it is (meaningless once the deal is over).
  int toAct;

  /// The landlord, once the auction is over.
  int? landlord;

  /// The bid, or 2 to the robs in call and rob; the auction's high bid so far.
  int stake = 0;

  /// Bombs and rockets played so far.
  int bombs = 0;

  /// The play to beat, or null when the player to act leads.
  Play? current;

  /// Who made [current].
  int? currentPlayer;

  /// Plays (not passes) made by each seat, for spring and anti-spring.
  final List<int> playsBySeat = [0, 0, 0];

  /// Everything that happened, in order.
  final List<DdzAction> history = [];

  DdzResult? result;

  // Set when the deal skipped the auction (see [DdzGame.fromCards]).
  int? _presetLandlord;

  // Auction state.
  int? _highBidder;
  int _passesInRow = 0;
  int _auctionPasses = 0;
  bool _robbing = false;
  int? _caller;
  int _robs = 0;
  final List<bool> _callDeclined;
  final List<int> _robQueue = [];
  bool _callerFinal = false;

  /// Each seat's rank counts.
  List<int> countsOf(int seat) => countsOfIds(hands[seat]);

  /// The cards of [seat]'s hand everyone at the table has seen: the
  /// face-up card, and the kitty once the landlord took it when the rules
  /// show it ([DdzRules.kittyShown]). Sorted ids; a card played is no longer
  /// in the hand, so it drops out by itself. (The table shows no eye once
  /// the deal is over, when every hand is face up; this answers anyway.)
  List<int> visibleIn(int seat) => [
    for (final id in hands[seat])
      if (id == faceUp || (seat == landlord && rules.kittyShown && kitty.contains(id))) id,
  ];

  /// Number of cards [seat] holds.
  int handSize(int seat) => hands[seat].length;

  /// Whether [seat] is on the landlord's side.
  bool isLandlord(int seat) => seat == landlord;

  /// Whether the player to act starts a new trick.
  bool get isLead => current == null;

  /// The stake multiplier as it stands now (bombs so far; spring counted
  /// only once the deal ends).
  int get multiplier => result?.multiplier ?? ddzMultiplier(rules, bombs, false);

  /// Whether the auction is in its rob round (call and rob only).
  bool get isRobbing => _robbing;

  /// The highest bidder or current landlord-to-be during the auction.
  int? get highBidder => _highBidder;

  /// Whether the player to act is the auction's last chance: nobody has
  /// bid or called and both others have declined, so declining now ends
  /// the auction with nobody (thrown in under [AllPassRule.redeal], the
  /// first bidder made landlord under the other rule).
  bool get isLastChance {
    if (phase != DdzPhase.bidding || _highBidder != null) return false;
    return switch (rules.bidding) {
      BiddingStyle.points => _auctionPasses == 2,
      BiddingStyle.callRob =>
        !_robbing && [for (var s = 0; s < 3; s++) s != toAct && _callDeclined[s]].where((d) => d).length == 2,
    };
  }

  /// Everything the player to act may do.
  List<DdzMove> legalMoves() {
    switch (phase) {
      case DdzPhase.bidding:
        if (rules.bidding == BiddingStyle.points) {
          return [const DdzBid(0), for (var b = stake + 1; b <= 3; b++) DdzBid(b)];
        }
        return _robbing ? const [DdzRob(false), DdzRob(true)] : const [DdzCall(false), DdzCall(true)];
      case DdzPhase.playing:
        final counts = countsOf(toAct);
        final c = current;
        if (c == null) return [for (final p in leadPlays(counts, rules)) DdzPlay(p)];
        return [const DdzPass(), for (final p in beatingPlays(counts, c, rules)) DdzPlay(p)];
      case DdzPhase.finished || DdzPhase.thrownIn:
        return const [];
    }
  }

  /// Whether [move] is legal now.
  bool isLegal(DdzMove move) {
    switch (move) {
      case DdzPlay(:final play):
        if (phase != DdzPhase.playing) return false;
        final counts = countsOf(toAct);
        for (final r in play.ranks) {
          if (--counts[r] < 0) return false;
        }
        // The play must be a real reading of its cards, rank and length
        // included: [Play.==] compares only the kind and the cards, and a
        // play made in code with the wrong rank would beat plays it can't.
        if (!classifyPlay(play.ranks, rules)
            .any((p) => p == play && p.rank == play.rank && p.length == play.length)) {
          return false;
        }
        final c = current;
        return c == null || play.beats(c);
      case DdzPass():
        return phase == DdzPhase.playing && current != null;
      default:
        return legalMoves().contains(move);
    }
  }

  /// Makes the player to act do [move]. For a play, [cardIds] may name the
  /// exact cards (different cards from the seat's hand, matching the play's
  /// ranks); otherwise the lowest suits are used. Throws [StateError] for an
  /// illegal move or wrong cards, and then nothing changes.
  void act(DdzMove move, {List<int>? cardIds}) {
    if (!isLegal(move)) throw StateError('Illegal move $move for seat $toAct');
    final seat = toAct;
    switch (move) {
      case DdzBid(:final points):
        history.add(DdzAction(seat, move));
        _bid(seat, points);
      case DdzCall(:final yes):
        history.add(DdzAction(seat, move));
        _call(seat, yes);
      case DdzRob(:final yes):
        history.add(DdzAction(seat, move));
        _rob(seat, yes);
      case DdzPlay(:final play):
        final ids = _takeCards(seat, play, cardIds);
        history.add(DdzAction(seat, move, ids));
        _play(seat, play);
      case DdzPass():
        history.add(DdzAction(seat, move));
        _passesInRow++;
        if (_passesInRow == 2) {
          current = null;
          currentPlayer = null;
          _passesInRow = 0;
        }
        toAct = (seat + 1) % 3;
    }
  }

  void _bid(int seat, int points) {
    if (points == 0) {
      _passesInRow++;
      _auctionPasses++;
      if (_highBidder != null && _passesInRow == 2) return _makeLandlord(_highBidder!, stake);
      if (_highBidder == null && _auctionPasses == 3) return _allPassed();
    } else {
      stake = points;
      _highBidder = seat;
      _passesInRow = 0;
      if (points == 3) return _makeLandlord(seat, 3);
    }
    toAct = (seat + 1) % 3;
  }

  void _call(int seat, bool yes) {
    if (!yes) {
      _callDeclined[seat] = true;
      if (_callDeclined.every((d) => d)) return _allPassed();
      toAct = (seat + 1) % 3;
      return;
    }
    _caller = seat;
    _highBidder = seat;
    stake = 1;
    _robbing = true;
    // Players after the caller who haven't declined may rob, in turn.
    for (var i = 1; i < 3; i++) {
      final s = (seat + i) % 3;
      if (!_callDeclined[s]) _robQueue.add(s);
    }
    _nextRobber();
  }

  void _rob(int seat, bool yes) {
    if (yes) {
      _robs++;
      stake *= 2;
      _highBidder = seat;
    }
    if (_callerFinal) return _makeLandlord(_highBidder!, stake);
    _nextRobber();
  }

  void _nextRobber() {
    if (_robQueue.isNotEmpty) {
      toAct = _robQueue.removeAt(0);
      return;
    }
    // Someone robbed: the caller has the last word.
    if (_robs > 0 && !_callerFinal) {
      _callerFinal = true;
      toAct = _caller!;
      return;
    }
    _makeLandlord(_highBidder!, stake);
  }

  void _allPassed() {
    if (rules.allPass == AllPassRule.redeal) {
      phase = DdzPhase.thrownIn;
      return;
    }
    _makeLandlord(firstBidder, 1);
  }

  void _makeLandlord(int seat, int finalStake) {
    landlord = seat;
    stake = finalStake;
    hands[seat]
      ..addAll(kitty)
      ..sort();
    phase = DdzPhase.playing;
    toAct = seat;
    current = null;
    currentPlayer = null;
    _passesInRow = 0;
  }

  List<int> _takeCards(int seat, Play play, List<int>? cardIds) {
    final hand = hands[seat];
    if (cardIds != null) {
      // The ids come from the player's selection, a save or a peer's
      // message: each must be a different card the seat holds, one per
      // card of the play, checked before anything is taken out of the hand.
      final ranks = cardIds.map(rankOfId).toList()..sort();
      if (cardIds.length != play.size ||
          cardIds.toSet().length != cardIds.length ||
          ranks.join(',') != play.ranks.join(',') ||
          !cardIds.every(hand.contains)) {
        throw StateError('Cards $cardIds are not the play $play');
      }
      for (final id in cardIds) {
        hand.remove(id);
      }
      return [...cardIds];
    }
    final ids = <int>[];
    for (final r in play.ranks) {
      final id = hand.firstWhere((id) => rankOfId(id) == r);
      hand.remove(id);
      ids.add(id);
    }
    return ids;
  }

  void _play(int seat, Play play) {
    current = play;
    currentPlayer = seat;
    _passesInRow = 0;
    playsBySeat[seat]++;
    if (play.isBombLike) bombs++;
    if (hands[seat].isEmpty) return _finish(seat);
    toAct = (seat + 1) % 3;
  }

  void _finish(int winner) {
    final lord = landlord!;
    final peasantPlays = playsBySeat[(lord + 1) % 3] + playsBySeat[(lord + 2) % 3];
    final spring = winner == lord && peasantPlays == 0;
    final antiSpring = winner != lord && playsBySeat[lord] == 1;
    final mult = ddzMultiplier(rules, bombs, spring || antiSpring);
    phase = DdzPhase.finished;
    result = DdzResult(
      landlord: lord,
      winner: winner,
      stake: stake,
      multiplier: mult,
      bombs: bombs,
      spring: spring,
      antiSpring: antiSpring,
      points: ddzPoints(lord, winner, stake, mult),
    );
  }

  /// The whole deal as JSON: the cards as dealt and every move, enough to
  /// replay it (the app keeps the most recent game this way for analysis).
  Map<String, Object?> toJson() {
    final start = [for (final h in hands) [...h]];
    for (final a in history) {
      start[a.seat].addAll(a.cardIds);
    }
    final lord = landlord;
    if (lord != null) start[lord].removeWhere(kitty.contains);
    for (final h in start) {
      h.sort();
    }
    final preset = _presetLandlord;
    return {
      'rules': rules.toJson(),
      'hands': start,
      'kitty': kitty,
      'firstBidder': firstBidder,
      'faceUp': ?faceUp,
      'landlord': ?preset,
      if (preset != null) 'stake': stake, // a preset deal's stake never changes
      'moves': [
        for (final a in history) [a.move.encode(), if (a.cardIds.isNotEmpty) a.cardIds],
      ],
    };
  }

  /// An independent copy.
  DdzGame copy() {
    final g = DdzGame._(rules, firstBidder, [for (final h in hands) [...h]], [...kitty], faceUp, [...removed])
      ..phase = phase
      ..toAct = toAct
      ..landlord = landlord
      ..stake = stake
      ..bombs = bombs
      ..current = current
      ..currentPlayer = currentPlayer
      ..result = result
      .._presetLandlord = _presetLandlord
      .._highBidder = _highBidder
      .._passesInRow = _passesInRow
      .._auctionPasses = _auctionPasses
      .._robbing = _robbing
      .._caller = _caller
      .._robs = _robs
      .._callerFinal = _callerFinal;
    for (var s = 0; s < 3; s++) {
      g.playsBySeat[s] = playsBySeat[s];
      g._callDeclined[s] = _callDeclined[s];
    }
    g._robQueue.addAll(_robQueue);
    g.history.addAll(history);
    return g;
  }

  /// What [seat] may know: their own cards, the public history, every
  /// hand's size, the face-up card, and the kitty once it is shown (or
  /// always for the landlord). Bots and the coach only ever see this.
  DdzView viewFor(int seat) {
    final lord = landlord;
    final seesKitty = lord != null && (rules.kittyShown || seat == lord);
    return DdzView(
      seat: seat,
      rules: rules,
      phase: phase,
      toAct: toAct,
      hand: [...hands[seat]],
      handSizes: [for (final h in hands) h.length],
      landlord: lord,
      kitty: seesKitty ? [...kitty] : null,
      stake: stake,
      bombs: bombs,
      current: current,
      currentPlayer: currentPlayer,
      playsBySeat: [...playsBySeat],
      history: List.unmodifiable(history),
      legalMoves: seat == toAct ? legalMoves() : const [],
      highBidder: _highBidder,
      firstBidder: firstBidder,
      faceUp: faceUp,
      result: result,
      removed: removed,
    );
  }

  /// What a spectator sees: everything, as the room design asks.
  List<List<int>> get allHands => [for (final h in hands) [...h]];
}
