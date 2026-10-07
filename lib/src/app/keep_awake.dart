import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the screen on ([on]), or lets it turn off again, on phones and
/// tablets: a room hosted there stops when the app goes to sleep. Asked of
/// the host app (see MainActivity / AppDelegate), without plugins.
Future<void> keepScreenOn(bool on) async {
  if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }
  try {
    await const MethodChannel('pokerfection/platform').invokeMethod<void>('keepScreenOn', on);
  } on Exception {
    // The screen may turn off by itself.
  }
}

/// While hosting a room on Android ([on]): hears the Wi-Fi's broadcasts,
/// which friends looking for the room by its code send (Android may drop
/// them otherwise). Asked of MainActivity, without plugins.
Future<void> hearRoomSearches(bool on) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await const MethodChannel('pokerfection/platform').invokeMethod<void>('hearBroadcasts', on);
  } on Exception {
    // Friends then join with the invite.
  }
}
