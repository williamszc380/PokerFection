import 'dart:math';

import '../../../kit/jobs/jobs_core.dart';
import '../doudizhu.dart';
import '../online/doudizhu_view_codec.dart';
import 'doudizhu_analysis.dart';
import 'doudizhu_jobs.dart';
import 'doudizhu_record.dart';

/// Fight the Landlord's jobs for a room (registered with the game's own,
/// in doudizhuJobs): a bot the host's device plays, and a spectator's
/// coach. Both start from a seat's view as the room sends it (or as a
/// spectator's device rebuilds it, doudizhu_view_codec.dart), never from a
/// record: online nobody holds the whole deal, so the view is replayed on
/// stand-in cards and the engine's own view of that seat taken from it,
/// which holds exactly what the seat may know.

/// The engine's view of the seat whose turn it is in [seatView] (a room's
/// view of that seat). Throws when it doesn't replay or isn't its turn.
DdzView ddzOnlineJobView(Map<String, Object?> seatView) {
  final wire = DdzWireView.read(seatView);
  final seat = wire.you ?? (throw const FormatException('Not a seat\'s view'));
  final game = wire.replay() ?? (throw const FormatException('The view doesn\'t replay'));
  if ((game.phase != DdzPhase.bidding && game.phase != DdzPhase.playing) || game.toAct != seat) {
    throw StateError('Not seat $seat\'s turn');
  }
  return game.viewFor(seat);
}

/// What the online bot job gets: the bot's view, its level ("easy",
/// "medium", "hard") and the seed of its random choices.
class DdzOnlineBotInput {
  const DdzOnlineBotInput({required this.view, required this.level, required this.seed});

  final Map<String, Object?> view;
  final String level;
  final int seed;
}

/// A bot's move in a room (the host's device plays it): the solo game's
/// bot at that level, on the bot's own view; the move in the room's
/// notation, a play with the lowest suits.
class DdzOnlineBotJob extends GameJob<DdzOnlineBotInput, String> {
  const DdzOnlineBotJob();

  @override
  String get name => 'doudizhu.onlineBot';

  @override
  Object? encodeInput(DdzOnlineBotInput input) => {'view': input.view, 'level': input.level, 'seed': input.seed};

  @override
  DdzOnlineBotInput decodeInput(Object? json) {
    final map = json! as Map<String, Object?>;
    return DdzOnlineBotInput(
      view: (map['view']! as Map).cast<String, Object?>(),
      level: map['level']! as String,
      seed: (map['seed']! as num).toInt(),
    );
  }

  @override
  Object? encodeOutput(String output) => output;

  @override
  String decodeOutput(Object? json) => json! as String;

  @override
  String run(DdzOnlineBotInput input, JobContext context) {
    final view = ddzOnlineJobView(input.view);
    final level = DdzLevel.values.byName(input.level);
    final bot = DdzBot(
      level,
      random: Random(input.seed),
      budget: ddzBotBudget(level, context.platform, context.remaining),
    );
    return ddzOnlineMoveFor(view, bot.chooseMove(view));
  }

  @override
  List<DdzOnlineBotInput> examples() {
    final views = _sampleViews(1);
    return [
      DdzOnlineBotInput(view: views[views.length ~/ 2], level: 'easy', seed: 3),
      DdzOnlineBotInput(view: views.last, level: 'hard', seed: 3),
    ];
  }

  @override
  List<DdzOnlineBotInput> checkInputs() => [
    for (final seed in const [1, 2, 3])
      for (final (i, view) in _sampleViews(seed).indexed)
        DdzOnlineBotInput(view: view, level: const ['easy', 'medium', 'hard'][i % 3], seed: seed * 13 + i),
  ];
}

/// What the online coach job gets: the acting seat's view and the seed of
/// its deals.
class DdzOnlineCoachInput {
  const DdzOnlineCoachInput({required this.view, required this.seed});

  final Map<String, Object?> view;
  final int seed;
}

/// A spectator's coach in a room: the solo coach's answer for the acting
/// seat, from that seat's view only (rebuilt from what the spectator sees,
/// so a hidden bot is never coached).
class DdzOnlineCoachJob extends GameJob<DdzOnlineCoachInput, DdzAdvice> {
  const DdzOnlineCoachJob();

  @override
  String get name => 'doudizhu.onlineCoach';

  @override
  Object? encodeInput(DdzOnlineCoachInput input) => {'view': input.view, 'seed': input.seed};

  @override
  DdzOnlineCoachInput decodeInput(Object? json) {
    final map = json! as Map<String, Object?>;
    return DdzOnlineCoachInput(
      view: (map['view']! as Map).cast<String, Object?>(),
      seed: (map['seed']! as num).toInt(),
    );
  }

  @override
  Object? encodeOutput(DdzAdvice output) => output.toJson();

  @override
  DdzAdvice decodeOutput(Object? json) => DdzAdvice.fromJson(json);

  @override
  DdzAdvice run(DdzOnlineCoachInput input, JobContext context) {
    final view = ddzOnlineJobView(input.view);
    final analysis = DdzCoach(budget: ddzCoachBudget(context.platform, context.remaining))
        .analyze(view, random: Random(input.seed));
    return DdzAdvice.of(analysis, view);
  }

  /// Numbers rounded as the solo coach's are, so a JavaScript and a native
  /// run compare equal.
  @override
  Object? normalize(Object? outputJson) => const DdzCoachJob().normalize(outputJson);

  @override
  List<DdzOnlineCoachInput> examples() => [DdzOnlineCoachInput(view: _sampleViews(1).last, seed: 7)];

  @override
  List<DdzOnlineCoachInput> checkInputs() => [
    for (final seed in const [1, 2, 3])
      for (final (i, view) in _sampleViews(seed).indexed) DdzOnlineCoachInput(view: view, seed: seed * 31 + i),
  ];
}

/// [move] made by [view]'s seat in the room's notation (a play with the
/// lowest suits of the hand).
String ddzOnlineMoveFor(DdzView view, DdzMove move) =>
    ddzOnlineMoveText(view.seat, move, move is DdzPlay ? ddzCardsFor(view.hand, move.play) : const []);

/// The acting seat's view at a few points of the sample deal of [seed]
/// (ddzSampleGame, three Easy bots): the opening bid, the first lead, the
/// middle and the end (at most 10 cards left in all), as the room sends
/// them.
List<Map<String, Object?>> _sampleViews(int seed) {
  final record = ddzSampleGame(seed);
  final n = record.moves.length;
  final game = ddzReplay(record, upTo: 0);
  final views = <Map<String, Object?>>[];
  var lead = false, late = false;
  for (var i = 0; i < n; i++) {
    final cardsLeft = game.hands.fold<int>(0, (sum, h) => sum + h.length);
    final take =
        i == 0 ||
        (!lead && game.phase == DdzPhase.playing) ||
        i == n ~/ 2 ||
        (!late && game.phase == DdzPhase.playing && cardsLeft <= 10);
    if (game.phase == DdzPhase.playing) lead = true;
    if (game.phase == DdzPhase.playing && cardsLeft <= 10) late = true;
    if (take) views.add(ddzSeatView(game, game.toAct, redeals: 0));
    ddzApply(game, record.moves[i]);
  }
  return views;
}
