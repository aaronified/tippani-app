import '../app_controller.dart';
import 'api_client.dart';

/// Anything that went wrong asking the server for something, in words for the reader.
class ServerException implements Exception {
  const ServerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Runs [run] against the paired server and turns every way it can fail into a [ServerException] with a
/// plain message. A call that returns nothing (a delete) is fine: "not paired" is decided by [AppController.paired],
/// never by what [run] returns.
Future<T> serverCall<T>(
  AppController controller,
  Future<T> Function(ApiClient client) run,
) async {
  if (!controller.paired) {
    throw const ServerException('This phone is not paired with a server.');
  }
  try {
    return await controller.withClient(run) as T;
  } on ApiException catch (e) {
    throw ServerException(switch (e.failure) {
      ApiFailure.network => 'The server could not be reached.',
      ApiFailure.timeout => 'The server took too long to answer.',
      ApiFailure.unauthorised =>
        'The server no longer accepts this phone. Pair it again.',
      ApiFailure.forbidden => 'The server does not allow that.',
      ApiFailure.rateLimited => 'The server asks you to wait a moment.',
      ApiFailure.server || ApiFailure.badResponse =>
        e.detail.isNotEmpty ? e.detail : 'The server could not do that.',
    });
  }
}

Map<String, Object?> asMap(Object? v) => v is Map
    ? Map<String, Object?>.from(v)
    : throw const ServerException('The server sent something unexpected.');
