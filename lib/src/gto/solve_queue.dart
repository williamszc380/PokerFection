import 'dart:async';

import 'package:flutter/foundation.dart';

/// How urgently a solve is wanted, most urgent first.
///
/// - [bot]: a bot is about to play from it (it waits at most its budget).
/// - [shown]: the user pressed Show GTO, or someone is looking at the answer.
/// - [nextHand]: the next hand's whole game, so its bots can play from it.
/// - [grade]: a move already made, graded when it lands.
/// - [ahead]: work that may never be needed (the user's next first decision).
///
/// A hand's solve is asked for at what it is for when asked; a reason that
/// comes later and passes (a bot waiting, Show GTO) is a claim on the
/// hand ([SolveOwner.claim]), and at hand over all of it is a grade at most.
enum SolvePriority { bot, shown, nextHand, grade, ahead }

/// What a queued solve's future fails with when every hand that wanted it
/// has moved on (see [SolveQueue.drop]). Nobody is waiting for its answer,
/// so it is never shown as a failure.
class SolveCancelled implements Exception {
  const SolveCancelled();

  /// A future that fails with [SolveCancelled], which nobody has to listen
  /// to: left alone it is not reported as an unhandled error.
  static Future<T> future<T>() {
    final cancelled = Future<T>.error(const SolveCancelled());
    cancelled.ignore();
    return cancelled;
  }

  @override
  String toString() => 'SolveCancelled';
}

/// One hand's solves (solo: the hand's follower; online: the session's
/// hand), and the reasons they are wanted sooner than they were asked for.
///
/// A hand's solves depend on each other (each street starts from the one
/// before), so when one of them becomes urgent they all do: while a
/// [claim] is open, every queued solve the owner holds, and every one it
/// asks for later, runs at least as urgently as the claim. Each claim lasts
/// as long as its reason (a bot waiting, Show GTO on) and is ended then,
/// so a hand that was urgent once doesn't stay ahead of the next hand's
/// work for good.
class SolveOwner {
  SolveOwner(this.hand);

  /// The hand number, for reading logs and tests.
  final int hand;

  final List<SolveClaim> _claims = [];
  bool _dropped = false;
  bool _finished = false;

  /// The most urgent claim still open ([SolvePriority.ahead] with none):
  /// the least urgent priority this hand's solves run at.
  SolvePriority get floor {
    var floor = SolvePriority.ahead;
    for (final claim in _claims) {
      if (claim.priority.index < floor.index) floor = claim.priority;
    }
    return floor;
  }

  /// Whether [SolveQueue.drop] has let go of this hand: it gets nothing more.
  bool get dropped => _dropped;

  /// Whether the hand is over ([finish]).
  bool get finished => _finished;

  /// Makes this hand's solves at least as urgent as [priority] until the
  /// claim is ended ([SolveClaim.end]). Claims add up: the most urgent one
  /// open wins. The queue reads every owner's floor each time it picks a
  /// job, so opening or ending a claim needs nothing else. A dropped or
  /// finished hand has no reason to hurry: its claim is ended already.
  SolveClaim claim(SolvePriority priority) {
    final claim = SolveClaim._(this, priority);
    if (!_dropped && !_finished) _claims.add(claim);
    return claim;
  }

  /// The hand is over: its claims end, later ones are ended at once, and
  /// what it asked for as urgent (a bot to play from, the next hand's
  /// game) counts as a grade at most. Nobody plays in a finished hand any
  /// more: what is left of it only grades moves, so it goes after the next
  /// hand's game.
  void finish() {
    _finished = true;
    _claims.clear();
  }

  @override
  String toString() =>
      'SolveOwner($hand, ${floor.name}${_finished ? ', finished' : ''}${_dropped ? ', dropped' : ''})';
}

/// One reason for a hand's solves to come sooner (see [SolveOwner.claim]),
/// open until [end].
class SolveClaim {
  SolveClaim._(this.owner, this.priority);

  final SolveOwner owner;
  final SolvePriority priority;

  /// Whether it still lifts the owner's solves.
  bool get open => owner._claims.any((c) => identical(c, this));

  /// Its reason has ended (the bot has moved, Show GTO was turned off): the
  /// owner's solves fall back to their own priority or its other claims.
  /// Ending it again, or after the hand is over or dropped, does nothing.
  void end() => owner._claims.removeWhere((c) => identical(c, this));

  @override
  String toString() => 'SolveClaim(${owner.hand}, ${priority.name}${open ? '' : ', ended'})';
}

/// One solve at a time per device, most urgent first.
///
/// Each solve already uses every core but one, so two at once would only
/// halve each other's speed and make the urgent one late. A running solve
/// is never stopped: the worst wait for an urgent one is the one running.
class SolveQueue {
  SolveQueue({this.maxRunning = 1}) : assert(maxRunning >= 1);

  /// How many jobs run at once.
  final int maxRunning;

  final List<_Job> _queued = [];
  final List<_Job> _running = [];
  var _order = 0;
  var _pumpScheduled = false;

  /// Runs [run] when it is the most urgent queued job (the first asked for,
  /// among equals), and completes with its result.
  ///
  /// [key] says what is being solved: asking again for a key that is queued
  /// or running joins that job instead (see [join]) and gets its future.
  /// [owner]: the hand that wants it (null for tools, the charts screen and
  /// tests: such a holder never drops, see [drop]). A dropped owner with no
  /// job to join gets [SolveCancelled] at once.
  ///
  /// The job starts in a microtask, not right here, so that jobs asked for
  /// in the same run of code are compared before one of them starts.
  Future<T> add<T>(Object key, Future<T> Function() run, {SolveOwner? owner, required SolvePriority priority}) {
    final existing = _find(key);
    if (existing != null) {
      existing._hold(owner, priority);
      return existing.completer.future as Future<T>;
    }
    if (owner != null && owner.dropped) return SolveCancelled.future();
    final job = _Job<T>(key, run, _order++);
    job._hold(owner, priority);
    _queued.add(job);
    _schedulePump();
    return job.completer.future;
  }

  /// Adds a holder to the job queued or running under [key] (a second
  /// request for the same solve), which may make it more urgent. False when
  /// there is no such job: it has finished, failed or been dropped.
  bool join(Object key, {SolveOwner? owner, required SolvePriority priority}) {
    final job = _find(key);
    if (job == null) return false;
    job._hold(owner, priority);
    return true;
  }

  /// Lets go of [owner]'s queued solves: [owner] is removed from every
  /// queued job, and a job left with no holder is taken off the queue (its
  /// future fails with [SolveCancelled]). Running jobs finish, and their
  /// answers are kept for whoever else asks. Later requests by [owner] get
  /// nothing new. Returns the keys of the jobs taken off, so the caller can
  /// forget them at once (a cache that kept the failed future until its
  /// error arrived would hand it to the next request for the same key).
  List<Object> drop(SolveOwner owner) {
    owner._dropped = true;
    owner._claims.clear();
    final dropped = <_Job>[];
    for (final job in _queued) {
      job.holders.removeWhere((h) => identical(h.owner, owner));
      if (job.holders.isEmpty) dropped.add(job);
    }
    _queued.removeWhere(dropped.contains);
    for (final job in dropped) {
      // Callers that never listened (work done ahead of time) aren't told
      // either: a cancel is not an error anyone has to handle.
      job.completer.future.ignore();
      job.completer.completeError(const SolveCancelled());
    }
    return [for (final job in dropped) job.key];
  }

  /// The keys of the jobs waiting, most urgent first (the order they will
  /// start in if nothing changes).
  @visibleForTesting
  List<Object> get queued => [for (final job in _byUrgency()) job.key];

  /// The keys of the jobs running.
  @visibleForTesting
  List<Object> get running => [for (final job in _running) job.key];

  /// Whether a job under [key] is queued or running.
  bool has(Object key) => _find(key) != null;

  /// How urgent the job under [key] is now (null when there is none).
  SolvePriority? priorityOf(Object key) => _find(key)?.priority;

  _Job? _find(Object key) {
    for (final job in _running) {
      if (job.key == key) return job;
    }
    for (final job in _queued) {
      if (job.key == key) return job;
    }
    return null;
  }

  List<_Job> _byUrgency() => [..._queued]..sort(_Job.compare);

  void _schedulePump() {
    if (_pumpScheduled) return;
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  /// Starts the most urgent jobs while there is room. The queue is a few
  /// entries long, so it is searched each time rather than kept sorted:
  /// owners' claims open and end without telling the queue.
  void _pump() {
    while (_running.length < maxRunning && _queued.isNotEmpty) {
      var next = _queued.first;
      for (final job in _queued.skip(1)) {
        if (_Job.compare(job, next) < 0) next = job;
      }
      _queued.remove(next);
      _running.add(next);
      unawaited(next._start(() {
        _running.remove(next);
        _schedulePump();
      }));
    }
  }
}

/// Who wants a job, and how much.
typedef _Holder = ({SolveOwner? owner, SolvePriority priority});

class _Job<T> {
  _Job(this.key, this.run, this.order);

  final Object key;
  final Future<T> Function() run;

  /// When it was asked for: first come, first served among equals.
  final int order;
  final completer = Completer<T>();
  final List<_Holder> holders = [];

  void _hold(SolveOwner? owner, SolvePriority priority) {
    if (owner != null && owner.dropped) return;
    holders.add((owner: owner, priority: priority));
  }

  /// The most urgent of its holders' priorities, each lifted to its
  /// owner's floor. A finished hand's holder counts as a grade at most:
  /// whatever it was urgent for is over (see [SolveOwner.finish]).
  SolvePriority get priority {
    var best = SolvePriority.ahead;
    for (final (:owner, :priority) in holders) {
      var p = priority;
      if (owner != null) {
        if (owner.finished && p.index < SolvePriority.grade.index) p = SolvePriority.grade;
        if (owner.floor.index < p.index) p = owner.floor;
      }
      if (p.index < best.index) best = p;
    }
    return best;
  }

  /// Runs the job, then calls [done] (so the queue no longer lists it
  /// when whoever asked hears the answer), then passes its result or error on.
  Future<void> _start(void Function() done) async {
    T result;
    try {
      result = await run();
    } catch (error, stack) {
      done();
      completer.completeError(error, stack);
      return;
    }
    done();
    completer.complete(result);
  }

  static int compare(_Job a, _Job b) {
    final byPriority = a.priority.index - b.priority.index;
    return byPriority != 0 ? byPriority : a.order - b.order;
  }
}
