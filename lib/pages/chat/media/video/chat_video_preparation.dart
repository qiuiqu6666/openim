import 'dart:io';
import 'dart:async';
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

Future<File> prepareChatVideo(File original, ChatVideoQuality quality,
    {Duration busyTimeout = const Duration(seconds: 30),
    Duration compressionTimeout = const Duration(minutes: 2)}) async {
  if (quality == ChatVideoQuality.original) return original;
  // Native compression is globally exclusive even across preparation lanes.
  // Never delete the source or cancel another module's compressor.
  // Overlapping albums must not silently bypass the selected compression.
  final waiting = Stopwatch()..start();
  while (VideoCompress.isCompressing) {
    if (waiting.elapsed >= busyTimeout) {
      throw TimeoutException('Video compressor is busy');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  // The accepted attachment task already owns local preparation feedback.
  // Compression must not block the chat or dismiss another task's loader.
  final operation = VideoCompress.compressVideo(original.path,
      quality: VideoQuality.Res1280x720Quality,
      deleteOrigin: false,
      frameRate: 30,
      includeAudio: true);
  final info = await operation.timeout(compressionTimeout, onTimeout: () async {
    // Only this operation owns the compressor. Do not reset its busy flag:
    // late native completion must not race a new encoder or mutate a message.
    try {
      await VideoCompress.cancelCompression()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // The caller still receives the timeout and can explicitly retry.
    }
    throw TimeoutException('Video compression timed out', compressionTimeout);
  });
  final output = info?.file;
  if (output == null || !await output.exists() || await output.length() == 0) {
    throw StateError('Video compression did not produce a playable file');
  }
  if (await output.length() >= await original.length()) return original;
  return output;
}
