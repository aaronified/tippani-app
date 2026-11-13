/// The version handshake with a Tippani server.
///
/// An installed app and the server on a NAS update on separate schedules, so one is sooner or later
/// older than the other. `GET /capabilities` needs no credential and answers an `api_revision`
/// integer, so the app can say so plainly before it holds a token instead of failing halfway through
/// a save (Tippani ADR-0931 records why this check carries the contract between two repositories).
library;

/// The API revision this build of the app was written against. Raise it when the app starts
/// depending on something a later revision added.
const int builtForRevision = 9;

/// The oldest server revision this app still works with. Device tokens and pairing arrived in
/// revision 1; raise it as screens come to need more, and the app will refuse an older server by
/// name rather than call a route it does not have.
const int minServerRevision = 1;

class Capabilities {
  const Capabilities({
    required this.version,
    required this.apiRevision,
    required this.minClientRevision,
    required this.features,
  });

  /// The server's own version string, for display.
  final String version;

  /// Increments when the API gains something a client can depend on.
  final int apiRevision;

  /// The oldest client revision the server still serves correctly.
  final int minClientRevision;

  /// Named capabilities, stable once published, so a screen can light up or hide on a string rather
  /// than probing for a 404.
  final Set<String> features;

  bool has(String feature) => features.contains(feature);

  /// Reads the server's JSON. Returns null for anything that is not a capabilities answer, so a web
  /// page or some other service at that address is "not a Tippani server" and not a crash.
  static Capabilities? fromJson(Object? json) {
    if (json is! Map) return null;
    final revision = json['api_revision'];
    if (revision is! int) return null;
    final min = json['min_client_revision'];
    final features = json['features'];
    return Capabilities(
      version: json['version'] is String ? json['version'] as String : '',
      apiRevision: revision,
      minClientRevision: min is int ? min : 1,
      features: features is List
          ? features.whereType<String>().toSet()
          : <String>{},
    );
  }
}

enum Compatibility {
  /// The app and the server can talk.
  ok,

  /// The server is older than this app needs. The reader updates the server.
  serverTooOld,

  /// The server has moved past what this app can speak. The reader updates the app.
  appTooOld,
}

Compatibility compatibilityOf(
  Capabilities server, {
  int builtFor = builtForRevision,
  int minServer = minServerRevision,
}) {
  if (server.apiRevision < minServer) return Compatibility.serverTooOld;
  if (builtFor < server.minClientRevision) return Compatibility.appTooOld;
  return Compatibility.ok;
}
