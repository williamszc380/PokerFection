import 'dart:js_interop';
import 'dart:typed_data';

import 'branch_jobs.dart';
import 'branches.dart';
import 'web_workers.dart';

/// Starts a Web Worker solving [job].
Future<BranchWorker> startBranchWorker(BranchJob job) async {
  final worker = await SolverWorker.start();
  if (worker == null) throw StateError('No solver worker to start');
  worker.send(SolverRequest.branches(job));
  return _WebWorker(worker);
}

class _WebWorker implements BranchWorker {
  _WebWorker(this._worker);

  final SolverWorker _worker;

  @override
  Future<Float64List> walk(int t, bool last, Uint8List active, Float64List reach, Float64List mass) async {
    _worker.send(SolverRequest(
      kind: 'walk',
      t: t,
      last: last,
      active: active.toJS,
      reach: reach.toJS,
      mass: mass.toJS,
    ));
    return (await _worker.next()).walked.toDart;
  }

  @override
  Future<BranchExport> export() async {
    _worker.send(SolverRequest(kind: 'export'));
    final reply = await _worker.next();
    return (reply.offsets.toDart, reply.average.toDart, reply.ownedValues.toDart);
  }

  @override
  void stop() => _worker.stop();
}
