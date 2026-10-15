import 'dart:io';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:video_compress/video_compress.dart';

enum ChatVideoQuality { standard, original }

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
  if (VideoCompress.isCompressing) return original;
  // The accepted attachment task already owns local preparation feedback.
  // Compression must not block the chat or dismiss another task's loader.
  final info = await VideoCompress.compressVideo(original.path,
      quality: VideoQuality.Res1280x720Quality,
      deleteOrigin: false,
      includeAudio: true);
  final output = info?.file;
  if (output == null || !await output.exists()) return original;
  if (await output.length() >= await original.length()) return original;
  return output;
}
