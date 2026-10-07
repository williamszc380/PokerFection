/// The room's chat, as the lobby and the table (☰ > Chat) show it: the
/// whole conversation, the quick messages, and a box to type in.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../online/online_client.dart';
import '../../online/protocol.dart';

/// One tap sends one of these, like any message.
const quickMessages = ['😂', '😭', '😡', '😱', '🤥', '🤡', '🍀', 'GG!'];

/// The chat: its messages (the newest at the bottom), the quick messages
/// and the box. Sending is greyed out while the connection is down, and
/// for a moment after a few messages at once (the server takes no more:
/// see OnlineClient.chatWait).
class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.client, this.height});

  final OnlineClient client;

  /// How high the messages are; null: all the height there is.
  final double? height;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  late final StreamSubscription<void> _changes;
  final _text = TextEditingController();

  /// Gives Send back once the wait is over.
  Timer? _wait;

  OnlineClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _changes = _client.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // Opened just after a few messages (sent from the lobby, say).
    _waitIfNeeded();
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    _wait?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (!_client.say(text)) return;
    if (text == _text.text) _text.clear();
    _waitIfNeeded();
    setState(() {});
  }

  /// After a few messages at once, Send comes back when the server takes
  /// more (the app counts them for every screen: see OnlineClient.say).
  void _waitIfNeeded() {
    _wait?.cancel();
    final wait = _client.chatWait;
    if (wait <= Duration.zero) return;
    _wait = Timer(wait, () {
      if (!mounted) return;
      setState(() {});
      _waitIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final lines = _client.chat;
    final open = _client.status == OnlineStatus.open;
    final waiting = _client.chatWait > Duration.zero;
    final canSend = open && !waiting;
    final length = _text.text.runes.length;
    final log = DecoratedBox(
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
      child: lines.isEmpty
          ? Center(
              child: Text(s.noMessages, style: const TextStyle(color: Colors.white38)),
            )
          : ListView.builder(
              // The newest at the bottom, where the view stays as messages come.
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: lines.length,
              itemBuilder: (context, i) => ChatLineText(line: lines[lines.length - 1 - i]),
            ),
    );
    final height = widget.height;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (height == null) Flexible(child: log) else SizedBox(height: height, child: log),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final quick in quickMessages)
                TextButton(
                  key: ValueKey('quick $quick'),
                  onPressed: canSend ? () => _send(quick) : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  // Emoji keep their colours when greyed out: faded instead.
                  child: Opacity(
                    opacity: canSend ? 1 : 0.38,
                    child: Text(
                      quick,
                      style: quick.runes.length == 1
                          ? const TextStyle(fontSize: 20)
                          : const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
        TextField(
          key: const ValueKey('chat box'),
          controller: _text,
          enabled: open,
          inputFormatters: [_ChatLimit()],
          textInputAction: TextInputAction.send,
          onChanged: (_) => setState(() {}),
          onSubmitted: canSend ? _send : null,
          // Stays open for the next message.
          onEditingComplete: () {},
          decoration: InputDecoration(
            hintText: s.chatHint,
            isDense: true,
            border: const OutlineInputBorder(),
            helperText: waiting ? s.chatTooFast : null,
            // Near the most a message can have.
            counterText: length >= chatMaxLength * 3 ~/ 4 ? '$length/$chatMaxLength' : null,
            suffixIcon: IconButton(
              key: const ValueKey('send'),
              tooltip: s.send,
              icon: const Icon(Icons.send),
              onPressed: canSend && cleanChat(_text.text) != null ? () => _send(_text.text) : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// One chat message: who said it (the user's own name lit up) and what.
class ChatLineText extends StatelessWidget {
  const ChatLineText({super.key, required this.line, this.maxLines, this.textAlign});

  final ChatLine line;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${line.name}: ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: line.you ? const Color(0xFFFFE082) : const Color(0xFF90CAF9),
              ),
            ),
            TextSpan(
              text: line.text,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        textAlign: textAlign,
      ),
    );
  }
}

/// Keeps what is typed within [chatMaxLength] characters, as the server
/// counts them.
class _ChatLimit extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final runes = newValue.text.runes;
    if (runes.length <= chatMaxLength) return newValue;
    final text = String.fromCharCodes(runes.take(chatMaxLength));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
