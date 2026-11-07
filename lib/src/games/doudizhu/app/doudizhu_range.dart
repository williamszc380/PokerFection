/// An opponent's range in Fight the Landlord: what they could hold, from
/// the player's side of the table. The job deals the hidden cards many
/// times in ways that fit everything the player has seen (their own cards,
/// the plays, each hand's size, and the cards everyone has seen that are
/// still in a hand: the face-up card in its holder's, the shown kitty cards
/// the landlord still holds), weighs each deal by how well it explains the bids and plays so
/// far (the coach's own inference, see dealWeight; during the auction, the
/// bids alone, see auctionWeight), then tallies the opponent's hands by
/// weight: the chance of holding each rank (and how many of it) and of each
/// kind of combination. The sheet's count of deals is their effective
/// number, which a few heavy guesses keep well under the pool's size.
///
/// The job reads the deal only through the player's view, so the cards the
/// Training option turns face up never reach it.
library;

import 'dart:math';

import '../../../kit/game_record.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/range.dart';
import '../doudizhu.dart';
import '../policy.dart';
import '../sampler.dart';
import 'doudizhu_jobs.dart' show ddzSampleGame;
import 'doudizhu_record.dart';

/// The ranks of a range, lowest first, in the range's notation: the
/// engine's rank letters ('T' is the 10), and 'SJ' / 'BJ' for the little
/// and big jokers, one of each.
const ddzRangeRanks = <(String, int)>[
  ('3', 4), ('4', 4), ('5', 4), ('6', 4), ('7', 4), ('8', 4), ('9', 4), //
  ('T', 4), ('J', 4), ('Q', 4), ('K', 4), ('A', 4), ('2', 4), ('SJ', 1), ('BJ', 1),
];

/// The kinds of combination a range names, in the order shown: pairs,
/// trios, straights (5 in a row), pair straights (3 pairs in a row),
/// airplanes (2 trios in a row), bombs and the rocket. A combination is
/// written as its cards in the engine's rank letters, lowest first ("77",
/// "34567", "334455", "333444", "8888"; the rocket "BR"). Straights and
/// chains are named by their shortest form: a hand with 3 to 8 makes the
/// straights 34567 and 45678.
const ddzRangeKinds = ['pair', 'trio', 'straight', 'pairs', 'airplane', 'bomb', 'rocket'];

/// A rank number's code in a range.
String ddzRangeRank(int rank) => switch (rank) {
  Rank.littleJoker => 'SJ',
  Rank.bigJoker => 'BJ',
  _ => Rank.chars[rank],
};

/// The combinations one hand of rank [counts] can make, by kind (see
/// [ddzRangeKinds]); a bomb also counts as a pair and a trio, since it can
/// be split.
Map<String, Set<String>> ddzRangeCombos(List<int> counts) {
  String repeat(int rank, int n) => Rank.chars[rank] * n;
  Set<String> chains(int length, int copies) => {
    for (var start = 0; start + length - 1 <= Rank.highestInChain; start++)
      if ([for (var r = start; r < start + length; r++) counts[r]].every((c) => c >= copies))
        [for (var r = start; r < start + length; r++) repeat(r, copies)].join(),
  };
  return {
    'pair': {for (var r = 0; r <= Rank.two; r++) if (counts[r] >= 2) repeat(r, 2)},
    'trio': {for (var r = 0; r <= Rank.two; r++) if (counts[r] >= 3) repeat(r, 3)},
    'straight': chains(PlayType.straight.minLength, 1),
    'pairs': chains(PlayType.pairStraight.minLength, 2),
    'airplane': chains(PlayType.airplane.minLength, 3),
    'bomb': {for (var r = 0; r <= Rank.two; r++) if (counts[r] == 4) repeat(r, 4)},
    'rocket': {if (counts[Rank.littleJoker] > 0 && counts[Rank.bigJoker] > 0) 'BR'},
  };
}

/// [seat]'s range seen by [viewer] (always the player's seat in the app),
/// from a pool of [pool] weighed guesses (fewer when [deadline] passes
/// first: a range from fewer deals is still a range).
OpponentRange ddzRange(
  DdzView view,
  int seat, {
  required Random random,
  required int pool,
  Duration? deadline,
}) {
  if (seat == view.seat || seat < 0 || seat > 2) throw ArgumentError.value(seat, 'seat', 'not an opponent');
  final clock = Stopwatch()..start();
  final sampler = DdzSampler(view);
  const policy = HeuristicPolicy();
  final guesses = <List<int>>[];
  final weights = <double>[];
  for (var i = 0; i < pool; i++) {
    // At least a few guesses, whatever the clock says.
    if (deadline != null && i >= 20 && clock.elapsed > deadline) break;
    final hands = sampler.deal(random);
    weights.add(auctionWeight(view, sampler.count, hands.sublist(0, 3), policy, 0.3));
    guesses.add(hands[seat]);
  }
  List<String> codes(List<int> counts) => [
    for (final (r, n) in counts.indexed)
      for (var k = 0; k < n; k++) ddzRangeRank(r),
  ];

  // Known for sure (every guess the same): one deal says it all.
  final unique = guesses.every((g) => _same(g, guesses.first));
  return OpponentRange.tally(
    seat: seat,
    hands: unique ? [codes(guesses.first)] : [for (final g in guesses) codes(g)],
    weights: unique ? null : weights,
    rankOrder: ddzRangeRanks,
    kinds: ddzRangeKinds,
    combosOf: (hand) => ddzRangeCombos(_counts(hand)),
  );
}

bool _same(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<int> _counts(List<String> hand) {
  final counts = List<int>.filled(Rank.count, 0);
  for (final code in hand) {
    counts[switch (code) {
      'SJ' => Rank.littleJoker,
      'BJ' => Rank.bigJoker,
      _ => Rank.chars.indexOf(code),
    }]++;
  }
  return counts;
}

/// The range's work on [platform]: how many guesses it weighs and tallies.
/// JavaScript and phones weigh fewer; tests few.
int ddzRangeBudget(JobPlatform platform) => switch (platform) {
  JobPlatform.desktop || JobPlatform.webWasm => 2000,
  JobPlatform.phone || JobPlatform.webJs => 800,
  JobPlatform.test => 60,
};

/// What the range job gets: the deal so far (GameRecord.jobJson), whose
/// view to work from ([viewer], the player), whose range ([seat]), and the
/// seed of its deals.
class DdzRangeInput {
  const DdzRangeInput({required this.record, required this.viewer, required this.seat, required this.seed});

  final Map<String, Object?> record;
  final int viewer;
  final int seat;
  final int seed;
}

/// An opponent's range (the sheet that opens when the player taps a bot's
/// seat in Training).
class DdzRangeJob extends GameJob<DdzRangeInput, OpponentRange> {
  const DdzRangeJob();

  @override
  String get name => 'doudizhu.range';

  @override
  Object? encodeInput(DdzRangeInput input) =>
      {'record': input.record, 'viewer': input.viewer, 'seat': input.seat, 'seed': input.seed};

  @override
  DdzRangeInput decodeInput(Object? json) {
    final map = json! as Map<String, Object?>;
    return DdzRangeInput(
      record: map['record']! as Map<String, Object?>,
      viewer: (map['viewer']! as num).toInt(),
      seat: (map['seat']! as num).toInt(),
      seed: (map['seed']! as num).toInt(),
    );
  }

  @override
  Object? encodeOutput(OpponentRange output) => output.toJson();

  @override
  OpponentRange decodeOutput(Object? json) => OpponentRange.fromJson(json);

  @override
  OpponentRange run(DdzRangeInput input, JobContext context) {
    final record = ddzRecordFromJson(input.record) ?? (throw const FormatException('Not a doudizhu record'));
    final view = ddzReplay(record).viewFor(input.viewer);
    final budget = ddzRangeBudget(context.platform);
    final remaining = context.remaining;
    return ddzRange(
      view,
      input.seat,
      random: Random(input.seed),
      pool: budget,
      // Most of the cap: the rest replays the record and sends the answer.
      deadline: remaining == null ? null : remaining * 0.6,
    );
  }

  @override
  Object? normalize(Object? outputJson) => _rounded(outputJson);

  @override
  List<DdzRangeInput> examples() {
    final game = ddzSampleGame(1);
    final mid = game.upTo(game.moves.length ~/ 2);
    return [
      DdzRangeInput(record: game.upTo(0).jobJson(), viewer: 0, seat: 1, seed: 3),
      DdzRangeInput(record: mid.jobJson(), viewer: 0, seat: 2, seed: 3),
    ];
  }

  @override
  List<DdzRangeInput> checkInputs() => [
    for (final seed in const [1, 2, 3])
      for (final (i, at) in _rangePoints(ddzSampleGame(seed)).indexed)
        DdzRangeInput(record: ddzSampleGame(seed).upTo(at).jobJson(), viewer: 0, seat: 1 + i % 2, seed: seed * 13 + i),
  ];
}

/// Points of a deal to work a range out at: the start of the auction, the
/// first lead, the middle, near the end.
List<int> _rangePoints(GameRecord game) {
  final replay = ddzReplay(game, upTo: 0);
  var firstLead = 0;
  for (var i = 0; i < game.moves.length; i++) {
    if (replay.phase == DdzPhase.playing) {
      firstLead = i;
      break;
    }
    ddzApply(replay, game.moves[i]);
  }
  final n = game.moves.length;
  return {0, firstLead, firstLead + (n - firstLead) ~/ 2, max(0, n - 3)}.toList()..sort();
}

/// Numbers rounded to 9 places, so a JavaScript and a native run compare
/// equal (they print doubles differently: "1" and "1.0").
Object? _rounded(Object? json) => switch (json) {
  final double d => (d * 1e9).round() / 1e9,
  final Map<String, Object?> m => {for (final e in m.entries) e.key: _rounded(e.value)},
  final List<Object?> l => [for (final e in l) _rounded(e)],
  _ => json,
};
