import '../api/api_client.dart';
import 'app_log.dart' show redact;

/// The levels the server's log keeps, in the order the screen offers them.
const serverLogLevels = ['error', 'warn', 'info', 'request', 'asset', 'trace'];

/// What the server shows by default: everything but file requests and traces, which are most of the log and
/// the least of what anybody opens it for.
const defaultServerLogLevels = {'error', 'warn', 'info', 'request'};

/// One line of the server's own log (`GET /admin/logs`). This is the SERVER's log, kept on the server for
/// thirty days, and is a different thing from the app's log ([AppLog]), which is this phone's own record.
/// The two are never mixed on a screen or in a file.
class ServerLogLine {
  const ServerLogLine({
    required this.id,
    required this.at,
    required this.level,
    required this.code,
    required this.line,
  });

  final int id;

  /// Unix milliseconds, the server's clock.
  final int at;
  final String level;
  final String code;
  final String line;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(at, isUtc: true);

  static ServerLogLine? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final at = json['at'];
    if (id is! int || at is! int) return null;
    return ServerLogLine(
      id: id,
      at: at,
      level: json['level'] is String ? json['level'] as String : '',
      code: json['code'] is String ? json['code'] as String : '',
      line: json['line'] is String ? json['line'] as String : '',
    );
  }
}

/// What the server's log is narrowed to. A window is a length of time ending now, taken from the SERVER's
/// clock (the server turns `since` into a time itself), so a phone whose clock is wrong still asks for the
/// right hour.
class ServerLogFilter {
  const ServerLogFilter({
    this.levels = defaultServerLogLevels,
    this.query = '',
    this.since = const Duration(days: 1),
  });

  final Set<String> levels;

  /// Matched literally and case-insensitively by the server, for ASCII letters.
  final String query;

  /// How far back, ending now. The server keeps thirty days whatever is asked.
  final Duration since;

  ServerLogFilter copyWith({
    Set<String>? levels,
    String? query,
    Duration? since,
  }) => ServerLogFilter(
    levels: levels ?? this.levels,
    query: query ?? this.query,
    since: since ?? this.since,
  );
}

/// One page of the log, newest first.
class ServerLogPage {
  const ServerLogPage({
    required this.lines,
    required this.more,
    required this.from,
    required this.upto,
  });

  final List<ServerLogLine> lines;

  /// Whether older lines remain in the window.
  final bool more;

  /// The window the server read, to send back for the next page so a line logged meanwhile is in neither.
  final int from;
  final int upto;
}

/// The path and query for one page. The first page sends `since`; later pages send the `from` and `upto`
/// the first answer gave (the window must not drift between pages) and `before`, the oldest id seen.
String serverLogPath(
  ServerLogFilter f, {
  int? before,
  int? upto,
  int? from,
  int limit = 200,
}) {
  final q = <String, String>{
    if (f.levels.isNotEmpty)
      'level': serverLogLevels.where(f.levels.contains).join(','),
    if (f.query.trim().isNotEmpty) 'q': f.query.trim(),
    'limit': '$limit',
    if (from != null) 'from': '$from' else 'since': '${f.since.inMilliseconds}',
    'upto': ?upto?.toString(),
    'before': ?before?.toString(),
  };
  return Uri(path: '/admin/logs', queryParameters: q).toString();
}

/// Reads one page of the server's log. Needs an admin's device token: a phone paired as anyone else gets
/// [ApiFailure.forbidden], which is not a reason to unpair it.
Future<ServerLogPage> fetchServerLog(
  ApiClient client,
  ServerLogFilter filter, {
  int? before,
  int? upto,
  int? from,
  int limit = 200,
}) async {
  final body = await client.getJson(
    serverLogPath(filter, before: before, upto: upto, from: from, limit: limit),
  );
  if (body is! Map || body['lines'] is! List) {
    throw const ApiException(ApiFailure.badResponse, 'not a log page');
  }
  final f = body['from'];
  final u = body['upto'];
  return ServerLogPage(
    lines: [for (final l in body['lines'] as List) ?ServerLogLine.fromJson(l)],
    more: body['more'] == true,
    from: f is int ? f : 0,
    upto: u is int ? u : 0,
  );
}

/// The lines as text, oldest first as a log is read. A credential is taken out of each line on the way (the
/// server's own request lines are not meant to hold one, and this is the last line of defence before a log
/// leaves the phone through Copy or Share).
String serverLogText(List<ServerLogLine> newestFirst) {
  final out = StringBuffer();
  for (final l in newestFirst.reversed) {
    final at = l.time.toIso8601String().split('.').first;
    out.writeln(
      redact(
        '${at}Z [${l.level}]${l.code.isEmpty ? '' : ' ${l.code}'} ${l.line}',
      ),
    );
  }
  return out.toString();
}
