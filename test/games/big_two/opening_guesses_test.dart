// Who goes first shows the table only what the rules make public, and
// every guesser keeps to what it showed. A probe: many deals under every
// preset, two to four players, the "must play the starting card" rule on
// and off, looked at from every seat at the deal and part-way through,
// and many guesses at the hidden cards from each, checking two rules every
// time:
// 1. a card the table has seen that is still in a hand (the starting card,
//    a three-player deal's face-up card) is with its holder, and nowhere
//    else;
// 2. in a two-player deal the starting card is the lowest card dealt (low
//    cards were called upward until someone held one), so nobody holds a
//    card below it: the other player holds nothing lower.
// The guessers are the engine's sampler (the coach's and the bots' plain
// guesses), its weighted guesses (the coach's reading of the moves), the
// proof solver's merged hands, the card counter, the range job, and the
// same from the views a room sends (a seat's, and one rebuilt from the
// spectators' for their coach). With three or four players the starting
// card is the deck's lowest, so rule 2 adds nothing there.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_range.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/games/big_two/inference.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_view_codec.dart';

/// How many guesses each view is probed with.
const _guesses = 150;

/// Every deal looked at: [deals] seeds per rule set, at the deal and after
/// a few random moves.
const _deals = 5;

final _ruleSets = [
  for (final players in [2, 3, 4])
    for (final preset in BigTwoPreset.values)
      for (final must in [true, false]) BigTwoRules.preset(preset, players: players).copyWith(mustPlayStartCard: must),
];

/// The deal of [seed] under [rules], played [moves] random moves on (no
/// further than its end).
BigTwoState _dealt(BigTwoRules rules, int seed, int moves) {
  final s = BigTwoState.deal(rules, seed: seed);
  final rng = GameRandom(seed * 31 + moves);
  for (var i = 0; i < moves && !s.isOver; i++) {
    final legal = s.legalMoves();
    s.apply(legal[rng.nextInt(legal.length)]);
  }
  return s;
}

/// Checks [hands] (a guess: engine codes by seat) against both rules for
/// [view], saying [where] it came from when one is broken.
void _check(BigTwoView view, List<List<int>> hands, String where) {
  for (final v in view.visibleCards) {
    for (var seat = 0; seat < view.players; seat++) {
      final holds = seat == view.seat ? view.handCodes.contains(v.code) : hands[seat].contains(v.code);
      expect(holds, seat == v.seat, reason: '$where: visible ${view.rules.cardOf(v.code)} of seat ${v.seat} at $seat');
    }
  }
  if (view.players == 2 && view.startCode >= 0) {
    for (var seat = 0; seat < 2; seat++) {
      final cards = seat == view.seat ? view.handCodes : hands[seat];
      expect(
        cards.every((c) => c >= view.startCode),
        isTrue,
        reason: '$where: seat $seat holds a card below ${view.rules.cardOf(view.startCode)}',
      );
    }
  }
}

/// Every probe of [view], from [what] (a description for failures).
void _probe(BigTwoView view, String what, {required int seed, bool range = false}) {
  final rng = GameRandom(seed);
  final sampler = DealSampler(view);
  for (var i = 0; i < _guesses; i++) {
    _check(view, sampler.sample(rng), '$what, guess $i');
  }
  if (view.history.isNotEmpty) {
    final weighted = WeightedDeals(view, () => sampler.sample(rng), const InferenceModel(), 30);
    for (final (i, hands) in weighted.deals.indexed) {
      _check(view, hands, '$what, weighted guess $i');
    }
  }
  // The proof solver deals each opponent every card it may hold.
  final merged = EndgameSolver.sharedState(BigTwoState.fromView(view, null), view.seat);
  for (var seat = 0; seat < view.players; seat++) {
    if (seat == view.seat) continue;
    final codes = merged.handCodesOf(seat);
    for (final v in view.visibleCards) {
      if (v.seat != view.seat) expect(codes.contains(v.code), v.seat == seat, reason: '$what: proof, seat $seat');
    }
    if (view.players == 2 && view.startCode >= 0) {
      expect(codes.every((c) => c >= view.startCode), isTrue, reason: '$what: proof, seat $seat');
    }
  }
  // The counter's cards still out are the ones the others may hold.
  final out = CardCounter.of(view).out;
  if (view.players == 2 && view.startCode >= 0) {
    expect(out.every((c) => c >= view.startCode), isTrue, reason: '$what: counter');
  }
  if (range) {
    for (var seat = 0; seat < view.players; seat++) {
      if (seat == view.seat || view.counts[seat] == 0) continue;
      final r = bigTwoRange(view, seat, seed: seed, samples: 120);
      for (final v in view.visibleCards) {
        final rank = r.ranks[v.code >> 2];
        // The holder has that rank every time.
        if (v.seat == seat) expect(rank.chance(1), 1.0, reason: '$what: range of $seat, ${view.rules.cardOf(v.code)}');
      }
      if (view.players == 2 && view.startCode >= 0) {
        // A rank whose every card is below the starting card was never dealt.
        for (var rk = 0; rk < 13 && rk * 4 + 3 < view.startCode; rk++) {
          expect(r.ranks[rk].chance(1), 0.0, reason: '$what: range of $seat, rank $rk');
        }
      }
    }
  }
}

void main() {
  test(
    'every guess keeps the shown cards with their holders, and two players\' cards at or above the starting card',
    () {
      var views = 0;
      for (final (r, rules) in _ruleSets.indexed) {
        for (var seed = 1; seed <= _deals; seed++) {
          for (final moves in [0, 3 + seed]) {
            final s = _dealt(rules, seed + 100 * r, moves);
            if (s.dragonWin || s.isOver) continue;
            for (var seat = 0; seat < rules.players; seat++) {
              final view = s.viewFor(seat);
              final what = '${rules.players} players, rules $r, deal $seed, $moves moves, seat $seat';
              _probe(view, what, seed: seed * 7 + seat, range: seed == 1);
              views++;
            }
          }
        }
      }
      expect(views, greaterThan(400));
    },
  );

  test(
    'a room\'s views, a seat\'s and one rebuilt from the spectators\', hold the same and are guessed the same way',
    () {
      for (final players in [2, 3, 4]) {
        final rules = BigTwoRules.standard(players: players);
        for (var seed = 1; seed <= 8; seed++) {
          final s = _dealt(rules, seed, seed.isEven ? 0 : 3);
          if (s.isOver) continue;
          final spectators = bigTwoSpectatorView(
            s,
            visible: {for (var i = 0; i < players; i++) i},
            deal: 1,
            match: null,
          );
          for (var seat = 0; seat < players; seat++) {
            final mine = bigTwoEngineView(bigTwoSeatView(s, seat, deal: 1, match: null));
            final rebuilt = bigTwoEngineView(bigTwoSeatViewFrom(spectators, seat)!);
            final real = s.viewFor(seat);
            for (final view in [mine, rebuilt]) {
              expect(view.startCode, real.startCode);
              expect(view.startSeat, real.startSeat);
              expect(view.visibleCards, real.visibleCards);
              _probe(view, 'room, $players players, deal $seed, seat $seat', seed: seed);
            }
          }
        }
      }
    },
  );

  test('two players: the deal\'s step calls every card up to the starting card, and none below it was dealt', () {
    final rules = BigTwoRules.standard(players: 2);
    var calledMore = 0;
    for (var seed = 1; seed <= 200; seed++) {
      final s = BigTwoState.deal(rules, seed: seed);
      if (s.isOver) continue;
      final step = BigTwoOpening.of(s)!;
      expect(step.kind, BigTwoOpeningKind.lowestCalled);
      expect(step.starter, s.startSeat);
      expect(step.called.last, s.startCode);
      expect(step.shown, [s.startCode], reason: 'only the starter\'s card');
      for (final code in step.undealtCalls) {
        expect(s.handCodesOf(0).contains(code) || s.handCodesOf(1).contains(code), isFalse);
      }
      if (step.called.length > 1) calledMore++;
      // Every seat's view gives the same step.
      for (var seat = 0; seat < 2; seat++) {
        final fromView = BigTwoOpening.of(BigTwoState.fromView(s.viewFor(seat), null))!;
        expect(fromView.toString(), step.toString());
      }
    }
    expect(calledMore, greaterThan(40), reason: 'about a third of two-player deals have no 3♦');
  });

  test('three or four players: the step shows the deck\'s lowest card (and the face-up card), nothing else', () {
    for (final players in [3, 4]) {
      for (final preset in BigTwoPreset.values) {
        final rules = BigTwoRules.preset(preset, players: players);
        for (var seed = 1; seed <= 30; seed++) {
          final s = BigTwoState.deal(rules, seed: seed);
          if (s.isOver) continue;
          final step = BigTwoOpening.of(s)!;
          expect(step.kind, BigTwoOpeningKind.startingCard);
          expect(step.startCode, 0, reason: 'the 3♦, or the 3♣ in the Taiwan and Pusoy Dos orders');
          expect(rules.cardOf(0).rank, Ranks.three);
          expect(step.called, [0]);
          expect(step.shown, [0, if (players == 3 && s.extraCode != 0) s.extraCode]);
          expect({for (final v in s.visibleCards) v.code}, step.shown.toSet());
        }
      }
    }
  });

  test('a chosen leader: the step names them and shows nothing, and the guesses are free', () {
    final rules = BigTwoRules.standard(players: 2);
    final s = BigTwoState.deal(rules, seed: 9, leader: 1);
    final step = BigTwoOpening.of(s)!;
    expect(step.kind, BigTwoOpeningKind.chosen);
    expect(step.starter, 1);
    expect(step.shown, isEmpty);
    final view = s.viewFor(0);
    expect(view.visibleCards, isEmpty);
    expect(view.startCode, -1, reason: 'nobody told the lowest card dealt');
    final rng = GameRandom(1);
    final sampler = DealSampler(view);
    final lowest = <int>{for (var i = 0; i < 300; i++) sampler.sample(rng)[1].reduce((a, b) => a < b ? a : b)};
    expect(lowest.length, greaterThan(1));
  });

  test(
    'the step\'s length: two seconds at Normal (1.2 s for a chosen leader), scaled by the speed, none at Instant',
    () {
      final cards = BigTwoOpening.of(BigTwoState.deal(BigTwoRules.standard(), seed: 2))!;
      final chosen = BigTwoOpening.of(BigTwoState.deal(BigTwoRules.standard(), seed: 2, leader: 1))!;
      expect(cards.lengthAt(1), const Duration(milliseconds: 2000));
      expect(cards.lengthAt(0.35), const Duration(milliseconds: 700));
      expect(cards.lengthAt(0), Duration.zero);
      expect(chosen.lengthAt(1), const Duration(milliseconds: 1200));
      // Two players: each call 15% of the step, at most half of it in all.
      final two = BigTwoRules.standard(players: 2);
      for (var seed = 1; seed <= 100; seed++) {
        final s = BigTwoState.deal(two, seed: seed);
        if (s.isOver) continue;
        final step = BigTwoOpening.of(s)!;
        expect(step.namedAt, lessThanOrEqualTo(0.5 + 1e-9));
        expect(step.namedAt, lessThan(BigTwoOpening.flyFrom), reason: 'named before the card flies');
        for (var i = 1; i < step.called.length; i++) {
          expect(step.callAt(i), greaterThan(step.callAt(i - 1)));
        }
      }
    },
  );
}
