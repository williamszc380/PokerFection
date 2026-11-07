/// Every game's background jobs, by name. The web worker and the apps'
/// isolates run jobs from this map; each game fills its own list in
/// `lib/src/games/<key>/app/<key>_jobs.dart`, so this file never changes.
library;

import '../../games/big_two/app/big_two_jobs.dart';
import '../../games/blackjack/app/blackjack_jobs.dart';
import '../../games/doudizhu/app/doudizhu_jobs.dart';
import '../../games/gomoku/app/gomoku_jobs.dart';
import 'jobs_core.dart';

/// Throws when it is first read if two jobs share a name.
final Map<String, GameJob<Object?, Object?>> kitJobs = jobsByName([
  ...gomokuJobs,
  ...bigTwoJobs,
  ...doudizhuJobs,
  ...blackjackJobs,
]);
