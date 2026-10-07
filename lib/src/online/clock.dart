import 'dart:async';

/// Where the server (and the online client) get the time and their timers,
/// so tests can run hours of play in an instant ([ManualClock]).
abstract interface class Clock {
  /// Milliseconds since some fixed moment; never goes back.
  int get nowMs;

  /// Calls [callback] once after [delay], unless the timer is cancelled.
  Timer schedule(Duration delay, void Function() callback);
}

/// The real time and real timers.
class SystemClock implements Clock {
  SystemClock() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  @override
  int get nowMs => _watch.elapsedMilliseconds;

  @override
  Timer schedule(Duration delay, void Function() callback) => Timer(delay, callback);
}

/// Time that only moves when a test says so ([advance]), firing the timers
/// that come due on the way, in order.
class ManualClock implements Clock {
  int _now = 0;
  int _created = 0;
  final List<_ManualTimer> _timers = [];

  @override
  int get nowMs => _now;

  @override
  Timer schedule(Duration delay, void Function() callback) {
    final ms = delay.inMilliseconds < 0 ? 0 : delay.inMilliseconds;
    final timer = _ManualTimer(this, _now + ms, _created++, callback);
    _timers.add(timer);
    return timer;
  }

  /// Timers still waiting to fire.
  int get pending => _timers.length;

  /// Moves time forward by [by], firing every timer that comes due (also
  /// ones the callbacks start), earliest first; timers due at the same
  /// moment fire in the order they were started.
  void advance(Duration by) {
    final end = _now + by.inMilliseconds;
    while (true) {
      _ManualTimer? next;
      for (final t in _timers) {
        if (t.due > end) continue;
        if (next == null || t.due < next.due || (t.due == next.due && t.order < next.order)) next = t;
      }
      if (next == null) break;
      _timers.remove(next);
      _now = next.due;
      next._fire();
    }
    _now = end;
  }

  /// Moves time forward to the next timer and fires it (and any due at the
  /// same moment). False if no timer is waiting.
  bool fireNext() {
    if (_timers.isEmpty) return false;
    final due = _timers.map((t) => t.due).reduce((a, b) => a < b ? a : b);
    advance(Duration(milliseconds: due - _now));
    return true;
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this._clock, this.due, this.order, this._callback);

  final ManualClock _clock;
  final int due;
  final int order;
  final void Function() _callback;
  bool _active = true;

  void _fire() {
    _active = false;
    _callback();
  }

  @override
  void cancel() {
    _active = false;
    _clock._timers.remove(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}
