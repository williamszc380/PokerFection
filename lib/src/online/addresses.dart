/// IPv4 addresses: which are a local network's, and which others can reach
/// from the internet. Plain Dart, for the router setup (server/upnp.dart)
/// and for the public address a host types by hand (any platform).
library;

/// Whether [address] is an IPv4 address of a local network (10/8,
/// 172.16/12, 192.168/16).
bool isPrivateAddress(String address) {
  final b = ipv4Bytes(address);
  if (b == null) return false;
  return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] < 32) || (b[0] == 192 && b[1] == 168);
}

/// Whether [address] is an IPv4 address others can reach from the
/// internet: not a local network's, not a shared one of the internet
/// provider (100.64/10, CGNAT), not this device's own or a special one.
bool isPublicAddress(String address) {
  final b = ipv4Bytes(address);
  if (b == null || isPrivateAddress(address)) return false;
  if (b[0] == 0 || b[0] == 127 || b[0] >= 224) return false;
  if (b[0] == 100 && b[1] >= 64 && b[1] < 128) return false;
  if (b[0] == 169 && b[1] == 254) return false;
  return true;
}

/// The 4 numbers of IPv4 [address]; null if it isn't one.
List<int>? ipv4Bytes(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return null;
  final bytes = [for (final p in parts) int.tryParse(p) ?? -1];
  return bytes.every((b) => b >= 0 && b <= 255) ? bytes : null;
}
