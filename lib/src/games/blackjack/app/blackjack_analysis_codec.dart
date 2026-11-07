/// The coach's analysis as plain JSON, the way the coach job sends it back,
/// and its reasons as short codes the strings turn into words.
///
/// Timing is left out (the same input always gives the same output), and
/// the reasons' fractional numbers are written with four decimals, so the
/// app, the browser's JavaScript and its WebAssembly all write the same text.
library;

import '../blackjack.dart';

/// [analysis] as JSON, without its time.
Map<String, Object?> analysisToJson(BlackjackAnalysis analysis) => {
  'phase': analysis.phase.name,
  'actions': [
    for (final a in analysis.actions)
      {
        'action': a.action.name,
        'evFresh': a.evFresh,
        'evSeen': a.evSeen,
        'lostFresh': a.lostFresh,
        'lostSeen': a.lostSeen,
        'reasons': [for (final r in a.reasons) reasonCode(r)],
      },
  ],
  'bestFresh': analysis.bestFresh.name,
  'bestSeen': analysis.bestSeen.name,
  'chart': ?analysis.chartAction?.name,
  'reasons': [for (final r in analysis.reasons) reasonCode(r)],
  'running': analysis.count.running,
  'unseen': analysis.count.unseenCards,
};

/// The analysis written by [analysisToJson] (its time reads 0). Throws if
/// [json] isn't one.
BlackjackAnalysis analysisFromJson(Object? json) {
  final map = json! as Map<String, Object?>;
  BlackjackAction action(Object? name) => BlackjackAction.values.byName(name! as String);
  double number(Object? v) => (v! as num).toDouble();
  List<CoachReason> reasons(Object? list) => [for (final code in list! as List) parseReasonCode(code! as String)];
  return BlackjackAnalysis(
    phase: RoundPhase.values.byName(map['phase']! as String),
    actions: [
      for (final a in (map['actions']! as List).cast<Map<String, Object?>>())
        ActionAnalysis(
          action: action(a['action']),
          evFresh: number(a['evFresh']),
          evSeen: number(a['evSeen']),
          lostFresh: number(a['lostFresh']),
          lostSeen: number(a['lostSeen']),
          reasons: reasons(a['reasons']),
        ),
    ],
    bestFresh: action(map['bestFresh']),
    bestSeen: action(map['bestSeen']),
    chartAction: map['chart'] == null ? null : action(map['chart']),
    reasons: reasons(map['reasons']),
    count: HiLoCount(map['running']! as int, map['unseen']! as int),
    elapsedMicros: 0,
  );
}

/// A reason as one short code: its kind, then its numbers, `|` between
/// them, empty where a number is absent:
/// `kind|total|soft|upcard|pairRank|trueCount|action|basicAction|chance`,
/// for example `dealerBustsOften|16|0|5|-1||||` or
/// `bustRisk|16|0|9|-1||||0.6181`. The coach list keeps reasons as
/// these codes; the strings turn one into a few words.
String reasonCode(CoachReason r) => [
  r.kind.name,
  r.total,
  r.soft ? 1 : 0,
  r.upcard,
  r.pairRank,
  r.trueCount?.toStringAsFixed(4) ?? '',
  r.action?.name ?? '',
  r.basicAction?.name ?? '',
  r.chance?.toStringAsFixed(4) ?? '',
].join('|');

/// The reason written by [reasonCode]. Throws a [FormatException] on
/// anything else.
CoachReason parseReasonCode(String code) {
  final f = code.split('|');
  if (f.length != 9) throw FormatException('not a reason code: $code');
  BlackjackAction? action(String s) => s.isEmpty ? null : BlackjackAction.values.byName(s);
  double? number(String s) => s.isEmpty ? null : double.parse(s);
  return CoachReason(
    ReasonKind.values.byName(f[0]),
    total: int.parse(f[1]),
    soft: f[2] == '1',
    upcard: int.parse(f[3]),
    pairRank: int.parse(f[4]),
    trueCount: number(f[5]),
    action: action(f[6]),
    basicAction: action(f[7]),
    chance: number(f[8]),
  );
}

/// [parseReasonCode], or null for a code that isn't one.
CoachReason? tryParseReasonCode(String code) {
  try {
    return parseReasonCode(code);
  } on Object {
    return null;
  }
}

/// What the coach job sends back: the analysis, the hand it is for (so its
/// actions can be written as moves), and whether the insurance on offer is
/// even money (the app labels the button so).
class BlackjackCoachResult {
  const BlackjackCoachResult({required this.hand, required this.evenMoney, required this.analysis});

  /// The player's hand number the decision is for.
  final int hand;

  /// The insurance on offer is "even money" (a blackjack at a 3:2 table).
  final bool evenMoney;
  final BlackjackAnalysis analysis;

  Map<String, Object?> toJson() => {'hand': hand, 'evenMoney': evenMoney, 'analysis': analysisToJson(analysis)};

  /// The result written by [toJson]; throws if [json] isn't one.
  factory BlackjackCoachResult.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return BlackjackCoachResult(
      hand: map['hand']! as int,
      evenMoney: map['evenMoney']! as bool,
      analysis: analysisFromJson(map['analysis']),
    );
  }
}
