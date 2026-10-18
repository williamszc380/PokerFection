/// Opening a port in the home router with UPnP (Internet Gateway Device),
/// so friends on the internet can also reach a room hosted on this device
/// at the router's public address: a second way in, behind the direct
/// connections (PeerHost), for guests whose network can't connect directly.
/// It runs silently: nobody is ever asked to set up a router.
/// Plain dart:io, no packages:
/// 1. find the router: SSDP, an M-SEARCH to 239.255.255.250:1900;
/// 2. read its description (XML) for the WANIPConnection (or
///    WANPPPConnection) service's control address;
/// 3. ask it with SOAP over HTTP: AddPortMapping, GetExternalIPAddress,
///    and DeletePortMapping when done.
///
/// Every step is best effort: a router without UPnP, or with it off, just
/// means no second way in (direct connections and same-network play don't
/// need any of this).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../online/addresses.dart';

export '../online/addresses.dart' show isPrivateAddress, isPublicAddress;

/// A router that can open ports, found on the local network.
class Gateway {
  Gateway._(this.control, this.service, this.localAddress);

  /// Where its port mapping service answers.
  final Uri control;

  /// The service type, as the router named it (urn:...:WANIPConnection:1).
  final String service;

  /// This device's address on the router's network (where ports lead).
  final String localAddress;

  /// The first router that answers within [wait], or null. Asks from each
  /// of [fromAddresses] too (this device's addresses: the router may be on
  /// any of its networks; ports lead to the one on the router's).
  static Future<Gateway?> find({
    List<String> fromAddresses = const [],
    Duration wait = const Duration(milliseconds: 2500),
  }) async {
    for (final location in await _search(fromAddresses, wait)) {
      try {
        final description = await _get(location);
        for (final (:service, :control) in gatewayServices(description, location)) {
          final local = await _localAddressTowards(control, fromAddresses);
          if (local != null) return Gateway._(control, service, local);
        }
      } on Object {
        // Not a router after all, or it didn't answer: try the next one.
      }
    }
    return null;
  }

  /// Maps [externalPort] on the router to [internalPort] on this device,
  /// for [lease] (zero: until taken away). Throws [UpnpError].
  Future<void> addPortMapping({
    required int externalPort,
    required int internalPort,
    required Duration lease,
    String description = 'PokerFection',
  }) => _call('AddPortMapping', {
    'NewRemoteHost': '',
    'NewExternalPort': '$externalPort',
    'NewProtocol': 'TCP',
    'NewInternalPort': '$internalPort',
    'NewInternalClient': localAddress,
    'NewEnabled': '1',
    'NewPortMappingDescription': description,
    'NewLeaseDuration': '${lease.inSeconds}',
  });

  /// Takes the mapping of [externalPort] away. Throws [UpnpError].
  Future<void> deletePortMapping(int externalPort) =>
      _call('DeletePortMapping', {'NewRemoteHost': '', 'NewExternalPort': '$externalPort', 'NewProtocol': 'TCP'});

  /// Whether the router has a mapping of [externalPort]; null if it can't
  /// say.
  Future<bool?> hasPortMapping(int externalPort) async {
    try {
      await _call('GetSpecificPortMappingEntry', {
        'NewRemoteHost': '',
        'NewExternalPort': '$externalPort',
        'NewProtocol': 'TCP',
      });
      return true;
    } on UpnpError catch (e) {
      return e.code == UpnpError.noSuchEntry ? false : null;
    }
  }

  /// The router's own address on the internet (as it says). Throws
  /// [UpnpError].
  Future<String?> externalAddress() async =>
      soapValue(await _call('GetExternalIPAddress', const {}), 'NewExternalIPAddress');

  /// Calls [action] with [arguments]; returns the answer (XML).
  Future<String> _call(String action, Map<String, String> arguments) async {
    final body = StringBuffer()
      ..write('<?xml version="1.0"?>')
      ..write(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>',
      )
      ..write('<u:$action xmlns:u="$service">');
    for (final MapEntry(:key, :value) in arguments.entries) {
      body.write('<$key>${_escape(value)}</$key>');
    }
    body.write('</u:$action></s:Body></s:Envelope>');
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.postUrl(control).timeout(_timeout);
      final bytes = utf8.encode(body.toString());
      request.headers
        ..set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"')
        ..set('SOAPAction', '"$service#$action"');
      // Its length up front: routers don't read a body sent in chunks (the
      // action then seems to come without its arguments).
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(_timeout);
      final text = await _read(response);
      if (response.statusCode == HttpStatus.ok) return text;
      throw UpnpError(int.tryParse(soapValue(text, 'errorCode') ?? '') ?? response.statusCode);
    } on UpnpError {
      rethrow;
    } on Object catch (e) {
      throw UpnpError(0, '$e');
    } finally {
      client.close(force: true);
    }
  }
}

/// How opening a port in the router went.
enum RouterSetup {
  /// Open, at a public address: friends on the internet can come in.
  ready,

  /// No router answered (none with UPnP, or it is off).
  noRouter,

  /// The router said no.
  refused,

  /// The router has no public address of its own: the internet provider
  /// shares one (CGNAT), or there is a second router in front of it.
  notPublic,
}

/// A port this device opened in the router, kept open (the lease renewed)
/// until [close].
class OpenPort {
  OpenPort._(this.gateway, this.externalPort, this.internalPort, this.externalAddress, this._lease, this._random) {
    // Renewed well before it runs out (a lease of zero never does).
    if (_lease > Duration.zero) {
      _renewal = Timer.periodic(_lease ~/ 3, (_) => unawaited(_renew()));
    }
  }

  final Gateway gateway;
  final int internalPort;

  /// Friends come in at the router's public address, [externalAddress], on
  /// [externalPort]. The port may change while open (see [onMoved]).
  final String externalAddress;
  int externalPort;

  /// Told when [externalPort] changes: on a router that won't renew a
  /// mapping, another port opens before the first runs out.
  void Function()? onMoved;

  final Duration _lease;
  final Random _random;
  Timer? _renewal;
  bool _closed = false;

  /// Ports opened before [externalPort] (the router wouldn't renew them):
  /// left until they run out, for friends who came in there, then closed
  /// with the rest.
  final List<int> _older = [];

  /// The lease asked for: short enough that a mapping left behind (the app
  /// was killed) goes away by itself, renewed every third of it.
  static const lease = Duration(hours: 1);

  /// Opens [port] (TCP) in the router towards this device: at the same port
  /// outside if free, else at one of the next few, else at a few others
  /// picked at random. Returns the open port, or null and why not.
  static Future<(OpenPort?, RouterSetup)> open(
    int port, {
    List<String> fromAddresses = const [],
    Random? random,
  }) async {
    final gateway = await Gateway.find(fromAddresses: fromAddresses);
    if (gateway == null) return (null, RouterSetup.noRouter);
    final pick = random ?? Random();
    final mapped = await _map(gateway, port, [
      for (var i = 0; i < 4; i++) port + i,
      for (var i = 0; i < 4; i++) _randomPort(port, pick),
    ], OpenPort.lease);
    if (mapped == null) return (null, RouterSetup.refused);
    String? address;
    try {
      address = await gateway.externalAddress();
    } on UpnpError {
      address = null;
    }
    if (address == null || !isPublicAddress(address)) {
      try {
        await gateway.deletePortMapping(mapped.port);
      } on UpnpError {
        // It runs out by itself.
      }
      return (null, RouterSetup.notPublic);
    }
    return (OpenPort._(gateway, mapped.port, port, address, mapped.lease, pick), RouterSetup.ready);
  }

  /// Maps the first of [outside] the router takes to [port] on this device,
  /// for [lease], and checks it kept the mapping. Null if none worked, or
  /// the router refuses (anything but "taken").
  static Future<({int port, Duration lease})?> _map(
    Gateway gateway,
    int port,
    List<int> outside,
    Duration lease,
  ) async {
    for (var i = 0; i < outside.length; i++) {
      final external = outside[i];
      try {
        await gateway.addPortMapping(externalPort: external, internalPort: port, lease: lease);
        // Some routers say yes without keeping it (one seen does so for a
        // port that was opened and closed before): another port then.
        if (await gateway.hasPortMapping(external) != false) return (port: external, lease: lease);
      } on UpnpError catch (e) {
        if (e.code == UpnpError.permanentOnly && lease > Duration.zero) {
          // This router only keeps mappings until taken away: ask again so.
          lease = Duration.zero;
          i--;
        } else if (e.code != UpnpError.conflict) {
          // Taken (by another device, or left over) is worth another port; nothing else is.
          return null;
        }
      }
    }
    return null;
  }

  /// A port outside picked at random, above the next few.
  static int _randomPort(int port, Random random) => port + 26 + random.nextInt(1500);

  /// Renews the mapping. A router that won't (one seen says it conflicts
  /// with itself) gets another port, before this one runs out.
  Future<void> _renew() async {
    try {
      await gateway.addPortMapping(externalPort: externalPort, internalPort: internalPort, lease: _lease);
      return;
    } on UpnpError {
      // Another port, below.
    }
    final moved = await _map(gateway, internalPort, [
      for (var i = 0; i < 4; i++) _randomPort(internalPort, _random),
    ], _lease);
    if (moved == null) return;
    if (_closed) {
      await _delete(moved.port);
      return;
    }
    _older.add(externalPort);
    externalPort = moved.port;
    onMoved?.call();
  }

  /// Closes the ports again (best effort).
  Future<void> close() async {
    _closed = true;
    _renewal?.cancel();
    _renewal = null;
    await Future.wait([for (final port in {..._older, externalPort}) _delete(port)]);
  }

  Future<void> _delete(int port) async {
    try {
      await gateway.deletePortMapping(port).timeout(const Duration(seconds: 3));
    } on Object {
      // It runs out by itself (or stays, on a router that keeps them).
    }
  }
}

/// The router refused (with a UPnP error code: 718 the port is taken, 725
/// only leases without an end, ...), or didn't answer (code 0).
class UpnpError implements Exception {
  const UpnpError(this.code, [this.detail]);
  final int code;
  final String? detail;

  static const noSuchEntry = 714;
  static const conflict = 718;
  static const samePortsOnly = 724;
  static const permanentOnly = 725;

  @override
  String toString() => 'UpnpError($code${detail == null ? '' : ': $detail'})';
}

const _timeout = Duration(seconds: 4);

/// The kinds of answer asked for: routers answer to one or another.
const _searchTargets = [
  'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
  'urn:schemas-upnp-org:device:InternetGatewayDevice:2',
  'urn:schemas-upnp-org:service:WANIPConnection:1',
  'urn:schemas-upnp-org:service:WANPPPConnection:1',
];

/// The description addresses of every router that answered the search
/// (in the order they answered).
Future<List<Uri>> _search(List<String> fromAddresses, Duration wait) async {
  final found = <Uri>[];
  final sockets = <RawDatagramSocket>[];
  final multicast = InternetAddress('239.255.255.250');
  final firstAnswer = Completer<void>();
  for (final from in ['0.0.0.0', ...fromAddresses]) {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress(from), 0);
      sockets.add(socket);
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final location = ssdpLocation(utf8.decode(datagram.data, allowMalformed: true));
        if (location != null && !found.contains(location)) {
          found.add(location);
          if (!firstAnswer.isCompleted) firstAnswer.complete();
        }
      });
    } on Object {
      // That network can't be searched from here.
    }
  }
  void send() {
    for (final socket in sockets) {
      for (final target in _searchTargets) {
        final message =
            'M-SEARCH * HTTP/1.1\r\n'
            'HOST: 239.255.255.250:1900\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: $target\r\n\r\n';
        try {
          socket.send(utf8.encode(message), multicast, 1900);
        } on Object {
          // No route that way.
        }
      }
    }
  }

  // Twice, as UDP may be lost.
  send();
  final again = Timer(const Duration(milliseconds: 600), send);
  try {
    // Once one answered, a moment more for others.
    await firstAnswer.future.timeout(wait);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  } on TimeoutException {
    // Nobody answered.
  }
  again.cancel();
  for (final socket in sockets) {
    socket.close();
  }
  return found;
}

/// The description address in an SSDP answer, if it is a plain http one on
/// the local network (anything else is ignored).
Uri? ssdpLocation(String answer) {
  final lines = answer.split(RegExp(r'\r?\n'));
  if (lines.isEmpty || !lines.first.toUpperCase().startsWith('HTTP/1.')) return null;
  for (final line in lines.skip(1)) {
    final colon = line.indexOf(':');
    if (colon < 0 || line.substring(0, colon).trim().toUpperCase() != 'LOCATION') continue;
    final uri = Uri.tryParse(line.substring(colon + 1).trim());
    if (uri == null || uri.scheme != 'http' || !isPrivateAddress(uri.host)) return null;
    return uri;
  }
  return null;
}

/// The port mapping services in a router's description ([location] is
/// where it came from), WANIPConnection ones first.
List<({String service, Uri control})> gatewayServices(String description, Uri location) {
  final base = Uri.tryParse(_tag(description, 'URLBase') ?? '') ?? location;
  final services = <({String service, Uri control})>[];
  for (final block in RegExp(r'<service>(.*?)</service>', dotAll: true, caseSensitive: false).allMatches(description)) {
    final type = _tag(block[1]!, 'serviceType');
    final control = _tag(block[1]!, 'controlURL');
    if (type == null || control == null) continue;
    if (!type.contains(':WANIPConnection:') && !type.contains(':WANPPPConnection:')) continue;
    services.add((service: type, control: (base.hasScheme ? base : location).resolve(control)));
  }
  services.sort((a, b) => (a.service.contains(':WANIPConnection:') ? 0 : 1) - (b.service.contains(':WANIPConnection:') ? 0 : 1));
  return services;
}

/// The text of the first <[tag]> in [xml] (namespace prefixes allowed),
/// unescaped; null if there is none.
String? soapValue(String xml, String tag) => _tag(xml, tag);

String? _tag(String xml, String tag) {
  final match = RegExp('<(?:\\w+:)?$tag(?:\\s[^>]*)?>(.*?)</(?:\\w+:)?$tag>', dotAll: true, caseSensitive: false)
      .firstMatch(xml);
  if (match == null) return null;
  return match[1]!
      .trim()
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

String _escape(String text) =>
    text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

Future<String> _get(Uri uri) async {
  final client = HttpClient()..connectionTimeout = _timeout;
  try {
    final response = await (await client.getUrl(uri).timeout(_timeout)).close().timeout(_timeout);
    if (response.statusCode != HttpStatus.ok) throw UpnpError(response.statusCode);
    return await _read(response);
  } finally {
    client.close(force: true);
  }
}

/// A router's answer, up to a sane size.
Future<String> _read(HttpClientResponse response) async {
  final bytes = <int>[];
  await for (final chunk in response.timeout(_timeout)) {
    bytes.addAll(chunk);
    if (bytes.length > 256 * 1024) throw const UpnpError(0, 'Answer too long');
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// This device's address on the router's network, where ports lead: the
/// first of [addresses] (this device's), nearest the router's address
/// first, that reaches the router at [uri]. (A socket can't tell its own
/// address: Socket.address is the one it connected to.)
Future<String?> _localAddressTowards(Uri uri, List<String> addresses) async {
  for (final address in nearestFirst(uri.host, addresses)) {
    try {
      final socket = await Socket.connect(
        uri.host,
        uri.port,
        sourceAddress: address,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return address;
    } on Object {
      // Not on the router's network.
    }
  }
  return null;
}

/// This device's local network [addresses] that may be on the network of
/// [router] (an IPv4 address), the most likely first: those sharing the
/// most leading bits with it (192.168.1.20 before 192.168.56.1 for a
/// router at 192.168.1.1).
List<String> nearestFirst(String router, List<String> addresses) {
  final r = ipv4Bytes(router);
  if (r == null) return const [];
  int shared(String address) {
    final b = ipv4Bytes(address)!;
    for (var i = 0; i < 4; i++) {
      final differ = b[i] ^ r[i];
      if (differ != 0) return i * 8 + 8 - differ.bitLength;
    }
    return 32;
  }

  return [
    for (final a in addresses)
      if (isPrivateAddress(a) && a != router) a,
  ]..sort((a, b) => shared(b) - shared(a));
}
