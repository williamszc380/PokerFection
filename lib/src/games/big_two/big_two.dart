/// Big Two (Big 2, Choh Dai Di, Da Lao Er, Pusoy Dos): rules, bots and the
/// coach, in pure Dart with no Flutter, so the app can run it in its worker
/// pool on every platform, the web included.
///
/// Start with [BigTwoRules] (or a preset), deal with [BigTwoState.deal],
/// give each player [BigTwoState.viewFor], and ask a [BigTwoBot] or the
/// [BigTwoCoach] for moves.
library;

export 'bot.dart';
export 'cards.dart';
export 'coach.dart';
export 'counter.dart';
export 'opening.dart';
export 'plan.dart';
export 'plays.dart' show Play, PlayKind, BigTwoPlays;
export 'policy.dart' show HeuristicPolicy;
export 'random.dart' show GameRandom;
export 'rules.dart';
export 'sampler.dart';
export 'solver.dart';
export 'sources.dart';
export 'state.dart';
