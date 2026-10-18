import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'in_process_host.dart';
import 'room_host.dart';
import 'rtc_support_web.dart';

/// A browser can host a room when it can make direct connections
/// (RTCPeerConnection): friends come in through the meeting service, since
/// a web page can't listen for connections. Very old or locked-down
/// browsers can't (Create Room is greyed out there).
bool get canHostHere => rtcMissing() == null;

/// Hosts a room in this page (InProcessHost): the room runs in the tab, its
/// code is taken at the meeting service, and this page's own app joins it
/// in memory. While it is open, closing the tab asks first; when the page
/// goes anyway, everyone is told the room closed. [openRouter] means
/// nothing here (a page can't ask a router).
Future<RoomHost> hostHere({void Function(String message)? log, bool openRouter = true}) async {
  final host = await InProcessHost.start(log: log);
  final guard = _TabGuard(host);
  unawaited(host.stopped.whenComplete(guard.remove));
  return host;
}

/// A browser can't ask the network around it: a bare code goes to the
/// meeting service.
Future<List<String>> findRoomNearby(String code) async => const [];

/// While a room is hosted in this tab: closing or reloading the tab asks
/// first (the browser's own question), and once the page goes, the room
/// closes properly, so friends hear at once rather than after a silence.
class _TabGuard {
  _TabGuard(this._host) {
    web.window.addEventListener('beforeunload', _ask);
    web.window.addEventListener('pagehide', _close);
  }

  final RoomHost _host;

  late final JSFunction _ask = ((web.Event event) {
    event.preventDefault();
    // Older browsers ask only when this is set.
    (event as web.BeforeUnloadEvent).returnValue = '';
  }).toJS;

  late final JSFunction _close = ((web.Event _) => unawaited(_host.stop())).toJS;

  void remove() {
    web.window.removeEventListener('beforeunload', _ask);
    web.window.removeEventListener('pagehide', _close);
  }
}
