/// Which version of the game this is, shown in the main menu's corner so two
/// copies (the app and the website, say) are easy to compare: the first two
/// numbers of pubspec.yaml's version, then how many commits the code has,
/// like "1.0.11", with a "+" when the code had uncommitted changes
/// ("1.0.11+"). `./run` and the website's build set it
/// (tool/build_label.dart); any other build shows "dev". Online play doesn't
/// use it: rooms check their protocol version.
const buildLabel = String.fromEnvironment('PF_BUILD', defaultValue: 'dev');
