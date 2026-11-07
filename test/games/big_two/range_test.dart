// An opponent's range (big_two.range): what they could hold, from the
// player's side of the table only, as the range sheet shows it.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_range.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/range.dart';
import 'package:pokerfection/src/kit/seats.dart';

Map<String, Set<String>> combos(String cards, [BigTwoRules? rules]) =>
    bigTwoCombos(rules ?? BigTwoRules.standard(), parseCards(cards));

final _seats = [
  const SeatSpec(human: true, name: 'Player'),
  for (final name in ['Ana', 'Ben', 'Kai']) SeatSpec(human: false, level: KitLevel.easy, name: name),
];

JobContext _noCap() => JobContext(platform: JobPlatform.test);

void main() {
  group('the combinations a hand can make', () {
    test('pairs and triples, each named by its rank, a triple also giving a pair', () {
      final c = combos('7d 7c 7s Ks Kh 4d');
      expect(c['pair'], {'7-7', 'K-K'});
      expect(c['triple'], {'7-7-7'});
    });

    test('a straight is a run the rules count; A-2-3-4-5 counts in the standard game, J-Q-K-A-2 never', () {
      expect(combos('3d 4c 5h 6s 7d')['straight'], {'3-4-5-6-7'});
      expect(combos('Ad 2c 3h 4s 5d')['straight'], {'A-2-3-4-5'});
      expect(combos('Jd Qc Kh As 2d')['straight'], isEmpty);
      expect(combos('Jd Qc Kh As 2d', BigTwoRules.standard().copyWith(straights: StraightRule.twoHigh))['straight'], {
        'J-Q-K-A-2',
      });
    });

    test('five of one suit in a run are a straight flush only, not a straight or a flush', () {
      final c = combos('3h 4h 5h 6h 7h');
      expect(c['straightFlush'], {'3h-4h-5h-6h-7h'});
      expect(c['straight'], isEmpty);
      expect(c['flush'], isEmpty);
      // A sixth heart makes a plain flush too; another 7 makes a plain straight.
      expect(combos('3h 4h 5h 6h 7h Kh')['flush'], {'flush:h'});
      expect(combos('3h 4h 5h 6h 7h 7s')['straight'], {'3-4-5-6-7'});
    });

    test('a full house is named by its triple with the lowest pair beside it', () {
      expect(combos('Kd Kc Ks 9h 9d 4c 4s')['fullHouse'], {'K-K-K-4-4'});
      expect(combos('Kd Kc Ks 9h')['fullHouse'], isEmpty, reason: 'no pair, and too few cards');
    });

    test('four of a kind needs a fifth card to be played with', () {
      expect(combos('9d 9c 9h 9s')['quads'], isEmpty);
      expect(combos('9d 9c 9h 9s 3d')['quads'], {'9-9-9-9'});
    });

    test('the 2s: at least one, two or three, with which ones', () {
      final c = combos('2d 2h 2s 5c');
      expect(c['twos:1'], {'2d', '2h', '2s'});
      expect(c['twos:2'], {'2d-2h', '2d-2s', '2h-2s'});
      expect(c['twos:3'], {'2d-2h-2s'});
      expect(combos('5c 6d')['twos:1'], isEmpty);
    });
  });

  group('the range', () {
    final rules = BigTwoRules.standard();
    final dealt = BigTwoRecord.deal(rules: rules, seats: _seats, seed: 41);

    test('the chances add up: on average they hold as many cards as they do', () {
      final range = bigTwoRange(BigTwoRecord.replay(dealt).viewFor(0), 1, seed: 3, samples: 500);
      expect(range.cards, 13);
      expect(range.samples, 500);
      expect(range.ranks.fold(0.0, (sum, r) => sum + r.expected), closeTo(13, 1e-9));
      expect(range.combos.map((c) => c.kind), bigTwoRangeKinds, reason: 'every kind listed, in order');
    });

    test('never a card the player holds or has seen played', () {
      final state = BigTwoRecord.replay(dealt);
      final mine = state.handOf(0);
      final range = bigTwoRange(state.viewFor(0), 2, seed: 4, samples: 400);
      for (final rank in {for (final c in mine) c.rank}) {
        final held = mine.where((c) => c.rank == rank).length;
        final chance = range.ranks[rank];
        // With [held] of the rank in the player's hand, nobody else can hold more than 4 - held.
        expect(chance.chance(5 - held), 0, reason: 'rank ${Ranks.labels[rank]}');
      }
      for (final example in range.combos.expand((c) => c.examples)) {
        for (final part in example.$1.split('-').where((p) => p.length == 2)) {
          expect(mine, isNot(contains(Card.parse(part))), reason: '${example.$1} uses a card the player holds');
        }
      }
    });

    test('it never peeks: two deals the player can\'t tell apart give the same range', () {
      // The same hand for the player; the two bots' hands swapped.
      final deck = [...fullDeck];
      final hands = [for (var s = 0; s < 4; s++) deck.sublist(s * 13, s * 13 + 13)];
      // The player must hold the 3 of diamonds (they lead), so nothing is known
      // about who holds what among the bots.
      final a = BigTwoState.fromHands(rules, hands);
      final b = BigTwoState.fromHands(rules, [hands[0], hands[2], hands[1], hands[3]]);
      final first = bigTwoRange(a.viewFor(0), 1, seed: 9, samples: 300).toJson();
      final second = bigTwoRange(b.viewFor(0), 1, seed: 9, samples: 300).toJson();
      expect(first, second);
    });

    test('a three-player deal\'s face-up card is public: its holder has it for sure', () {
      final three = BigTwoRules.standard(players: 3);
      for (var seed = 1; seed < 40; seed++) {
        final record = BigTwoRecord.deal(rules: three, seats: _seats.take(3).toList(), seed: seed);
        final state = BigTwoRecord.replay(record);
        final view = state.viewFor(0);
        if (view.extraSeat == 0 || !view.knownOtherCards.contains(view.extraCode)) continue;
        final card = three.cardOf(view.extraCode);
        final range = bigTwoRange(view, view.extraSeat, seed: 1, samples: 200);
        expect(range.ranks[card.rank].chance(1), 1.0);
        return;
      }
      fail('no seed dealt the face-up card to a bot');
    });

    test('the starting card\'s holder has it for sure; no other opponent\'s range ever holds it', () {
      // Before the first play, and after it with "must play the starting
      // card" off: either way it is still in its holder's hand.
      var checked = 0;
      for (final must in [true, false]) {
        final table = BigTwoRules.standard().copyWith(mustPlayStartCard: must);
        for (var seed = 1; seed < 30 && checked < (must ? 3 : 6); seed++) {
          final state = BigTwoState.deal(table, seed: seed);
          if (state.isOver || state.startSeat == 0) continue;
          if (!must) {
            // A first play without the 3♦, if the leader has one.
            final lead = state.legalMoves().where((m) => !m.containsCode(state.startCode)).firstOrNull;
            if (lead == null) continue;
            state.apply(lead);
          }
          final view = state.viewFor(0);
          expect(view.knownOtherCards, contains(state.startCode));
          final start = table.cardOf(state.startCode);
          final mine = view.hand.where((c) => c.rank == start.rank).length;
          for (var seat = 1; seat < 4; seat++) {
            final range = bigTwoRange(view, seat, seed: seed, samples: 200);
            final threes = range.ranks[start.rank];
            if (seat == state.startSeat) {
              expect(threes.chance(1), 1.0, reason: 'seed $seed: seat $seat holds ${start.short}');
            } else {
              // Without the 3♦ the other seats share at most 3 - mine of the 3s.
              expect(threes.chance(4 - mine), 0, reason: 'seed $seed: seat $seat never holds ${start.short}');
            }
          }
          checked++;
        }
      }
      expect(checked, 6);
    });

    test('the job replays the record, takes the player\'s view and repeats exactly', () {
      const job = BigTwoRangeJob();
      final input = BigTwoRangeInput(record: dealt.jobJson(), viewer: 0, seat: 3, seed: 12, samples: 300);
      final once = job.encodeOutput(job.run(job.decodeInput(job.encodeInput(input)), _noCap()));
      final again = job.encodeOutput(job.run(input, _noCap()));
      expect(once, again);
      final range = job.decodeOutput(once);
      expect(range.seat, 3);
      expect(range.samples, 300);
    });

    test('the job never gets the record\'s extra, where the Training option keeps Show cards', () {
      final shown = dealt.withExtra('showCards', true);
      final input = BigTwoRangeInput(record: shown.jobJson(), viewer: 0, seat: 1, seed: 1);
      expect((input.toJson()['record']! as Map).containsKey('extra'), isFalse);
    });

    test('asking the player\'s own range is refused', () {
      const job = BigTwoRangeJob();
      expect(
        () => job.run(BigTwoRangeInput(record: dealt.jobJson(), viewer: 0, seat: 0, seed: 1), _noCap()),
        throwsArgumentError,
      );
    });

    test('under a spent time cap it still samples enough to show', () {
      final range = bigTwoRange(
        BigTwoRecord.replay(dealt).viewFor(0),
        1,
        seed: 2,
        context: JobContext(platform: JobPlatform.desktop, timeCap: Duration.zero),
      );
      expect(range.samples, inInclusiveRange(200, 250));
    });

    test('its examples and check inputs run and survive the JSON round trip', () {
      const job = BigTwoRangeJob();
      expect(job.checkInputs(), hasLength(greaterThanOrEqualTo(20)));
      for (final input in job.examples()) {
        final out = job.run(job.decodeInput(job.encodeInput(input)), _noCap());
        expect(OpponentRange.fromJson(job.encodeOutput(out)).toJson(), job.encodeOutput(out));
      }
    });
  });
}
