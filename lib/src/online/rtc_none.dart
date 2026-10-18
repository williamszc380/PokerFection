import 'rtc.dart';

/// Where Flutter isn't (a tool run with plain Dart, such as
/// tool/host_check.dart): no direct connections.
RtcFactory platformRtc() => throw UnsupportedError('peer-to-peer is not available here');
