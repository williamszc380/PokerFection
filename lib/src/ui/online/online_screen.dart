import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_settings.dart';
import '../../app/keep_awake.dart';
import '../../l10n/strings.dart';
import '../../online/host_here.dart';
import '../../online/invite.dart';
import '../../online/online_client.dart';
import '../../online/online_socket.dart';
import '../../online/protocol.dart';
import '../../online/room_host.dart';
import '../glossary.dart';
import 'lobby_screen.dart';

/// Play Online: the player's name and a room code or invite link, then one
/// button at the bottom: Create Room while the code is empty, Join Room once
/// there is one.
///
/// Create Room runs the room on this device (the game server inside the
/// app); the web version can't, so there it only joins. Join Room tries the
/// invite's addresses in order (the host's on the same network first), else
/// looks for the room on the local network. An invite (a link that opened
/// the app, or one pasted) fills in the code and the addresses. The server
/// can be set by hand (a server of your own, see bin/server.dart): then
/// rooms are created and joined there.
///
/// When the app closed (or the page reloaded) during a game, Rejoin Room
/// takes the player back to their seat, if the room kept it.
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key, this.connect, this.invite});

  /// The invite the app was opened with.
  final Invite? invite;

  /// Opens the connection to the server (a WebSocket by default).
  final Future<OnlineSocket> Function(String url)? connect;

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
    if (widget.invite case final invite?) _useInvite(invite);
  }

  void _useInvite(Invite invite) {
    _invite = invite;
    _code.text = invite.code;
  }

  /// A room is created on the server set by hand, else on this device.
  bool get _canCreate => canHostHere || _server.text.trim().isNotEmpty;

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

  /// Opens [client] with [opening], then goes to the lobby. [unreachable]
  /// says why when no server could be reached, if there is more to say.
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
          _error = e.error == null && unreachable != null ? unreachable : s.joinError(e.error);
        });
      }
      return;
    }
    if (!mounted) {
      unawaited(client.close());
      return;
    }
    setState(() => _busy = null);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LobbyScreen(client: client)));
  }

  /// Creates a room: on the server set by hand, else on this device (the
  /// game server starts inside the app, and this app joins it).
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
      );
    }
    setState(() {
      _busy = s.startingRoom;
      _error = null;
    });
    final RoomHost host;
    try {
      host = await hostHere();
    } on Object {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = s.cantStartRoom;
        });
      }
      return;
    }
    _whileHosting(host);
    if (!mounted) {
      unawaited(host.stop());
      return;
    }
    // The public address typed last time (for a router that isn't opened automatically).
    host.byHand = parsePublicAddress(AppSettings.of(context).publicAddress, port: host.port);
    await _open(OnlineClient(host.ownServer, host: host, connect: widget.connect), CreateRoom(name: name));
  }

  /// While [host] serves the room: the screen stays on and the Wi-Fi's
  /// broadcasts are heard (phones), and closing the app closes the room
  /// properly (everyone is told, the router's port closes).
  void _whileHosting(RoomHost host) {
    unawaited(keepScreenOn(true));
    unawaited(hearRoomSearches(true));
    final exit = AppLifecycleListener(
      onExitRequested: () async {
        try {
          await host.stop().timeout(const Duration(seconds: 2));
        } on Object {
          // Closing anyway.
        }
        return AppExitResponse.exit;
      },
    );
    unawaited(
      host.stopped.whenComplete(() {
        exit.dispose();
        unawaited(keepScreenOn(false));
        unawaited(hearRoomSearches(false));
      }),
    );
  }

  /// Joins the room in the code box (a code, or an invite link): at the
  /// invite's addresses in order, at the server set by hand, at the host
  /// that served this page (web), else wherever the room is found on the
  /// local network; last, a room on this computer.
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
    final servers = [
      ...known.servers,
      if (override.isNotEmpty) override,
      if (kIsWeb) ?pageServer(Uri.base),
    ];
    String? unreachable;
    if (kIsWeb && Uri.base.scheme == 'https') {
      // The website may not reach a room on someone's device (the browser
      // blocks it): the host's own browser address can.
      unreachable = s.websiteCantJoin;
    } else if (servers.isEmpty) {
      servers.addAll(await findRoomNearby(invite.code));
      if (servers.isEmpty) unreachable = s.roomNotNearby;
    }
    servers.add('ws://127.0.0.1:$gamePort/ws');
    if (!mounted) return;
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
  /// long (else why not, and the room is forgotten).
  Future<void> _rejoin(RejoinRecord record) {
    setState(() {
      _busy = S.of(context).connecting;
      _error = null;
    });
    return _open(
      OnlineClient(record.server, onRecord: AppSettings.of(context).remember, connect: widget.connect),
      RejoinRoom(code: record.code, token: record.token),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final busy = _busy != null;
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
              if (busy)
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
              // A browser can't host: Create Room greyed out, and why.
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
