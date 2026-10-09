// The solvers' per-hand vector arithmetic, in 32-bit numbers. Native
// builds work four numbers at a time (SIMD); in browsers SIMD is emulated
// and slow, so web builds work one at a time.
//
// A vector's length, and every position and length passed in, is a
// multiple of 4 (see [roundUpToLanes]).
export 'vectors_io.dart' if (dart.library.js_interop) 'vectors_web.dart';
