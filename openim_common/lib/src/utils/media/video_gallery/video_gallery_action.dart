import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'video_gallery_saver.dart';

/// Keeps feedback and duplicate taps scoped to the preview that requested it.
class VideoGalleryAction {
  final _saver = VideoGallerySaver();
  bool _saving = false, _closed = false;

  Future<void> save(
      {File? file,
      String? url,
      Uint8List? bytes,
      required bool Function() isCurrent,
      CancelToken? cancelToken,
      void Function(int, int)? onProgress}) async {
    if (_saving || _closed || !isCurrent()) return;
    _saving = true;
    final watch = Stopwatch()..start();
    var lastProgressMs = -250;
    late VideoGalleryResult result;
    EasyLoading.show(status: 'videoSavePreparing'.tr, dismissOnTap: false);
    try {
      result = await _saver.save(
          file: file,
          url: url,
          bytes: bytes,
          cancelToken: cancelToken,
          isCurrent: () => !_closed && isCurrent(),
          onWriting: () => EasyLoading.show(
              status: 'videoSaveWriting'.tr, dismissOnTap: false),
          onProgress: (count, total) {
            onProgress?.call(count, total);
            if (watch.elapsedMilliseconds - lastProgressMs < 250 &&
                count != total) {
              return;
            }
            lastProgressMs = watch.elapsedMilliseconds;
            // Download percentage is progress only, never the completion signal.
            final progress = total > 0
                ? '${(count * 100 / total).clamp(0, 100).toInt()}%'
                : '${(count / (1024 * 1024)).toStringAsFixed(1)} MB';
            EasyLoading.show(
                status: '${'videoSaveDownloading'.tr} $progress',
                dismissOnTap: false);
          });
    } finally {
      if (!_closed) await EasyLoading.dismiss();
      _saving = false;
    }
    // No signed URL, path, token or user identifier is written to logs.
    Logger.print(
        '[VideoSave] result=${result.name} elapsedMs=${watch.elapsedMilliseconds}');
    if (_closed || !isCurrent() || result == VideoGalleryResult.canceled) {
      return;
    }
    IMViews.showToast(switch (result) {
      VideoGalleryResult.success => StrRes.saveSuccessfully,
      VideoGalleryResult.permissionDenied => 'videoSavePermissionDenied'.tr,
      VideoGalleryResult.downloadFailed => 'videoSaveDownloadFailed'.tr,
      VideoGalleryResult.invalidVideo => 'videoSaveInvalid'.tr,
      VideoGalleryResult.timedOut => 'videoSaveTimedOut'.tr,
      VideoGalleryResult.writing => 'videoSaveWriting'.tr,
      VideoGalleryResult.unsupported => 'videoSaveUnsupported'.tr,
      _ => StrRes.saveFailed,
    });
  }

  void dispose() {
    _closed = true;
    _saver.dispose();
    if (_saving) EasyLoading.dismiss();
  }
}
