import 'package:flutter/widgets.dart';

import '../../app/last_games.dart';
import '../../kit/jobs/jobs.dart';

/// Gives each game screen its background jobs and the most recent games.
///
/// The app places one around everything (with isolates or Web Workers and
/// the saved records); tests pass `newJobs: () => Jobs.inline()`, so a test
/// never starts an isolate by accident.
class KitScope extends InheritedWidget {
  const KitScope({super.key, required this.newJobs, required this.lastGames, required super.child});

  /// A new [Jobs] for one game screen (its controller disposes of it).
  final Jobs Function() newJobs;
  final LastGames lastGames;

  /// The nearest scope; without one (a test pumping one screen), jobs on
  /// the same thread and records kept in memory. It never changes while the
  /// app runs, so nothing depends on it: a screen may call this in initState
  /// to make its controller.
  static KitScope of(BuildContext context) => context.getInheritedWidgetOfExactType<KitScope>() ?? _fallback;

  static final _fallback = KitScope(newJobs: Jobs.inline, lastGames: LastGames(), child: const SizedBox.shrink());

  @override
  bool updateShouldNotify(KitScope oldWidget) => newJobs != oldWidget.newJobs || lastGames != oldWidget.lastGames;
}
