/// One round of blackjack at a table of 1 to 7 seats: the deal, the
/// offers (early surrender, insurance), the dealer's peek, the players'
/// hands seat by seat and hand by hand, the dealer's hand and the
/// settlement.
library;

import 'dart:math' as math;

import 'action.dart';
import 'cards.dart';
import 'count.dart';
import 'rules.dart';
import 'shoe.dart';

/// Where a round is.
enum RoundPhase {
  /// Early surrender is offered before the dealer checks for blackjack
  /// (hole card games with early surrender, dealer showing an ace or ten).
  earlySurrender,

  /// Insurance (even money with a blackjack) is offered: the dealer shows
  /// an ace.
  insurance,

  /// The players play their hands.
  playing,

  /// Settled; see [BlackjackRound.result].
  over,
}

/// How one hand ended.
enum HandOutcome {
  /// Not settled yet.
  pending,

  /// A blackjack, paid at the table's blackjack payout.
  blackjack,

  /// Beat the dealer (or the dealer busted).
  win,

  /// Same total as the dealer, or a blackjack against a dealer blackjack.
  push,

  /// Lower than the dealer.
  lose,

  /// Went over 21.
  bust,

  /// Lost to the dealer's blackjack.
  dealerBlackjack,

  /// Surrendered: half the bet back.
  surrender,
}

/// One player hand. Read-only outside the round.
class BlackjackHand {
  BlackjackHand._(this.bet, {this.fromSplit = false, this.splitAces = false});

  /// A hand as a view describes it, for a [BlackjackView.restored]: the
  /// online game rebuilds the deciding seat's view from the room's message
  /// (every player's cards are face up, so nothing hidden goes into it).
  /// Its outcome stays pending: only decisions are worked out from it.
  BlackjackHand.restored({
    required this.bet,
    required List<Card> cards,
    this.fromSplit = false,
    this.splitAces = false,
    this._doubled = false,
    this._surrendered = false,
    this._done = false,
  }) : _cards = List<Card>.of(cards);

  BlackjackHand._copy(BlackjackHand o)
    : bet = o.bet,
      fromSplit = o.fromSplit,
      splitAces = o.splitAces,
      _cards = List<Card>.of(o._cards),
      _doubled = o._doubled,
      _surrendered = o._surrendered,
      _done = o._done,
      _outcome = o._outcome,
      _net = o._net;

  /// The bet on this hand before any double.
  final int bet;

  /// The hand came from a split.
  final bool fromSplit;

  /// The hand came from splitting aces.
  final bool splitAces;

  List<Card> _cards = [];
  bool _doubled = false;
  bool _surrendered = false;
  bool _done = false;
  HandOutcome _outcome = HandOutcome.pending;
  double _net = 0;

  /// The cards, in the order dealt.
  List<Card> get cards => List.unmodifiable(_cards);

  /// The bet was doubled.
  bool get doubled => _doubled;

  /// The hand was surrendered.
  bool get surrendered => _surrendered;

  /// No more decisions for this hand.
  bool get done => _done;

  /// The money at risk on this hand: the bet, twice it if doubled.
  int get stake => _doubled ? bet * 2 : bet;

  /// The hand's total.
  HandTotal get total => handTotal(_cards);

  /// Over 21.
  bool get isBust => total.isBust;

  /// A two-card 21 that didn't come from a split (21 after a split is
  /// just 21: Wizard of Odds lists "ace and 10 after splitting aces is a
  /// blackjack" as a rare player-friendly variation).
  bool get isBlackjack => !fromSplit && _cards.length == 2 && total.value == 21;

  /// A two-card pair (same blackjack rank; any two ten-value cards count).
  bool get isPair => _cards.length == 2 && _cards[0].rank == _cards[1].rank;

  /// How the hand ended (pending until the round is over).
  HandOutcome get outcome => _outcome;

  /// What the hand won (positive) or lost (negative), in chips, once
  /// settled. Insurance is not included (see [SeatResult]).
  double get net => _net;

  @override
  String toString() => '${_cards.join(' ')} ($total)${_doubled ? ' doubled' : ''}${_surrendered ? ' surrendered' : ''}';
}

/// One seat: its bet, its hands, its insurance.
class BlackjackSeat {
  BlackjackSeat._(this.bet) : _hands = [BlackjackHand._(bet)];

  /// A seat as a view describes it (see [BlackjackHand.restored]).
  BlackjackSeat.restored({required this.bet, required List<BlackjackHand> hands, this._insurance})
    : _hands = List.of(hands);

  BlackjackSeat._copy(BlackjackSeat o)
    : bet = o.bet,
      _hands = [for (final h in o._hands) BlackjackHand._copy(h)],
      _insurance = o._insurance;

  /// The seat's original bet.
  final int bet;

  final List<BlackjackHand> _hands;
  bool? _insurance;

  /// The seat's hands (more than one after splitting).
  List<BlackjackHand> get hands => List.unmodifiable(_hands);

  /// Whether the seat took insurance (or even money): null if it was
  /// never offered or not yet answered.
  bool? get insurance => _insurance;

  /// The insurance bet: half the original bet.
  double get insuranceBet => bet / 2;

  /// The seat was dealt a blackjack.
  bool get hasBlackjack => _hands.length == 1 && _hands[0].isBlackjack;
}

/// A seat's result once the round is over.
class SeatResult {
  /// See the fields.
  const SeatResult({required this.net, required this.handsNet, required this.insuranceNet});

  /// Everything the seat won (positive) or lost (negative), in chips.
  final double net;

  /// What each hand won or lost.
  final List<double> handsNet;

  /// What the insurance bet won or lost (0 if none).
  final double insuranceNet;
}

/// Who acts next: a seat and one of its hands.
class Turn {
  /// Seat [seat], hand [hand].
  const Turn(this.seat, this.hand);

  /// The seat index (0 = first base, the first to act).
  final int seat;

  /// The hand index within the seat.
  final int hand;

  @override
  bool operator ==(Object other) => other is Turn && other.seat == seat && other.hand == hand;

  @override
  int get hashCode => seat * 8 + hand;

  @override
  String toString() => 'seat $seat hand $hand';
}

/// A table: the rules and the shoe, which lasts from round to round until
/// the cut card comes out.
class BlackjackTable {
  /// A table with a freshly shuffled shoe; [seed] fixes every deal.
  BlackjackTable(this.rules, {int seed = 0}) : shoe = Shoe.forRules(rules, seed: seed);

  /// The rules.
  final BlackjackRules rules;

  /// The shoe.
  final Shoe shoe;

  /// Deals the next round with these bets (one per seat).
  BlackjackRound deal(List<int> bets) => BlackjackRound.deal(rules, shoe, bets);
}

/// One round. Mutable: [apply] moves it on; [copy] gives an independent
/// round (shoe included) for look-ahead and tests.
class BlackjackRound {
  BlackjackRound._(this.rules, this.shoe, List<int> bets) : _seats = [for (final b in bets) BlackjackSeat._(b)];

  BlackjackRound._copy(BlackjackRound o)
    : rules = o.rules,
      shoe = o.shoe.copy(),
      _seats = [for (final s in o._seats) BlackjackSeat._copy(s)],
      _holeHidden = o._holeHidden,
      _peeked = o._peeked,
      _phase = o._phase,
      _turn = o._turn {
    _dealer.addAll(o._dealer);
  }

  /// Deals a new round from [shoe] (shuffled first if the cut card came
  /// out) with one bet per seat (1 to 7 seats, bets in chips, at least 1).
  /// Cards go round as at a real table: one to each seat, the dealer's
  /// upcard, a second to each seat, then the hole card (hole card games
  /// only; without a hole card the dealer's second card comes after the
  /// players have played).
  factory BlackjackRound.deal(BlackjackRules rules, Shoe shoe, List<int> bets) {
    if (bets.isEmpty || bets.length > 7) throw ArgumentError('1 to 7 seats');
    if (bets.any((b) => b < 1)) throw ArgumentError('bets must be at least 1');
    final r = BlackjackRound._(rules, shoe, bets);
    shoe.startRound();
    for (final s in r._seats) {
      s._hands[0]._cards.add(shoe.draw());
    }
    r._dealer.add(shoe.draw());
    for (final s in r._seats) {
      s._hands[0]._cards.add(shoe.draw());
    }
    if (rules.holeCard) {
      r._dealer.add(shoe.draw());
      r._holeHidden = true;
    }
    r._start();
    return r;
  }

  /// The table rules.
  final BlackjackRules rules;

  /// The shoe the round deals from (shared with the table across rounds).
  final Shoe shoe;

  final List<BlackjackSeat> _seats;
  final List<Card> _dealer = [];
  bool _holeHidden = false;
  bool _peeked = false;
  RoundPhase _phase = RoundPhase.playing;
  Turn? _turn;

  /// An independent copy, shoe included.
  BlackjackRound copy() => BlackjackRound._copy(this);

  /// The seats, first base first.
  List<BlackjackSeat> get seats => List.unmodifiable(_seats);

  /// Where the round is.
  RoundPhase get phase => _phase;

  /// Settled.
  bool get isOver => _phase == RoundPhase.over;

  /// Who acts next (null when the round is over).
  Turn? get turn => _turn;

  /// The dealer's upcard.
  Card get dealerUpcard => _dealer[0];

  /// The dealer's cards that everyone can see (the upcard, the hole card
  /// once turned over, and any drawn cards).
  List<Card> get dealerVisible => _holeHidden ? [_dealer[0]] : List.unmodifiable(_dealer);

  /// All the dealer's cards, the hidden hole card included. Not for views.
  List<Card> get dealerCards => List.unmodifiable(_dealer);

  /// The hole card is dealt and still face down.
  bool get holeCardHidden => _holeHidden;

  /// The dealer has checked for blackjack and doesn't have one.
  bool get dealerPeeked => _peeked;

  /// The dealer has blackjack (known once revealed or at the end).
  bool get dealerHasBlackjack => _dealer.length == 2 && handTotal(_dealer).value == 21;

  bool get _upTenOrAce => dealerUpcard.rank == aceIndex || dealerUpcard.rank == tenIndex;

  // ---- Flow ------------------------------------------------------------

  void _start() {
    if (rules.holeCard && rules.surrender == Surrender.early && _upTenOrAce) {
      _phase = RoundPhase.earlySurrender;
      _turn = _nextOfferSeat(0, earlySurrender: true);
      if (_turn != null) return;
    }
    _startInsurance();
  }

  void _startInsurance() {
    if (rules.insurance && dealerUpcard.rank == aceIndex) {
      _phase = RoundPhase.insurance;
      _turn = _nextOfferSeat(0, earlySurrender: false);
      if (_turn != null) return;
    }
    _afterOffers();
  }

  Turn? _nextOfferSeat(int from, {required bool earlySurrender}) {
    for (var s = from; s < _seats.length; s++) {
      final h = _seats[s]._hands[0];
      if (h._surrendered) continue;
      if (earlySurrender && h.isBlackjack) continue;
      return Turn(s, 0);
    }
    return null;
  }

  void _afterOffers() {
    if (rules.holeCard && _upTenOrAce) {
      if (dealerHasBlackjack) {
        _holeHidden = false;
        _finish();
        return;
      }
      _peeked = true;
    }
    _phase = RoundPhase.playing;
    _turn = null;
    _advance(0, 0);
  }

  /// Moves to the first hand from ([seat], [hand]) on that still needs a
  /// decision, dealing second cards to split hands as they come up.
  void _advance(int seat, int hand) {
    for (var s = seat; s < _seats.length; s++) {
      final st = _seats[s];
      for (var h = s == seat ? hand : 0; h < st._hands.length; h++) {
        final hd = st._hands[h];
        if (hd._done) continue;
        if (hd._cards.length == 1) hd._cards.add(shoe.draw());
        if (_autoDone(st, hd)) {
          hd._done = true;
          continue;
        }
        _turn = Turn(s, h);
        return;
      }
    }
    _turn = null;
    _dealerPlays();
  }

  bool _autoDone(BlackjackSeat seat, BlackjackHand h) {
    if (h.isBlackjack || h.total.value >= 21) return true;
    // Split aces get one card each unless hitting them is allowed; a
    // second ace may still be split again with resplit aces.
    if (h.splitAces && !rules.hitSplitAces) return !_canSplit(seat, h);
    return false;
  }

  bool _canSplit(BlackjackSeat seat, BlackjackHand h) =>
      h.isPair && seat._hands.length < rules.maxHands && (!h.splitAces || rules.resplitAces);

  bool _canDouble(BlackjackHand h) {
    if (h._cards.length != 2 || h.total.value >= 21) return false;
    var hard = 0;
    var ace = false;
    for (final c in h._cards) {
      hard += c.points;
      if (c.rank == aceIndex) ace = true;
    }
    return rules.doubling.allows(hard, ace) &&
        (!h.fromSplit || rules.doubleAfterSplit) &&
        (!h.splitAces || rules.hitSplitAces);
  }

  bool _canSurrender(BlackjackSeat seat, BlackjackHand h) {
    if (rules.surrender == Surrender.none) return false;
    if (h._cards.length != 2 || h.fromSplit || seat._hands.length != 1) return false;
    // Early surrender against an ace or ten was offered before the peek.
    if (rules.surrender == Surrender.early && rules.holeCard && _upTenOrAce) return false;
    return true;
  }

  /// The actions the player to act may take now (empty when over).
  List<BlackjackAction> legalActions() {
    final t = _turn;
    if (t == null) return const [];
    final seat = _seats[t.seat];
    final h = seat._hands[t.hand];
    switch (_phase) {
      case RoundPhase.earlySurrender:
        return const [BlackjackAction.surrender, BlackjackAction.keepPlaying];
      case RoundPhase.insurance:
        return const [BlackjackAction.insurance, BlackjackAction.noInsurance];
      case RoundPhase.playing:
        final oneCardOnly = h.splitAces && !rules.hitSplitAces;
        return [
          BlackjackAction.stand,
          if (!oneCardOnly) BlackjackAction.hit,
          if (_canDouble(h)) BlackjackAction.double,
          if (_canSplit(seat, h)) BlackjackAction.split,
          if (_canSurrender(seat, h)) BlackjackAction.surrender,
        ];
      case RoundPhase.over:
        return const [];
    }
  }

  /// Plays [action] for the player to act. Throws if it isn't legal.
  void apply(BlackjackAction action) {
    final t = _turn;
    if (t == null || !legalActions().contains(action)) {
      throw StateError('$action is not legal now (${_phase.name}, $t)');
    }
    final seat = _seats[t.seat];
    final h = seat._hands[t.hand];
    switch (_phase) {
      case RoundPhase.earlySurrender:
        if (action == BlackjackAction.surrender) {
          h._surrendered = true;
          h._done = true;
        }
        _turn = _nextOfferSeat(t.seat + 1, earlySurrender: true);
        if (_turn == null) _startInsurance();
      case RoundPhase.insurance:
        seat._insurance = action == BlackjackAction.insurance;
        _turn = _nextOfferSeat(t.seat + 1, earlySurrender: false);
        if (_turn == null) _afterOffers();
      case RoundPhase.playing:
        _play(seat, h, t, action);
      case RoundPhase.over:
        break;
    }
  }

  void _play(BlackjackSeat seat, BlackjackHand h, Turn t, BlackjackAction action) {
    switch (action) {
      case BlackjackAction.stand:
        h._done = true;
      case BlackjackAction.hit:
        h._cards.add(shoe.draw());
        if (h.total.value >= 21) h._done = true;
      case BlackjackAction.double:
        h._doubled = true;
        h._cards.add(shoe.draw());
        h._done = true;
      case BlackjackAction.surrender:
        h._surrendered = true;
        h._done = true;
      case BlackjackAction.split:
        final aces = h._cards[0].rank == aceIndex;
        final second = h._cards.removeLast();
        final fresh = BlackjackHand._(h.bet, fromSplit: true, splitAces: aces || h.splitAces).._cards.add(second);
        final replaced = BlackjackHand._(h.bet, fromSplit: true, splitAces: aces || h.splitAces)
          .._cards.add(h._cards[0]);
        seat._hands[t.hand] = replaced;
        seat._hands.insert(t.hand + 1, fresh);
        // The first hand gets its second card now; the next gets its own
        // when its turn comes.
        _advance(t.seat, t.hand);
        return;
      default:
        throw StateError('$action is not a play');
    }
    _advance(t.seat, t.hand);
  }

  void _dealerPlays() {
    final live = <BlackjackHand>[
      for (final s in _seats)
        for (final h in s._hands)
          if (!h._surrendered && !h.isBust) h,
    ];
    final needsComparison = live.any((h) => !h.isBlackjack);
    if (rules.holeCard) {
      _holeHidden = false;
    } else {
      // No hole card: the dealer's second card now. Always dealt, since
      // blackjacks, insurance and late surrenders all depend on it.
      _dealer.add(shoe.draw());
    }
    if (needsComparison && !dealerHasBlackjack) {
      while (true) {
        final t = handTotal(_dealer);
        if (t.value > 17 || (t.value == 17 && !(t.soft && rules.dealerHitsSoft17))) break;
        _dealer.add(shoe.draw());
      }
    }
    _finish();
  }

  // ---- Settlement ------------------------------------------------------

  void _finish() {
    _phase = RoundPhase.over;
    _turn = null;
    final dealerBj = dealerHasBlackjack;
    final dealerTotal = handTotal(_dealer);
    for (final s in _seats) {
      for (var i = 0; i < s._hands.length; i++) {
        final h = s._hands[i];
        h._done = true;
        final bet = h.bet.toDouble();
        if (h._surrendered) {
          final lateLoss = !rules.holeCard && rules.surrender == Surrender.late && dealerBj;
          h._outcome = HandOutcome.surrender;
          h._net = lateLoss ? -bet : -bet / 2;
        } else if (h.isBlackjack) {
          h._outcome = dealerBj ? HandOutcome.push : HandOutcome.blackjack;
          h._net = dealerBj ? 0 : bet * rules.payout.multiplier;
        } else if (dealerBj) {
          h._outcome = HandOutcome.dealerBlackjack;
          // Hole card games end before any double or split. Without a hole
          // card, every bet loses, or only the original bet ("OBO").
          h._net = rules.losesOriginalOnly ? (i == 0 ? -bet : 0) : -h.stake.toDouble();
        } else if (h.isBust) {
          h._outcome = HandOutcome.bust;
          h._net = -h.stake.toDouble();
        } else {
          final p = h.total.value;
          final d = dealerTotal.value;
          if (d > 21 || p > d) {
            h._outcome = HandOutcome.win;
            h._net = h.stake.toDouble();
          } else if (p == d) {
            h._outcome = HandOutcome.push;
            h._net = 0;
          } else {
            h._outcome = HandOutcome.lose;
            h._net = -h.stake.toDouble();
          }
        }
      }
    }
  }

  /// The result of [seat] (only once the round is over).
  SeatResult result(int seat) {
    if (!isOver) throw StateError('the round is not over');
    final s = _seats[seat];
    final ins = s._insurance == true ? (dealerHasBlackjack ? s.insuranceBet * 2 : -s.insuranceBet) : 0.0;
    final hands = [for (final h in s._hands) h._net];
    return SeatResult(net: hands.fold<double>(0, (a, b) => a + b) + ins, handsNet: hands, insuranceNet: ins);
  }

  // ---- Views -----------------------------------------------------------

  /// What [seat] knows: everything except the face-down hole card and the
  /// order of the shoe.
  BlackjackView viewFor(int seat) {
    final t = _turn;
    final hiddenHole = _holeHidden ? 1 : 0;
    final seenSinceShuffle = <Card>[..._publicDealt()];
    final roundStart = shoe.dealtBeforeRound.length;
    final dealtAll = shoe.dealt;
    final roundCards = dealtAll.sublist(roundStart.clamp(0, dealtAll.length));
    final hole = _holeHidden ? _dealer[1] : null;
    final thisRound = [for (final c in roundCards) c];
    if (hole != null) thisRound.remove(hole);
    return BlackjackView._(
      rules: rules,
      seat: seat,
      phase: _phase,
      turn: t,
      legalActions: t != null && t.seat == seat ? legalActions() : const [],
      seats: List.unmodifiable([for (final s in _seats) BlackjackSeat._copy(s)]),
      dealerVisible: dealerVisible,
      holeCardHidden: _holeHidden,
      dealerPeeked: _peeked,
      seenSinceShuffle: seenSinceShuffle,
      seenThisRound: thisRound,
      unseenCount: shoe.cardsLeft + hiddenHole,
    );
  }

  /// Every card dealt since the shuffle except a face-down hole card.
  List<Card> _publicDealt() {
    final all = List<Card>.of(shoe.dealt);
    if (_holeHidden) {
      // The hole card is the most recent copy of that card dealt to the
      // dealer; remove one copy (which copy doesn't matter for counts).
      final i = all.lastIndexOf(_dealer[1]);
      if (i >= 0) all.removeAt(i);
    }
    return all;
  }
}

/// What one seat knows about the round: all public information. It holds
/// no reference to the shoe, so a bot or coach can't peek.
class BlackjackView {
  /// A view put together from its parts: the online game's view codec
  /// rebuilds the deciding seat's view from the room's message (which holds
  /// only what this seat may know, never the hole card or the shoe's
  /// order), so the bots and the coach work from exactly what a seat at the
  /// table would see. The parts mean what the fields below say.
  factory BlackjackView.restored({
    required BlackjackRules rules,
    required int seat,
    required RoundPhase phase,
    required Turn? turn,
    required List<BlackjackAction> legalActions,
    required List<BlackjackSeat> seats,
    required List<Card> dealerVisible,
    required bool holeCardHidden,
    required bool dealerPeeked,
    required List<Card> seenSinceShuffle,
    required List<Card> seenThisRound,
    required int unseenCount,
  }) => BlackjackView._(
    rules: rules,
    seat: seat,
    phase: phase,
    turn: turn,
    legalActions: List.unmodifiable(legalActions),
    seats: List.unmodifiable(seats),
    dealerVisible: List.unmodifiable(dealerVisible),
    holeCardHidden: holeCardHidden,
    dealerPeeked: dealerPeeked,
    seenSinceShuffle: List.unmodifiable(seenSinceShuffle),
    seenThisRound: List.unmodifiable(seenThisRound),
    unseenCount: unseenCount,
  );

  BlackjackView._({
    required this.rules,
    required this.seat,
    required this.phase,
    required this.turn,
    required this.legalActions,
    required this.seats,
    required this.dealerVisible,
    required this.holeCardHidden,
    required this.dealerPeeked,
    required this.seenSinceShuffle,
    required this.seenThisRound,
    required this.unseenCount,
  });

  /// The table rules.
  final BlackjackRules rules;

  /// The seat this view belongs to.
  final int seat;

  /// Where the round is.
  final RoundPhase phase;

  /// Who acts next (null when over).
  final Turn? turn;

  /// The actions this seat may take now (empty if it isn't this seat's
  /// turn).
  final List<BlackjackAction> legalActions;

  /// Every seat's bet, hands and insurance (all face up in blackjack).
  /// Copies: changing them can't change the round.
  final List<BlackjackSeat> seats;

  /// The dealer's cards everyone can see.
  final List<Card> dealerVisible;

  /// The dealer's upcard.
  Card get dealerUpcard => dealerVisible.first;

  /// The hole card is dealt and face down.
  final bool holeCardHidden;

  /// The dealer has checked for blackjack and doesn't have one.
  final bool dealerPeeked;

  /// Every card seen since the shoe was last shuffled, this round's
  /// visible cards included.
  final List<Card> seenSinceShuffle;

  /// The cards seen this round (players' cards and the dealer's visible
  /// cards).
  final List<Card> seenThisRound;

  /// Cards not seen: the rest of the shoe plus a face-down hole card.
  final int unseenCount;

  /// The seat's hand to act now (null if it's not this seat's turn).
  BlackjackHand? get handToPlay {
    final t = turn;
    if (t == null || t.seat != seat) return null;
    return seats[t.seat]._hands[t.hand];
  }

  /// It is this seat's turn.
  bool get isMyTurn => turn?.seat == seat;

  /// The unseen cards if only this round's visible cards are taken out of
  /// a full shoe: what basic strategy assumes ("fresh" knowledge).
  Composition get unseenFresh => Composition.decks(rules.decks).without(seenThisRound);

  /// The unseen cards given everything seen since the shuffle: perfect
  /// use of public information, which is what card counting
  /// approximates ("seen" knowledge).
  Composition get unseenSeen => Composition.decks(rules.decks).without(seenSinceShuffle);

  /// The Hi-Lo count of the cards seen since the shuffle.
  HiLoCount get count => HiLoCount.of(seenSinceShuffle, unseenCount);

  /// The cards in [unseenSeen] might not last the round: the hands still
  /// to play and the dealer could, at worst, need more cards than are
  /// left. Then the dealer would reshuffle the discards mid-round (see
  /// `Shoe.draw`), so what comes next is no longer [unseenSeen] but the
  /// full shoe minus the cards on the table, which is [unseenFresh]. The
  /// coach uses [unseenFresh] for SEEN in that case, instead of values
  /// worked out on a nearly empty shoe (which would be meaningless).
  ///
  /// When this is false the unseen cards are sure to last. The bound: a
  /// hand keeps drawing only while its hard total (aces as 1) is under 21
  /// (17 for the dealer, whose first draw is the hole card), so all its
  /// cards but the last add up to at most 20 minus its total (16 minus
  /// the upcard). Over every hand still to play, a pair that may be split
  /// counting as the most hands the rules allow, the cards drawn number
  /// at most one per hand plus the most of the smallest unseen cards that
  /// fit in the sum of those allowances. It is shared among the hands, so
  /// it stays tight enough for shoe games (a six-deck shoe at its cut card
  /// still lasts seven seats) and only trips near the end of a shoe.
  bool get seenMayRunOut {
    final unseen = unseenSeen;
    var hands = 0;
    var points = 0;
    void drawing(int hard, int stop, [int count = 1]) {
      if (hard >= stop) return;
      hands += count;
      points += (stop - 1 - hard) * count;
    }

    drawing(rankPoints(dealerUpcard.rank), 17);
    final t = turn;
    for (var s = 0; s < seats.length; s++) {
      final st = seats[s];
      for (var h = 0; h < st.hands.length; h++) {
        final hand = st.hands[h];
        final current = t != null && t.seat == s && t.hand == h;
        if (hand.done && !current) continue;
        if (hand.isPair && rules.canSplit && st.hands.length < rules.maxHands) {
          // Splitting gives more hands, each with more room: the worst case.
          drawing(hand.cards.first.points, 21, rules.maxHands - st.hands.length + 1);
        } else {
          var hard = 0;
          for (final c in hand.cards) {
            hard += c.points;
          }
          drawing(hard, 21);
        }
      }
    }
    // The most unseen cards, smallest first, whose points fit in [points].
    var fit = 0;
    for (var r = 0; r < rankCount; r++) {
      final each = rankPoints(r);
      final n = math.min(unseen[r], points ~/ each);
      fit += n;
      points -= n * each;
      if (n < unseen[r]) break;
    }
    return hands + fit > unseen.total;
  }

  /// The insurance offer here is "even money": this seat has blackjack
  /// and blackjack pays 3 to 2, so insuring it pays exactly 1 to 1
  /// whatever the dealer has. At 6:5 or 1:1 insuring a blackjack nets
  /// +0.7 or +0.5 bets when the dealer has no blackjack, which is not even
  /// money (casinos don't offer it there; Las Vegas Advisor, "Even money
  /// at 6-5 blackjack"), so the offer is plain insurance.
  bool get offersEvenMoney =>
      phase == RoundPhase.insurance &&
      isMyTurn &&
      seats[seat].hasBlackjack &&
      rules.payout == BlackjackPayout.threeToTwo;
}
