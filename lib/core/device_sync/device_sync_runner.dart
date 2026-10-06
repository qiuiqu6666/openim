import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';

import 'data/device_sync_api.dart';
import 'data/device_sync_store.dart';
import 'models/device_sync_preferences.dart';
import 'platform/device_sync_hasher.dart';
import 'platform/device_sync_source.dart';

/// One low-concurrency pass. Only metadata and paths cross into this worker.
class DeviceSyncRunner {
  DeviceSyncRunner({
    required this.store,
    required this.api,
    required this.source,
    required this.hasher,
    required this.device,
    required this.isCurrent,
    required this.onStatus,
  });
  final DeviceSyncStore store;
  final DeviceSyncApi api;
  final DeviceSyncSource source;
  final DeviceSyncHasher hasher;
  final DeviceSyncDevice device;
  final bool Function() isCurrent;
  final void Function(DeviceSyncStatus) onStatus;
  CancelToken? _cancellation;
  Future<void>? _running;
  bool locationAttempted = false;
  bool _locationUnavailable = false;
  DeviceSyncLocation? _capturedLocation;
  bool get cancelled => _cancellation?.isCancelled ?? false;

  Future<void> run(DeviceSyncPreferences preferences,
      {required String locationClientID}) {
    final running = _running;
    if (running != null) return running;
    final token = _cancellation = CancelToken();
    return _running = _run(preferences, locationClientID, token)
        .whenComplete(() => _running = null);
  }

  void cancel() => _cancellation?.cancel('Device sync paused');

  void discardLocation() {
    if (_capturedLocation != null) locationAttempted = true;
    _capturedLocation = null;
    _locationUnavailable = true;
  }

  bool _canWrite(CancelToken token) => isCurrent() && !token.isCancelled;

  void _check(CancelToken token) {
    if (!isCurrent() || token.isCancelled) {
      throw StateError('Device sync retired');
    }
  }

  Future<void> _run(DeviceSyncPreferences preferences, String locationID,
      CancelToken token) async {
    _check(token);
    if (!preferences.enabled) return;
    if (preferences.location) {
      if (store.pendingLocations.any((point) => point.clientID == locationID)) {
        locationAttempted = true;
        _locationUnavailable = false;
      }
      if (!locationAttempted) {
        final point = _capturedLocation ??
            await source.locate(locationID, cancelToken: token);
        _check(token);
        _locationUnavailable = point == null;
        if (point != null) {
          // Keep one in-memory fix if persistence fails; never reacquire GPS
          // just because a durable enqueue needs to be retried.
          _capturedLocation = point;
          await store.enqueueLocation(point, isCurrent: () => _canWrite(token));
          _check(token);
          _capturedLocation = null;
        }
        // A canceled capture remains eligible; denied/no fix is not polled.
        locationAttempted = true;
      }
      final pending = store.pendingLocations;
      if (!_locationUnavailable && pending.isNotEmpty) {
        await api.locations(pending, cancelToken: token);
        _check(token);
        await store.removeLocations(pending.map((point) => point.clientID),
            isCurrent: () => _canWrite(token));
        _check(token);
      }
    }
    if (!preferences.photos) {
      onStatus(DeviceSyncStatus.idle);
      return;
    }
    if (preferences.wifiOnly && !await source.hasUnmeteredNetwork()) {
      _check(token);
      onStatus(DeviceSyncStatus.paused);
      return;
    }
    _check(token);
    onStatus(DeviceSyncStatus.scanning);
    var foundMedia = false;
    await for (final page in source.pages(includeVideos: preferences.videos)) {
      _check(token);
      for (final asset in page) {
        _check(token);
        if (!(asset.kind == 'video'
                ? DeviceSyncMedia.videoTypes
                : DeviceSyncMedia.imageTypes)
            .contains(asset.contentType)) {
          continue;
        }
        if (asset.kind == 'video' && !preferences.videos) continue;
        foundMedia = true;
        if (store.isCompleted(asset.id, asset.fingerprint)) continue;
        if (preferences.wifiOnly && !await source.hasUnmeteredNetwork()) {
          _check(token);
          onStatus(DeviceSyncStatus.paused);
          return;
        }
        _check(token);
        final ownedFile = await source.openFile(asset, cancelToken: token);
        if (ownedFile == null) continue;
        try {
          _check(token);
          final file = ownedFile.file;
          final snapshot = await file.stat();
          _check(token);
          final limit =
              asset.kind == 'video' ? 512 * 1024 * 1024 : 30 * 1024 * 1024;
          if (snapshot.type != FileSystemEntityType.file ||
              snapshot.size <= 0 ||
              snapshot.size > limit) {
            continue;
          }
          final previous = store.prepared(asset.id, asset.fingerprint);
          late DeviceSyncMedia media;
          {
            final digest = await hasher.hash(file, cancelToken: token);
            _check(token);
            await _checkFile(file, snapshot, token);
            media = DeviceSyncMedia(
              localID: previous?.sha256 == digest
                  ? previous!.localID
                  : _id(asset.id),
              sha256: digest,
              size: snapshot.size,
              kind: DeviceSyncMediaKind.values.byName(asset.kind),
              name: asset.name,
              capturedAt: asset.capturedAt,
              contentType: asset.contentType,
            );
            try {
              media.validate();
            } on ArgumentError {
              continue;
            }
            await store.saveMedia(asset.id, asset.fingerprint, media,
                isCurrent: () => _canWrite(token));
            _check(token);
          }
          final completed =
              await _upload(file, snapshot, asset, media, preferences, token);
          _check(token);
          if (completed != null) {
            await _checkFile(file, snapshot, token);
            await store.saveMedia(asset.id, asset.fingerprint, completed,
                done: true, isCurrent: () => _canWrite(token));
            _check(token);
          } else {
            return;
          }
        } finally {
          await ownedFile.dispose();
        }
        // No decode/compress, whole-file buffering or progress-driven UI rebuild.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        _check(token);
      }
    }
    _check(token);
    onStatus(foundMedia
        ? DeviceSyncStatus.idle
        : DeviceSyncStatus.waitingPermission);
  }

  String _id(String assetID, [String? hash]) => 'album_${crypto.sha256.convert(
        utf8.encode(
            '${device.deviceID}|$assetID${hash == null ? '' : '|$hash'}'),
      )}';

  Future<DeviceSyncMedia?> _upload(
      File file,
      FileStat snapshot,
      DeviceSyncAsset asset,
      DeviceSyncMedia original,
      DeviceSyncPreferences preferences,
      CancelToken token) async {
    var media = original;
    var probe = (await api.probe([media], cancelToken: token)).single;
    _check(token);
    if (probe.state == DeviceSyncMediaState.conflict) {
      media = media.copyWith(localID: _id(asset.id, media.sha256));
      await store.saveMedia(asset.id, asset.fingerprint, media,
          isCurrent: () => _canWrite(token));
      _check(token);
      probe = (await api.probe([media], cancelToken: token)).single;
      _check(token);
      if (probe.state == DeviceSyncMediaState.conflict) {
        throw StateError('Repeated media conflict');
      }
    }
    if (probe.state == DeviceSyncMediaState.done) return media;
    onStatus(DeviceSyncStatus.uploading);
    for (var round = 0; round < 3; round++) {
      final ticket = await api.ticket(media, cancelToken: token);
      _check(token);
      if (ticket.state == DeviceSyncMediaState.done) return media;
      for (final part in ticket.pendingParts) {
        _check(token);
        if (preferences.wifiOnly && !await source.hasUnmeteredNetwork()) {
          _check(token);
          onStatus(DeviceSyncStatus.paused);
          return null;
        }
        await _checkFile(file, snapshot, token);
        await api.putPart(file, ticket, part, cancelToken: token);
        _check(token);
      }
      await _checkFile(file, snapshot, token);
      final receipt = await api.finish(media, cancelToken: token);
      _check(token);
      if (receipt.state == DeviceSyncMediaState.done) return media;
      // Re-ticket the same localID, and skip server-confirmed doneParts.
    }
    throw StateError('Device sync confirmation incomplete');
  }

  Future<void> _checkFile(
      File file, FileStat expected, CancelToken token) async {
    final actual = await file.stat();
    _check(token);
    if (actual.size != expected.size || actual.modified != expected.modified) {
      throw StateError('Media changed while uploading');
    }
  }
}
