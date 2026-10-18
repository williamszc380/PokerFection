import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/online/invite.dart';
import 'package:pokerfection/src/online/peer_config.dart';
import 'package:pokerfection/src/online/room_host.dart';
import 'package:pokerfection/src/server/upnp.dart';

import 'fake_room_host.dart';

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
    // The website's join page (the link copied by default) carries the same servers.
    final site = siteInviteLink('K7M2Q', [local, public]);
    expect(site, startsWith('$inviteSite' 'join.html?code=K7M2Q&server='));
    expectInvite(parseInvite('Come play: $site'), 'K7M2Q', [local, public]);
    // A bare code, as typed; and the route Android and iOS hand the app.
    expectInvite(parseInvite(' abcde '), 'ABCDE', <String>[]);
    expectInvite(inviteFromUri(Uri.parse('/?code=ABCDE&server=10.0.0.5:47474')), 'ABCDE', ['ws://10.0.0.5:47474/ws']);
    expect(parseInvite('hello'), isNull);
    expect(isThisComputer('ws://127.0.0.1:47474/ws'), isTrue);
    expect(isThisComputer(local), isFalse);
  });

  test('an invite to a room hosted here names its addresses on the same Wi-Fi, then the room through the meeting '
      "service, then the router's public address once the router opened the port by itself", () async {
    final net = FakeInternet();
    final host = await TestRoomHost.start(net, code: 'K7M2Q', localAddresses: ['192.168.1.20', '10.0.0.5']);
    expect(host.peerCode, 'K7M2Q');
    expect(hostServers(host, 'K7M2Q'), ['ws://192.168.1.20:47474/ws', 'ws://10.0.0.5:47474/ws', 'peer:K7M2Q']);
    // The silent backup: friends whose network can't connect directly may still come in there.
    host.routerEndpoint = (address: '203.0.113.7', port: 47475);
    final servers = hostServers(host, 'K7M2Q');
    expect(servers, [
      'ws://192.168.1.20:47474/ws',
      'ws://10.0.0.5:47474/ws',
      'peer:K7M2Q',
      'ws://203.0.113.7:47475/ws',
    ]);
    expectInvite(parseInvite(siteInviteLink('K7M2Q', servers)), 'K7M2Q', servers);
    // A host that serves its own web version says so: the join page then offers its addresses to browsers too
    // (on the same Wi-Fi they need no internet), after the website.
    final withWeb = siteInviteLink('K7M2Q', servers, web: true);
    expect(Uri.parse(withWeb).queryParameters['web'], '1');
    expect(Uri.parse(siteInviteLink('K7M2Q', servers)).queryParameters, isNot(contains('web')));
    expectInvite(parseInvite(withWeb), 'K7M2Q', servers);
    await host.stop();
  });

  test('an invite never names an all-digit room code through the meeting service in a form older apps read as a '
      'server (rooms never get such codes)', () {
    // An older app's reading of an invite entry (as released): "address:port", or a whole ws:// address.
    String? olderApp(String value) {
      final url = value.contains('://') ? value : 'ws://$value/ws';
      final uri = Uri.tryParse(url);
      return uri == null || uri.host.isEmpty || (uri.scheme != 'ws' && uri.scheme != 'wss') ? null : url;
    }

    expect(olderApp('peer:K7M2Q'), isNull);
    expect(olderApp('peer:2345A'), isNull);
    expect(olderApp('peer:23456'), isNotNull, reason: 'why rooms never get all-digit codes (see room_test)');
  });

  test('a code someone else holds at the meeting service is never named: the invite would lead to their '
      'room', () async {
    final net = FakeInternet();
    await net.broker.connect('$peerBroker?id=${hostPeerId('K7M2Q')}&token=someoneelse');
    final host = await TestRoomHost.start(net, code: 'K7M2Q');
    expect(host.internet, const PeerStatus.unavailable(PeerTrouble.codeTaken));
    expect(host.peerCode, isNull);
    expect(hostServers(host, 'K7M2Q'), ['ws://192.168.1.20:47474/ws']);
    await host.stop();
  });

  test("a guest's invite names where the guest reached the room, then the room through the meeting service only "
      "when the host said the room is there; a room on a server of its own, or whose host holds no name at the "
      "meeting service, is never named there (the name could be anyone's)", () {
    expect(guestServers('ws://192.168.1.20:47474/ws', 'K7M2Q', peer: true), [
      'ws://192.168.1.20:47474/ws',
      'peer:K7M2Q',
    ]);
    expect(guestServers('peer:K7M2Q', 'K7M2Q', peer: true), ['peer:K7M2Q']);
    expect(guestServers('wss://poker.example.org/ws', 'K7M2Q', peer: false), ['wss://poker.example.org/ws']);
    expect(guestServers('ws://192.168.1.20:47474/ws', 'K7M2Q', peer: false), ['ws://192.168.1.20:47474/ws']);
  });

  test("the website opens at a room from the join page's link (the room through the meeting service), and a page "
      'there tries no plain ws:// address (the browser refuses those on a secure page); a page from a host keeps them',
      () {
    expectInvite(
      inviteFromPage(Uri.parse('https://williamszc380.github.io/PokerFection/?code=K7M2Q&server=peer%3AK7M2Q')),
      'K7M2Q',
      ['peer:K7M2Q'],
    );
    expectInvite(inviteFromPage(Uri.parse('https://williamszc380.github.io/PokerFection/?code=K7M2Q')), 'K7M2Q', []);
    const servers = ['ws://192.168.1.20:47474/ws', 'peer:K7M2Q', 'wss://pf.example.com/ws', 'ws://203.0.113.7:47475/ws'];
    expect(reachableFromPage(servers, Uri.parse('https://williamszc380.github.io/PokerFection/')), [
      'peer:K7M2Q',
      'wss://pf.example.com/ws',
    ]);
    expect(reachableFromPage(servers, Uri.parse('http://192.168.1.20:47474/?code=K7M2Q')), servers);
    expect(reachableFromPage(servers, Uri.parse('http://localhost:8080/')), servers);
  });

  test("the router's answers are read: where its description is, its port service, and whether its address is "
      'really public (a shared one leads nowhere)', () {
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
