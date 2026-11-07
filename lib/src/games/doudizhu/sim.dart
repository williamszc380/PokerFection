/// A fast, all-cards-known copy of a deal in its play phase, for the
/// bots' and the coach's look-ahead.
///
/// [DdzGame] keeps card ids, a history and the auction for the app; this
/// keeps only rank counts, so the coach can play thousands of deals to the
/// end per second. It is created from a guessed deal of the hidden cards
/// (see sampler.dart) and never shown to the player.
library;

import 'cards.dart';
import 'game.dart';
import 'play_gen.dart';
import 'plays.dart';
import 'rules.dart';

/// One deal in play with every hand known.
class DdzSim {
  DdzSim({
    required this.rules,
    required this.hands,
    required this.landlord,
    required this.toAct,
    required this.stake,
    this.bombs = 0,
    this.current,
    this.currentPlayer = -1,
    this.passes = 0,
    List<int>? playsBySeat,
  })  : sizes = [for (final h in hands) h.fold(0, (a, b) => a + b)],
        playsBySeat = playsBySeat ?? [0, 0, 0];

  /// The play phase of [game] with every hand known, for tests and tools.
  factory DdzSim.fromGame(DdzGame game) => DdzSim(
        rules: game.rules,
        hands: [for (var s = 0; s < 3; s++) game.countsOf(s)],
        landlord: game.landlord!,
        toAct: game.toAct,
        stake: game.stake,
        bombs: game.bombs,
        current: game.current,
        currentPlayer: game.currentPlayer ?? -1,
        passes: _passesOf(game),
        playsBySeat: [...game.playsBySeat],
      );

  static int _passesOf(DdzGame game) {
    if (game.current == null) return 0;
    var n = 0;
    for (var i = game.history.length - 1; i >= 0 && game.history[i].move is DdzPass; i--) {
      n++;
    }
    return n;
  }

  final DdzRules rules;

  /// Rank counts of each seat.
  final List<List<int>> hands;

  /// Cards each seat holds.
  final List<int> sizes;

  final int landlord;
  int toAct;
  final int stake;
  int bombs;

  /// The play to beat, or null when [toAct] leads.
  Play? current;
  int currentPlayer;

  /// Passes since [current] was played.
  int passes;

  final List<int> playsBySeat;

  /// The seat that went out, or -1 while the deal goes on.
  int winner = -1;

  bool get over => winner >= 0;

  /// Moves for the seat to act; null stands for passing.
  List<Play?> legalMoves() {
    final c = current;
    if (c == null) return leadPlays(hands[toAct], rules);
    return [null, ...beatingPlays(hands[toAct], c, rules)];
  }

  /// Plays [play] for the seat to act, or passes when it is null.
  void apply(Play? play) {
    final seat = toAct;
    if (play == null) {
      passes++;
      if (passes == 2) {
        current = null;
        currentPlayer = -1;
        passes = 0;
      }
      toAct = seat == 2 ? 0 : seat + 1;
      return;
    }
    final h = hands[seat];
    for (final r in play.ranks) {
      h[r]--;
    }
    sizes[seat] -= play.size;
    current = play;
    currentPlayer = seat;
    passes = 0;
    playsBySeat[seat]++;
    if (play.isBombLike) bombs++;
    if (sizes[seat] == 0) {
      winner = seat;
      return;
    }
    toAct = seat == 2 ? 0 : seat + 1;
  }

  /// An independent copy.
  DdzSim copy() => DdzSim(
        rules: rules,
        hands: [for (final h in hands) List<int>.of(h)],
        landlord: landlord,
        toAct: toAct,
        stake: stake,
        bombs: bombs,
        current: current,
        currentPlayer: currentPlayer,
        passes: passes,
        playsBySeat: List<int>.of(playsBySeat),
      )..winner = winner;

  /// Whether [seat]'s side won (only once [over]).
  bool wonBy(int seat) => (seat == landlord) == (winner == landlord);

  /// The final multiplier, spring included (only once [over]).
  int get finalMultiplier {
    final lord = landlord;
    final peasantPlays = playsBySeat[(lord + 1) % 3] + playsBySeat[(lord + 2) % 3];
    final spring = winner == lord ? peasantPlays == 0 : playsBySeat[lord] == 1;
    return ddzMultiplier(rules, bombs, spring);
  }

  /// Points [seat] wins (negative: loses) once [over].
  int pointsFor(int seat) {
    final each = stake * finalMultiplier;
    final mine = seat == landlord ? 2 * each : each;
    return wonBy(seat) ? mine : -mine;
  }

  /// Cards [seat] can't see: everything in the other two hands.
  List<int> unseenBy(int seat) {
    final a = hands[(seat + 1) % 3], b = hands[(seat + 2) % 3];
    return [for (var r = 0; r < Rank.count; r++) a[r] + b[r]];
  }

  @override
  String toString() =>
      'lord $landlord, to act $toAct, current $current by $currentPlayer, hands ${hands.map(countsText).join(' | ')}';
}
