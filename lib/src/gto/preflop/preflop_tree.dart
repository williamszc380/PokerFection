import 'dart:math';

import '../../engine/rules.dart';
import '../hand_classes.dart';

/// Stacks and blinds for one preflop game.
///
/// Players are listed in preflop acting order: first to act first, big blind
/// last. Heads-up that is the button (who posts the small blind), then the
/// big blind.
class PreflopSpec {
  PreflopSpec({
    required List<int> stacks,
    this.smallBlind = 50,
    this.bigBlind = 100,
    this.ante = 0,
    this.raiseRule = RaiseRule.standard,
    List<double> raiseMultiples = PreflopSettings.defaultRaiseMultiples,
    List<PreflopAction> history = const [],
    this.hero = -1,
  })  : stacks = List.unmodifiable(stacks),
        raiseMultiples = List.unmodifiable(raiseMultiples),
        history = List.unmodifiable(history) {
    if (stacks.length < 2 || stacks.length > 8) throw ArgumentError('2 to 8 players');
    if (hero < -1 || hero >= stacks.length) throw ArgumentError('No such player: $hero');
  }

  final List<int> stacks;
  final int smallBlind;
  final int bigBlind;
  final int ante;
  final RaiseRule raiseRule;

  /// The user's raise sizes, as multiples of the bet they face: by default
  /// raise to 2, 2.5, 3, 4 or 5 BB when first in, or 2x to 5x an open or a 3-bet.
  final List<double> raiseMultiples;

  /// Actions already taken before the solved part starts. Empty for the
  /// whole game; otherwise this is a subgame starting at [hero]'s decision.
  final List<PreflopAction> history;

  /// The user's player in a subgame: at the first decision they may take
  /// every legal action (fold when facing a bet, check or call, each size of
  /// [raiseMultiples], all-in). Everyone else, and the user later on,
  /// choose from a smaller menu, which keeps the game small enough to
  /// solve. The subgame ends when the user folds. -1 for the whole game.
  final int hero;

  int get players => stacks.length;
  int get smallBlindPlayer => players == 2 ? 0 : players - 2;
  int get bigBlindPlayer => players - 1;

  String get key => '${stacks.join(',')}/$smallBlind/$bigBlind/$ante/${raiseRule.name}'
      '${hero < 0 ? '' : '/$hero/${raiseMultiples.join(',')}/${history.join(',')}'}';

  /// For sending to the web version's solver worker (lib/solver_worker.dart),
  /// which rebuilds the spec from it: every field belongs here.
  Map<String, Object?> toJson() => {
        'stacks': stacks,
        'smallBlind': smallBlind,
        'bigBlind': bigBlind,
        'ante': ante,
        'raiseRule': raiseRule.name,
        'raiseMultiples': raiseMultiples,
        'history': [for (final a in history) [a.move.name, a.raiseTo]],
        'hero': hero,
      };

  factory PreflopSpec.fromJson(Map<String, Object?> json) {
    int integer(String key) => (json[key] as num).toInt();
    return PreflopSpec(
      stacks: [for (final s in json['stacks'] as List) (s as num).toInt()],
      smallBlind: integer('smallBlind'),
      bigBlind: integer('bigBlind'),
      ante: integer('ante'),
      raiseRule: RaiseRule.values.byName(json['raiseRule'] as String),
      raiseMultiples: [for (final m in json['raiseMultiples'] as List) (m as num).toDouble()],
      history: [
        for (final a in json['history'] as List)
          PreflopAction(PreflopMove.values.byName((a as List)[0] as String), (a[1] as num).toInt()),
      ],
      hero: integer('hero'),
    );
  }

  @override
  bool operator ==(Object other) => other is PreflopSpec && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Which bets the solver considers, and how it values seeing a flop.
///
/// The user's player ([PreflopSpec.hero]) gets every size of
/// [PreflopSpec.raiseMultiples]. Bots get one size per situation plus
/// all-in, which is standard: every extra size multiplies the work.
class PreflopSettings {
  const PreflopSettings({
    this.nearlyAllIn = 0.9,
    this.openBb = 2.5,
    this.shortOpenBb = 2.0,
    this.smallBlindOpenBb = 3.0,
    this.threeBetInPosition = 3.0,
    this.threeBetOutOfPosition = 4.0,
    this.fourBet = 2.3,
    this.shortStackBb = 30,
    this.maxCommit = 0.4,
    this.maxColdCallers = 2,
    this.maxAllInCallers = 2,
    this.positionEdge = 0.3,
    this.pushFoldOnly = false,
  });

  static const defaultRaiseMultiples = [2.0, 2.5, 3.0, 4.0, 5.0];

  /// A raise to at least this share of the player's whole stack is left
  /// out: it is practically all-in, and the all-in choice covers it.
  final double nearlyAllIn;

  /// Bots' opening raise, in big blinds (stacks deeper than
  /// [shortStackBb]), plus 1 BB for every limper.
  final double openBb;

  /// Opening raise with [shortStackBb] or less.
  final double shortOpenBb;

  /// Small blind's raise when folded to (3+ players).
  final double smallBlindOpenBb;

  /// 3-bet size as a multiple of the open, from later position / from the blinds.
  final double threeBetInPosition;
  final double threeBetOutOfPosition;

  /// 4-bet size as a multiple of the 3-bet.
  final double fourBet;
  final double shortStackBb;

  /// A raise that would put more than this share of the effective stack in
  /// the pot is dropped: the player can go all-in instead.
  final double maxCommit;

  /// Flat calls allowed after an open (the big blind may always call).
  final int maxColdCallers;
  final int maxAllInCallers;

  /// How much of a close matchup's equity the player acting last after the
  /// flop is assumed to gain (and the other to lose), when stacks are deep.
  final double positionEdge;

  /// Only fold or all-in (for tests against known push/fold results).
  final bool pushFoldOnly;
}

enum PreflopMove { fold, check, call, raise, allIn }

class PreflopAction {
  const PreflopAction(this.move, [this.raiseTo = 0]);

  final PreflopMove move;

  /// For raises and all-ins: the player's total bet after acting.
  final int raiseTo;

  @override
  String toString() => move == PreflopMove.raise ? 'raise to $raiseTo' : move.name;
}

sealed class PreflopNode {}

/// A player's decision.
class PreflopDecision extends PreflopNode {
  PreflopDecision._(this.player, this.actions, this.contributions);

  /// Acting player (preflop order).
  final int player;
  final List<PreflopAction> actions;

  /// Chips each player has put in so far (antes, blinds and bets).
  final List<int> contributions;
  late final List<PreflopNode> children;

  /// Index in [PreflopTree.decisions].
  late final int id;

  /// Start of this node's numbers in the solver's arrays:
  /// `offset + action * 169 + handClass`.
  late final int offset;
}

class PreflopPot {
  const PreflopPot(this.amount, this.eligible);
  final int amount;
  final List<int> eligible;
}

/// End of the preflop game: everyone else folded, or the players left see
/// the flop (or are all-in).
class PreflopTerminal extends PreflopNode {
  PreflopTerminal._({
    required this.contributions,
    required this.live,
    required this.pots,
    required this.allIn,
    required this.inPosition,
    required this.positionEdge,
  });

  final List<int> contributions;
  final List<int> live;
  final List<PreflopPot> pots;

  /// Someone is all-in: the board is dealt with no more betting.
  final bool allIn;

  /// With exactly two players seeing the flop: who acts last. Otherwise -1.
  final int inPosition;
  final double positionEdge;

  bool get uncontested => live.length == 1;
}

/// Every action sequence the solver considers before the flop (from the end
/// of [PreflopSpec.history]).
class PreflopTree {
  PreflopTree(this.spec, {this.settings = const PreflopSettings()}) {
    final start = _State.start(spec);
    for (final action in spec.history) {
      final player = start.nextToAct();
      if (player == null) throw ArgumentError('The history goes past the end of the betting');
      start.apply(player, action);
    }
    root = _build(start, root: true);
  }

  final PreflopSpec spec;
  final PreflopSettings settings;
  late final PreflopNode root;
  final List<PreflopDecision> decisions = [];
  final List<PreflopTerminal> terminals = [];
  int _storage = 0;

  /// Numbers per solver array: one per (decision, action, starting hand).
  int get storageSize => _storage;

  PreflopNode _build(_State s, {bool root = false}) {
    // In a subgame, what the others do after the user folds doesn't matter.
    final heroFolded = spec.hero >= 0 && s.folded[spec.hero];
    final player = s.liveCount > 1 && !heroFolded ? s.nextToAct() : null;
    if (player == null) return _terminal(s);
    final actions = _options(s, player, fullMenu: root && player == spec.hero);
    final node = PreflopDecision._(player, List.unmodifiable(actions), List.unmodifiable(s.contrib))
      ..id = decisions.length
      ..offset = _storage;
    decisions.add(node);
    _storage += actions.length * handClassCount;
    node.children = [for (final a in actions) _build(s.copy()..apply(player, a))];
    return node;
  }

  /// The raise to [multiple] times [currentBet], to the chip (0.01 BB).
  static int raiseSize(int currentBet, double multiple) => (currentBet * multiple).round();

  List<PreflopAction> _options(_State s, int p, {required bool fullMenu}) {
    final bb = spec.bigBlind;
    final toCall = s.currentBet - s.bet[p];
    final allInTo = s.bet[p] + s.remaining(p);
    final effective = min(spec.stacks[p], s.biggestOtherStack(p));
    final deep = effective > settings.shortStackBb * bb;
    final canRaise = allInTo > s.currentBet &&
        s.someoneElseCanAct(p) &&
        (!s.acted[p] || toCall >= s.fullRaise);
    if (fullMenu) {
      // Every legal choice: fold (only when facing a bet), check or call,
      // each raise size (below the min-raise isn't allowed; nearly all-in
      // is covered by all-in), all-in.
      return [
        if (toCall > 0) const PreflopAction(PreflopMove.fold),
        PreflopAction(toCall == 0 ? PreflopMove.check : PreflopMove.call),
        if (canRaise) ...[
          for (final to in {for (final m in spec.raiseMultiples) raiseSize(s.currentBet, m)})
            if (to >= s.currentBet + s.fullRaise && to < allInTo * settings.nearlyAllIn)
              PreflopAction(PreflopMove.raise, to),
          PreflopAction(PreflopMove.allIn, allInTo),
        ],
      ];
    }
    final options = <PreflopAction>[];

    void fold() {
      if (toCall > 0) options.add(const PreflopAction(PreflopMove.fold));
    }

    void checkOrCall() => options.add(PreflopAction(toCall == 0 ? PreflopMove.check : PreflopMove.call));

    void raiseTo(double amount) {
      final to = amount.round();
      if (!canRaise || settings.pushFoldOnly) return;
      if (to < s.currentBet + s.fullRaise || to >= allInTo) return;
      if (s.contrib[p] - s.bet[p] + to > settings.maxCommit * effective) return;
      options.add(PreflopAction(PreflopMove.raise, to));
    }

    void allIn() {
      if (canRaise) options.add(PreflopAction(PreflopMove.allIn, allInTo));
    }

    final isBlind = p == spec.smallBlindPlayer || p == spec.bigBlindPlayer;
    if (s.jammed) {
      if (toCall == 0) {
        checkOrCall();
      } else {
        fold();
        if (s.allInCallers < settings.maxAllInCallers) checkOrCall();
      }
      return options;
    }
    switch (s.raises) {
      case 0:
        // Limpers so far (only the user limps from outside the blinds).
        final limpers = s.callsAtLevel;
        final open = deep ? settings.openBb : settings.shortOpenBb;
        if (p == spec.bigBlindPlayer) {
          checkOrCall();
          raiseTo((open + limpers) * bb);
        } else if (p == spec.smallBlindPlayer) {
          fold();
          if (!settings.pushFoldOnly) checkOrCall();
          final first = spec.players == 2 ? open : (deep ? settings.smallBlindOpenBb : settings.openBb);
          raiseTo((first + limpers) * bb);
        } else {
          fold();
          raiseTo((open + limpers) * bb);
        }
        allIn();
      case 1:
        fold();
        if (s.entered[p]) {
          checkOrCall(); // a limper facing a raise
        } else {
          if (s.callsAtLevel < settings.maxColdCallers || p == spec.bigBlindPlayer) checkOrCall();
          final multiple = isBlind ? settings.threeBetOutOfPosition : settings.threeBetInPosition;
          raiseTo(s.currentBet * (multiple + s.callsAtLevel));
        }
        allIn();
      case 2:
        fold();
        if (p == s.opener) {
          if (s.callsAtLevel < 1) checkOrCall();
          raiseTo(s.currentBet * settings.fourBet);
        } else if (s.entered[p] && s.callsAtLevel < 1) {
          checkOrCall();
        }
        allIn();
      default:
        fold();
        if ((p == s.threeBettor || p == s.opener) && s.callsAtLevel < 1) checkOrCall();
        allIn();
    }
    return options;
  }

  PreflopTerminal _terminal(_State s) {
    final contrib = List.of(s.contrib);
    // The part of the biggest bet that nobody matched goes back.
    final bets = List.of(s.bet)..sort();
    final top = s.bet.indexOf(bets.last);
    final excess = bets.last - bets[bets.length - 2];
    if (excess > 0) contrib[top] -= excess;

    final live = [for (var p = 0; p < spec.players; p++) if (!s.folded[p]) p];
    final total = contrib.fold(0, (a, b) => a + b);
    if (live.length == 1) {
      final node = PreflopTerminal._(
        contributions: contrib,
        live: live,
        pots: [PreflopPot(total, live)],
        allIn: false,
        inPosition: -1,
        positionEdge: 0,
      );
      terminals.add(node);
      return node;
    }

    final allIn = live.any((p) => spec.stacks[p] == contrib[p]);
    var inPosition = -1;
    var edge = 0.0;
    if (!allIn && live.length == 2) {
      inPosition = _postflopOrder(live[0]) > _postflopOrder(live[1]) ? live[0] : live[1];
      final behind = live.map((p) => spec.stacks[p] - contrib[p]).reduce(min);
      edge = settings.positionEdge * min(1.0, behind / total / 8);
    }
    final node = PreflopTerminal._(
      contributions: contrib,
      live: live,
      pots: _pots(contrib, live),
      allIn: allIn,
      inPosition: inPosition,
      positionEdge: edge,
    );
    terminals.add(node);
    return node;
  }

  /// Order of acting after the flop: small blind first, button last.
  int _postflopOrder(int p) {
    final n = spec.players;
    if (n == 2) return p == 0 ? 1 : 0;
    return (p - (n - 2) + n) % n;
  }

  /// Main pot and side pots, the same way the game engine builds them.
  List<PreflopPot> _pots(List<int> contrib, List<int> live) {
    final levels = live.map((p) => contrib[p]).toSet().toList()..sort();
    final pots = <PreflopPot>[];
    var previous = 0;
    for (final level in levels) {
      var amount = 0;
      for (final c in contrib) {
        amount += min(c, level) - min(c, previous);
      }
      if (amount > 0) pots.add(PreflopPot(amount, [for (final p in live) if (contrib[p] >= level) p]));
      previous = level;
    }
    var leftover = 0;
    for (final c in contrib) {
      if (c > previous) leftover += c - previous;
    }
    if (leftover > 0) {
      pots[pots.length - 1] = PreflopPot(pots.last.amount + leftover, pots.last.eligible);
    }
    return pots;
  }
}

/// Betting state while the tree is built. Mirrors the rules of the game
/// engine, so every tree action is legal in a real hand.
class _State {
  _State._(this.spec);

  factory _State.start(PreflopSpec spec) {
    final n = spec.players;
    final s = _State._(spec)
      ..contrib = List.filled(n, 0)
      ..bet = List.filled(n, 0)
      ..folded = List.filled(n, false)
      ..acted = List.filled(n, false)
      ..entered = List.filled(n, false);
    for (var p = 0; p < n; p++) {
      s.contrib[p] = min(spec.ante, spec.stacks[p]);
    }
    s._post(spec.smallBlindPlayer, spec.smallBlind);
    s._post(spec.bigBlindPlayer, spec.bigBlind);
    s
      ..currentBet = spec.bigBlind
      ..minRaise = spec.bigBlind
      ..lastActor = spec.bigBlindPlayer;
    return s;
  }

  final PreflopSpec spec;
  late List<int> contrib;
  late List<int> bet;
  late List<bool> folded;
  late List<bool> acted;
  late List<bool> entered;
  int currentBet = 0;
  int minRaise = 0;

  /// The smallest raise increment allowed now (see [RaiseRule]).
  int get fullRaise => spec.raiseRule.minimumIncrease(minRaise, spec.bigBlind);
  int raises = 0;
  int callsAtLevel = 0;
  bool jammed = false;
  int allInCallers = 0;
  int opener = -1;
  int threeBettor = -1;
  int lastActor = 0;

  _State copy() => _State._(spec)
    ..contrib = List.of(contrib)
    ..bet = List.of(bet)
    ..folded = List.of(folded)
    ..acted = List.of(acted)
    ..entered = List.of(entered)
    ..currentBet = currentBet
    ..minRaise = minRaise
    ..raises = raises
    ..callsAtLevel = callsAtLevel
    ..jammed = jammed
    ..allInCallers = allInCallers
    ..opener = opener
    ..threeBettor = threeBettor
    ..lastActor = lastActor;

  int get liveCount => folded.where((f) => !f).length;
  int remaining(int p) => spec.stacks[p] - contrib[p];
  bool canAct(int p) => !folded[p] && remaining(p) > 0;
  bool someoneElseCanAct(int p) {
    for (var q = 0; q < spec.players; q++) {
      if (q != p && canAct(q)) return true;
    }
    return false;
  }

  int biggestOtherStack(int p) {
    var biggest = 0;
    for (var q = 0; q < spec.players; q++) {
      if (q != p && !folded[q]) biggest = max(biggest, spec.stacks[q]);
    }
    return biggest;
  }

  void _post(int p, int amount) {
    final posted = min(amount, remaining(p));
    contrib[p] += posted;
    bet[p] += posted;
  }

  /// Next player with a decision, using the same rule as the game engine.
  int? nextToAct() {
    final n = spec.players;
    final able = [for (var p = 0; p < n; p++) if (canAct(p)) p];
    if (able.isEmpty) return null;
    if (able.length == 1 && bet[able.single] >= currentBet) return null;
    for (var k = 1; k <= n; k++) {
      final p = (lastActor + k) % n;
      if (canAct(p) && (!acted[p] || bet[p] < currentBet)) return p;
    }
    return null;
  }

  void apply(int p, PreflopAction action) {
    switch (action.move) {
      case PreflopMove.fold:
        folded[p] = true;
      case PreflopMove.check:
        break;
      case PreflopMove.call:
        final amount = min(currentBet - bet[p], remaining(p));
        contrib[p] += amount;
        bet[p] += amount;
        entered[p] = true;
        if (jammed) {
          allInCallers++;
        } else {
          callsAtLevel++;
        }
      case PreflopMove.raise || PreflopMove.allIn:
        final to = action.raiseTo;
        final increase = to - currentBet;
        if (increase >= minRaise) minRaise = increase;
        currentBet = to;
        contrib[p] += to - bet[p];
        bet[p] = to;
        entered[p] = true;
        raises++;
        callsAtLevel = 0;
        if (raises == 1) opener = p;
        if (raises == 2) threeBettor = p;
        if (action.move == PreflopMove.allIn) {
          jammed = true;
          allInCallers = 0;
        }
    }
    acted[p] = true;
    lastActor = p;
  }
}
