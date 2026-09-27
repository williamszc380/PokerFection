/// Where the app keeps its settings between runs: a small JSON file, or
/// the browser's local storage on the web.
library;

export 'settings_store_io.dart' if (dart.library.js_interop) 'settings_store_web.dart';
