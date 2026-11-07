/// `big_two.range`: what an opponent could hold, from the player's side of
/// the table (the range sheet a tap on an opponent opens, in Training).
///
/// The job replays the record up to the position and takes the VIEWER's
/// view (the player's: their own hand and everything played in public),
/// never the opponent's hand, and never the cards the Training option
/// shows face up (those live in the record's extra, which a job never
/// gets). The engine's DealSampler then deals the cards the viewer can't
/// see in ways that fit everything public (every card everyone has seen:
/// the starting card until it is played and a three-player deal's face-up
/// card, both fixed to their holder, and the low card that face-up
/// card's taker must hold; the last-card rule's bound; the
/// lowest card dealt in a two-player deal), and the samples are tallied
/// (OpponentRange.tally):
/// the chance the opponent holds at least 1, 2, 3 or 4 of each rank, and
/// each kind of combination they could make, with its likeliest instances.
///
/// Kinds ([bigTwoRangeKinds]), each read under the table's rules:
/// - 'pair', 'triple': two or three of a rank (instances "7-7", "7-7-7");
/// - 'straight': five ranks in a run the rules count, not all one suit
///   ("3-4-5-6-7");
/// - 'flush': five of a suit that aren't a straight flush ("flush:s");
/// - 'fullHouse': a triple and a pair, named by the triple with the lowest
///   pair beside it ("K-K-K-4-4");
/// - 'quads': four of a rank with a fifth card to play it with ("9-9-9-9");
/// - 'straightFlush': a run in one suit ("3s-4s-5s-6s-7s");
/// - 'twos:1', 'twos:2', 'twos:3': at least that many 2s, with which ones
///   ("2s", "2h-2s"): the 2s win tricks, so where they are matters most.
library;

import 'dart:collection';

import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/range.dart';
import '../../../kit/seats.dart';
import '../big_two.dart';
import 'big_two_record.dart';

/// The combination kinds of a Big Two range, in the order the sheet lists
/// them (the plays from low to high, then the 2s).
const bigTwoRangeKinds = [
  'pair',
  'triple',
  'straight',
  'flush',
  'fullHouse',
  'quads',
  'straightFlush',
  'twos:1',
  'twos:2',
  'twos:3',
];

/// The range job's input.
class BigTwoRangeInput {
  const BigTwoRangeInput({
    required this.record,
    required this.viewer,
    required this.seat,
    required this.seed,
    this.samples,
  });

  /// GameRecord.jobJson of the deal up to the position.
  final Map<String, Object?> record;

  /// Whose knowledge the range uses: the player's seat.
  final int viewer;

  /// The opponent whose range it is.
  final int seat;
  final int seed;

  /// How many hidden deals to sample instead of [BigTwoRangeJob.samples]
  /// (examples, checks).
  final int? samples;

  Map<String, Object?> toJson() => {
    'record': record,
    'viewer': viewer,
    'seat': seat,
    'seed': seed,
    'samples': ?samples,
  };

  factory BigTwoRangeInput.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return BigTwoRangeInput(
      record: (map['record']! as Map).cast<String, Object?>(),
      viewer: map['viewer']! as int,
      seat: map['seat']! as int,
      seed: map['seed']! as int,
      samples: map['samples'] as int?,
    );
  }
}

/// `big_two.range`: [BigTwoRangeInput.seat]'s range as the viewer sees it.
class BigTwoRangeJob extends GameJob<BigTwoRangeInput, OpponentRange> {
  const BigTwoRangeJob();

  /// Hidden deals sampled for one range: enough that a chance is within
  /// about 2 points (the sampling error of 2000 is at most 1.1%), and quick
  /// everywhere (a few milliseconds natively).
  static const samples = 2000;

  /// Under a time cap, the fewest samples worth showing.
  static const _minSamples = 200;

  @override
  String get name => '${GameKeys.bigTwo}.range';

  @override
  Object? encodeInput(BigTwoRangeInput input) => input.toJson();
  @override
  BigTwoRangeInput decodeInput(Object? json) => BigTwoRangeInput.fromJson(json);
  @override
  Object? encodeOutput(OpponentRange output) => output.toJson();
  @override
  OpponentRange decodeOutput(Object? json) => OpponentRange.fromJson(json);

  @override
  OpponentRange run(BigTwoRangeInput input, JobContext context) {
    if (input.seat == input.viewer) throw ArgumentError('A range is of an opponent, not of seat ${input.viewer}');
    final view = BigTwoRecord.replayJson(input.record).viewFor(input.viewer);
    return bigTwoRange(view, input.seat, seed: input.seed, samples: input.samples ?? samples, context: context);
  }

  @override
  List<BigTwoRangeInput> examples() => [
    for (final (i, (record, seat)) in _spots.take(3).indexed)
      BigTwoRangeInput(record: record.jobJson(), viewer: 0, seat: seat, seed: 5 + i, samples: 200),
  ];

  @override
  List<BigTwoRangeInput> checkInputs() => [
    for (final (i, (record, seat)) in _spots.indexed)
      BigTwoRangeInput(record: record.jobJson(), viewer: 0, seat: seat, seed: 300 + i, samples: 400 + 100 * (i % 4)),
  ];
}

/// [seat]'s range as [view]'s seat sees it: [samples] hidden deals from the
/// engine's sampler, tallied. Under [context]'s time cap it stops early (but
/// not before a couple of hundred samples).
OpponentRange bigTwoRange(BigTwoView view, int seat, {required int seed, int samples = 2000, JobContext? context}) {
  final rules = view.rules;
  final sampler = DealSampler(view);
  final rng = GameRandom(seed);
  final hands = <_SampledHand>[];
  for (var i = 0; i < samples; i++) {
    // The cap is looked at every 50 samples, never on the first few hundred.
    if (i >= BigTwoRangeJob._minSamples && i % 50 == 0 && context?.remaining == Duration.zero) break;
    hands.add(_SampledHand([for (final code in sampler.sample(rng)[seat]) rules.cardOf(code)]));
  }
  return OpponentRange.tally(
    seat: seat,
    hands: hands,
    rankOrder: [for (final r in Ranks.chars.split('')) (r, 4)],
    kinds: bigTwoRangeKinds,
    combosOf: (hand) => bigTwoCombos(rules, (hand as _SampledHand).cards),
  );
}

/// One sampled hand, as the tally reads it (the rank of each card: '3' ..
/// 'T' .. '2') while keeping the cards themselves for the combinations
/// that need suits (flushes, straight flushes, which 2s).
class _SampledHand extends ListBase<String> {
  _SampledHand(this.cards) : _ranks = [for (final c in cards) Ranks.chars[c.rank]];

  final List<Card> cards;
  final List<String> _ranks;

  @override
  int get length => _ranks.length;
  @override
  set length(int length) => throw UnsupportedError('A sampled hand is fixed');
  @override
  String operator [](int index) => _ranks[index];
  @override
  void operator []=(int index, String value) => throw UnsupportedError('A sampled hand is fixed');
}

/// Every combination [cards] can make under [rules], by kind (see the
/// library comment for the kinds and how instances are named).
Map<String, Set<String>> bigTwoCombos(BigTwoRules rules, List<Card> cards) {
  final byRank = List.generate(13, (_) => <Card>[]);
  final bySuit = {for (final s in Suit.values) s: <Card>[]};
  for (final c in cards) {
    byRank[c.rank].add(c);
    bySuit[c.suit]!.add(c);
  }
  String r(int rank) => Ranks.chars[rank];
  String same(int rank, int n) => List.filled(n, r(rank)).join('-');
  final five = cards.length >= 5;
  final combos = <String, Set<String>>{for (final kind in bigTwoRangeKinds) kind: {}};
  for (var rank = 0; rank < 13; rank++) {
    final n = byRank[rank].length;
    if (n >= 2) combos['pair']!.add(same(rank, 2));
    if (n >= 3) combos['triple']!.add(same(rank, 3));
    if (n == 4 && five) combos['quads']!.add(same(rank, 4));
  }
  if (five) {
    // Full houses: each triple with the lowest other pair.
    for (var t = 0; t < 13; t++) {
      if (byRank[t].length < 3) continue;
      final p = [
        for (var q = 0; q < 13; q++)
          if (q != t && byRank[q].length >= 2) q,
      ].firstOrNull;
      if (p != null) combos['fullHouse']!.add('${same(t, 3)}-${same(p, 2)}');
    }
    for (final start in rules.straights.order) {
      final run = [for (var k = 0; k < 5; k++) (start + k) % 13];
      if (run.any((rank) => byRank[rank].isEmpty)) continue;
      final runText = run.map(r).join('-');
      // Plain unless the run can only be made of one suit: one card of each
      // rank, all of one suit.
      final suits = {
        for (final rank in run)
          for (final c in byRank[rank]) c.suit,
      };
      final forced = run.every((rank) => byRank[rank].length == 1) && suits.length == 1;
      if (!forced) combos['straight']!.add(runText);
      for (final suit in Suit.values) {
        if (run.every((rank) => byRank[rank].any((c) => c.suit == suit))) {
          combos['straightFlush']!.add(run.map((rank) => '${r(rank)}${suit.letter}').join('-'));
        }
      }
    }
    for (final MapEntry(key: suit, value: held) in bySuit.entries) {
      if (held.length < 5) continue;
      // Exactly five that run in order make only a straight flush.
      final bits = held.fold(0, (b, c) => b | 1 << c.rank);
      if (held.length > 5 || rules.straightPosition(bits) < 0) combos['flush']!.add('flush:${suit.letter}');
    }
  }
  // Which 2s, lowest suit first as the rules order them ("2d-2s").
  final twos = [...byRank[Ranks.two]]..sort((a, b) => rules.suitStrength(a.suit).compareTo(rules.suitStrength(b.suit)));
  for (var n = 1; n <= 3; n++) {
    for (final pick in _choose(twos, n)) {
      combos['twos:$n']!.add(pick.map((c) => c.short).join('-'));
    }
  }
  return combos;
}

/// Every way to choose [n] of [items], in order.
Iterable<List<T>> _choose<T>(List<T> items, int n, [int from = 0]) sync* {
  if (n == 0) {
    yield const [];
    return;
  }
  for (var i = from; i <= items.length - n; i++) {
    for (final rest in _choose(items, n - 1, i + 1)) {
      yield [items[i], ...rest];
    }
  }
}

/// Positions to test the job with: deals of every preset and table size
/// played on a way by Easy bots, each with an opponent of the player.
final List<(GameRecord, int)> _spots = [
  for (var i = 0; i < 24; i++)
    _spot(
      BigTwoRules.preset(BigTwoPreset.values[i % 4], players: const [4, 3, 2][i % 3]),
      3000 + i,
      const [0, 5, 12, 20][i % 4],
      opponent: 1 + i % (const [4, 3, 2][i % 3] - 1),
    ),
];

(GameRecord, int) _spot(BigTwoRules rules, int seed, int moves, {required int opponent}) {
  var record = BigTwoRecord.deal(
    rules: rules,
    seed: seed,
    seats: [
      const SeatSpec(human: true, name: 'Player'),
      for (var i = 1; i < rules.players; i++) SeatSpec(human: false, level: KitLevel.easy, name: kitBotNames[i - 1]),
    ],
  );
  final state = BigTwoRecord.replay(record);
  for (var i = 0; i < moves; i++) {
    final seat = state.toMove;
    final play = BigTwoBot(BotLevel.easy, seed: mixSeed(seed, i, seat)).chooseMove(state.viewFor(seat));
    final next = state.copy()..applyTrusted(play);
    if (next.isOver) break;
    state.apply(play);
    record = record.withMove(bigTwoMoveText(seat, play));
  }
  return (record, opponent);
}
