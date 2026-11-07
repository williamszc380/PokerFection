import '../../../games/gomoku/app/gomoku_analysis.dart';
import '../../../games/gomoku/app/gomoku_grading.dart';
import '../../../games/gomoku/app/gomoku_jobs.dart';
import '../../../games/gomoku/app/gomoku_record.dart';
import '../../../games/gomoku/gomoku.dart';
import '../../../kit/coach_answer.dart';
import '../../../kit/game_keys.dart';
import '../../../kit/game_record.dart';
import '../../../kit/grading.dart';
import '../../../kit/jobs/jobs_core.dart';
import '../../../kit/seats.dart';
import '../../kit/game_sounds.dart';
import '../../kit/turn_controller.dart';

/// Runs a game of Gomoku against a bot: the engine's game, the bot's and
/// the coach's jobs, and the engine's grading. Seats are colours (0 Black,
/// 1 White); the player's comes from the setup. One game is one record:
/// New game starts another with the same choices.
class GomokuController extends TurnController {
  GomokuController({
    required this.options,
    required super.jobs,
    required super.lastGames,
    super.speed,
    super.random,
    this.toggles = const {},
    this.opening = const [],
  }) : super(gameKey: GameKeys.gomoku, training: options.training);

  /// The setup's choices.
  final GomokuOptions options;

  /// The screen's toggles from the last game ('coach'), for the first game
  /// of this screen; after that the kit carries them from game to game.
  final Map<String, Object?> toggles;

  /// Moves already on the board when a game starts (tests use it to reach a
  /// position quickly).
  final List<String> opening;

  GomokuGame _game = GomokuGame();

  /// The game as the engine sees it now.
  GomokuGame get game => _game;

  /// The player's colour (Black if both seats are bots, as in some tests).
  Stone get playerColor => started && !record.seats[0].human && record.seats[1].human ? Stone.white : Stone.black;

  /// The coach's analysis behind [coach], once it has come.
  GomokuAnalysis? get analysis => coach?.detail as GomokuAnalysis?;

  @override
  int? get seatToAct => !started || _game.isOver ? null : GomokuRecord.seatOf(_game.toMove);

  @override
  bool isHuman(int seat) => started && record.seats[seat].human;

  @override
  bool get isOver => started && _game.isOver;

  @override
  List<int> get winners => [if (_game.result?.winner case final winner?) GomokuRecord.seatOf(winner)];

  @override
  Map<String, Object?> get result => {
    'winners': winners,
    if (_game.result case final result? when result.line.isNotEmpty) 'line': [for (final m in result.line) m.notation],
  };

  @override
  GameRecord deal({GameRecord? previous}) {
    final fresh = GomokuRecord.start(options, seed: nextGameSeed(), botName: kitBotNames.first, moves: opening);
    _game = GomokuRecord.replay(fresh);
    // The first game of the screen takes the last game's toggles; later
    // ones keep this screen's (the kit carries the old extra over).
    return started ? fresh : fresh.copyWith(extra: {...fresh.extra, ...toggles});
  }

  @override
  void applyMove(int seat, String move) {
    if (seatToAct != seat) throw StateError('Not seat $seat\'s turn');
    _game = _game.play(GomokuMove.parse(move));
    playSound(SoundEffect.stone);
  }

  /// A pass, when it is legal (Renju, when Black has no point left): it
  /// is then always among the coach's rows, like every game's Pass.
  @override
  List<String> listedMoves(int seat) => gomokuListedMoves(_game);

  @override
  JobRequest botRequest(int seat, int seed) => JobRequest(
    const GomokuBotJob(),
    GomokuBotInput(record: record.jobJson(), seat: seat, level: record.seats[seat].level ?? options.level, seed: seed),
    JobKind.bot,
  );

  @override
  String toBotMove(Object? output) => (output! as GomokuBotOutput).move;

  @override
  String fallbackBotMove(int seat) => GomokuBot(
    BotLevel.easy,
    seed: mixSeed(record.seed, record.moves.length, seat),
  ).chooseMove(_game.viewFor(GomokuRecord.colorOf(seat))).notation;

  @override
  JobRequest coachRequest(GameRecord position, int seat, {String? include, bool deep = false, required int seed}) =>
      JobRequest(
        const GomokuCoachJob(),
        GomokuCoachInput(
          record: position.jobJson(),
          seat: seat,
          include: include,
          depth: deep ? GomokuDepth.deep : GomokuDepth.normal,
        ),
        JobKind.coach,
      );

  @override
  CoachAnswer toAnswer(Object? output) => gomokuAnswer(output! as GomokuAnalysis);

  @override
  GradeScale get scale => gomokuScale;

  /// The engine's own grading (proofs first), from the analysis the answer
  /// carries; null when the move wasn't analysed, so the kit asks again
  /// with it included.
  @override
  MoveMark? grade(CoachAnswer answer, String played) {
    final analysis = answer.detail;
    return analysis is GomokuAnalysis ? gomokuMark(analysis, played) : null;
  }
}
