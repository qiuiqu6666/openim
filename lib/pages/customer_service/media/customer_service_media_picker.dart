import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../data/data.dart';
import '../models/customer_service_chat_entry.dart';

/// Reuses the app's native album picker; only generated covers are owned here.
class CustomerServiceMediaPicker {
  final _covers = <File>[];
  bool _closed = false;

  Future<List<CustomerServiceUpload>> pick(BuildContext context,
      {required bool video, required bool Function() isActive}) async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final assets = await AssetPicker.pickAssets(context,
        pickerConfig: AssetPickerConfig(
          maxAssets: 9,
          requestType: video ? RequestType.video : RequestType.image,
          sortPathsByModifiedDate: true,
        ));
    final uploads = <CustomerServiceUpload>[];
    if (_closed || !isActive() || assets == null) return uploads;
    for (final asset in assets) {
      if (_closed || !isActive()) break;
      final file = await asset.originFile;
      if (file == null || _closed || !isActive()) continue;
      final bytes = await file.length();
      if (_closed || !isActive()) break;
      if (bytes <= 0 || bytes > CustomerServiceApi.maxAttachmentBytes) {
        IMViews.showToast(
            zh ? '附件大小不能超过 40MB' : 'Attachments must be smaller than 40 MB');
        continue;
      }
      var coverPath = '';
      if (video) {
        final cover =
            await asset.thumbnailDataWithSize(const ThumbnailSize(640, 640));
        if (_closed || !isActive()) break;
        if (cover != null) {
          final directory = await getTemporaryDirectory();
          if (_closed || !isActive()) break;
          final coverFile = File(path.join(
              directory.path, 'customer-service-${const Uuid().v4()}.jpg'));
          _covers.add(coverFile);
          await coverFile.writeAsBytes(cover);
          if (_closed || !isActive()) {
            if (await coverFile.exists()) await coverFile.delete();
            break;
          }
          coverPath = coverFile.path;
        }
      }
      uploads.add(CustomerServiceUpload(
        path: file.path,
        filename: path.basename(file.path),
        fileType: video ? 'video' : 'image',
        width: asset.width,
        height: asset.height,
        thumbnailPath: coverPath,
      ));
    }
    return uploads;
  }

  Future<void> dispose() async {
    _closed = true;
    for (final file in _covers) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _covers.clear();
  }
}
