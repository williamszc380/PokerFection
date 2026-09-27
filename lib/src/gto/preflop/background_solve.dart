// Solving off the UI thread uses isolates, which browsers don't have: web
// builds use Web Workers instead (lib/solver_worker.dart).
export 'background_solve_io.dart' if (dart.library.js_interop) 'background_solve_web.dart';
