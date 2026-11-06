import '../api/api_client.dart';

/// One row of the account's device list (`GET /auth/devices`). It carries no token material.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.lastSeenAt,
    required this.current,
  });

  final int id;
  final String name;
  final String createdAt;

  /// Empty until the device has been used.
  final String lastSeenAt;

  /// True on the device that asked (server API revision 9 and later); false on an older server, where
  /// the app cannot tell which row is itself and so must not offer to revoke any without saying so.
  final bool current;

  static DeviceInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! int) return null;
    return DeviceInfo(
      id: id,
      name: json['name'] is String ? json['name'] as String : '',
      createdAt: json['created_at'] is String
          ? json['created_at'] as String
          : '',
      lastSeenAt: json['last_seen_at'] is String
          ? json['last_seen_at'] as String
          : '',
      current: json['current'] == true,
    );
  }
}

/// The account's paired devices, newest first. Unreadable rows are skipped rather than failing the list.
Future<List<DeviceInfo>> listDevices(ApiClient client) async {
  final body = await client.getJson('/auth/devices');
  final rows = body is Map ? body['devices'] : null;
  if (rows is! List) {
    throw const ApiException(
      ApiFailure.badResponse,
      'no device list in the answer',
    );
  }
  return [for (final r in rows) ?DeviceInfo.fromJson(r)];
}

/// Unpairs one device. The server answers 404 for a device that is not this account's, and for one that
/// is already gone; both read as "not found" here.
Future<void> revokeDevice(ApiClient client, int id) async {
  await client.delete('/auth/devices/$id');
}
