import 'dart:math';

import '../../engine/events.dart';
import '../../engine/rules.dart';

/// One street of heads-up betting to solve.
///
/// Player 0 acts first on this street (out of position), player 1 last.
class PostflopSpec {
  PostflopSpec({
    required List<int> board,
    required this.pot,
    required List<int> stacks,
    required this.bigBlind,
    this.raiseRule = RaiseRule.standard,
    this.hero = -1,
    List<double> heroSizes = defaultHeroSizes,
    List<double> botBetSizes = defaultBotBetSizes,
    List<double> botRaiseSizes = defaultBotRaiseSizes,
  })  : board = List.unmodifiable(board),
        stacks = List.unmodifiable(stacks),
        heroSizes = List.unmodifiable(heroSizes),
        botBetSizes = List.unmodifiable(botBetSizes),
        botRaiseSizes = List.unmodifiable(botRaiseSizes) {
    if (board.length < 3 || board.length > 5) throw ArgumentError('Board needs 3 to 5 cards');
    if (stacks.length != 2) throw ArgumentError('Two players');
    if (hero < -1 || hero > 1) throw ArgumentError('No such player: $hero');
  }

  /// The user's sizes, for bets and raises alike, at every decision.
  static const defaultHeroSizes = [0.33, 0.5, 0.75, 1.0, 1.5];

  /// Bots use fewer sizes, and raise only against the first bet (after
  /// that they can still go all-in): every size adds to the work.
  static const defaultBotBetSizes = [0.33, 0.75, 1.5];
  static const defaultBotRaiseSizes = [0.75];

  /// A bet or raise to at least this share of the player's stack is left
  /// out: it is practically all-in, and the all-in choice covers it.
  static const nearlyAllIn = 0.9;

  /// Board cards (0-51): 3 on the flop, 4 on the turn, 5 on the river.
  final List<int> board;

  /// Chips in the middle when the street starts.
  final int pot;

  /// Chips behind for each player when the street starts.
  final List<int> stacks;
  final int bigBlind;

  /// How small a raise may be.
  final RaiseRule raiseRule;

  /// The user's player (0 or 1), who gets [heroSizes] at every decision;
  /// -1 when both players are bots.
  final int hero;

  /// Sizes as a share of the pot: for bets, of the pot; for raises, of the
  /// pot after calling. All-in is always available too.
  final List<double> heroSizes;
  final List<double> botBetSizes;
  final List<double> botRaiseSizes;

  Street get street => switch (board.length) { 3 => Street.flop, 4 => Street.turn, _ => Street.river };

  /// For sending to the web version's solver worker (lib/solver_worker.dart).
  Map<String, Object?> toJson() => {
        'board': board,
        'pot': pot,
        'stacks': stacks,
        'bigBlind': bigBlind,
        'raiseRule': raiseRule.name,
        'hero': hero,
        'heroSizes': heroSizes,
        'botBetSizes': botBetSizes,
        'botRaiseSizes': botRaiseSizes,
      };

  factory PostflopSpec.fromJson(Map<String, Object?> json) {
    List<int> ints(String key) => [for (final v in json[key] as List) (v as num).toInt()];
    List<double> doubles(String key) => [for (final v in json[key] as List) (v as num).toDouble()];
    return PostflopSpec(
      board: ints('board'),
      pot: (json['pot'] as num).toInt(),
      stacks: ints('stacks'),
      bigBlind: (json['bigBlind'] as num).toInt(),
      raiseRule: RaiseRule.values.byName(json['raiseRule'] as String),
      hero: (json['hero'] as num).toInt(),
      heroSizes: doubles('heroSizes'),
      botBetSizes: doubles('botBetSizes'),
      botRaiseSizes: doubles('botRaiseSizes'),
    );
  }
}

enum PostflopMove { fold, check, call, bet, raise, allIn }

class PostflopAction {
  const PostflopAction(this.move, {this.to = 0, this.potShare});

  final PostflopMove move;

  /// For bets, raises and all-ins: the player's total bet on the street after acting.
  final int to;

  /// For sized bets and raises: the size as a share of the pot (see [PostflopSpec]).
  final double? potShare;

  @override
  String toString() => switch (move) {
        PostflopMove.bet || PostflopMove.raise || PostflopMove.allIn => '${move.name} $to',
        _ => move.name,
      };
}

sealed class PostflopNode {}

class PostflopDecision extends PostflopNode {
  PostflopDecision._(this.player, this.actions, this.bets);

  /// 0 = acts first on the street, 1 = acts last.
  final int player;
  final List<PostflopAction> actions;

  /// What each player has bet on this street before this decision.
  final List<int> bets;
  late final List<PostflopNode> children;
  late final int id;

  /// Start of this node's numbers in the solver's arrays: `offset + action * hands + hand`.
  late final int offset;
}

class PostflopTerminal extends PostflopNode {
  PostflopTerminal._({required this.bets, required this.foldedBy, required this.allIn});

  /// Each player's bet on this street (after any uncalled part went back).
  final List<int> bets;

  /// Player who folded, or -1 if the street ended with both still in.
  final int foldedBy;

  /// Someone is all-in: the remaining cards are dealt with no more betting.
  final bool allIn;
}

/// Every betting sequence on one street.
class PostflopTree {
  PostflopTree(this.spec, {required this.hands}) {
    root = _build(_State(spec));
  }

  final PostflopSpec spec;

  /// Number of hands per player (for storage offsets).
  final int hands;
  late final PostflopNode root;
  final List<PostflopDecision> decisions = [];
  final List<PostflopTerminal> terminals = [];
  int _storage = 0;
  int get storageSize => _storage;

  PostflopNode _build(_State s) {
    final player = s.nextToAct();
    if (player == null) return _terminal(s);
    final actions = _options(s, player);
    final node = PostflopDecision._(player, List.unmodifiable(actions), List.unmodifiable(s.bets))
      ..id = decisions.length
      ..offset = _storage;
    decisions.add(node);
    _storage += actions.length * hands;
    node.children = [for (final a in actions) _build(s.copy()..apply(player, a))];
    return node;
  }

  List<PostflopAction> _options(_State s, int p) {
    final toCall = s.currentBet - s.bets[p];
    final allInTo = s.bets[p] + s.left(p);
    final canRaise = allInTo > s.currentBet && s.left(1 - p) > 0 && (!s.acted[p] || toCall >= s.fullRaise);
    final options = <PostflopAction>[
      if (toCall == 0) const PostflopAction(PostflopMove.check),
      if (toCall > 0) const PostflopAction(PostflopMove.fold),
      if (toCall > 0) const PostflopAction(PostflopMove.call),
    ];
    if (!canRaise) return options;

    final List<double> shares;
    if (p == spec.hero) {
      shares = spec.heroSizes;
    } else if (s.currentBet == 0) {
      shares = spec.botBetSizes;
    } else {
      shares = s.raises == 1 ? spec.botRaiseSizes : const [];
    }
    final sized = <int>{};
    for (final share in shares) {
      final to = sizeTo(s.currentBet, s.bets[p], spec.pot + s.bets[0] + s.bets[1], share, spec.bigBlind);
      // Sizes below the min-raise aren't allowed; (nearly) all-in ones are
      // covered by the all-in choice.
      if (s.currentBet > 0 && to < s.currentBet + s.fullRaise) continue;
      if (to >= allInTo * PostflopSpec.nearlyAllIn || !sized.add(to)) continue;
      options.add(PostflopAction(s.currentBet == 0 ? PostflopMove.bet : PostflopMove.raise, to: to, potShare: share));
    }
    options.add(PostflopAction(PostflopMove.allIn, to: allInTo));
    return options;
  }

  /// The total bet for a size given as a share of the pot: a bet of that
  /// share of [pot] (at least one big blind), or a raise of that share of
  /// the pot after calling.
  static int sizeTo(int currentBet, int playerBet, int pot, double share, int bigBlind) => currentBet == 0
      ? max((share * pot).round(), bigBlind)
      : currentBet + (share * (pot + currentBet - playerBet)).round();

  PostflopTerminal _terminal(_State s) {
    final bets = List.of(s.bets);
    // The part of a bet nobody matched goes back (also when the other player folds).
    if (bets[0] != bets[1]) {
      final high = bets[0] > bets[1] ? 0 : 1;
      bets[high] = bets[1 - high];
    }
    final node = PostflopTerminal._(
      bets: List.unmodifiable(bets),
      foldedBy: s.foldedBy,
      allIn: s.foldedBy < 0 && (spec.stacks[0] == bets[0] || spec.stacks[1] == bets[1]),
    );
    terminals.add(node);
    return node;
  }
}

/// Betting state while the tree is built; same rules as the game engine.
class _State {
  _State(this.spec)
      : bets = [0, 0],
        acted = [false, false],
        currentBet = 0,
        minRaise = spec.bigBlind,
        raises = 0,
        foldedBy = -1,
        // Player 0 acts first, so the search starts after player 1.
        lastActor = 1;

  _State._copy(_State o)
      : spec = o.spec,
        bets = List.of(o.bets),
        acted = List.of(o.acted),
        currentBet = o.currentBet,
        minRaise = o.minRaise,
        raises = o.raises,
        foldedBy = o.foldedBy,
        lastActor = o.lastActor;

  final PostflopSpec spec;
  final List<int> bets;
  final List<bool> acted;
  int currentBet;
  int minRaise;

  /// The smallest raise increment allowed now (see [RaiseRule]).
  int get fullRaise => spec.raiseRule.minimumIncrease(minRaise, spec.bigBlind);
  int raises;
  int foldedBy;
  int lastActor;

  _State copy() => _State._copy(this);

  int left(int p) => spec.stacks[p] - bets[p];
  bool canAct(int p) => foldedBy < 0 && left(p) > 0;

  int? nextToAct() {
    if (foldedBy >= 0) return null;
    final able = [for (var p = 0; p < 2; p++) if (canAct(p)) p];
    if (able.isEmpty) return null;
    if (able.length == 1 && bets[able.single] >= currentBet) return null;
    for (var k = 1; k <= 2; k++) {
      final p = (lastActor + k) % 2;
      if (canAct(p) && (!acted[p] || bets[p] < currentBet)) return p;
    }
    return null;
  }

  void apply(int p, PostflopAction a) {
    switch (a.move) {
      case PostflopMove.fold:
        foldedBy = p;
      case PostflopMove.check:
        break;
      case PostflopMove.call:
        bets[p] += min(currentBet - bets[p], left(p));
      case PostflopMove.bet || PostflopMove.raise || PostflopMove.allIn:
        final increase = a.to - currentBet;
        if (increase >= minRaise) minRaise = increase;
        currentBet = a.to;
        bets[p] = a.to;
        raises++;
    }
    acted[p] = true;
    lastActor = p;
  }
}
