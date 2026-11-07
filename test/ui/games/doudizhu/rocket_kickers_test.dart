// "Rocket as kickers" is a setup switch: with it on, both jokers may ride
// along as the kickers of a four-with-two or an airplane. Every place the
// screen reads a move back must then read it under the game's rules, not
// the standard ones, or the coach's rows and the panel break.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_grading.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_jobs.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart' show DecisionGrade;
import 'package:pokerfection/src/kit/coach_answer.dart';
import 'package:pokerfection/src/kit/game_keys.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/grading.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/seats.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_coach_view.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/l10n/doudizhu_strings.dart';
import 'package:pokerfection/src/ui/kit/game_sounds.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'states.dart';

const rules = DdzRules(rocketAsKickers: true);

/// Both jokers as the wings of an airplane: legal only under [rules].
const airplane = '0:xairplaneSolos:333444BR';

/// The player is the landlord holding 333 444 and both jokers, to lead.
GameRecord landlordWithRocket() {
  final game = DdzGame.fromRanks(rules: rules, hands: ['333444BR', '55', '66'], landlord: 0);
  return GameRecord(
    game: GameKeys.doudizhu,
    version: ddzRecordVersion,
    seed: 1,
    rules: rules.toJson(),
    seats: const [
      SeatSpec(human: true, name: 'Player'),
      SeatSpec(human: false, level: KitLevel.easy, name: 'Ana'),
      SeatSpec(human: false, level: KitLevel.easy, name: 'Ben'),
    ],
    deal: ddzDealOf(game),
  );
}

/// The coach's real answer for [landlordWithRocket]: its pick is the
/// airplane (it goes out in one play).
CoachAnswer rocketAnswer() => ddzAnswer(
  const DdzCoachJob().run(
    DdzCoachInput(record: landlordWithRocket().jobJson(), seat: 0, include: airplane, seed: 1),
    JobContext(platform: JobPlatform.test),
  ),
);

/// A controller whose last graded move is [played] (the kit keeps marks
/// in its record; this stands in for a graded deal).
class _Graded extends LandlordController {
  _Graded(this.played)
    : super(
        jobs: Jobs.inline(),
        lastGames: LastGames(),
        choice: const LandlordChoice(rules: rules),
      );

  final String played;

  @override
  List<MoveMark?> get marks => [
    MoveMark(grade: DecisionGrade.good, loss: 0.02, score: 67, played: played, best: played),
  ];
}

/// A Training game under [rules] whose coach answer on screen is [answer]
/// (the deal itself is whatever the seed gives; only the panel matters).
class _Coached extends LandlordController {
  _Coached(this.answer)
    : super(
        jobs: Jobs.inline(),
        lastGames: LastGames(),
        choice: const LandlordChoice(rules: rules, levels: [KitLevel.easy, KitLevel.easy]),
        // No deal's first step to wait for: newGame is awaited on fake time.
        speed: () => PlaybackSpeed.instant,
      );

  final CoachAnswer answer;

  @override
  CoachAnswer? get coach => answer;
}

void main() {
  setUpAll(() async {
    GameSounds.output = (_) {};
    await loadShotFonts();
  });

  test('the coach rates the airplane with both jokers as wings, and its pick is that airplane', () {
    final answer = rocketAnswer();
    expect(answer.lineFor(airplane), isNotNull, reason: 'a legal move under these rules');
    expect(answer.pick, airplane);
    for (final line in answer.lines) {
      expect(() => ddzParseMove(line.move, rules), returnsNormally, reason: line.move);
    }
  });

  test('its coach row reads as a play, not as notation', () {
    final c = _Graded(airplane);
    final look = landlordLook(c, LandlordStrings.forLanguage(AppLanguage.english));
    expect(look.moveText(airplane), 'Airplane + singles 333444 + Little Joker Big Joker');
    c.dispose();
  });

  test('the grade of a rocket-kicker play says its own unit (win chance), whatever was graded before', () {
    final mark = ddzMark(rocketAnswer(), airplane)!;
    expect(mark.unit, ValueUnit.winChance);
    // The controller has one scale; the panel reads each mark's unit.
    final c = _Graded(airplane);
    expect(c.scale, ddzPlayScale);
    c.dispose();
  });

  testWidgets('the screen builds with that airplane as the coach\'s pick, its row in words', (tester) async {
    final c = _Coached(rocketAnswer());
    await c.newGame();
    c.coachVisible = true;
    await showGame(tester, c, const Size(1280, 800), AppLanguage.english);
    expect(tester.takeException(), isNull);
    expect(find.text('Airplane + singles'), findsWidgets);
    expect(find.textContaining('333444'), findsNothing, reason: 'no raw notation in the rows');
    await closeGame(tester, c);
  });
}
