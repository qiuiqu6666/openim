import 'package:openim_common/media_localization.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// Reuse the app's chat album on mobile; keep desktop file selection separate.
Future<PlatformFile?> pickPersonalStickerMedia({
  BuildContext? context,
  bool Function()? isCurrent,
}) async {
  final mobile = defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  bool current() => isCurrent?.call() != false && (context?.mounted ?? !mobile);
  if (isCurrent?.call() == false) return null;
  final PlatformFile file;
  if (mobile) {
    if (context == null || !context.mounted) {
      throw StateError('无法打开相册，请返回表情页面重试');
    }
    final assets = await AssetPicker.pickAssets(context,
        pickerConfig: AssetPickerConfig(
          textDelegate: AppMediaCopy.assets,
          maxAssets: 1,
          requestType: RequestType.common,
          sortPathsByModifiedDate: true,
          filterOptions: FilterOptionGroup(
            containsPathModified: true,
            orders: const [OrderOption(type: OrderOptionType.createDate)],
          ),
        ));
    if (!current() || assets == null || assets.isEmpty) return null;
    // Use the original file, not the thumbnail or a flattened GIF/WebP frame.
    final original = await assets.single.originFile;
    if (!current()) return null;
    if (original == null) throw StateError('无法读取所选相册文件，请重试');
    file = PlatformFile(
        path: original.path,
        name: path.basename(original.path),
        size: await original.length());
  } else {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'png',
        'jpg',
        'jpeg',
        'webp',
        'gif',
        'mp4',
        'heic',
        'heif'
      ],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    file = result.files.single;
  }
  if (!current()) return null;
  if (file.path == null) throw StateError('无法读取所选相册文件，请重试');
  final extension = file.extension?.toLowerCase();
  // Preserve GIF/WebP bytes. Only iPhone HEIC photos need conversion to a
  // format accepted by the existing sticker backend.
  if (extension == 'heic' || extension == 'heif') {
    final cache = await getTemporaryDirectory();
    final directory =
        Directory(path.join(cache.path, 'personal_sticker_imports'));
    await directory.create(recursive: true);
    final target = path.join(directory.path, '${const Uuid().v4()}.jpg');
    final image = await FlutterImageCompress.compressAndGetFile(
      file.path!,
      target,
      format: CompressFormat.jpeg,
      quality: 95,
    );
    if (!current()) return null;
    if (image == null) throw StateError('照片转换失败，请选择其他图片');
    return PlatformFile(
        path: image.path,
        name: path.basename(image.path),
        size: await image.length());
  }
  if (!['png', 'jpg', 'jpeg', 'webp', 'gif', 'mp4'].contains(extension)) {
    throw StateError('请选择 PNG、JPEG、WebP、GIF 图片或 MP4 短视频');
  }
  return file;
}
