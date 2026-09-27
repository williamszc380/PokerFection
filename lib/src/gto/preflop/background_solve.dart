// Solving off the UI thread uses isolates, which browsers don't have: web
// builds get a version that solves on the main thread instead.
export 'background_solve_io.dart' if (dart.library.js_interop) 'background_solve_web.dart';
