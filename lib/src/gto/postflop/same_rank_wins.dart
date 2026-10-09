// Native builds show a group of same-rank rivers down in one pass, four
// numbers at a time (SIMD); in browsers SIMD is emulated and slow, so web
// builds take two passes.
export 'same_rank_wins_io.dart' if (dart.library.js_interop) 'same_rank_wins_web.dart';
