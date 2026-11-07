/// What a game other than Hold'em gives the app to be played and watched
/// online (registered in online_game_uis.dart, one per game, from
/// `lib/src/ui/games/<key>/online/<key>_online_ui.dart`): its server side
/// ([OnlineGameUi.online]), the jobs its bots and the spectators' coach
/// run on this device, and the widgets of its table, its seated player's
/// hand and buttons, and its rules. The room's game screen
/// (online_game_screen.dart) lays them out; a [RunnerClient] runs the
/// game on the device.
///
/// Every seat here is a hand seat (the round's own numbering, see
/// game_envelope.dart): the views, the moves and the jobs are the game's,
/// as its runner made them.
library;

import 'package:flutter/widgets.dart';

import '../../kit/coach_answer.dart';
import '../../kit/jobs/jobs.dart';
import '../../kit/jobs/jobs_core.dart';
import '../../online/games/game_runner.dart';
import '../kit/l10n/game_strings.dart';
import 'runner_client.dart';

/// A job a game's online part runs on this device: its kit job (from the
/// game's own `<key>Jobs` list, so it runs in a worker) and its input.
class OnlineJob<I, O> {
  const OnlineJob(this.job, this.input);

  final GameJob<I, O> job;
  final I input;

  /// Starts it on [jobs]: the bot's move on the bot lane, the coach's on
  /// the coach lane.
  JobHandle<O> start(Jobs jobs, {required JobLane lane, required JobKind kind}) =>
      jobs.start<I, O>(job, input, lane: lane, kind: kind);
}

/// One game's online part on the app's side. A game agent extends it in
/// its own `<key>_online_ui.dart`.
abstract class OnlineGameUi {
  const OnlineGameUi();

  /// The game's server side (its runner file's OnlineGame): its key and
  /// version, rules, seats and bot levels.
  OnlineGame get online;

  /// The game's GameKeys key, and the version of its views and moves (a
  /// room playing another version shows "Update the app to watch").
  String get key => online.key;
  int get gv => online.gv;

  /// The game's own strings (the coach's pick label, its glossary and
  /// rules).
  GameStrings strings(BuildContext context);

  /// Hand seat [seat]'s view rebuilt from the spectators' view (the game's
  /// view codec); null when its hidden cards aren't in it (a bot while the
  /// host's switch is off). The coach works only from this.
  Map<String, Object?>? seatViewFrom(Map<String, Object?> spectatorView, int seat);

  /// The host's device plays a bot at [level] ("easy", "medium", "hard")
  /// seeing [seatView] (the bot's own view): the game's `<key>.onlineBot`
  /// job, with [seed] (from the round, turn and seat).
  OnlineJob<Object?, Object?> botJob(Map<String, Object?> seatView, String level, {required int seed});

  /// The move in the bot job's output.
  String botMove(Object? output);

  /// A legal move for the seat seeing [seatView], cheap and inline (the
  /// Easy rule): when the bot job fails or runs out of time. [seed] is the
  /// one [botJob] would have had (salted with the host's secret), so a
  /// fallback that draws at random is no easier for the other players to
  /// work out than the bot's own move.
  String fallbackMove(Map<String, Object?> seatView, {required int seed});

  /// The spectators' coach for the seat seeing [seatView] (rebuilt by
  /// [seatViewFrom]): the game's `<key>.onlineCoach` job, with [seed].
  OnlineJob<Object?, Object?> coachJob(Map<String, Object?> seatView, {required int seed});

  /// The coach job's output as the kit's answer (CoachList shows it).
  CoachAnswer toAnswer(Object? output);

  /// The table: the board or felt, the seats (names, scores, whose turn)
  /// and every card [c]'s view holds, face up only when the view has it.
  /// Fits any size from 232×276 (a sideways phone) up.
  Widget table(BuildContext context, RunnerClient c);

  /// The seated player's own hand under the table (the kit's hand fan);
  /// null for none (a spectator, or a game without one: Gomoku).
  Widget? bottom(BuildContext context, RunnerClient c);

  /// The seated player's buttons in the Game tab (greyed out when it isn't
  /// their turn): each plays with [RunnerClient.move]. Fits 256–420 wide.
  Widget actions(BuildContext context, RunnerClient c);

  /// The host's rules in the room's Rules part (the game's own setup rows,
  /// greyed out unless [enabled]): [onChange] with the new rules. Fits
  /// 256–420 wide.
  Widget rulesForm(
    BuildContext context,
    Map<String, Object?> rules, {
    required bool enabled,
    required ValueChanged<Map<String, Object?>> onChange,
  });

  /// [move] in words, for the coach's rows and the last move ("Pair of 7s").
  String moveLabel(BuildContext context, String move);

  /// The round's result in a few words (who won, the scores): the Game
  /// tab's status line once [c]'s round is over.
  String resultText(BuildContext context, RunnerClient c);

  /// The Game tab's status line in place of [resultText] while the table
  /// still plays [c]'s finished round out (the dealer's cards in the air,
  /// say), so the tab doesn't tell the result before the table shows it;
  /// null (the default) once there is nothing left to play.
  String? heldResultText(BuildContext context, RunnerClient c) => null;

  /// The Game tab's status line in place of whose turn it is while the
  /// table still plays the opening of [c]'s deal (who goes first: Big Two,
  /// Fight the Landlord), so the tab neither names the starter before the
  /// felt does nor says "Your turn" over greyed-out buttons: what the felt
  /// says so far ("Who starts?", then "Kai starts: 3♦"), '' for nothing
  /// yet; null (the default) once the opening is over.
  String? heldTurnText(BuildContext context, RunnerClient c) => null;

  /// What changes when [heldResultText] or [heldTurnText] does (the
  /// table's playback), for the Game tab to listen to; null (the default)
  /// when nothing is held. [context] gives the Animations setting, for a
  /// game whose playback starts here.
  Listenable? tablePlayback(BuildContext context, RunnerClient c) => null;
}
