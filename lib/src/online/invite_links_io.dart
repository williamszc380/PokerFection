import 'dart:io';

/// On Windows, makes pokerfection:// links open this app (for the current
/// user, no admin rights needed). Android and iOS get it from their app
/// settings (AndroidManifest.xml, Info.plist). Done once per app location.
Future<void> registerInviteLinks() async {
  if (!Platform.isWindows) return;
  try {
    final exe = Platform.resolvedExecutable;
    const key = r'HKCU\Software\Classes\pokerfection';
    final now = await Process.run('reg', ['query', '$key\\shell\\open\\command', '/ve']);
    if (now.exitCode == 0 && '${now.stdout}'.contains(exe)) return;
    await Process.run('reg', ['add', key, '/ve', '/d', 'URL:PokerFection', '/f']);
    await Process.run('reg', ['add', key, '/v', 'URL Protocol', '/d', '', '/f']);
    await Process.run('reg', ['add', '$key\\shell\\open\\command', '/ve', '/d', '"$exe" "%1"', '/f']);
  } on Object {
    // Links then don't open the app; pasting the invite still works.
  }
}
