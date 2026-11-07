/// tool/games/game_worker_check.dart's own rules: it may never say "All the
/// same." about a job it didn't compare, and the game agents' runs may
/// overlap.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/games/game_worker_check.dart' as check;

void main() {
  const games = {'nim', 'gomoku', 'big_two', 'doudizhu', 'blackjack'};

  test('a job the worker has and the check never compared is reported (no checkInputs, or a game it skips)', () {
    expect(
      check.uncheckedJobs(
        listed: {'gomoku.coach', 'gomoku.bot', 'gomoku.guide', 'big_two.coach', 'chess.coach'},
        checked: {'nim.coach', 'gomoku.coach', 'gomoku.bot'},
        checkedGames: {'nim', 'gomoku'},
        allGames: games,
      ),
      ['chess.coach', 'gomoku.guide'],
      reason: "gomoku.guide had no inputs; chess isn't in the check at all; Big Two wasn't asked for (--only)",
    );
  });

  test('every job compared: nothing to report', () {
    expect(
      check.uncheckedJobs(
        listed: {'gomoku.coach', 'gomoku.bot'},
        checked: {'nim.coach', 'nim.bot', 'gomoku.coach', 'gomoku.bot'},
        checkedGames: games,
        allGames: games,
      ),
      isEmpty,
    );
  });

  test('each run gets its own work folder, so one run never deletes files another is using', () {
    final a = check.workFolder(), b = check.workFolder();
    addTearDown(() {
      a.deleteSync(recursive: true);
      b.deleteSync(recursive: true);
    });
    expect(a.path, isNot(b.path));
    expect(a.existsSync() && b.existsSync(), isTrue);
  });
}
