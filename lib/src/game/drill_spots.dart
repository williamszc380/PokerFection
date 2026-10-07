/// Mistake drills: every Mistake or Blunder in solo training is saved as a
/// spot (the hand up to the user's decision) to play again later. Each spot
/// comes back after a cooldown that grows while it is played right and
/// starts over when it is played wrong (spaced repetition), in real time.
library;

import 'dart:math';

import '../bots/bot.dart';
import '../engine/actions.dart';
import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/poker_hand.dart';
import '../engine/positions.dart';
import '../engine/rules.dart';
import '../gto/hand_classes.dart';
import '../gto/spot_strategy.dart';
import '../online/mirror.dart' show actionOf;
import 'table_session.dart';

/// How long a spot waits after [step] right plays in a row: 10 minutes
/// (none yet: a mistake just made, or played wrong again), then 1 hour,
/// 1 day, 3 days, 1 week, then about 2.5 times longer each time (100
/// years at most).
Duration drillCooldown(int step) {
  const ladder = [Duration(minutes: 10), Duration(hours: 1), Duration(days: 1), Duration(days: 3), Duration(days: 7)];
  if (step < ladder.length) return ladder[step];
  final days = min(7 * pow(2.5, step - ladder.length + 1), 36500.0);
  return Duration(minutes: (days * Duration.minutesPerDay).round());
}

/// One move before the saved decision: who made it, and what.
typedef DrillMove = ({int seat, PlayerAction action});

/// A Mistake or a Blunder saved to play again: the hand up to the user's
/// decision (the user in seat 0), how it was graded, and when it is due.
class DrillSpot {
  DrillSpot({
    required this.names,
    required this.styles,
    required this.stacks,
    required this.button,
    this.ante = 0,
    this.raiseRule = RaiseRule.standard,
    required this.cards,
    this.board = const [],
    required this.moves,
    required this.grade,
    required this.evLoss,
    required this.saved,
    this.step = 0,
    DateTime? due,
  }) : due = due ?? saved.add(drillCooldown(step));

  /// [hand] at the user's decision, graded [grade] (giving up [evLoss]
  /// BB) at [now]; [players] and [styles] are the session's. Null if this
  /// device doesn't know every player's cards.
  static DrillSpot? at(
    PokerHand hand, {
    required List<PlayerInfo> players,
    required List<BotStyle?> styles,
    required DecisionGrade grade,
    required double evLoss,
    required DateTime now,
  }) {
    final n = hand.playerCount;
    if (hand.toAct != TableSession.heroSeat || players.length != n) return null;
    for (var seat = 0; seat < n; seat++) {
      if (!hand.knows(seat)) return null;
    }
    return DrillSpot(
      names: [for (final p in players) p.name],
      styles: [for (var seat = 0; seat < n; seat++) seat == TableSession.heroSeat ? null : styles[seat]],
      stacks: [for (var seat = 0; seat < n; seat++) hand.startingStackOf(seat)],
      button: hand.buttonSeat,
      ante: hand.ante,
      raiseRule: hand.raiseRule,
      cards: [for (var seat = 0; seat < n; seat++) hand.holeCards(seat)],
      board: hand.board,
      moves: [
        for (final e in hand.log)
          if (e is ActionTaken) (seat: e.seat, action: actionOf(e)),
      ],
      grade: grade,
      evLoss: evLoss,
      saved: now,
    );
  }

  /// The players' names and bot styles (null for the user), by seat.
  final List<String> names;
  final List<BotStyle?> styles;

  /// Everyone's chips when the hand started, by seat.
  final List<int> stacks;
  final int button;

  /// Ante per player, in chips, and the min-raise rule.
  final int ante;
  final RaiseRule raiseRule;

  /// Every player's two cards, by seat, and the board at the decision.
  final List<List<PlayingCard>> cards;
  final List<PlayingCard> board;

  /// Every move before the decision, in order (the user's own too).
  final List<DrillMove> moves;

  /// How the mistake was graded, what it gave up (BB) and when it was made.
  final DecisionGrade grade;
  final double evLoss;
  final DateTime saved;

  /// Right plays in a row since it was saved (or last played wrong), and
  /// when it is due again.
  int step;
  DateTime due;

  int get playerCount => stacks.length;

  /// The user's position, the street of the decision, and their starting
  /// hand ("AJo").
  Position get position => positionsBySeat(playerCount, button)[TableSession.heroSeat]!;
  Street get street => switch (board.length) {
        0 => Street.preflop,
        3 => Street.flop,
        4 => Street.turn,
        _ => Street.river,
      };
  String get handName => handClassName(handClassOf(cards[0][0], cards[0][1]));

  /// How long it waits now.
  Duration get cooldown => drillCooldown(step);

  /// What makes two mistakes the same spot: the table, the user's hand
  /// (before the flop its kind, like "AJo", whose answer is the same; after
  /// it the exact cards), the board and every move before the decision.
  String get key => [
        stacks.join(','),
        button,
        ante,
        raiseRule.name,
        board.isEmpty ? handName : cards[0].join(),
        board.join(),
        for (final m in moves) '${m.seat}:${m.action}',
      ].join('|');

  Map<String, Object?> toJson() => {
        'names': names,
        'styles': [for (final style in styles) style?.name],
        'stacks': stacks,
        'button': button,
        if (ante > 0) 'ante': ante,
        'rule': raiseRule.name,
        'cards': [for (final c in cards) c.join()],
        'board': board.join(),
        'moves': [
          for (final m in moves) [m.seat, m.action.type.name, if (m.action.type == ActionType.raise) m.action.amount],
        ],
        'grade': grade.name,
        'evLoss': evLoss,
        'saved': saved.millisecondsSinceEpoch,
        'step': step,
        'due': due.millisecondsSinceEpoch,
      };

  /// A spot saved by [toJson]; null if it isn't one (or isn't a hand that
  /// can be dealt: a card twice, a seat that doesn't exist).
  static DrillSpot? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    try {
      List<PlayingCard> cardsOf(Object? text) {
        final s = text as String;
        return [for (var i = 0; i + 1 < s.length; i += 2) PlayingCard.parse(s.substring(i, i + 2))];
      }

      final stacks = [for (final s in json['stacks'] as List<Object?>) s as int];
      final n = stacks.length;
      final cards = [for (final c in json['cards'] as List<Object?>) cardsOf(c)];
      final board = cardsOf(json['board']);
      final all = [...cards.expand((c) => c), ...board];
      final button = json['button'] as int;
      final moves = <DrillMove>[
        for (final m in json['moves'] as List<Object?>)
          if (m case [final int seat, final String type, ...final rest])
            (
              seat: seat,
              action: switch (type) {
                'fold' => const PlayerAction.fold(),
                'check' => const PlayerAction.check(),
                'call' => const PlayerAction.call(),
                'raise' => PlayerAction.raiseTo(rest.single as int),
                _ => throw FormatException('Unknown move', type),
              },
            ),
      ];
      final names = [for (final name in json['names'] as List<Object?>) name as String];
      final styles = [
        for (final style in json['styles'] as List<Object?>)
          style == null ? null : BotStyle.values.byName(style as String),
      ];
      final valid = n >= 2 &&
          n <= 8 &&
          names.length == n &&
          styles.length == n &&
          cards.length == n &&
          cards.every((c) => c.length == 2) &&
          const [0, 3, 4, 5].contains(board.length) &&
          all.toSet().length == all.length &&
          stacks.every((s) => s > 0) &&
          button >= 0 &&
          button < n &&
          moves.length == (json['moves'] as List).length &&
          moves.every((m) => m.seat >= 0 && m.seat < n);
      if (!valid) return null;
      return DrillSpot(
        names: names,
        styles: styles,
        stacks: stacks,
        button: button,
        ante: json['ante'] as int? ?? 0,
        raiseRule: RaiseRule.values.byName(json['rule'] as String),
        cards: cards,
        board: board,
        moves: moves,
        grade: DecisionGrade.values.byName(json['grade'] as String),
        evLoss: (json['evLoss'] as num).toDouble(),
        saved: DateTime.fromMillisecondsSinceEpoch(json['saved'] as int),
        step: max(0, json['step'] as int),
        due: DateTime.fromMillisecondsSinceEpoch(json['due'] as int),
      );
    } on Object {
      return null;
    }
  }
}

/// The saved spots: at most [capacity], each kept until there's no room
/// (then the ones learned best go first), however long it was learned.
class DrillList {
  DrillList([Iterable<DrillSpot> spots = const []]) {
    for (final spot in spots) {
      _makeRoom();
      _spots.add(spot);
    }
  }

  static const capacity = 256;

  final List<DrillSpot> _spots = [];

  List<DrillSpot> get spots => List.unmodifiable(_spots);

  /// Saves [spot], a mistake just made (due after its first cooldown).
  /// The same spot saved before (see [DrillSpot.key]) starts over instead:
  /// false then.
  bool add(DrillSpot spot) {
    final same = _spots.indexWhere((s) => s.key == spot.key);
    if (same >= 0) {
      _spots[same] = spot;
      return false;
    }
    _makeRoom();
    _spots.add(spot);
    return true;
  }

  /// Full: the spots with the longest cooldown go first (of those, the one
  /// due last).
  void _makeRoom() {
    while (_spots.length >= capacity) {
      _spots.remove(_spots.reduce((a, b) => _learnedBetter(b, a) ? b : a));
    }
  }

  static bool _learnedBetter(DrillSpot a, DrillSpot b) => a.step != b.step ? a.step > b.step : a.due.isAfter(b.due);

  bool remove(DrillSpot spot) => _spots.remove(spot);

  /// The spots due at [now], in the order to play them: the most overdue
  /// first; due the same minute, Blunders first (then the bigger EV loss).
  List<DrillSpot> due(DateTime now) => [for (final s in _spots) if (!s.due.isAfter(now)) s]..sort(_order);

  static int _order(DrillSpot a, DrillSpot b) {
    int minute(DrillSpot s) => s.due.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
    final byTime = minute(a).compareTo(minute(b));
    if (byTime != 0) return byTime;
    final byGrade = b.grade.index.compareTo(a.grade.index);
    return byGrade != 0 ? byGrade : b.evLoss.compareTo(a.evLoss);
  }

  /// When the next spot is due after [now], if any isn't due yet.
  DateTime? nextDue(DateTime now) => [
        for (final s in _spots) if (s.due.isAfter(now)) s.due,
      ].fold<DateTime?>(null, (first, due) => first == null || due.isBefore(first) ? due : first);

  /// [spot] played again at [now]: [right] (Good or better), it waits its
  /// next cooldown; wrong, 10 minutes again; null (it couldn't be graded),
  /// its cooldown once more. Returns the wait.
  Duration review(DrillSpot spot, {required bool? right, required DateTime now}) {
    spot.step = switch (right) {
      true => spot.step + 1,
      false => 0,
      null => spot.step,
    };
    final wait = spot.cooldown;
    spot.due = now.add(wait);
    return wait;
  }
}
