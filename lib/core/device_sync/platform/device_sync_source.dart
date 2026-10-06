import 'dart:io';

import 'package:dio/dio.dart';

import '../models/device_sync_models.dart';

export '../models/device_sync_models.dart' show DeviceSyncLocation;

/// Library metadata only. [fingerprint] detects metadata changes; it is not a
/// content checksum. The upload checksum always comes from the exported file.
class DeviceSyncAsset {
  const DeviceSyncAsset({
    required this.id,
    required this.fingerprint,
    required this.kind,
    required this.name,
    required this.contentType,
    required this.capturedAt,
  });

  final String id;
  final String fingerprint;
  final String kind;
  final String name;
  final String contentType;
  final int capturedAt;
}

/// A readable original and its cleanup ownership. Borrowed Android library
/// files must never be deleted when a transfer finishes or is cancelled.
class DeviceSyncFile {
  DeviceSyncFile({required this.file, Future<void> Function()? onDispose})
      : _onDispose = onDispose;

  final File file;
  final Future<void> Function()? _onDispose;
  Future<void>? _disposing;

  Future<void> dispose() => _disposing ??= _onDispose?.call() ?? Future.value();
}

abstract class DeviceSyncSource {
  Stream<List<DeviceSyncAsset>> pages({required bool includeVideos});

  Future<DeviceSyncFile?> openFile(
    DeviceSyncAsset asset, {
    required CancelToken cancelToken,
  });

  Future<DeviceSyncLocation?> locate(
    String clientID, {
    required CancelToken cancelToken,
  });

  Future<bool> hasUnmeteredNetwork();

  void dispose();
}
