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
  final info = await LoadingView.singleton.wrap(
      asyncFunction: () => VideoCompress.compressVideo(original.path,
          quality: VideoQuality.Res1280x720Quality,
          deleteOrigin: false,
          includeAudio: true));
  final output = info?.file;
  if (output == null || !await output.exists()) return original;
  if (await output.length() >= await original.length()) return original;
  return output;
}
