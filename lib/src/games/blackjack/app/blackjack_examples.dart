/// Ready-made inputs for blackjack's jobs: a few rule sets with their
/// strategy charts written out, and decisions dealt from them. The jobs'
/// `examples()` and `checkInputs()` use them, so making an input costs
/// nothing: building a chart takes a second, far more than an example may.
/// A test checks that each chart here is the one the engine builds.
library;

import '../../../kit/game_record.dart';
import '../blackjack.dart';
import 'blackjack_jobs.dart';
import 'blackjack_record.dart';

/// The example rule sets: the default game, late surrender (Vegas Strip),
/// no hole card (European), a single deck (where seen cards matter most),
/// and early surrender.
List<BlackjackRules> get exampleRules => [for (final e in _examples) e.$1];

/// The chart for each of [exampleRules], in the same order.
List<BasicStrategyChart> get exampleCharts => [
  for (final (rules, :edge, :hard, :soft, :pairs) in _examples)
    BasicStrategyChart.fromJson({'rules': rules.toJson(), 'edge': edge, 'hard': hard, 'soft': soft, 'pairs': pairs}),
];

final _examples = <(BlackjackRules, {double edge, List<String> hard, List<String> soft, List<String> pairs})>[
  (
    BlackjackRules.preset(BlackjackPreset.standard),
    edge: 0.004025672671951102,
    hard: [
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHDDDDHHHH',
      'HDDDDDDDDH',
      'HDDDDDDDDD',
      'HHHSSSHHHH',
      'HSSSSSHHHH',
      'HSSSSSHHHH',
      'HSSSSSHHHH',
      'HSSSSSHHHH',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
    ],
    soft: [
      'HHHHHDHHHH',
      'HHHHDDHHHH',
      'HHHHDDHHHH',
      'HHHDDDHHHH',
      'HHHDDDHHHH',
      'HHDDDDHHHH',
      'HSddddSSHH',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
    ],
    pairs: [
      'PPPPPPPPPP',
      'HPPPPPPHHH',
      'HPPPPPPHHH',
      'HHHHPPHHHH',
      'HDDDDDDDDH',
      'HPPPPPHHHH',
      'HPPPPPPHHH',
      'PPPPPPPPPP',
      'SPPPPPSPPS',
      'SSSSSSSSSS',
    ],
  ),
  (
    BlackjackRules.preset(BlackjackPreset.vegasStrip),
    edge: 0.002611887950346092,
    hard: [
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHDDDDHHHH',
      'HDDDDDDDDH',
      'HDDDDDDDDD',
      'HHHSSSHHHH',
      'HSSSSSHHHH',
      'HSSSSSHHHH',
      'HSSSSSHHHR',
      'RSSSSSHHRR',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
    ],
    soft: [
      'HHHHHDHHHH',
      'HHHHDDHHHH',
      'HHHHDDHHHH',
      'HHHDDDHHHH',
      'HHHDDDHHHH',
      'HHDDDDHHHH',
      'HSddddSSHH',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
    ],
    pairs: [
      'PPPPPPPPPP',
      'HPPPPPPHHH',
      'HPPPPPPHHH',
      'HHHHPPHHHH',
      'HDDDDDDDDH',
      'HPPPPPHHHH',
      'HPPPPPPHHH',
      'PPPPPPPPPP',
      'SPPPPPSPPS',
      'SSSSSSSSSS',
    ],
  ),
  (
    BlackjackRules.preset(BlackjackPreset.european),
    edge: 0.006608753897911018,
    hard: [
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHDDDDHHHH',
      'HDDDDDDDDH',
      'HDDDDDDDDH',
      'HHHSSSHHHH',
      'HSSSSSHHHH',
      'HSSSSSHHHH',
      'HSSSSSHHHH',
      'HSSSSSHHHH',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
    ],
    soft: [
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HSSSSSSSHH',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
    ],
    pairs: [
      'HPPPPPPPPP',
      'HPPPPPPHHH',
      'HPPPPPPHHH',
      'HHHHPPHHHH',
      'HDDDDDDDDH',
      'HPPPPPHHHH',
      'HPPPPPPHHH',
      'HPPPPPPPPH',
      'SPPPPPSPPS',
      'SSSSSSSSSS',
    ],
  ),
  (
    BlackjackRules.preset(BlackjackPreset.singleDeck),
    edge: 0.0015117186750886382,
    hard: [
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHHHHHHH',
      'HHHHDDHHHH',
      'HDDDDDHHHH',
      'HDDDDDDDDH',
      'DDDDDDDDDD',
      'HHHSSSHHHH',
      'HSSSSSHHHH',
      'HSSSSSHHHH',
      'HSSSSSHHHH',
      'HSSSSSHHHH',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
    ],
    soft: [
      'HHHHDDHHHH',
      'HHHDDDHHHH',
      'HHHDDDHHHH',
      'HHHDDDHHHH',
      'HHHDDDHHHH',
      'HDDDDDHHHH',
      'HSddddSSHH',
      'SSSSSdSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
    ],
    pairs: [
      'PPPPPPPPPP',
      'HHPPPPPHHH',
      'HHHPPPPHHH',
      'HHHHDDHHHH',
      'HDDDDDDDDH',
      'HPPPPPHHHH',
      'HPPPPPPHHS',
      'PPPPPPPPPP',
      'SPPPPPSPPS',
      'SSSSSSSSSS',
    ],
  ),
  (
    const BlackjackRules(surrender: Surrender.early),
    edge: -0.0022442489545180487,
    hard: [
      'HHHHHHHHHH',
      'RHHHHHHHHH',
      'RHHHHHHHHH',
      'RHHHHHHHHH',
      'HHHHHHHHHH',
      'HHDDDDHHHH',
      'HDDDDDDDDH',
      'HDDDDDDDDD',
      'RHHSSSHHHH',
      'RSSSSSHHHH',
      'RSSSSSHHHR',
      'RSSSSSHHHR',
      'RSSSSSHHRR',
      'rSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
    ],
    soft: [
      'HHHHHDHHHH',
      'HHHHDDHHHH',
      'HHHHDDHHHH',
      'HHHDDDHHHH',
      'HHHDDDHHHH',
      'HHDDDDHHHH',
      'HSddddSSHH',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
      'SSSSSSSSSS',
    ],
    pairs: [
      'PPPPPPPPPP',
      'HPPPPPPHHH',
      'RPPPPPPHHH',
      'HHHHPPHHHH',
      'HDDDDDDDDH',
      'RPPPPPHHHH',
      'RPPPPPPHHR',
      'pPPPPPPPPp',
      'SPPPPPSPPS',
      'SSSSSSSSSS',
    ],
  ),
];

/// Player decisions from the example rule sets, each with its chart: the
/// Hard bot plays a few rounds of each shoe and every decision it meets is
/// a candidate, insurance and early-surrender offers first.
///
/// [quick]: three easy ones (no pair against a 2, 3 or ace, the coach's
/// slowest spots), for the registry test; otherwise about thirty, for the
/// cross-platform check and the cold bench.
List<BlackjackDecisionInput> exampleDecisions({bool quick = false}) {
  final out = <BlackjackDecisionInput>[];
  final charts = exampleCharts;
  final perRules = quick ? 1 : 6;
  final sets = quick ? 3 : charts.length;
  for (var r = 0; r < sets; r++) {
    final chart = charts[r];
    var record = newBlackjackRecord(rules: chart.rules, seed: 101 + r, playerName: 'Player', dealerName: 'Dealer');
    final play = BlackjackPlay(chart.rules, shoeSeed: 101 + r);
    final offers = <GameRecord>[], plays = <GameRecord>[];
    final bot = BlackjackBot(BotLevel.hard, chart: chart);
    while (play.rounds < 12 && !play.shoeOver) {
      if (play.betweenRounds) {
        play.apply(dealMove);
        record = record.withMove(dealMove);
        continue;
      }
      final view = play.view();
      final hand = view.handToPlay!;
      final slow = hand.isPair && const [1, 2, aceIndex].contains(view.dealerUpcard.rank);
      if (view.phase != RoundPhase.playing) {
        offers.add(record);
      } else if (!(quick && slow)) {
        plays.add(record);
      }
      final move = handMove(view.turn!.hand, bot.chooseAction(view));
      play.apply(move);
      record = record.withMove(move);
    }
    final picked = [...offers.take(quick ? 0 : 2), ...plays].take(perRules);
    out.addAll([for (final position in picked) BlackjackDecisionInput(position: position, chart: chart)]);
  }
  return out;
}
