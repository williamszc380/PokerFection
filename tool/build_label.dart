// The version shown in the main menu's corner (lib/src/app/build_info.dart):
// the first two numbers of pubspec.yaml's version (set by hand), then how
// many commits the code has, like "1.0.11". The last number goes up by one
// with every commit by itself, and a "+" follows when there are uncommitted
// changes ("1.0.11+"). tool/run.dart and tool/build_web.dart pass it to
// Flutter as --dart-define=PF_BUILD=..., so two copies of the game (the app
// and the website, say) show the same version exactly when they come from
// the same code.
import 'dart:io';

/// The define that carries the version.
const buildLabelDefine = 'PF_BUILD';

/// The version for the code in the current folder (the project root), or
/// null without git.
Future<String?> buildLabel() async {
  Future<String?> git(List<String> args) async {
    try {
      final result = await Process.run('git', args, runInShell: Platform.isWindows);
      return result.exitCode == 0 ? '${result.stdout}'.trim() : null;
    } on ProcessException {
      return null;
    }
  }

  final commits = int.tryParse(await git(['rev-list', '--count', 'HEAD']) ?? '');
  if (commits == null) return null;
  // The website's build (GitHub Actions) is the pushed commit by definition,
  // whatever its own setup steps touch.
  final changes = Platform.environment['GITHUB_ACTIONS'] == 'true' ? '' : await git(['status', '--porcelain']);
  return formatBuildLabel(_majorMinor(), commits, changed: changes != null && changes.isNotEmpty);
}

/// "1.0.11", with "+" when [changed].
String formatBuildLabel(String majorMinor, int commits, {required bool changed}) =>
    '$majorMinor.$commits${changed ? '+' : ''}';

/// The first two numbers of pubspec.yaml's version ("1.0" in "version: 1.0.0+1").
String _majorMinor() {
  final pubspec = File('pubspec.yaml');
  final match = pubspec.existsSync()
      ? RegExp(r'^version:\s*(\d+)\.(\d+)', multiLine: true).firstMatch(pubspec.readAsStringSync())
      : null;
  return match == null ? '1.0' : '${match.group(1)}.${match.group(2)}';
}

/// The `--dart-define` that gives Flutter [label], or nothing without one.
List<String> buildLabelOptions(String? label) => [if (label != null) '--dart-define=$buildLabelDefine=$label'];
