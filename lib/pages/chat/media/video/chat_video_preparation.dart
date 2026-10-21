import 'dart:io';
import 'dart:async';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:video_compress/video_compress.dart';
import '../preparation/media_operation_wait.dart';

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

final _videoQueue = <Object>[];
bool _encoderAwaitingCompletion = false;

Future<File> prepareChatVideo(File original, ChatVideoQuality quality,
    {Duration? busyTimeout,
    Duration compressionTimeout = const Duration(minutes: 10),
    Duration idleTimeout = const Duration(seconds: 60),
    bool Function()? isCancelled,
    void Function(String)? onPhase}) async {
  final cancelled = isCancelled ?? () => false;
  if (cancelled()) throw StateError('Video preparation cancelled');
  if (quality == ChatVideoQuality.original) return original;
  if (_videoQueue.length >= 20) {
    throw StateError('Video preparation queue is full');
  }
  final ticket = Object();
  _videoQueue.add(ticket);
  onPhase?.call('queued');
  final waiting = Stopwatch()..start();
  try {
    while (_videoQueue.first != ticket || VideoCompress.isCompressing) {
      if (cancelled()) throw StateError('Video preparation cancelled');
      if (_encoderAwaitingCompletion) {
        throw StateError(
            'Video encoder is still stopping; retry or select original');
      }
      if (busyTimeout != null && waiting.elapsed >= busyTimeout) {
        throw TimeoutException('Video compressor is busy');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (cancelled()) throw StateError('Video preparation cancelled');
    onPhase?.call('compressing');
    final progress = StreamController<double>();
    final subscription =
        VideoCompress.compressProgress$.subscribe(progress.add);
    var completed = false;
    final operation = VideoCompress.compressVideo(original.path,
        quality: VideoQuality.Res1280x720Quality,
        deleteOrigin: false,
        frameRate: 30,
        includeAudio: true);
    // Only actual native completion releases the compressor, including after
    // the observer times out. Never reset the plugin's global busy flag.
    unawaited(operation
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() {
      completed = true;
      _encoderAwaitingCompletion = false;
      subscription.unsubscribe();
      unawaited(progress.close());
    }));
    MediaInfo? info;
    try {
      info = await waitMediaOperation(operation,
          totalTimeout: compressionTimeout,
          idleTimeout: idleTimeout,
          isCancelled: cancelled,
          progress: progress.stream);
    } catch (_) {
      if (!completed) {
        _encoderAwaitingCompletion = true;
        try {
          await VideoCompress.cancelCompression()
              .timeout(const Duration(seconds: 2));
        } catch (_) {/* Keep ownership until the native completion arrives. */}
      }
      rethrow;
    }
    if (cancelled()) throw StateError('Video preparation cancelled');
    final File? output = info?.file;
    if (output == null ||
        !await output.exists() ||
        await output.length() == 0) {
      throw StateError('Video compression did not produce a playable file');
    }
    if (await output.length() >= await original.length()) return original;
    return output;
  } finally {
    _videoQueue.remove(ticket);
  }
}
