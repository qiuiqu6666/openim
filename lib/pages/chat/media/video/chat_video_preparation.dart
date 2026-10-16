import 'dart:io';
import 'dart:async';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:video_compress/video_compress.dart';

enum ChatVideoQuality { standard, original }

Future<bool?> chooseChatMediaOriginal() => Get.bottomSheet<bool>(
      BottomSheetView(useThemeColors: true, items: [
        SheetItem(label: 'chatMediaStandard'.tr, result: false),
        SheetItem(label: 'chatMediaOriginal'.tr, result: true),
      ]),
    );

Future<ChatVideoQuality?> chooseChatVideoQuality() =>
    Get.bottomSheet<ChatVideoQuality>(
      BottomSheetView(useThemeColors: true, items: [
        SheetItem(
            label: 'chatVideoStandard'.tr, result: ChatVideoQuality.standard),
        SheetItem(
            label: 'chatVideoOriginal'.tr, result: ChatVideoQuality.original),
      ]),
    );

Future<File> prepareChatVideo(File original, ChatVideoQuality quality) async {
  if (quality == ChatVideoQuality.original) return original;
  // Native compression is serialized by the album preparation loop. Never
  // delete the source or cancel another module's compressor.
  // Overlapping albums must not silently bypass the selected compression.
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (VideoCompress.isCompressing) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Video compressor is busy');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  // The accepted attachment task already owns local preparation feedback.
  // Compression must not block the chat or dismiss another task's loader.
  final info = await VideoCompress.compressVideo(original.path,
      quality: VideoQuality.Res1280x720Quality,
      deleteOrigin: false,
      frameRate: 30,
      includeAudio: true);
  final output = info?.file;
  if (output == null || !await output.exists() || await output.length() == 0) {
    throw StateError('Video compression did not produce a playable file');
  }
  if (await output.length() >= await original.length()) return original;
  return output;
}
