/// [platformJobs]: the app's jobs, on isolates (Windows, Android, iOS) or
/// in the browser. The conditional import keeps dart:isolate and
/// package:web out of everything that only needs jobs.dart.
library;

import 'backend_web.dart' if (dart.library.io) 'backend_io.dart';
import 'jobs.dart';

/// A new [Jobs] for one game screen, running every game's jobs where this
/// platform runs them best.
Jobs platformJobs() => createPlatformJobs();
