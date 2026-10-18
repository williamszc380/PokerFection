/// In the apps: read from the operating system.
library;

import 'dart:io';

/// This process's memory in use (resident set), in MB.
double? residentMb() => ProcessInfo.currentRss / (1024 * 1024);

/// Processor time this process has used so far, in ms (all its threads,
/// WebRTC's too), on Windows; null elsewhere.
Future<double?> cpuMs() async {
  if (!Platform.isWindows) return null;
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    '(Get-Process -Id $pid).TotalProcessorTime.TotalMilliseconds',
  ]);
  return double.tryParse((result.stdout as String).trim());
}
