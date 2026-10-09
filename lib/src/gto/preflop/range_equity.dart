// Native builds add four numbers at a time (SIMD); in browsers SIMD is
// emulated and slow, so web builds add one at a time.
export 'range_equity_io.dart' if (dart.library.js_interop) 'range_equity_web.dart';
