import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mime/mime.dart';
import 'package:photo_manager/photo_manager.dart';

import 'device_sync_source.dart';

/// Existing permission only. This source never opens a permission dialog or
/// downloads iCloud originals; callers own scheduling and account preferences.
class DeviceSyncPlatformSource implements DeviceSyncSource {
  DeviceSyncPlatformSource({TargetPlatform? platform, MethodChannel? channel})
      : _platform = platform ?? defaultTargetPlatform,
        _channel =
            channel ?? const MethodChannel('openim_device_sync_originals');

  static const pageSize = 24;
  final TargetPlatform _platform;
  final MethodChannel _channel;
  final Set<CancelToken> _operations = {};
  bool _disposed = false;
  bool _locating = false;
  int _nextRequest = 0;

  bool get _mobile =>
      !kIsWeb &&
      (_platform == TargetPlatform.android || _platform == TargetPlatform.iOS);

  Future<bool> _hasMediaAccess(RequestType type) async {
    if (_disposed || !_mobile) return false;
    final state = await PhotoManager.getPermissionState(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(type: type, mediaLocation: false),
      ),
    );
    return !_disposed && state.hasAccess;
  }

  @override
  Stream<List<DeviceSyncAsset>> pages({required bool includeVideos}) async* {
    final type = includeVideos ? RequestType.common : RequestType.image;
    if (!await _hasMediaAccess(type)) return;
    final albums = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: type,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(needTitle: true),
        videoOption: const FilterOption(needTitle: true),
      ),
    );
    if (_disposed || albums.isEmpty) return;
    final album = albums.first;
    for (var page = 0; !_disposed; page++) {
      // Permission and limited selection can change between pages. The count is
      // not a stable snapshot, so terminate on an empty page rather than count.
      if (!await _hasMediaAccess(type)) return;
      final assets = await album.getAssetListPaged(page: page, size: pageSize);
      if (_disposed || assets.isEmpty) return;
      final metadata = <DeviceSyncAsset>[];
      for (final asset in assets) {
        if (asset.type != AssetType.image &&
            !(includeVideos && asset.type == AssetType.video)) {
          continue;
        }
        final name = asset.title ?? '';
        final kind = asset.type == AssetType.video ? 'video' : 'image';
        final contentType = asset.mimeType ??
            lookupMimeType(name) ??
            (kind == 'video' ? 'video/mp4' : 'image/jpeg');
        metadata.add(DeviceSyncAsset(
          id: asset.id,
          fingerprint: '${asset.modifiedDateSecond ?? 0}:${asset.width}:'
              '${asset.height}:${asset.duration}:${asset.typeInt}:$name',
          kind: kind,
          name: name,
          contentType: contentType,
          capturedAt: (asset.createDateSecond ?? 0) * 1000,
        ));
      }
      if (metadata.isNotEmpty) yield metadata;
    }
  }

  @override
  Future<DeviceSyncFile?> openFile(
    DeviceSyncAsset asset, {
    required CancelToken cancelToken,
  }) async {
    if (_disposed || !_mobile) return null;
    _throwIfCancelled(cancelToken);
    _operations.add(cancelToken);
    try {
      final type =
          asset.kind == 'video' ? RequestType.video : RequestType.image;
      if (!await _hasMediaAccess(type)) return null;
      _throwIfCancelled(cancelToken);
      if (_platform == TargetPlatform.iOS) {
        return await _openIosOriginal(asset, cancelToken);
      }
      final entity = await AssetEntity.fromId(asset.id);
      _throwIfCancelled(cancelToken);
      if (entity == null) return null;
      // Android returns the original library path (or a plugin-managed cache),
      // not our owned file. Cleanup must not remove either of those paths.
      final file = await entity.originFile;
      _throwIfCancelled(cancelToken);
      if (file == null || !await file.exists()) return null;
      _throwIfCancelled(cancelToken);
      return DeviceSyncFile(file: file);
    } on PlatformException catch (error) {
      _throwIfCancelled(cancelToken);
      if (const {'not_local', 'not_found', 'permission_denied', 'too_large'}
          .contains(error.code)) {
        return null;
      }
      rethrow;
    } finally {
      _operations.remove(cancelToken);
    }
  }

  Future<DeviceSyncFile?> _openIosOriginal(
    DeviceSyncAsset asset,
    CancelToken token,
  ) async {
    final requestID =
        '${DateTime.now().microsecondsSinceEpoch}-${_nextRequest++}';
    var released = false;
    Future<void> release(String method) async {
      if (released) return;
      released = true;
      await _channel.invokeMethod<void>(method, {'requestID': requestID});
    }

    unawaited(token.whenCancel.then((_) async {
      try {
        await release('cancel');
      } on PlatformException {
        // The original export's Future retains its error. Cancellation cleanup
        // must not become an unhandled independent Future error.
      } on MissingPluginException {
        // Unsupported host cannot own an export.
      }
    }));
    final value = await _channel.invokeMapMethod<String, dynamic>('open', {
      'requestID': requestID,
      'assetID': asset.id,
      'kind': asset.kind,
    });
    if (token.isCancelled || _disposed) {
      await release('cancel');
      _throwIfCancelled(token);
      return null;
    }
    final path = value?['path'];
    if (path is! String || path.isEmpty) {
      await release('release');
      return null;
    }
    return DeviceSyncFile(
      file: File(path),
      onDispose: () => release('release'),
    );
  }

  @override
  Future<DeviceSyncLocation?> locate(
    String clientID, {
    required CancelToken cancelToken,
  }) async {
    if (_disposed || !_mobile) return null;
    _throwIfCancelled(cancelToken);
    if (_locating) return null;
    _locating = true;
    _operations.add(cancelToken);
    try {
      final permission = await Geolocator.checkPermission();
      _throwIfCancelled(cancelToken);
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      _throwIfCancelled(cancelToken);
      // The user requires a new fix. A timeout must not fall back to a cached or
      // late location, even if that would otherwise be useful for resume logic.
      final position = await _onePosition(cancelToken);
      _throwIfCancelled(cancelToken);
      if (position == null ||
          !position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        return null;
      }
      return DeviceSyncLocation(
        clientID: clientID,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy.isFinite && position.accuracy >= 0
            ? position.accuracy.clamp(0, 10000000).toDouble()
            : 0,
        recordedAt: position.timestamp.millisecondsSinceEpoch,
      );
    } on PermissionDeniedException {
      return null;
    } on LocationServiceDisabledException {
      return null;
    } finally {
      _operations.remove(cancelToken);
      _locating = false;
    }
  }

  Future<Position?> _onePosition(CancelToken token) async {
    final result = Completer<Position?>();
    final startedAt = DateTime.now();
    final settings = _platform == TargetPlatform.iOS
        ? AppleSettings(
            accuracy: LocationAccuracy.low,
            allowBackgroundLocationUpdates: false,
            pauseLocationUpdatesAutomatically: true,
          )
        : const LocationSettings(accuracy: LocationAccuracy.low);
    final subscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
            (value) {
      if (value.timestamp.isBefore(startedAt)) return;
      if (!result.isCompleted) result.complete(value);
    }, onError: (Object error) {
      if (!result.isCompleted) result.completeError(error);
    }, onDone: () {
      if (!result.isCompleted) result.complete(null);
    });
    final timer = Timer(const Duration(seconds: 10), () {
      if (!result.isCompleted) result.complete(null);
    });
    unawaited(token.whenCancel.then((error) {
      if (!result.isCompleted) result.completeError(error);
    }));
    try {
      return await result.future;
    } finally {
      timer.cancel();
      // Cancelling the EventChannel stops native CLLocationManager/FusedLocation
      // updates; Future.timeout on Apple's one-shot API cannot do that.
      await subscription.cancel();
    }
  }

  @override
  Future<bool> hasUnmeteredNetwork() async {
    if (_disposed || !_mobile) return false;
    final connectivity = await Connectivity().checkConnectivity();
    return !_disposed &&
        (connectivity.contains(ConnectivityResult.wifi) ||
            connectivity.contains(ConnectivityResult.ethernet));
  }

  void _throwIfCancelled(CancelToken token) {
    if (token.isCancelled) throw token.cancelError!;
    if (_disposed) throw StateError('Device sync source is disposed');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final token in _operations.toList()) {
      if (!token.isCancelled) token.cancel('Device sync source disposed');
    }
    _operations.clear();
  }
}
