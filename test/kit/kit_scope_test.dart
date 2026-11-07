import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';

/// Reads the scope in initState, as a game screen making its controller does.
class _Screen extends StatefulWidget {
  const _Screen({required this.found});

  final void Function(KitScope scope) found;

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  @override
  void initState() {
    super.initState();
    widget.found(KitScope.of(context));
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('a screen gets its jobs and the most recent games from the scope, in initState', (tester) async {
    final lastGames = LastGames();
    late KitScope scope;
    await tester.pumpWidget(KitScope(
      newJobs: () => Jobs.inline(),
      lastGames: lastGames,
      child: _Screen(found: (s) => scope = s),
    ));
    expect(scope.lastGames, same(lastGames));
  });

  testWidgets('without a scope: jobs on the same thread and records in memory, never an isolate', (tester) async {
    late KitScope scope;
    await tester.pumpWidget(_Screen(found: (s) => scope = s));
    final jobs = scope.newJobs();
    expect(jobs.platform, JobPlatform.test);
    jobs.dispose();
    expect(scope.lastGames, same(KitScope.of(tester.element(find.byType(SizedBox))).lastGames), reason: 'one shared store');
  });
}
