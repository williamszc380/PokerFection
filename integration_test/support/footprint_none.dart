/// In a browser: the page can't see its own memory or processor time.
library;

/// This process's memory in use (resident set), in MB; null if unknown.
double? residentMb() => null;

/// Processor time this process has used so far, in ms; null if unknown.
Future<double?> cpuMs() async => null;
