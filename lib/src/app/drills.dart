import 'dart:async';

import 'package:flutter/widgets.dart';

import '../game/drill_spots.dart';
import 'settings_store.dart';

export '../game/drill_spots.dart';

/// The user's mistake drills (see [DrillList]), kept between runs: a file
/// next to the settings (`drills.json`), or the browser's local storage.
/// Widgets read them with [Drills.maybeOf], which rebuilds them on a change.
class Drills extends ChangeNotifier {
  Drills({this._store, DateTime Function()? clock}) : now = clock ?? DateTime.now;

  final SettingsStore? _store;

  /// The time now (real time: a spot comes back even while the app is closed).
  final DateTime Function() now;

  DrillList _list = DrillList();

  List<DrillSpot> get spots => _list.spots;
  bool get isEmpty => _list.spots.isEmpty;

  /// The spots due now, in the order to play them (see [DrillList.due]).
  List<DrillSpot> get due => _list.due(now());
  int get dueCount => due.length;

  /// When the next spot not due yet is due, if any.
  DateTime? get nextDue => _list.nextDue(now());

  /// The app's drills; null outside the app (tests: nothing is saved).
  static Drills? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DrillsScope>()?.notifier;

  /// The same, without rebuilding on a change (also before a widget is built).
  static Drills? read(BuildContext context) => context.getInheritedWidgetOfExactType<DrillsScope>()?.notifier;

  /// Reads the saved spots (spots that can't be read are left out).
  Future<void> load() async {
    final saved = await _store?.read() ?? const {};
    _list = DrillList([
      if (saved['spots'] case final List<Object?> spots)
        for (final json in spots) ?DrillSpot.fromJson(json),
    ]);
    notifyListeners();
  }

  /// Saves a mistake just made; false if the same spot was saved already
  /// (it starts over).
  bool save(DrillSpot spot) {
    final added = _list.add(spot);
    _changed();
    return added;
  }

  /// [spot] played again: see [DrillList.review]. Returns the wait.
  Duration review(DrillSpot spot, {required bool? right}) {
    final wait = _list.review(spot, right: right, now: now());
    _changed();
    return wait;
  }

  /// Drops a spot that can't be played any more (the rules changed).
  void remove(DrillSpot spot) {
    if (_list.remove(spot)) _changed();
  }

  void _changed() {
    notifyListeners();
    unawaited(_store?.write({
      'version': 1,
      'spots': [for (final spot in _list.spots) spot.toJson()],
    }));
  }
}

/// Makes the app's [Drills] available below it.
class DrillsScope extends InheritedNotifier<Drills> {
  const DrillsScope({super.key, required Drills drills, required super.child}) : super(notifier: drills);
}
