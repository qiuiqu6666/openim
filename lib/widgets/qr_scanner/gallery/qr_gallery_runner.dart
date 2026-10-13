import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'qr_gallery_cancellation.dart';
import 'qr_gallery_result.dart';
import 'qr_gallery_worker.dart';

/// Serializes real native work, including completion after UI cancellation.
class QrGalleryRunner {
  static Future<void> _tail = Future.value();
  static QrGalleryCancellation? _active;

  /// Resource-drain hook for shutdown/diagnostics; never blocks the UI cancel.
  static Future<void> get settled => _tail;
  static const _channel = MethodChannel('99chat/qr_image_decoder');
  static Future<QrGalleryResult> scan(String path, QrGalleryCancellation token,
      {Duration timeout = const Duration(seconds: 12)}) {
    _active?.cancel();
    _active = token;
    final watch = Stopwatch()..start();
    final result = Completer<QrGalleryResult>();
    void complete(QrGalleryResult value) {
      if (!result.isCompleted) {
        result.complete(QrGalleryResult(value.status,
            codes: value.codes,
            width: value.width,
            height: value.height,
            passes: value.passes,
            partial: value.partial,
            engine: value.engine,
            elapsedMs: watch.elapsedMilliseconds));
      }
    }

    final deadline = Timer(timeout, () {
      complete(const QrGalleryResult(QrGalleryStatus.timeout));
      token.cancel();
    });
    unawaited(token.whenCancelled.then(
        (_) => complete(const QrGalleryResult(QrGalleryStatus.cancelled))));
    _tail = _tail.then((_) async {
      if (token.isCancelled) return;
      try {
        complete(await _run(path, token, timeout - watch.elapsed));
      } catch (_) {
        complete(const QrGalleryResult(QrGalleryStatus.invalidImage));
      }
    });
    return result.future.whenComplete(() {
      deadline.cancel();
      if (identical(_active, token)) _active = null;
    });
  }

  static Future<QrGalleryResult> _run(
      String source, QrGalleryCancellation token, Duration budget) async {
    final watch = Stopwatch()..start();
    String? temporary;
    var path = source, width = 0, height = 0, orientation = 1;
    try {
      if (source.trim().isEmpty) {
        return const QrGalleryResult(QrGalleryStatus.invalidImage);
      }
      if (await File(source).length() > 32 * 1024 * 1024) {
        return const QrGalleryResult(QrGalleryStatus.tooLarge);
      }
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          final data = await _channel
              .invokeMapMethod<String, dynamic>('decode', {'path': source});
          if (data == null) {
            return const QrGalleryResult(QrGalleryStatus.invalidImage);
          }
          temporary = path = data['path'] as String;
          width = data['width'] as int;
          height = data['height'] as int;
          orientation = data['orientation'] as int;
        } on MissingPluginException {
          /* Older hosts retain Dart codecs. */
        } on PlatformException catch (error) {
          return QrGalleryResult(error.code == 'tooLarge'
              ? QrGalleryStatus.tooLarge
              : QrGalleryStatus.invalidImage);
        }
      }
      if (token.isCancelled) {
        return const QrGalleryResult(QrGalleryStatus.cancelled);
      }
      final remaining = budget - watch.elapsed;
      if (remaining <= Duration.zero) {
        return const QrGalleryResult(QrGalleryStatus.timeout);
      }
      return await _worker(path, width, height, orientation, remaining, token);
    } finally {
      if (temporary != null) {
        try {
          await File(temporary).delete();
        } catch (_) {}
      }
    }
  }

  static Future<QrGalleryResult> _worker(String path, int width, int height,
      int orientation, Duration budget, QrGalleryCancellation token) async {
    final messages = ReceivePort(), exited = ReceivePort();
    final answer = Completer<QrGalleryResult>(), stopped = Completer<void>();
    SendPort? control;
    final replies = messages.listen((event) {
      if (event is SendPort) {
        control = event;
        if (token.isCancelled) control!.send(true);
        return;
      }
      if (!answer.isCompleted) {
        answer.complete(event is QrGalleryResult
            ? event
            : const QrGalleryResult(QrGalleryStatus.invalidImage));
      }
    });
    final exits = exited.listen((_) {
      if (!stopped.isCompleted) stopped.complete();
    });
    unawaited(token.whenCancelled.then((_) {
      control?.send(true);
      if (!answer.isCompleted) {
        answer.complete(const QrGalleryResult(QrGalleryStatus.cancelled));
      }
    }));
    try {
      await Isolate.spawn(
          qrGalleryWorker,
          (
            messages.sendPort,
            path,
            width,
            height,
            orientation,
            budget.inMilliseconds
          ),
          onError: messages.sendPort,
          onExit: exited.sendPort,
          errorsAreFatal: true);
      if (token.isCancelled) control?.send(true);
      final value = await answer.future;
      // Native results must be freed by the FFI wrapper before cancellation.
      // Cooperatively stop between passes, and serialize until actual exit.
      await stopped.future;
      return value;
    } finally {
      control?.send(true);
      await replies.cancel();
      await exits.cancel();
      messages.close();
      exited.close();
    }
  }
}
