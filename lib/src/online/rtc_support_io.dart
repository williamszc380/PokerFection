import 'dart:io';

/// Why the apps can't make direct connections here, or null if they can.
///
/// The flutter_webrtc plugin is in every app build. Only `flutter test`'s
/// own host (flutter_tester) runs without plugins: a peer connection there
/// would never answer. Tests use a fake instead (test/online/fake_peer.dart),
/// and code that reaches for the real one hears at once that there is none,
/// as on a device without WebRTC.
String? rtcMissing() =>
    Platform.environment['FLUTTER_TEST'] == 'true' ? 'no plugins under flutter test' : null;
