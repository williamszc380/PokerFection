import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_settings.dart';
import '../../l10n/strings.dart';
import '../../online/host_here.dart';
import '../../online/invite.dart';
import '../../online/online_client.dart';
import '../../online/online_socket.dart';
import '../../online/peer_config.dart' show peerEntry;
import '../../online/protocol.dart';
import '../../online/room_host.dart';
import '../glossary.dart';
import 'room_panel.dart' show roomEndedText;
import 'room_scope.dart';

/// Play Online: the player's name and a room code or invite link, then one
/// button at the bottom: Create Room while the code is empty, Join Room once
/// there is one.
///
/// Create Room runs the room on this device (the game server inside the
/// app, and the room's code taken at the meeting service so friends
/// anywhere can come in); in a browser, the room runs in the page and
/// everyone comes in through the meeting service (greyed out where the
/// browser can't make direct connections). Join Room tries the invite's
/// ways in in order (the host's addresses on the same network first, then
/// the room through the meeting service when the invite names it, minus
/// those the page can't open); with just a code, it looks for the room on
/// the local network, then through the meeting service, wherever its host
/// is. An invite (a link that opened the app, or one pasted) fills in the
/// code and the ways in. The server can be set by hand (a server of your
/// own, see bin/server.dart): then rooms are created and joined there.
///
/// When the app closed (or the page reloaded) during a game, Rejoin Room
/// takes the player back to their seat, if the room kept it.
///
/// Once in, the room is the app's (RoomService): this screen closes, and
/// the room stays beside every screen. While in a room, this screen says
/// so at the top (with Leave Room, or Close Room for the host) and greys
/// out the rest: one room at a time.
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key, this.connect, this.invite, this.startHost, this.findNearby, this.page});

  /// The invite the app was opened with.
  final Invite? invite;

  /// Opens the connection to the server (connectAny by default: a WebSocket,
  /// or a direct connection for a room reached through the meeting service).
  final Future<OnlineSocket> Function(String url)? connect;

  /// Starts hosting a room on this device (hostHere by default); tests host
  /// on fakes.
  final Future<RoomHost> Function()? startHost;

  /// The game servers on the local network that have a room (findRoomNearby
  /// by default); tests answer for the network.
  final Future<List<String>> Function(String code)? findNearby;

  /// The address of the page the web version runs at (Uri.base by default
  /// there; none in the apps): what it may connect to depends on it. Tests
  /// give one.
  final Uri? page;

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _server = TextEditingController();
  bool _loaded = false;

  /// What is going on: starting a room here, or connecting.
  String? _busy;
  String? _error;

  /// The last invite used: its addresses go with its code.
  Invite? _invite;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final settings = AppSettings.of(context);
    _name.text = settings.nickname;
    _server.text = settings.serverUrl;
    if (widget.invite case final invite?) {
      _useInvite(invite);
      // An invite to the room the app is in already: the room, not this screen.
      final rooms = RoomScope.maybeOf(context);
      if (rooms != null && rooms.stage == RoomStage.open && rooms.room?.code == invite.code) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
          rooms.openPanel();
        });
      }
    }
  }

  void _useInvite(Invite invite) {
    _invite = invite;
    _code.text = invite.code;
  }

  /// A room is created on the server set by hand, else on this device.
  bool get _canCreate => canHostHere || _server.text.trim().isNotEmpty;

  /// The page the web version runs at; null in the apps.
  Uri? get _page => widget.page ?? (kIsWeb ? Uri.base : null);

  /// The one button: create a room, or join the one in the code box (back
  /// to the seat kept there, if this device was just in that room: the app
  /// closed, or the page reloaded).
  void _go() {
    if (_code.text.trim().isEmpty) {
      unawaited(_create());
    } else if (_rejoinFor(_code.text) case final record?) {
      unawaited(_rejoin(record));
    } else {
      unawaited(_join());
    }
  }

  /// The seat kept for this device in the room in [text], while it may
  /// still be kept.
  RejoinRecord? _rejoinFor(String text) {
    final record = AppSettings.of(context).rejoin.value;
    final code = parseInvite(text)?.code;
    return record != null && record.fresh && record.code == code ? record : null;
  }

  /// Fills in the code (and addresses) from an invite on the clipboard. A
  /// browser may not let the page read it (a host's http page): then it is
  /// pasted into the box by hand.
  Future<void> _paste() async {
    final s = S.of(context);
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Object {
      text = null;
    }
    final invite = text == null ? null : parseInvite(text);
    if (!mounted) return;
    setState(() {
      if (invite != null) _useInvite(invite);
      _error = invite != null ? null : ((text ?? '').isEmpty && kIsWeb ? s.pasteBlocked : s.noInvite);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _server.dispose();
    super.dispose();
  }

  /// The player's name, saved with the server; null (and why) if empty.
  String? _checkName() {
    final name = cleanName(_name.text);
    if (name == null) {
      setState(() => _error = S.of(context).enterName);
      return null;
    }
    AppSettings.of(context).update((a) {
      a.nickname = name;
      a.serverUrl = _server.text.trim();
    });
    return name;
  }

  /// Opens [client] with [opening], then hands the room to the app (it
  /// stays beside every screen) and closes. [unreachable] says why when no
  /// server could be reached, if there is more to say.
  Future<void> _open(OnlineClient client, ClientMessage opening, {String? unreachable}) async {
    final s = S.of(context);
    final settings = AppSettings.of(context);
    try {
      await client.open(opening);
    } on OnlineFailure catch (e) {
      // A room that can't be rejoined is forgotten.
      if (opening is RejoinRoom) settings.remember(null);
      await client.host?.stop();
      if (mounted) {
        setState(() {
          _busy = null;
          _error = switch (e) {
            // The host is there, but this network can't reach it directly: what to try instead.
            OnlineFailure(noDirectRoute: true) => s.noDirectRoute,
            OnlineFailure(error: null) when unreachable != null => unreachable,
            _ => s.joinError(e.error),
          };
        });
      }
      return;
    }
    if (!mounted) {
      unawaited(client.close());
      return;
    }
    final rooms = RoomScope.maybeOf(context);
    if (rooms == null || rooms.inRoom) {
      unawaited(client.close());
      return;
    }
    setState(() => _busy = null);
    rooms.enter(client);
    // Play Online sits above Home: back there, with the room beside it.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  /// Creates a room: on the server set by hand, else on this device (the
  /// game server starts inside the app, the room's code is taken at the
  /// meeting service, and this app joins it).
  Future<void> _create() async {
    final s = S.of(context);
    final name = _checkName();
    if (name == null || !_canCreate) return;
    final server = _server.text.trim();
    if (server.isNotEmpty) {
      setState(() {
        _busy = s.connecting;
        _error = null;
      });
      return _open(
        OnlineClient(server, onRecord: AppSettings.of(context).remember, connect: widget.connect),
        CreateRoom(name: name),
        unreachable: _blockedHere(server) ? s.wsOnWebsite : s.cantReachServer,
      );
    }
    setState(() {
      _busy = s.startingRoom;
      _error = null;
    });
    final RoomHost host;
    try {
      host = await (widget.startHost ?? hostHere)();
    } on Object {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = s.cantStartRoom;
        });
      }
      return;
    }
    if (!mounted) {
      unawaited(host.stop());
      return;
    }
    // The app's room takes over the hosting duties (the screen kept on, closing properly on exit).
    await _open(OnlineClient(host.ownServer, host: host, connect: widget.connect), CreateRoom(name: name));
  }

  /// Whether this page may not open [server] at all: a plain ws:// one
  /// from the website (https), which the browser refuses.
  bool _blockedHere(String server) {
    final page = _page;
    return page != null && reachableFromPage([server], page).isEmpty;
  }

  /// Joins the room in the code box (a code, or an invite link): at the
  /// invite's ways in in order (the room through the meeting service among
  /// them, when its host holds the room's name there), at the server set by
  /// hand, at the host that served this page (web), else wherever the room
  /// is found on the local network. With just a code (no invite, no server
  /// set by hand), the room through the meeting service too, wherever its
  /// host is; never when an invite left it out (its host holds no name
  /// there: the name could be anyone's) or for a server set by hand (its
  /// rooms aren't there). Last, a room on this computer. On the website
  /// (https), the ws:// ones are left out: the browser would refuse them
  /// anyway (a server set by hand that way is said to be no good here).
  Future<void> _join() async {
    final s = S.of(context);
    final invite = parseInvite(_code.text);
    if (invite == null) {
      setState(() => _error = s.notACode);
      return;
    }
    final name = _checkName();
    if (name == null) return;
    final known = invite.servers.isNotEmpty || invite.code != _invite?.code ? invite : _invite!;
    setState(() {
      _useInvite(known);
      _busy = s.connecting;
      _error = null;
    });
    final override = _server.text.trim();
    final page = _page;
    List<String> reachable(List<String> servers) => page == null ? servers : reachableFromPage(servers, page);
    final servers = reachable([
      ...known.servers,
      if (override.isNotEmpty) override,
      if (page != null) ?pageServer(page),
    ]);
    String? unreachable = switch (override) {
      '' => null,
      _ when _blockedHere(override) => s.wsOnWebsite,
      _ => s.cantReachServer,
    };
    if (servers.isEmpty) {
      servers.addAll(await (widget.findNearby ?? findRoomNearby)(invite.code));
      if (servers.isEmpty) unreachable ??= s.roomNotNearby;
    }
    // Just a code: the room through the meeting service too, wherever its host is.
    if (known.servers.isEmpty && override.isEmpty) servers.add(peerEntry(invite.code));
    servers.addAll(reachable(['ws://127.0.0.1:$gamePort/ws']));
    if (!mounted) return;
    if (servers.isEmpty) {
      // Nothing this page can open (the website, with only ws:// ways in).
      setState(() {
        _busy = null;
        _error = unreachable ?? s.roomNotNearby;
      });
      return;
    }
    await _open(
      OnlineClient(
        servers.first,
        alsoTry: servers.skip(1).toList(),
        onRecord: AppSettings.of(context).remember,
        connect: widget.connect,
      ),
      // With the app's key: a room the host removed this player from keeps them out.
      JoinRoom(code: invite.code, name: name, device: AppSettings.of(context).device),
      unreachable: unreachable,
    );
  }

  /// Back to the room the app was in when it closed, with the token the
  /// room gave: the seat is the player's again if they weren't away too
  /// long (else why not, and the room is forgotten). Where the room was
  /// last reached first, then the other ways back (the room through the
  /// meeting service, for a phone no longer on the host's Wi-Fi).
  Future<void> _rejoin(RejoinRecord record) {
    setState(() {
      _busy = S.of(context).connecting;
      _error = null;
    });
    final page = _page;
    final servers = [record.server, ...record.alsoTry];
    final ways = page == null ? servers : reachableFromPage(servers, page);
    return _open(
      OnlineClient(
        ways.firstOrNull ?? record.server,
        alsoTry: ways.skip(1).toList(),
        onRecord: AppSettings.of(context).remember,
        connect: widget.connect,
      ),
      RejoinRoom(code: record.code, token: record.token),
    );
  }

  /// While in a room: which one, and Leave Room (Close Room for the host),
  /// asked first; once it has ended, why, and OK.
  Widget _inRoom(BuildContext context, RoomService rooms) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final client = rooms.client;
    final ended = rooms.stage == RoomStage.ended;
    final host = rooms.isHost;
    final code = rooms.room?.code ?? client?.welcome?.code ?? '';
    return Card(
      key: const ValueKey('in room'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ended && client != null ? roomEndedText(s, client) : s.inRoom(code),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ended
                  ? FilledButton(key: const ValueKey('room ok'), onPressed: rooms.dismiss, child: Text(s.ok))
                  : OutlinedButton.icon(
                      key: ValueKey(host ? 'close room' : 'leave room'),
                      onPressed: () => _askToLeave(context, rooms),
                      icon: Icon(host ? Icons.cancel_outlined : Icons.logout, size: 18),
                      label: Text(host ? s.closeRoom : s.leaveRoom),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _askToLeave(BuildContext context, RoomService rooms) async {
    final s = S.of(context);
    final host = rooms.isHost;
    final client = rooms.client;
    final seated = client != null && (client.mySeat != null || client.queuedSeat != null);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(host ? s.closeRoomQuestion : s.leaveRoomQuestion),
        content: host || seated ? Text(s.leaveWarning(host: host)) : null,
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
          FilledButton(
            key: ValueKey(host ? 'close room sure' : 'leave room sure'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(host ? s.closeRoom : s.leaveRoom),
          ),
        ],
      ),
    );
    if (sure == true) await rooms.leave();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final rooms = RoomScope.maybeOf(context);
    // In a room already: one at a time (greyed out until it is left).
    final inRoom = rooms?.inRoom ?? false;
    final busy = _busy != null || inRoom;
    final creating = _code.text.trim().isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.playOnline),
        actions: const [
          HelpButton(section: GlossarySection.online),
          SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            shrinkWrap: true,
            children: [
              if (inRoom) _inRoom(context, rooms!),
              TextField(
                key: const ValueKey('online name'),
                controller: _name,
                enabled: !busy,
                maxLength: 16,
                decoration: InputDecoration(labelText: s.yourName, prefixIcon: const Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 8),
              // A room code or an invite link; empty to create a room.
              TextField(
                key: const ValueKey('online code'),
                controller: _code,
                enabled: !busy,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: s.roomCodeOrLink,
                  helperText: _canCreate ? s.emptyToCreate : null,
                  prefixIcon: const Icon(Icons.tag),
                  suffixIcon: IconButton(
                    key: const ValueKey('paste invite'),
                    icon: const Icon(Icons.content_paste),
                    onPressed: busy ? null : _paste,
                  ),
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _go(),
              ),
              const SizedBox(height: 16),
              if (_busy != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text(_busy!),
                  ],
                ),
              if (_error != null)
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFFFCC80)),
                ),
              // A server of your own.
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(s.server, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                children: [
                  TextField(
                    controller: _server,
                    enabled: !busy,
                    decoration: InputDecoration(hintText: 'ws://192.168.1.10:$gamePort/ws', helperText: s.serverHint),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // A browser that can't make direct connections can't host: Create Room greyed out, and why.
              if (creating && !_canCreate)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          s.cantHostInBrowser,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                        ),
                      ),
                      const HelpButton(section: GlossarySection.online, terms: [GlossaryTerm.hosting]),
                    ],
                  ),
                ),
              ValueListenableBuilder(
                valueListenable: AppSettings.of(context).rejoin,
                builder: (context, rejoin, _) {
                  // The room the app was in when it closed, while its seat may still be kept: the one
                  // button goes back to it when its code is in the box (a page that reloaded), else it
                  // has its own button.
                  final back = creating ? null : _rejoinFor(_code.text);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (rejoin != null && rejoin.fresh && back == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton.icon(
                            key: const ValueKey('rejoin'),
                            onPressed: busy ? null : () => _rejoin(rejoin),
                            icon: const Icon(Icons.replay),
                            label: Text(s.rejoinRoom(rejoin.code)),
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          ),
                        ),
                      // At the bottom: Create Room, or Join Room once there is a code.
                      FilledButton.icon(
                        key: const ValueKey('online go'),
                        onPressed: busy || (creating && !_canCreate) ? null : _go,
                        icon: Icon(creating ? Icons.add : (back != null ? Icons.replay : Icons.login)),
                        label: Text(creating ? s.createRoom : (back != null ? s.rejoinRoom(back.code) : s.joinRoom)),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
