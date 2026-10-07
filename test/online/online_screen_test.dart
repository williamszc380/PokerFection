import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/online/memory_link.dart';
import 'package:pokerfection/src/online/online_client.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/online/online_screen.dart';

void main() {
  // A browser page that reloads (or an app opened again with the invite) comes back to Play Online with the
  // room's code: the one button takes the player back to their seat, rather than seating them a second time.
  testWidgets('with the code of the room this device was just in, the one button rejoins it', (tester) async {
    final settings = AppSettings()..nickname = 'Ben';
    settings.remember(
      RejoinRecord(
        server: 'ws://192.168.1.20:47474/ws',
        code: 'K7M2Q',
        token: 'secret',
        savedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final opened = <String>[];
    MemoryLink? server;
    await tester.pumpWidget(
      AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          home: OnlineScreen(
            invite: (code: 'K7M2Q', servers: const ['ws://192.168.1.20:47474/ws']),
            connect: (url) async {
              final (s, device) = MemoryLink.pair();
              server = s;
              s.messages.listen(opened.add);
              return device;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Rejoin Room K7M2Q'), findsOneWidget, reason: 'the one button, and no second one');
    expect(find.text('Join Room'), findsNothing);

    // Another code: the button joins; the kept seat has its own button.
    await tester.enterText(find.byKey(const ValueKey('online code')), 'ABCDE');
    await tester.pump();
    expect(find.text('Join Room'), findsOneWidget);
    expect(find.text('Rejoin Room K7M2Q'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('online code')), 'K7M2Q');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('online go')));
    await tester.pump();
    final message = ClientMessage.decode(opened.single);
    expect(message, isA<RejoinRoom>().having((m) => m.token, 'token', 'secret').having((m) => m.code, 'code', 'K7M2Q'));

    // Away too long: the seat is gone, the record is forgotten, and the button joins again.
    server!.send(const ServerError(JoinError.seatGone).encode());
    await tester.pump();
    await tester.pump();
    expect(find.text('Join Room'), findsOneWidget);
    expect(settings.rejoin.value, isNull);
  });
}
