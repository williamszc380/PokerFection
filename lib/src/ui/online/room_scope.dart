/// The app's room for every screen (see RoomService), the tags of the
/// routes it cares about, and where a dialog opened from the docked room
/// goes. Small on purpose: the glossary's "?" uses it without pulling in
/// the room's shell and panel.
library;

import 'package:flutter/widgets.dart';

import 'room_service.dart';

export 'room_service.dart' show RoomService, RoomStage;

/// The routes the room tells apart, by their `RouteSettings.arguments`
/// (never by name: the app's Navigator reports names to the browser, which
/// would put them in the address bar and open them again on a reload).
enum RoomRoute {
  /// Play Online.
  online,

  /// The room's game (the online table).
  game,
}

/// Gives every screen the app's room (see RoomService), and rebuilds what
/// reads it as the room changes.
class RoomScope extends InheritedNotifier<RoomService> {
  const RoomScope({super.key, required RoomService super.notifier, required super.child});

  static RoomService of(BuildContext context) => maybeOf(context)!;

  /// The room service, or null outside one (tests that pump a screen alone).
  static RoomService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoomScope>()?.notifier;
}

/// Marks the room docked beside the screen (RoomShell): its own Navigator
/// is only as wide as the dock, so dialogs opened from it go to the app's
/// (see [roomDialogContext]).
class InDockedPanel extends InheritedWidget {
  const InDockedPanel({super.key, required super.child});

  static bool of(BuildContext context) => context.getInheritedWidgetOfExactType<InDockedPanel>() != null;

  @override
  bool updateShouldNotify(InDockedPanel oldWidget) => false;
}

/// Where a dialog or sheet opened from [context] goes: from the docked
/// panel, the app's Navigator (over the screen beside it); from anywhere
/// else, [context] itself.
BuildContext roomDialogContext(BuildContext context) {
  if (!InDockedPanel.of(context)) return context;
  final rooms = context.getInheritedWidgetOfExactType<RoomScope>()?.notifier;
  return rooms?.dialogContext ?? context;
}
