/// Headless Chrome and Edge for the tests that check the web version
/// against the Windows app (rtc_interop_test.dart, web_peer_test.dart).
library;

import 'dart:async';
import 'dart:io';

/// Where each browser is installed on Windows.
const browsers = {
  'Chrome': r'C:\Program Files\Google\Chrome\Application\chrome.exe',
  'Edge': r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
};

/// A headless browser, with a profile of its own (deleted afterwards), so
/// it never touches the person's own browser or its windows.
class HeadlessBrowser {
  HeadlessBrowser._(this._process, this._profile);

  final Process _process;
  final Directory _profile;

  static Future<HeadlessBrowser> open(String exe, String url) async {
    final profile = await Directory.systemTemp.createTemp('rtc_interop_profile');
    final process = await Process.start(exe, [
      '--headless=new',
      '--no-first-run',
      '--no-default-browser-check',
      '--user-data-dir=${profile.path}',
      url,
    ]);
    // Read what it writes, or once the pipe is full the browser stops,
    // waiting to write more (after half a minute or so).
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    return HeadlessBrowser._(process, profile);
  }

  /// Stops the browser: every process started with its profile (Edge's
  /// first process hands over to another and exits).
  Future<void> close() async {
    _process.kill();
    final name = _profile.path.split(Platform.pathSeparator).last;
    await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      'Get-CimInstance Win32_Process | Where-Object { \$_.Name -match "msedge|chrome" -and '
          '\$_.CommandLine -like "*$name*" } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }',
    ]);
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      _profile.deleteSync(recursive: true);
    } on FileSystemException {
      // A browser process still letting go of a file: it stays in Temp.
    }
  }
}
