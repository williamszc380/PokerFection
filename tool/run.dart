// Runs the game on this computer: picks Flutter's device for this OS
// (Windows, macOS or Linux) and starts it with hot reload. Started by the
// `run` scripts in the project root (`run` for bash, `run.cmd` for
// PowerShell and cmd), which put Flutter on the PATH: from FLUTTER_ROOT,
// else ~/dev/flutter, else whatever the PATH already has.
//
//   ./run                  the game
//   ./run --profile=2      another copy with its own settings and name online
//                          (--profile 2 works too), to play against yourself
//   ./run --release        any other option goes to `flutter run`
//   ./run -h               what it does and its options (also --help)
//
// Only one `flutter run` per OS can run at a time: the running game locks
// its program file against a rebuild. So while the game is running,
// --profile=N starts the program that is already built instead, without hot
// reload (start it again to pick up changes).
import 'dart:io';

/// Options that show [_help] instead of starting the game. They take the
/// place of `flutter run`'s own -h, which `flutter run -h` still shows.
const _helpOptions = {'-h', '--help'};

const _help = '''
Runs PokerFection on this computer (Windows, macOS or Linux), with hot reload.

Usage: ./run [options]     (run.cmd works the same in cmd)

Options:
  -h, --help           Show this help.
  --profile N          Start another copy with its own settings and online
  --profile=N          name (N = 2, 3, ...), to play against yourself. If the
                       game is already running, the copy starts from the last
                       build, without hot reload.
  anything else        Goes to flutter run, e.g. --release or -v
                       (all of them: flutter run -h).

While the game runs, in this window:
  r  hot reload    R  hot restart    q  quit

Examples:
  ./run
  ./run --profile 2
  ./run --release

Flutter comes from FLUTTER_ROOT, else ~/dev/flutter, else the PATH.
''';

Future<void> main(List<String> args) async {
  if (args.any(_helpOptions.contains)) {
    stdout.write(_help);
    return;
  }
  // The project root, wherever the script was started from.
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final device = switch (Platform.operatingSystem) {
    'windows' => 'windows',
    'macos' => 'macos',
    'linux' => 'linux',
    final other => _fail('Running on $other isn\'t supported; use Windows, macOS or Linux.'),
  };
  if (!Directory(device).existsSync()) {
    _fail('This project has no $device app yet. Add it once with: flutter create --platforms=$device .');
  }
  // --profile=N or --profile N; everything else goes to flutter run.
  String? profile;
  final rest = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a.startsWith('--profile=')) {
      profile = a;
    } else if (a == '--profile') {
      if (i + 1 >= args.length || int.tryParse(args[i + 1]) == null) _fail('--profile needs a number, like --profile 2.');
      profile = '--profile=${args[++i]}';
    } else {
      rest.add(a);
    }
  }

  if (profile != null && await _gameRunning(device)) {
    final app = _builtApp(device);
    if (app == null) _fail('No built game found yet: start the first copy with ./run.');
    stdout.writeln('The game is already running: starting another copy with $profile (no hot reload).');
    final copy = device == 'macos'
        ? await Process.start('open', ['-n', '-W', app, '--args', profile], mode: ProcessStartMode.inheritStdio)
        : await Process.start(app, [profile], mode: ProcessStartMode.inheritStdio);
    exit(await copy.exitCode);
  }

  stdout.writeln('Starting the game on $device${profile == null ? '' : ' with $profile'}...');
  final Process flutter;
  try {
    flutter = await Process.start(
      'flutter',
      ['run', '-d', device, if (profile != null) '--dart-entrypoint-args=$profile', ...rest],
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
  } on ProcessException {
    _fail('Flutter not found: add its bin folder to PATH, or set FLUTTER_ROOT.');
  }
  exit(await flutter.exitCode);
}

/// Whether a copy of the game is running on this computer.
Future<bool> _gameRunning(String device) async {
  if (device == 'windows') {
    final tasks = await Process.run('tasklist', ['/FI', 'IMAGENAME eq PokerFection.exe', '/NH']);
    return '${tasks.stdout}'.toLowerCase().contains('pokerfection.exe');
  }
  final found = await Process.run('pgrep', ['-xi', device == 'macos' ? 'PokerFection' : 'pokerfection']);
  return found.exitCode == 0;
}

/// The game as last built by `flutter run` (debug first), or null.
String? _builtApp(String device) {
  final candidates = switch (device) {
    'windows' => ['build/windows/x64/runner/Debug/PokerFection.exe', 'build/windows/x64/runner/Release/PokerFection.exe'],
    'macos' => ['build/macos/Build/Products/Debug/pokerfection.app', 'build/macos/Build/Products/Release/pokerfection.app'],
    _ => ['build/linux/x64/debug/bundle/pokerfection', 'build/linux/x64/release/bundle/pokerfection'],
  };
  for (final path in candidates) {
    if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) return path;
  }
  return null;
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
