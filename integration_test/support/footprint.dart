/// How much memory and processor time this app uses, where that can be
/// read (the apps); nothing in a browser.
library;

export 'footprint_none.dart' if (dart.library.io) 'footprint_io.dart';
