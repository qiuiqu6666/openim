import 'dart:io';

import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// Gallery exports can be missing, stale, or wait indefinitely on cloud media.
/// Retry the original resource before failing this item and advancing the batch.
Future<File?> loadChatMediaAsset(
  AssetEntity asset, {
  required Duration timeout,
  required bool Function() isCancelled,
  void Function(String stage, Object error)? onReadFailure,
}) async {
  final readers = [() => asset.file, () => asset.originFile];
  for (var index = 0; index < readers.length; index++) {
    if (isCancelled()) return null;
    try {
      final file = await (() async {
        final candidate = await readers[index]();
        if (candidate != null &&
            await candidate.exists() &&
            await candidate.length() > 0) {
          return candidate;
        }
        return null;
      })()
          .timeout(timeout);
      if (isCancelled()) return null;
      if (file != null) return file;
      onReadFailure?.call(index == 0 ? 'asset_export' : 'asset_original',
          StateError('Empty or unavailable gallery file'));
    } catch (error) {
      onReadFailure?.call(
          index == 0 ? 'asset_export' : 'asset_original', error);
      // A failed/timed-out export must not prevent trying the original file.
    }
  }
  throw StateError('Selected asset file is unavailable');
}
