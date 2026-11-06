/// What a reader types for "where is my Tippani", turned into the address the app keeps.
///
/// A self-hosted server is reached at whatever the reader set up: `192.168.1.20:8124` on the home
/// network, `https://quotes.example.org` behind a proxy. The app keeps the origin only, with no
/// trailing slash and no `/api`: [apiBaseOf] adds that where requests are made.
library;

/// Returns the normalised origin, or null when [raw] cannot be an address.
///
/// A bare host or `host:port` takes `https://`, since a typed address with no scheme is far more
/// often a proxied domain than a LAN IP; a LAN address the reader types as `http://...` keeps it.
String? normaliseServerUrl(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  // The origin, and any path the server is mounted under, without `/api` and without a trailing slash.
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.endsWith('/api')) path = path.substring(0, path.length - 4);
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

/// The API root for a stored server address.
Uri apiBaseOf(String serverUrl) => Uri.parse('$serverUrl/api');

/// True when sending a token to this address would cross a network in the clear: plain `http` to a
/// host that is not this device or a private network address. The app warns before it pairs.
bool isRiskyCleartext(String serverUrl) {
  final uri = Uri.tryParse(serverUrl);
  if (uri == null || uri.scheme != 'http') return false;
  return !_isLocalHost(uri.host);
}

bool _isLocalHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' ||
      h == '10.0.2.2' ||
      h.endsWith('.local') ||
      h.endsWith('.lan') ||
      h.endsWith('.home.arpa')) {
    return true;
  }
  final parts = h.split('.');
  if (parts.length != 4) return false;
  final n = parts.map(int.tryParse).toList();
  if (n.any((x) => x == null || x < 0 || x > 255)) return false;
  final a = n[0]!;
  final b = n[1]!;
  return a == 10 ||
      a == 127 ||
      (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 169 && b == 254) ||
      // Tailscale and other carrier-grade-NAT ranges: private to the tailnet, not the open internet.
      (a == 100 && b >= 64 && b <= 127);
}
