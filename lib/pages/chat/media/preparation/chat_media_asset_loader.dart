import 'dart:async';
import 'dart:io';

import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'media_operation_wait.dart';

/// Gallery exports can be missing, stale, or wait indefinitely on cloud media.
/// Retry the original resource before failing this item and advancing the batch.
Future<File?> loadChatMediaAsset(
  AssetEntity asset, {
  required Duration timeout,
  required bool Function() isCancelled,
  void Function(String stage, Object error)? onReadFailure,
  Duration videoIdleTimeout = const Duration(seconds: 60),
  Duration videoTotalTimeout = const Duration(minutes: 10),
  Future<File?> Function(bool origin, void Function(double) progress)?
      videoReader,
}) async {
  if (asset.type == AssetType.video) {
    return _loadVideo(asset,
        isCancelled: isCancelled,
        idleTimeout: videoIdleTimeout,
        totalTimeout: videoTotalTimeout,
        onReadFailure: onReadFailure,
        reader: videoReader);
  }
  final readers = [() => asset.file, () => asset.originFile];
  for (var index = 0; index < readers.length; index++) {
    if (isCancelled()) return null;
    try {
      final file = await (() async {
        final candidate = await readers[index]();
        if (candidate != null &&
            await candidate.exists() &&
            await candidate.length() > 0) {
          return candidate;
        }
        return null;
      })()
          .timeout(timeout);
      if (isCancelled()) return null;
      if (file != null) return file;
      onReadFailure?.call(index == 0 ? 'asset_export' : 'asset_original',
          StateError('Empty or unavailable gallery file'));
    } catch (error) {
      onReadFailure?.call(
          index == 0 ? 'asset_export' : 'asset_original', error);
      // A failed/timed-out export must not prevent trying the original file.
    }
  }
  throw StateError('Selected asset file is unavailable');
}

// A timed-out observer must not start another native export for the same asset.
// Keep the owner until native completion; retries can observe that same work.
final _videoReads = <String, _VideoRead>{};

class _VideoRead {
  final progress = StreamController<double>.broadcast();
  late Future<File?> result;
}

Future<File?> _loadVideo(
  AssetEntity asset, {
  required bool Function() isCancelled,
  required Duration idleTimeout,
  required Duration totalTimeout,
  void Function(String stage, Object error)? onReadFailure,
  Future<File?> Function(bool, void Function(double))? reader,
}) async {
  final elapsed = Stopwatch()..start();
  for (final origin in [false, true]) {
    if (isCancelled()) return null;
    final key = '${asset.id}:$origin';
    var pending = _videoReads[key];
    if (pending == null) {
      if (_videoReads.length >= 20) {
        throw StateError('Video downloads are busy');
      }
      pending = _VideoRead();
      final owner = pending;
      _videoReads[key] = owner;
      owner.result = (() async {
        StreamSubscription<PMProgressState>? subscription;
        try {
          if (reader != null) return await reader(origin, owner.progress.add);
          PMProgressHandler? handler;
          if (Platform.isIOS || Platform.isMacOS) {
            handler = PMProgressHandler();
            subscription = handler.stream
                .listen((event) => owner.progress.add(event.progress));
          }
          if (handler == null) {
            return await (origin ? asset.originFile : asset.file);
          }
          return await asset.loadFile(
              isOrigin: origin, progressHandler: handler);
        } finally {
          await subscription?.cancel();
          _videoReads.remove(key);
          unawaited(owner.progress.close());
        }
      })();
    }
    try {
      final remaining = totalTimeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Video download timed out');
      }
      final candidate = await waitMediaOperation(pending.result,
          totalTimeout: remaining,
          idleTimeout: idleTimeout,
          isCancelled: isCancelled,
          progress: pending.progress.stream);
      if (isCancelled()) return null;
      if (candidate != null &&
          await candidate.exists() &&
          await candidate.length() > 0) {
        return candidate;
      }
      onReadFailure?.call(origin ? 'asset_original' : 'asset_export',
          StateError('Video file unavailable'));
    } on TimeoutException catch (error) {
      onReadFailure?.call(origin ? 'asset_original' : 'asset_export', error);
      rethrow; // Native work may still be running. No overlapping fallback.
    } catch (error) {
      if (isCancelled()) return null;
      onReadFailure?.call(origin ? 'asset_original' : 'asset_export', error);
      // Native failure completed: it is now safe to try the original resource.
    }
  }
  throw StateError('Selected video file is unavailable');
}
