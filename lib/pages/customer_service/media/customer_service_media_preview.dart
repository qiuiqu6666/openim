import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

/// Uses the existing media browser without exposing IM credentials to Kefu.
Future<void> openCustomerServiceMedia(BuildContext context,
    {required String url,
    required String path,
    required String thumbnail,
    required bool video,
    required String name,
    required bool file}) async {
  if (file) {
    if (path.isNotEmpty) {
      await OpenFilex.open(path);
    } else {
      final uri = Uri.tryParse(url);
      if (uri != null && const ['http', 'https'].contains(uri.scheme)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    return;
  }
  if (!context.mounted) return;
  final source = MediaSource(
      url: url.isEmpty ? null : url,
      file: path.isEmpty ? null : File(path),
      thumbnail: thumbnail.isEmpty && !video ? url : thumbnail,
      isVideo: video);
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (_) => MediaBrowser(
        sources: [source],
        initialIndex: 0,
        showGallery: false,
        showCounter: false,
        onAutoPlay: (_) => video,
        onSave: (_) => _save(source, name),
      ),
    ),
  );
}

Future<void> _save(MediaSource source, String name) async {
  File? temporary;
  final client = Dio();
  try {
    var file = source.file;
    if (file == null) {
      final url = source.url;
      if (url == null || url.isEmpty) throw StateError('No media source');
      final directory = await getTemporaryDirectory();
      var filename = paths.basename(name);
      if (filename.isEmpty || paths.extension(filename).isEmpty) {
        filename = source.isVideo ? 'video.mp4' : 'image.png';
      }
      temporary = File(paths.join(
          directory.path, 'customer-service-${const Uuid().v4()}-$filename'));
      await client.download(url, temporary.path,
          options: Options(receiveTimeout: const Duration(minutes: 2)));
      file = temporary;
    }
    if (source.isVideo) {
      // Older Android gallery writes require storage permission. Await the
      // permission result before releasing the downloaded temporary file.
      if (Platform.isAndroid &&
          (await DeviceInfoPlugin().androidInfo).version.sdkInt < 29 &&
          !await Permission.storage.request().isGranted) {
        IMViews.showToast(StrRes.saveFailed);
        return;
      }
      final result = await ImageGallerySaverPlus.saveFile(file.path);
      IMViews.showToast(result is Map && result['isSuccess'] == true
          ? StrRes.saveSuccessfully
          : StrRes.saveFailed);
    } else {
      await HttpUtil.saveFileToGallerySaver(file, name: name);
    }
  } catch (_) {
    IMViews.showToast(StrRes.saveFailed);
  } finally {
    client.close(force: true);
    if (temporary != null) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
    }
  }
}
