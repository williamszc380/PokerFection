// Generates assets/preflop_equity.bin: the all-in equity of every starting
// hand against every other (wins plus half of ties), as a 169x169 table of
// little-endian float32 values. Row = hand, column = opponent's hand.
//
// Run from the project root:  dart run tool/generate_preflop_equity.dart [samples]
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pokerfection/src/engine/hand_evaluator.dart';
import 'package:pokerfection/src/gto/hand_classes.dart';

Future<void> main(List<String> args) async {
  final samples = args.isNotEmpty ? int.parse(args.first) : 20000;
  final workers = Platform.numberOfProcessors;
  final pairs = [
    for (var h = 0; h < handClassCount; h++)
      for (var o = h; o < handClassCount; o++) (h, o),
  ];
  final watch = Stopwatch()..start();
  stdout.writeln('Computing ${pairs.length} matchups x $samples boards on $workers cores...');

  final chunks = [
    for (var w = 0; w < workers; w++) [for (var i = w; i < pairs.length; i += workers) pairs[i]],
  ];
  final results = await Future.wait([
    for (var w = 0; w < workers; w++) Isolate.run(() => _equities(chunks[w], samples, seed: 1000 + w)),
  ]);

  final table = Float32List(handClassCount * handClassCount);
  for (final chunk in results) {
    for (final (h, o, equity) in chunk) {
      table[h * handClassCount + o] = equity;
      table[o * handClassCount + h] = 1 - equity;
    }
  }
  final bytes = ByteData(table.length * 4);
  for (var i = 0; i < table.length; i++) {
    bytes.setFloat32(i * 4, table[i], Endian.little);
  }
  File('assets/preflop_equity.bin')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
  stdout.writeln('Wrote assets/preflop_equity.bin in ${watch.elapsed.inSeconds}s');
}

/// Monte Carlo equity for each (hand, opponent) pair. Card combinations are
/// cycled evenly so every suit pattern gets its fair share of samples.
List<(int, int, double)> _equities(List<(int, int)> pairs, int samples, {required int seed}) {
  final rng = Random(seed);
  final mine = List<int>.filled(7, 0);
  final theirs = List<int>.filled(7, 0);
  final used = List<bool>.filled(52, false);
  final result = <(int, int, double)>[];

  for (final (h, o) in pairs) {
    if (h == o) {
      result.add((h, o, 0.5)); // same starting hand: even by symmetry
      continue;
    }
    final matchups = [
      for (final a in handClassCards(h))
        for (final b in handClassCards(o))
          if (a.$1 != b.$1 && a.$1 != b.$2 && a.$2 != b.$1 && a.$2 != b.$2) (a, b),
    ];
    var won = 0.0;
    for (var s = 0; s < samples; s++) {
      final (a, b) = matchups[s % matchups.length];
      used.fillRange(0, 52, false);
      used[a.$1] = used[a.$2] = used[b.$1] = used[b.$2] = true;
      mine[0] = a.$1;
      mine[1] = a.$2;
      theirs[0] = b.$1;
      theirs[1] = b.$2;
      for (var i = 2; i < 7; i++) {
        var card = rng.nextInt(52);
        while (used[card]) {
          card = rng.nextInt(52);
        }
        used[card] = true;
        mine[i] = card;
        theirs[i] = card;
      }
      final mineScore = evaluateIndices(mine), theirScore = evaluateIndices(theirs);
      won += mineScore > theirScore ? 1 : (mineScore == theirScore ? 0.5 : 0);
    }
    result.add((h, o, won / samples));
  }
  return result;
}
