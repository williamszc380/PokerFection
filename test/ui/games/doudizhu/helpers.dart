/// Shared helpers for Fight the Landlord's UI tests: a controller that
/// plays on the same thread, and ways to drive the player's turns.
library;

import 'dart:math';

import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/match.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

/// A controller with jobs on this thread, no pauses (unless [speed] says
/// otherwise, or [speedNow], read at each move, when a test changes it as
/// it goes) and a fixed seed. The match is the setup's standard (to 30)
/// unless [match] says otherwise.
LandlordController testController({
  bool training = true,
  DdzRules rules = DdzRules.standard,
  List<KitLevel> levels = const [KitLevel.easy, KitLevel.easy],
  int seed = 1,
  Jobs? jobs,
  LastGames? lastGames,
  Map<String, Object?> extra = const {},
  MatchTarget match = landlordStandardMatch,
  PlaybackSpeed speed = PlaybackSpeed.instant,
  PlaybackSpeed Function()? speedNow,
}) {
  GameSounds.output = (_) {};
  return LandlordController(
    jobs: jobs ?? Jobs.inline(),
    lastGames: lastGames ?? LastGames(),
    choice: LandlordChoice(rules: rules, levels: levels, training: training, match: match, extra: extra),
    speed: speedNow ?? () => speed,
    random: Random(seed),
  );
}

/// Lets jobs, bot turns and forced moves run until [done] (or
/// gives up after many rounds, so a broken game fails instead of hanging).
Future<void> runUntil(bool Function() done, {int rounds = 4000}) async {
  for (var i = 0; i < rounds && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Waits for the player's next decision or the end of the deal (a turn
/// with one legal move plays itself, see LandlordController.forcedMove).
Future<void> untilYourTurn(LandlordController c) => runUntil(
  () =>
      c.isOver ||
      (c.seatToAct == LandlordController.you &&
          c.forcedMove(LandlordController.you) == null &&
          (!c.training || !c.coachThinking)),
);

/// What an Easy bot would play in the player's seat, as a record move.
String easyMove(LandlordController c, {int seed = 0}) {
  final game = c.game;
  return ddzMoveTextFor(game, DdzBot(DdzLevel.easy, random: Random(seed)).chooseMove(game.viewFor(game.toAct)));
}

/// Plays the deal to its end, the player moving like an Easy bot (or by
/// [pick] when given). Returns how many moves the player made.
Future<int> playDeal(LandlordController c, {String Function(LandlordController c)? pick}) async {
  var mine = 0;
  for (var guard = 0; guard < 200; guard++) {
    await untilYourTurn(c);
    if (c.isOver) return mine;
    c.humanMove((pick ?? easyMove)(c));
    mine++;
  }
  throw StateError('the deal never ended');
}
