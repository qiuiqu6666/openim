import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:permission_handler/permission_handler.dart';

enum MomentsMediaSaveResult {
  success,
  permissionDenied,
  failed,
  unsupported,
  canceled
}

/// Explicitly saves authorized bytes with the same gallery plugin as the shared
/// media viewer. Protected images do not need a public cache or temporary file.
Future<MomentsMediaSaveResult> saveMomentImageToGallery(
  Uint8List bytes, {
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return MomentsMediaSaveResult.canceled;
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return MomentsMediaSaveResult.unsupported;
  }
  if (bytes.isEmpty) return MomentsMediaSaveResult.failed;
  try {
    var allowed = true;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      allowed = (await Permission.photosAddOnly.request()).isGranted;
    } else if ((await DeviceInfoPlugin().androidInfo).version.sdkInt < 29) {
      allowed = (await Permission.storage.request()).isGranted;
    }
    // The account, post or route may have changed while the OS asked permission.
    if (!isCurrent()) return MomentsMediaSaveResult.canceled;
    if (!allowed) return MomentsMediaSaveResult.permissionDenied;
    final result = await ImageGallerySaverPlus.saveImage(
      bytes,
      quality: 100,
      name: 'moment_${DateTime.now().microsecondsSinceEpoch}',
    );
    return result is Map && result['isSuccess'] == true
        ? MomentsMediaSaveResult.success
        : MomentsMediaSaveResult.failed;
  } catch (_) {
    return MomentsMediaSaveResult.failed;
  }
}
