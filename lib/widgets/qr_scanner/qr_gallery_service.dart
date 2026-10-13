import 'package:image_picker/image_picker.dart';
import 'gallery/qr_gallery_cancellation.dart';
import 'gallery/qr_gallery_result.dart';
import 'gallery/qr_gallery_runner.dart';
export 'gallery/qr_gallery_cancellation.dart';
export 'gallery/qr_gallery_result.dart';

/// Local recognition only; business validation belongs to the caller.
class QrGalleryService {
  const QrGalleryService();
  Future<String?> pickImage() async =>
      (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;
  Future<QrGalleryResult> scan(String path,
          {QrGalleryCancellation? cancellation,
          Duration timeout = const Duration(seconds: 12)}) =>
      QrGalleryRunner.scan(path, cancellation ?? QrGalleryCancellation(),
          timeout: timeout);

  /// Never silently choose an ambiguous code for legacy single-code callers.
  Future<String?> readCode(String path) async {
    final result = await scan(path);
    final values = result.codes.map((c) => c.text).toSet();
    return values.length == 1 ? values.single : null;
  }
}
