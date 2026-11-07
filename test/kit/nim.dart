/// A tiny game to test the kit with: Nim. A pile of stones; each turn takes
/// 1 to [NimController.take] of them; whoever takes the last stone wins.
/// The player sits at seat 0 and moves first, a bot at seat 1. Moves are
/// the number taken ("2").
///
/// Its coach rates each take by how close it leaves the pile to a multiple
/// of take + 1 (a sure win for the mover); it can be told to rate only the
/// top few moves, and to honour (or ignore) `include`, to test grading.
library;

import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/grading.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/kit/turn_controller.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import 'nim_jobs.dart';

export 'nim_jobs.dart';

class NimController extends TurnController {
  NimController({
    required super.jobs,
    LastGames? lastGames,
    super.training = true,
    this.pile = 7,
    this.take = 3,
    this.top,
    this.honorsInclude = true,
    this.rounds = false,
    PlaybackSpeed speed = PlaybackSpeed.instant,
    this.extraAtStart = const {},
  }) : super(gameKey: 'nim', lastGames: lastGames ?? LastGames(), speed: () => speed);

  final int pile;
  final int take;

  /// The coach rates only this many moves (null: all).
  final int? top;

  /// Whether the coach rates an `include`d move it would leave out.
  final bool honorsInclude;

  /// Deals follow deals (as in the card games).
  final bool rounds;

  /// What the setup puts in a new game's extra.
  final Json extraAtStart;

  /// Makes the next bot jobs fail (the Easy bot plays: always takes 1).
  bool botFails = false;

  /// Holds the game after each move, as an animation would (the test then
  /// clears [animating] and calls resume).
  bool animateMoves = false;
  bool animating = false;

  int left = 0;
  int deals = 0;
  int? lastMover;
  final sounds = <SoundEffect>[];

  @override
  int? get seatToAct => left == 0 || animating ? null : record.moves.length % 2;

  @override
  bool isHuman(int seat) => seat == 0;

  @override
  bool get isOver => started && left == 0;

  @override
  List<int> get winners => isOver ? [lastMover!] : const [];

  @override
  bool get playsRounds => rounds;

  @override
  GameRecord deal({GameRecord? previous}) {
    deals++;
    left = pile;
    lastMover = null;
    return GameRecord(
      game: 'nim',
      version: 1,
      seed: nextGameSeed(),
      rules: {'pile': pile, 'take': take},
      seats: const [SeatSpec(human: true, name: 'You'), SeatSpec(human: false, level: KitLevel.easy, name: 'Ana')],
      extra: {'mode': training ? 'training' : 'free', ...extraAtStart},
    );
  }

  @override
  void applyMove(int seat, String move) {
    final k = int.tryParse(move) ?? 0;
    if (k < 1 || k > take || k > left) throw ArgumentError('illegal take $move');
    left -= k;
    lastMover = seat;
    animating = animateMoves;
    playSound(SoundEffect.stone);
  }

  @override
  void playSound(SoundEffect effect) => sounds.add(effect);

  @override
  JobRequest botRequest(int seat, int seed) =>
      JobRequest(const NimBotJob(), {'record': record.jobJson(), 'seat': seat, 'fail': botFails}, JobKind.bot);

  @override
  String fallbackBotMove(int seat) => '1';

  @override
  JobRequest coachRequest(GameRecord position, int seat, {String? include, bool deep = false, required int seed}) =>
      JobRequest(
        const NimCoachJob(),
        {
          'record': position.jobJson(),
          'seat': seat,
          'top': ?top,
          if (honorsInclude) 'include': ?include,
          'deep': deep,
        },
        JobKind.coach,
      );

  @override
  CoachAnswer toAnswer(Object? output) => CoachAnswer(
        unit: ValueUnit.winChance,
        lines: [
          for (final line in (output! as List).cast<Json>())
            CoachLine(
              move: line['move']! as String,
              value: (line['value']! as num).toDouble(),
              // A second number in another unit, as the card games have.
              points: ((line['value']! as num) - 0.5) * 6,
              reasons: [for (final r in line['reasons']! as List) r as String],
            ),
        ],
      );

  @override
  GradeScale get scale => const GradeScale(unit: ValueUnit.winChance, cutoffs: [0.01, 0.05, 0.1, 0.2], scoreScale: 0.1);
}
