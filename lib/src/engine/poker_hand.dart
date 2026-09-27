import 'dart:math';

import 'actions.dart';
import 'cards.dart';
import 'events.dart';
import 'hand_evaluator.dart';
import 'positions.dart';
import 'rules.dart';

class _Seat {
  _Seat(this.index, this.stack);

  final int index;
  int stack;
  final List<PlayingCard> cards = [];

  /// Chips bet on the current street (not yet collected into the pot).
  int streetBet = 0;

  /// Everything this player has put in during the hand (antes and blinds included).
  int committed = 0;
  bool folded = false;
  bool actedThisStreet = false;

  bool get canAct => !folded && stack > 0;
}

/// One hand of No-Limit Hold'em, from posting blinds to paying the winners.
///
/// All amounts are integer chips. Create a hand, then repeatedly call [act]
/// for the seat in [toAct] until [isOver]. Everything that happens is recorded
/// as [GameEvent]s, which the UI fetches with [drainEvents] and animates.
class PokerHand {
  PokerHand({
    required List<int> stacks,
    required this.buttonSeat,
    required this.smallBlind,
    required this.bigBlind,
    this.ante = 0,
    this.handNumber = 1,
    this.raiseRule = RaiseRule.standard,
    Random? random,
    Map<int, List<PlayingCard>> holeCards = const {},
    List<PlayingCard> board = const [],
  }) : _presetBoard = List.of(board) {
    final n = stacks.length;
    if (n < 2 || n > 8) throw ArgumentError('A table needs 2 to 8 players');
    if (stacks.any((s) => s <= 0)) throw ArgumentError('Every stack must be positive');
    if (buttonSeat < 0 || buttonSeat >= n) throw RangeError.index(buttonSeat, stacks);
    if (smallBlind <= 0 || bigBlind < smallBlind || ante < 0) {
      throw ArgumentError('Invalid blinds or ante');
    }
    _checkPresets(n, holeCards, board);

    _seats = [for (var i = 0; i < n; i++) _Seat(i, stacks[i])];
    _startingStacks = List.unmodifiable(stacks);
    _positions = positionsBySeat(n, buttonSeat);
    _deck = Deck.shuffled(
      random ?? Random(),
      exclude: [...holeCards.values.expand((c) => c), ...board],
    );

    _emit(HandStarted(
      handNumber: handNumber,
      buttonSeat: buttonSeat,
      stacks: _startingStacks,
      positions: _positions,
    ));
    _postAntes();
    _postBlind(smallBlindSeat(n, buttonSeat), smallBlind, isBig: false);
    _postBlind(bigBlindSeat(n, buttonSeat), bigBlind, isBig: true);
    _dealHoleCards(holeCards);

    // The big blind sets the price even if that player is all-in for less.
    _currentBet = bigBlind;
    _minRaise = bigBlind;
    _toAct = _findNextToAct(after: bigBlindSeat(n, buttonSeat));
    if (_toAct == null) _endStreet();
  }

  final int buttonSeat;
  final int smallBlind;
  final int bigBlind;
  final int ante;
  final int handNumber;

  /// How small a raise may be.
  final RaiseRule raiseRule;

  late final List<_Seat> _seats;
  late final List<int> _startingStacks;
  late final Map<int, Position> _positions;
  late final Deck _deck;
  final List<PlayingCard> _presetBoard;

  Street _street = Street.preflop;
  final List<PlayingCard> _board = [];
  int _currentBet = 0;

  /// Size of the last full bet or raise on this street.
  int _minRaise = 0;

  /// The smallest raise increment allowed now, under [raiseRule].
  int get _fullRaise => raiseRule.minimumIncrease(_minRaise, bigBlind);
  int _raisesThisStreet = 0;
  int _callsSinceRaise = 0;
  final Map<Street, int> _aggressors = {};
  List<Pot> _pots = const [];
  int? _toAct;
  bool _isOver = false;
  bool _revealed = false;

  final List<GameEvent> _log = [];
  int _drained = 0;

  // ---------------------------------------------------------------------------
  // Read-only state
  // ---------------------------------------------------------------------------

  int get playerCount => _seats.length;
  Street get street => _street;
  List<PlayingCard> get board => List.unmodifiable(_board);
  int? get toAct => _toAct;
  bool get isOver => _isOver;
  int get currentBet => _currentBet;
  int get raisesThisStreet => _raisesThisStreet;

  /// Calls since the last bet or raise. Preflop with no raise yet: the limpers.
  int get callsSinceLastRaise => _callsSinceRaise;

  /// All chips in the middle, including bets not yet collected.
  int get potTotal => _seats.fold(0, (sum, s) => sum + s.committed);

  int get livePlayerCount => _seats.where((s) => !s.folded).length;
  List<PlayingCard> holeCards(int seat) => List.unmodifiable(_seats[seat].cards);
  int stackOf(int seat) => _seats[seat].stack;
  int startingStackOf(int seat) => _startingStacks[seat];
  int streetBetOf(int seat) => _seats[seat].streetBet;
  bool isFolded(int seat) => _seats[seat].folded;
  bool isAllIn(int seat) => !_seats[seat].folded && _seats[seat].stack == 0;
  Position positionOf(int seat) => _positions[seat]!;

  /// Seat that made the last bet or raise on [street], if any.
  int? aggressorOn(Street street) => _aggressors[street];

  /// Every event so far.
  List<GameEvent> get log => List.unmodifiable(_log);

  /// Events since the previous call.
  List<GameEvent> drainEvents() {
    final fresh = _log.sublist(_drained);
    _drained = _log.length;
    return fresh;
  }

  LegalActions legalActions() {
    final seat = _toAct;
    if (seat == null) throw StateError('Nobody is due to act');
    final s = _seats[seat];
    final maxRaiseTo = s.streetBet + s.stack;
    final someoneCanRespond = _seats.any((o) => o.index != seat && o.canAct);
    // A short all-in raise does not reopen the betting for players who
    // already acted, unless they now face at least a full raise.
    final reopened = !s.actedThisStreet || _currentBet - s.streetBet >= _fullRaise;
    return LegalActions(
      toCall: min(_currentBet - s.streetBet, s.stack),
      canRaise: someoneCanRespond && reopened && maxRaiseTo > _currentBet,
      minRaiseTo: min(_currentBet + _fullRaise, maxRaiseTo),
      maxRaiseTo: maxRaiseTo,
      currentBet: _currentBet,
      streetBet: s.streetBet,
      stack: s.stack,
      pot: potTotal,
    );
  }

  // ---------------------------------------------------------------------------
  // Acting
  // ---------------------------------------------------------------------------

  void act(PlayerAction action) {
    final seat = _toAct;
    if (_isOver || seat == null) throw StateError('Nobody is due to act');
    final s = _seats[seat];
    final legal = legalActions();

    switch (action.type) {
      case ActionType.fold:
        s.folded = true;
        _emitAction(s, ActionKind.fold, 0);
      case ActionType.check:
        if (!legal.canCheck) throw ArgumentError('Cannot check when facing a bet');
        _emitAction(s, ActionKind.check, 0);
      case ActionType.call:
        if (!legal.canCall) throw ArgumentError('There is nothing to call');
        _commit(s, legal.toCall);
        _callsSinceRaise++;
        _emitAction(s, ActionKind.call, legal.toCall);
      case ActionType.raise:
        final to = action.amount;
        if (!legal.canRaise) throw ArgumentError('Raising is not allowed here');
        if (to < legal.minRaiseTo || to > legal.maxRaiseTo) {
          throw ArgumentError(
              'Raise must be between ${legal.minRaiseTo} and ${legal.maxRaiseTo}, got $to');
        }
        final isBet = _currentBet == 0;
        final increase = to - _currentBet;
        if (increase >= _minRaise) _minRaise = increase;
        _currentBet = to;
        final added = to - s.streetBet;
        _commit(s, added);
        _raisesThisStreet++;
        _callsSinceRaise = 0;
        _aggressors[_street] = seat;
        _emitAction(s, isBet ? ActionKind.bet : ActionKind.raise, added);
    }

    s.actedThisStreet = true;
    if (livePlayerCount == 1) {
      _endStreet();
      return;
    }
    _toAct = _findNextToAct(after: seat);
    if (_toAct == null) _endStreet();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _emit(GameEvent event) => _log.add(event);

  void _emitAction(_Seat s, ActionKind kind, int added) => _emit(ActionTaken(
        seat: s.index,
        kind: kind,
        chipsAdded: added,
        streetBet: s.streetBet,
        isAllIn: !s.folded && s.stack == 0,
        street: _street,
      ));

  void _commit(_Seat s, int amount) {
    s.stack -= amount;
    s.streetBet += amount;
    s.committed += amount;
  }

  void _checkPresets(int n, Map<int, List<PlayingCard>> holeCards, List<PlayingCard> board) {
    if (board.length > 5) throw ArgumentError('The board has at most 5 cards');
    final all = <PlayingCard>[...board];
    holeCards.forEach((seat, cards) {
      if (seat < 0 || seat >= n) throw RangeError.range(seat, 0, n - 1, 'seat');
      if (cards.length != 2) throw ArgumentError('Seat $seat needs exactly 2 cards');
      all.addAll(cards);
    });
    if (all.toSet().length != all.length) throw ArgumentError('A card is used twice');
  }

  void _postAntes() {
    if (ante == 0) return;
    final amounts = <int, int>{};
    for (final s in _seats) {
      final amount = min(ante, s.stack);
      s.stack -= amount;
      s.committed += amount;
      amounts[s.index] = amount;
    }
    _emit(AntesPosted(amounts));
  }

  void _postBlind(int seat, int amount, {required bool isBig}) {
    final s = _seats[seat];
    final posted = min(amount, s.stack);
    if (posted == 0) return;
    _commit(s, posted);
    _emit(BlindPosted(seat: seat, amount: posted, isBigBlind: isBig));
  }

  void _dealHoleCards(Map<int, List<PlayingCard>> preset) {
    final n = playerCount;
    final order = [for (var k = 1; k <= n; k++) (buttonSeat + k) % n];
    for (var round = 0; round < 2; round++) {
      for (final seat in order) {
        _seats[seat].cards.add(preset[seat]?[round] ?? _deck.deal());
      }
    }
    _emit(HoleCardsDealt(
      dealOrder: order,
      cards: {for (final s in _seats) s.index: List.unmodifiable(s.cards)},
    ));
  }

  /// Next seat that still has a decision to make, or null if the betting
  /// round is over.
  int? _findNextToAct({required int after}) {
    if (livePlayerCount <= 1) return null;
    final able = _seats.where((s) => s.canAct).toList();
    if (able.isEmpty) return null;
    // A lone player with chips left has nobody to bet against, unless they
    // still have to decide whether to call.
    if (able.length == 1 && able.single.streetBet >= _currentBet) return null;
    final n = playerCount;
    for (var k = 1; k <= n; k++) {
      final s = _seats[(after + k) % n];
      if (s.canAct && (!s.actedThisStreet || s.streetBet < _currentBet)) return s.index;
    }
    return null;
  }

  void _endStreet() {
    _toAct = null;
    _returnUncalledBet();
    _collectBets();

    final live = _seats.where((s) => !s.folded).toList();
    if (live.length == 1) {
      _awardUncontested(live.single);
      return;
    }
    if (_street == Street.river) {
      _showdown();
      return;
    }
    if (live.where((s) => s.canAct).length <= 1) {
      // Nobody can bet any more: turn the cards over and deal the rest.
      _reveal();
      while (_street != Street.river) {
        _dealNextStreet();
      }
      _showdown();
      return;
    }
    _dealNextStreet();
    _startBettingRound();
  }

  void _returnUncalledBet() {
    final byBet = [..._seats]..sort((a, b) => b.streetBet.compareTo(a.streetBet));
    final excess = byBet[0].streetBet - byBet[1].streetBet;
    if (excess <= 0) return;
    final s = byBet[0];
    s.streetBet -= excess;
    s.committed -= excess;
    s.stack += excess;
    _emit(UncalledBetReturned(seat: s.index, amount: excess));
  }

  void _collectBets() {
    var total = 0;
    for (final s in _seats) {
      total += s.streetBet;
      s.streetBet = 0;
    }
    _pots = _computePots();
    if (total > 0) _emit(BetsCollected(_pots));
  }

  /// Main pot and side pots, built from how much each player put in.
  List<Pot> _computePots() {
    final live = _seats.where((s) => !s.folded).toList();
    final levels = live.map((s) => s.committed).toSet().toList()..sort();
    final pots = <Pot>[];
    var previous = 0;
    for (final level in levels) {
      var amount = 0;
      for (final s in _seats) {
        amount += min(s.committed, level) - min(s.committed, previous);
      }
      if (amount > 0) {
        pots.add(Pot(amount, [
          for (final s in live)
            if (s.committed >= level) s.index,
        ]));
      }
      previous = level;
    }
    // Chips from folded players above every live player's total (rare) join the last pot.
    var leftover = 0;
    for (final s in _seats) {
      if (s.committed > previous) leftover += s.committed - previous;
    }
    if (leftover > 0) {
      if (pots.isEmpty) {
        pots.add(Pot(leftover, [for (final s in live) s.index]));
      } else {
        pots[pots.length - 1] = Pot(pots.last.amount + leftover, pots.last.eligibleSeats);
      }
    }
    return pots;
  }

  void _dealNextStreet() {
    final next = Street.values[_street.index + 1];
    final count = next == Street.flop ? 3 : 1;
    final dealt = <PlayingCard>[];
    for (var i = 0; i < count; i++) {
      final index = _board.length;
      final card = index < _presetBoard.length ? _presetBoard[index] : _deck.deal();
      _board.add(card);
      dealt.add(card);
    }
    _street = next;
    _emit(BoardDealt(street: next, cards: dealt));
  }

  void _startBettingRound() {
    _currentBet = 0;
    _minRaise = bigBlind;
    _raisesThisStreet = 0;
    _callsSinceRaise = 0;
    for (final s in _seats) {
      s.actedThisStreet = false;
    }
    _toAct = _findNextToAct(after: buttonSeat);
    if (_toAct == null) _endStreet();
  }

  void _reveal() {
    if (_revealed) return;
    _revealed = true;
    _emit(HandsRevealed({
      for (final s in _seats)
        if (!s.folded) s.index: List.unmodifiable(s.cards),
    }));
  }

  void _awardUncontested(_Seat winner) {
    final total = _pots.fold(0, (sum, p) => sum + p.amount);
    winner.stack += total;
    _emit(PotAwarded(potIndex: 0, amount: total, shares: {winner.index: total}, winningHand: null));
    _finish();
  }

  void _showdown() {
    _reveal();
    final values = {
      for (final s in _seats)
        if (!s.folded) s.index: evaluateHand([...s.cards, ..._board]),
    };
    // Side pots are paid first, the main pot last.
    for (var i = _pots.length - 1; i >= 0; i--) {
      final pot = _pots[i];
      final best = pot.eligibleSeats.map((s) => values[s]!).reduce((a, b) => a > b ? a : b);
      final winners = pot.eligibleSeats.where((s) => values[s] == best).toList()
        ..sort((a, b) => _seatsLeftOfButton(a).compareTo(_seatsLeftOfButton(b)));
      final shares = _split(pot.amount, winners);
      shares.forEach((seat, chips) => _seats[seat].stack += chips);
      _emit(PotAwarded(potIndex: i, amount: pot.amount, shares: shares, winningHand: best));
    }
    _finish();
  }

  /// 1 for the seat left of the button, up to playerCount for the button itself.
  int _seatsLeftOfButton(int seat) {
    final d = (seat - buttonSeat) % playerCount;
    return d == 0 ? playerCount : d;
  }

  /// Splits a pot evenly; odd chips go to the first winners left of the button.
  Map<int, int> _split(int amount, List<int> winners) {
    final base = amount ~/ winners.length;
    final remainder = amount % winners.length;
    return {
      for (var i = 0; i < winners.length; i++) winners[i]: base + (i < remainder ? 1 : 0),
    };
  }

  void _finish() {
    _isOver = true;
    _toAct = null;
    _emit(HandEnded(
      finalStacks: [for (final s in _seats) s.stack],
      netChange: {for (final s in _seats) s.index: s.stack - _startingStacks[s.index]},
    ));
  }
}
