/// Inviting friends to a room, from the lobby and from the table (☰ >
/// Table): the invite to send, and for a room hosted on this device which
/// ways in work.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
/// page, with every way in to try (the host's local addresses first, then
/// the room through the meeting service, when it is there). It opens the
/// app at the room, or the website at the room to play in the browser.
String siteInvite(OnlineClient client, String code) {
  final host = client.host;
  return siteInviteLink(
    code,
    host == null ? guestServers(client.url, code, peer: client.atMeetingService) : hostServers(host, code),
    // The host's own web version, for browsers on its Wi-Fi.
    web: host?.servesWeb ?? false,
  );
}

/// Shows the invite link to room [code] to copy, rebuilt as the ways in
/// change (the meeting service, the router); for a room hosted here, with
/// which ways in work.
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
/// on a network) and the internet (the meeting service's status, with a
/// short reason when not available), with a "?" on how playing from
/// anywhere works and what can stand in the way. A room hosted in a browser
/// tab has no way in on the same Wi-Fi of its own: that line is greyed out,
/// and the "?" says to keep the tab open.
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
        final browser = host.inBrowser;
        final internet = host.internet;
        Widget way(IconData icon, String text, Color color, {bool greyed = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: greyed ? color : null)),
            ),
          ],
        );
        const good = Color(0xFF81C784), bad = Color(0xFFFFCC80), off = Colors.white38;
        final platform = defaultTargetPlatform;
        return Wrap(
          spacing: 16,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            KeyedSubtree(
              key: const ValueKey('same wifi'),
              child: browser
                  ? way(Icons.wifi_off, s.sameWifiAppOnly, off, greyed: true)
                  : way(wifi ? Icons.wifi : Icons.wifi_off, s.sameWifi(wifi), wifi ? good : bad),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: KeyedSubtree(
                    key: const ValueKey('internet status'),
                    child: way(
                      switch (internet.phase) {
                        PeerPhase.starting => Icons.hourglass_empty,
                        PeerPhase.ready => Icons.public,
                        PeerPhase.unavailable => Icons.public_off,
                      },
                      s.internetStatus(internet),
                      switch (internet.phase) {
                        PeerPhase.starting => Colors.white54,
                        PeerPhase.ready => good,
                        PeerPhase.unavailable => bad,
                      },
                    ),
                  ),
                ),
                HelpButton(
                  key: const ValueKey('internet help'),
                  section: GlossarySection.online,
                  terms: const [GlossaryTerm.hosting],
                  intro: s.internetHelp(
                    status: internet,
                    windows: !browser && platform == TargetPlatform.windows,
                    phone: !browser && (platform == TargetPlatform.android || platform == TargetPlatform.iOS),
                    browser: browser,
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
