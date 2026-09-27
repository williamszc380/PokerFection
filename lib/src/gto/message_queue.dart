import 'dart:async';

/// Reads messages from a stream one at a time, in order (a minimal version
/// of StreamQueue from package:async). Used to talk to worker isolates.
class MessageQueue {
  MessageQueue(Stream<Object?> stream) {
    _subscription = stream.listen((event) {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete(event);
      } else {
        _buffer.add(event);
      }
    });
  }

  late final StreamSubscription<Object?> _subscription;
  final List<Object?> _buffer = [];
  final List<Completer<Object?>> _waiting = [];

  Future<Object?> get next {
    if (_buffer.isNotEmpty) return Future.value(_buffer.removeAt(0));
    final completer = Completer<Object?>();
    _waiting.add(completer);
    return completer.future;
  }

  void cancel() => _subscription.cancel();
}
