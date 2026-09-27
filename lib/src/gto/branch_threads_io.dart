import 'dart:isolate';
import 'dart:typed_data';

import 'branch_jobs.dart';
import 'branches.dart';
import 'message_queue.dart';

/// Starts an isolate solving [job].
Future<BranchWorker> startBranchWorker(BranchJob job) async {
  final replies = ReceivePort();
  // Errors arrive on the same port, so a failing worker makes the solve fail
  // instead of waiting forever.
  final isolate = await Isolate.spawn(_workerMain, (replies.sendPort, job), onError: replies.sendPort);
  final queue = MessageQueue(replies);
  final send = await queue.next as SendPort;
  return _IsolateWorker(isolate, send, queue);
}

class _IsolateWorker implements BranchWorker {
  _IsolateWorker(this._isolate, this._send, this._replies);

  final Isolate _isolate;
  final SendPort _send;
  final MessageQueue _replies;

  @override
  Future<Float64List> walk(int t, bool last, Uint8List active, Float64List reach, Float64List mass) async {
    _send.send((t, last, active, reach, mass));
    return await _replies.next as Float64List;
  }

  @override
  Future<BranchExport> export() async {
    _send.send('export');
    return await _replies.next as BranchExport;
  }

  @override
  void stop() {
    _send.send('stop');
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _replies.cancel();
  }
}

void _workerMain((SendPort, BranchJob) setup) {
  final (reply, job) = setup;
  final branches = job.start();
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  inbox.listen((message) {
    if (message == 'stop') {
      inbox.close();
    } else if (message == 'export') {
      reply.send(branches.export());
    } else {
      final (t, last, active, reach, mass) = message as (int, bool, Uint8List, Float64List, Float64List);
      reply.send(branches.walk(t, last, active, reach, mass));
    }
  });
}
