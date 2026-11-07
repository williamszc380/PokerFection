/// Which version of the game this is, shown in Home's corner so two
/// copies (the app and the website, say) are easy to compare: the first two
/// numbers of pubspec.yaml's version, then how many commits the code has,
/// like "2.0.11", with a "+" when the code had uncommitted changes
/// ("2.0.11+"). `./run` and the website's build set it
/// (tool/build_label.dart); any other build shows "dev". Tapping it opens
/// About (home_screen.dart's showAbout), which reads it back with
/// [parseBuildLabel]. Online play doesn't use it: rooms check their
/// protocol version.
const buildLabel = String.fromEnvironment('PF_BUILD', defaultValue: 'dev');

/// The app's version number: the first number of pubspec.yaml's version
/// (keep the two the same). About shows it ("Version 2") for a build
/// without a label.
const appMajorVersion = 2;

/// What a [buildLabel] says, for About: the version ("2.0.11", without the
/// "+"), how many commits the code had (11) and whether it had uncommitted
/// changes (the "+"). Null for a label that isn't one of those ("dev").
({String version, int commits, bool changed})? parseBuildLabel(String label) {
  final match = RegExp(r'^(\d+\.\d+\.(\d+))(\+?)$').firstMatch(label);
  if (match == null) return null;
  return (version: match.group(1)!, commits: int.parse(match.group(2)!), changed: match.group(3)!.isNotEmpty);
}
