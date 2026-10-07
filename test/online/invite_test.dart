import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/online/invite.dart';
import 'package:pokerfection/src/server/upnp.dart';

/// [invite] is room [code], with [servers] in that order.
void expectInvite(Invite? invite, String code, List<String> servers) {
  expect(invite?.code, code);
  expect(invite?.servers, servers);
}

void main() {
  test('invites carry every address of the host, in order, and read back from app and browser links', () {
    const local = 'ws://192.168.1.20:47474/ws', public = 'ws://203.0.113.7:47475/ws';
    final link = inviteLink('K7M2Q', [local, public]);
    expect(link, 'pokerfection://join?code=K7M2Q&server=192.168.1.20%3A47474&server=203.0.113.7%3A47475');
    final message =
        'Join my PokerFection table, room K7M2Q.\nIn the app: $link\n'
        'In a browser on the same Wi-Fi: ${browserLink('K7M2Q', '192.168.1.20', 47474)}';
    expectInvite(parseInvite(message), 'K7M2Q', [local, public]);
    // A server of one's own keeps its whole address.
    expectInvite(parseInvite(inviteLink('ABCDE', ['wss://poker.example.org/play'])), 'ABCDE', [
      'wss://poker.example.org/play',
    ]);
    // The browser address alone: the room on the host that serves the page.
    expectInvite(parseInvite('http://192.168.1.20:47474/?code=k7m2q'), 'K7M2Q', [local]);
    expectInvite(
      inviteFromPage(Uri.parse('https://williamszc380.github.io/PokerFection/?code=ABCDE')),
      'ABCDE',
      <String>[],
    );
    // A bare code, as typed; and the route Android and iOS hand the app.
    expectInvite(parseInvite(' abcde '), 'ABCDE', <String>[]);
    expectInvite(inviteFromUri(Uri.parse('/?code=ABCDE&server=10.0.0.5:47474')), 'ABCDE', ['ws://10.0.0.5:47474/ws']);
    expect(parseInvite('hello'), isNull);
    expect(isThisComputer('ws://127.0.0.1:47474/ws'), isTrue);
    expect(isThisComputer(local), isFalse);
  });

  test("a public address typed by hand: the port defaults to the room's; local addresses are refused", () {
    expect(parsePublicAddress(' 203.0.113.7 ', port: 47475), (address: '203.0.113.7', port: 47475));
    expect(parsePublicAddress('203.0.113.7:47500', port: 47474), (address: '203.0.113.7', port: 47500));
    expect(parsePublicAddress('http://203.0.113.7:47474/health', port: 47474), (address: '203.0.113.7', port: 47474));
    expect(parsePublicAddress('MyHome.duckdns.org', port: 47474), (address: 'myhome.duckdns.org', port: 47474));
    for (final wrong in ['', '203.0.113', '192.168.1.20', '100.72.1.1', 'localhost', '203.0.113.7:99999', 'a b']) {
      expect(parsePublicAddress(wrong, port: 47474), isNull, reason: wrong);
    }
  });

  test("the router's answers are read: where its description is, its port service, and public addresses", () {
    expect(
      ssdpLocation(
        'HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=120\r\nLocation: http://192.168.1.1:5000/rootDesc.xml\r\n'
        'ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n',
      ),
      Uri.parse('http://192.168.1.1:5000/rootDesc.xml'),
    );
    // Only plain http on the local network is followed.
    expect(ssdpLocation('HTTP/1.1 200 OK\r\nLOCATION: http://203.0.113.9/desc.xml\r\n\r\n'), isNull);
    const description = '''<?xml version="1.0"?><root><device><serviceList>
      <service><serviceType>urn:schemas-upnp-org:service:Layer3Forwarding:1</serviceType>
        <controlURL>/ctl/L3F</controlURL></service></serviceList><deviceList><device><serviceList>
      <service><serviceType>urn:schemas-upnp-org:service:WANPPPConnection:1</serviceType>
        <controlURL>/ctl/PPP</controlURL></service>
      <service><serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>
        <controlURL>/ctl/IPConn</controlURL></service></serviceList></device></deviceList></device></root>''';
    final services = gatewayServices(description, Uri.parse('http://192.168.1.1:5000/rootDesc.xml'));
    expect(
      [for (final s in services) s.control.toString()],
      ['http://192.168.1.1:5000/ctl/IPConn', 'http://192.168.1.1:5000/ctl/PPP'],
    );
    expect(
      soapValue(
        '<s:Body><u:GetExternalIPAddressResponse><NewExternalIPAddress>203.0.113.7</NewExternalIPAddress>',
        'NewExternalIPAddress',
      ),
      '203.0.113.7',
    );
    expect(
      soapValue('<s:Fault><detail><UPnPError><errorCode>718</errorCode></UPnPError></detail>', 'errorCode'),
      '718',
    );
    expect(
      [
        for (final a in ['203.0.113.7', '192.168.1.1', '10.1.2.3', '172.20.0.1', '100.72.1.1', '127.0.0.1'])
          isPublicAddress(a),
      ],
      [true, false, false, false, false, false],
    );
    // Ports lead to this device's address on the router's network (never the router's own).
    expect(nearestFirst('192.168.1.1', ['192.168.56.1', '10.0.0.4', '192.168.1.167', '192.168.1.1']), [
      '192.168.1.167',
      '192.168.56.1',
      '10.0.0.4',
    ]);
    expect(nearestFirst('10.0.0.1', ['192.168.1.20', '10.0.0.37']).first, '10.0.0.37');
  });
}
