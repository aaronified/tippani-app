import 'package:image_picker/image_picker.dart';

/// Where a page's picture comes from. An interface so a test can stand in for the camera.
abstract class PhotoSource {
  /// Opens the camera; the path of the picture taken, or null if the reader backed out.
  Future<String?> take();

  /// Opens the gallery; the path of the picture chosen, or null if the reader backed out.
  Future<String?> choose();
}

/// The phone's camera app and gallery. The camera is the system's own, so the app asks for no camera permission.
class DevicePhotos implements PhotoSource {
  DevicePhotos();

  final _picker = ImagePicker();

  @override
  Future<String?> take() async =>
      (await _picker.pickImage(source: ImageSource.camera))?.path;

  @override
  Future<String?> choose() async =>
      (await _picker.pickImage(source: ImageSource.gallery))?.path;
}
