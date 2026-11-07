// The dealer's range (Training, tapping the dealer): what the hole card
// could be and what the dealer's two cards could add up to, worked out
// exactly from the cards the player has seen.
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_jobs.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_range.dart';
import 'package:pokerfection/src/games/blackjack/app/blackjack_record.dart';
import 'package:pokerfection/src/games/blackjack/blackjack.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/range.dart';

/// Shoes of the default 6-deck game (as in the screens' tests) whose first
/// round is a hard 16 against a ten (the dealer has checked for blackjack),
const _tenUp = 80;

/// the dealer showing an ace, insurance offered (not checked yet),
const _aceUp = 15;

/// a pair of eights against a 2 to 6 (nothing to check).
const _lowUp = 534;

const _rules = BlackjackRules();

BlackjackPlay _dealt(int seed, {BlackjackRules rules = _rules}) => BlackjackPlay(rules, shoeSeed: seed)..apply(dealMove);

double _rank(OpponentRange range, String rank) => range.ranks.singleWhere((r) => r.rank == rank).chance(1);
double _kind(OpponentRange range, String kind) => range.combos.singleWhere((c) => c.kind == kind).chance;

void main() {
  group('with the hole card face down', () {
    test('each rank is as likely as its share of the cards the player has not seen', () {
      final play = _dealt(_lowUp);
      final unseen = play.view().unseenSeen;
      final range = dealerRange(play);
      expect(play.round!.holeCardHidden, isTrue);
      expect(range.seat, dealerSeat);
      expect(range.cards, 1, reason: 'one hole card');
      expect(range.samples, unseen.total, reason: 'every unseen card is one possible hole card');
      for (var r = 0; r < rankCount; r++) {
        expect(_rank(range, rankName(r)), closeTo(unseen[r] / unseen.total, 1e-12), reason: rankName(r));
      }
      expect(_rank(range, 'T'), greaterThan(0.29), reason: 'about 4 in 13 cards count ten');
    });

    test('the ranks read 2 to 10 then the ace, one copy each, and add up to 100%', () {
      final range = dealerRange(_dealt(_lowUp));
      expect([for (final r in range.ranks) r.rank], ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'A']);
      expect(range.ranks.every((r) => r.atLeast.length == 1), isTrue);
      expect(range.ranks.fold(0.0, (sum, r) => sum + r.chance(1)), closeTo(1, 1e-9));
    });

    test('every two-card hand is one kind: the kinds add up to 100%, in the order shown', () {
      for (final seed in [_lowUp, _tenUp, _aceUp]) {
        final range = dealerRange(_dealt(seed));
        expect([for (final c in range.combos) c.kind], dealerStartKinds);
        expect(range.combos.fold(0.0, (sum, c) => sum + c.chance), closeTo(1, 1e-9), reason: 'seed $seed');
      }
    });

    test('a dealer who checked and played on has no blackjack: no ace under a ten', () {
      final play = _dealt(_tenUp);
      expect(play.round!.dealerPeeked, isTrue);
      final range = dealerRange(play);
      expect(_rank(range, 'A'), 0);
      expect(_kind(range, 'blackjack'), 0);
      expect(range.combos.firstWhere((c) => c.kind == 'blackjack').examples, isEmpty);
      // The ten under a ten is then the likeliest 17 to 21.
      expect(range.combos.firstWhere((c) => c.kind == 'total17to21').examples.first.$1, 'T+T');
    });

    test('before the check (insurance offered) a ten under the ace is still possible: that is blackjack', () {
      final play = _dealt(_aceUp);
      expect(play.round!.phase, RoundPhase.insurance);
      expect(play.round!.dealerPeeked, isFalse);
      final range = dealerRange(play);
      expect(_kind(range, 'blackjack'), closeTo(_rank(range, 'T'), 1e-12));
      expect(range.combos.firstWhere((c) => c.kind == 'blackjack').examples.single.$1, 'A+T');
    });

    test('against a low card the likeliest hands come first, each with its chance', () {
      final play = _dealt(_lowUp);
      final up = rankName(play.view().dealerUpcard.rank);
      final middle = dealerRange(play).combos.firstWhere((c) => c.kind == 'total12to16');
      final (combo, chance) = middle.examples.first;
      expect(combo, '$up+T', reason: 'a ten under a 2 to 6 is the likeliest 12 to 16');
      expect(chance, closeTo(_rank(dealerRange(play), 'T'), 1e-12));
      expect(middle.examples.length, lessThanOrEqualTo(OpponentRange.maxExamples));
    });
  });

  test('once the hole card is turned over, the range is that card for sure', () {
    final play = _dealt(_lowUp)..apply(handMove(0, BlackjackAction.stand));
    final round = play.round!;
    expect(round.isOver, isTrue);
    final range = dealerRange(play);
    final hole = rankName(round.dealerCards[1].rank);
    expect(range.samples, 1);
    for (final r in range.ranks) {
      expect(r.chance(1), r.rank == hole ? 1 : 0, reason: r.rank);
    }
  });

  group('when there is no range to show', () {
    test('before the first deal, and at tables without a hole card', () {
      expect(dealerRangeShows(BlackjackPlay(_rules, shoeSeed: 1)), isFalse);
      final european = BlackjackRules.preset(BlackjackPreset.european);
      expect(european.holeCard, isFalse);
      expect(dealerRangeShows(_dealt(_lowUp, rules: european)), isFalse);
      expect(() => dealerRange(_dealt(_lowUp, rules: european)), throwsStateError);
    });
  });

  group('the job', () {
    const job = BlackjackRangeJob();

    test('is registered, named after the game', () {
      expect(blackjackJobs.map((j) => j.name), contains('blackjack.range'));
      expect(job.name, 'blackjack.range');
    });

    test('replays the shoe it is given and answers the same range, through JSON', () {
      final play = _dealt(_tenUp);
      final record = newBlackjackRecord(rules: _rules, seed: _tenUp, playerName: 'Player', dealerName: 'Dealer')
          .withMove(dealMove);
      final input = job.decodeInput(job.encodeInput(record));
      final output = job.decodeOutput(job.encodeOutput(job.run(input, JobContext(platform: JobPlatform.test))));
      expect(output.toJson(), dealerRange(play).toJson());
    });

    test('its check inputs include hole cards face down and turned over', () {
      final inputs = job.checkInputs();
      final plays = [for (final i in inputs) BlackjackPlay.replay(i)];
      expect(plays.where((p) => p.round!.holeCardHidden), isNotEmpty);
      expect(plays.where((p) => !p.round!.holeCardHidden), isNotEmpty);
      expect(job.examples(), isNotEmpty);
    });

    test('writes every number as a whole count, the same on every platform', () {
      final json = job.normalize(job.encodeOutput(dealerRange(_dealt(_lowUp)))) as Map<String, Object?>;
      expect(json['samples'], isA<int>());
      final first = (json['ranks']! as List).first as Map<String, Object?>;
      expect((first['p']! as List).single, isA<int>());
    });
  });
}
