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
      ApiFailure.network => 'app.admin_service.the_server_could_not_be_reached',
      ApiFailure.timeout => 'app.admin_service.the_server_took_too_long_to',
      ApiFailure.unauthorised =>
        'app.board_service.the_server_no_longer_accepts_this',
      ApiFailure.forbidden =>
        'app.account_service.the_server_does_not_allow_that',
      ApiFailure.rateLimited => 'app.board_service.the_server_asks_you_to_wait',
      ApiFailure.server || ApiFailure.badResponse =>
        e.detail.isNotEmpty
            ? e.detail
            : 'app.admin_service.the_server_could_not_do_that',
    });
  }
}

Map<String, Object?> asMap(Object? v) => v is Map
    ? Map<String, Object?>.from(v)
    : throw const ServerException('The server sent something unexpected.');
