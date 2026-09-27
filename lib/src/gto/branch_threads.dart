/// Starts the worker threads of a parallel solve (see branches.dart):
/// isolates, or Web Workers in browsers, which have no isolates.
library;

export 'branch_threads_io.dart' if (dart.library.js_interop) 'branch_threads_web.dart';
