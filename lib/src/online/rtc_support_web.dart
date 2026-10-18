import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Why this browser can't make direct connections, or null if it can: very
/// old browsers, and some locked-down ones, have no RTCPeerConnection.
String? rtcMissing() => globalContext.has('RTCPeerConnection') ? null : 'this browser has no WebRTC';
