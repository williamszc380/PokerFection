/// Inviting friends to a room, from the lobby and from the table (☰ >
/// Table): the invite to send, and for a room hosted on this device which
/// ways in work (and, in the lobby, the public address set by hand).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_settings.dart';
import '../../l10n/strings.dart';
import '../../online/invite.dart';
import '../../online/online_client.dart';
import '../../online/room_host.dart';
import '../glossary.dart';

/// Copies [text] and says so; false if not allowed (a browser on a host's
/// http page may refuse: the text is selectable to copy by hand then).
Future<bool> copyText(BuildContext context, String text) async {
  final s = S.of(context);
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } on Object {
    return false;
  }
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.copied)));
  return true;
}

/// The invite link to room [code] that [client] is in: the website's join
/// page, with every address to try (the host's local ones first). It opens
/// the app at the room, or the host's web version in a browser.
String siteInvite(OnlineClient client, String code) {
  final host = client.host;
  return siteInviteLink(code, host == null ? [client.url] : hostServers(host));
}

/// Shows the invite link to room [code] to copy, rebuilt as the router
/// setup goes on; for a room hosted here, with which ways in work.
Future<void> showInvite(BuildContext context, OnlineClient client, String code) {
  final s = S.of(context);
  final host = client.host;
  return showDialog<void>(
    context: context,
    builder: (context) => StreamBuilder<void>(
      stream: host?.changes,
      builder: (context, _) {
        final link = siteInvite(client, code);
        return AlertDialog(
          title: Text(s.invite),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(link),
                const SizedBox(height: 12),
                if (host != null)
                  WaysIn(host: host)
                // A server on this computer: friends elsewhere can't reach it.
                else if (isThisComputer(client.url))
                  Text(s.inviteThisComputer, style: const TextStyle(color: Color(0xFFFFCC80))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.close)),
            FilledButton.icon(
              icon: const Icon(Icons.link),
              label: Text(s.copyInviteLink),
              onPressed: () async {
                if (await copyText(context, link) && context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    ),
  );
}

/// Which ways into a room hosted on this device work: the same Wi-Fi (when
/// on a network) and the internet (once the router opened the port), with a
/// "?" on how to open the router by hand and what can stand in the way.
class WaysIn extends StatelessWidget {
  const WaysIn({super.key, required this.host});

  final RoomHost host;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return StreamBuilder<void>(
      stream: host.changes,
      builder: (context, _) {
        final wifi = host.localAddresses.isNotEmpty;
        final internet = host.internet;
        // The public address typed in the lobby, while the router isn't open (nothing can check it).
        final byHand = internet == InternetAccess.ready ? null : host.byHand;
        final setByHand = byHand != null && internet != InternetAccess.checking;
        Widget way(IconData icon, String text, Color color) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: theme.textTheme.bodySmall)),
          ],
        );
        const good = Color(0xFF81C784), bad = Color(0xFFFFCC80);
        final platform = defaultTargetPlatform;
        return Wrap(
          spacing: 16,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            way(wifi ? Icons.wifi : Icons.wifi_off, s.sameWifi(wifi), wifi ? good : bad),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: setByHand
                      ? way(Icons.public, s.internetByHand, Colors.white70)
                      : way(
                          switch (internet) {
                            InternetAccess.checking => Icons.hourglass_empty,
                            InternetAccess.ready => Icons.public,
                            _ => Icons.public_off,
                          },
                          s.internetStatus(internet),
                          switch (internet) {
                            InternetAccess.checking => Colors.white54,
                            InternetAccess.ready => good,
                            _ => bad,
                          },
                        ),
                ),
                HelpButton(
                  key: const ValueKey('internet help'),
                  section: GlossarySection.online,
                  terms: const [GlossaryTerm.hosting],
                  intro: s.internetHelp(
                    access: internet,
                    // Once open, the port outside (the router may have picked another); else the one
                    // to forward by hand.
                    port: internet == InternetAccess.ready ? host.publicEndpoint?.port ?? host.port : host.port,
                    address: host.localAddresses.firstOrNull,
                    byHand: byHand == null ? null : '${byHand.address}:${byHand.port}',
                    windows: platform == TargetPlatform.windows,
                    phone: platform == TargetPlatform.android || platform == TargetPlatform.iOS,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// For a room hosted on this device whose router isn't opened
/// automatically (no UPnP, or an iPhone): the public address the host types
/// (the router's, its port forwarded here by hand), kept for next time.
/// Invites then carry it. Hidden once the router opened the port.
class PublicAddressField extends StatefulWidget {
  const PublicAddressField({super.key, required this.host});

  final RoomHost host;

  @override
  State<PublicAddressField> createState() => _PublicAddressFieldState();
}

class _PublicAddressFieldState extends State<PublicAddressField> {
  /// What Create Room set from the settings ("address", or "address:port"
  /// when the port outside isn't this device's).
  late final _text = TextEditingController(
    text: switch (widget.host.byHand) {
      null => '',
      final b => b.port == widget.host.port ? b.address : '${b.address}:${b.port}',
    },
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Invites follow the box; an address (or an empty box) is saved.
  void _changed(String text) {
    final host = widget.host;
    final address = parsePublicAddress(text, port: host.port);
    host.byHand = address;
    final value = text.trim();
    final settings = AppSettings.of(context);
    if ((address != null || value.isEmpty) && settings.publicAddress != value) {
      settings.update((a) => a.publicAddress = value);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final host = widget.host;
    return StreamBuilder<void>(
      stream: host.changes,
      builder: (context, _) {
        if (host.internet == InternetAccess.ready) return const SizedBox.shrink();
        final value = _text.text.trim();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('public address'),
                    controller: _text,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: s.publicAddress,
                      hintText: '203.0.113.7',
                      prefixIcon: const Icon(Icons.public, size: 20),
                      errorText: value.isEmpty || host.byHand != null ? null : s.notPublicAddress,
                    ),
                    onChanged: _changed,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: HelpButton(
                    key: const ValueKey('public address help'),
                    section: GlossarySection.online,
                    terms: const [],
                    intro: s.publicAddressHelp(
                      port: host.port,
                      address: host.localAddresses.firstOrNull,
                      windows: defaultTargetPlatform == TargetPlatform.windows,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
