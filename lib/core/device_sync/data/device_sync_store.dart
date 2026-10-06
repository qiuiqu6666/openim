import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../models/device_sync_models.dart';
import '../models/device_sync_preferences.dart';

/// A fixed account/endpoint/device owner. No tokens, URLs or media bytes stored.
class DeviceSyncStore {
  DeviceSyncStore._(this.accountID, this._box);
  final String accountID;
  final Box<dynamic> _box;
  Future<void> _writes = Future.value();

  static Future<DeviceSyncStore> open({
    required String accountID,
    required String endpoint,
    required String deviceID,
  }) async {
    final scope = sha256.convert(utf8.encode('$endpoint|$accountID|$deviceID'));
    final box = await Hive.openBox<dynamic>('device_sync_${scope.toString()}');
    return DeviceSyncStore._(accountID, box);
  }

  DeviceSyncPreferences get preferences =>
      DeviceSyncPreferences.fromJson(accountID, _box.get('preferences'));

  Future<void> savePreferences(DeviceSyncPreferences preferences,
      {bool Function()? isCurrent}) {
    if (preferences.accountID != accountID) {
      throw StateError('Device sync preference owner mismatch');
    }
    return _write(() => _box.put('preferences', preferences.toJson()),
        isCurrent: isCurrent);
  }

  String _assetKey(String id) => 'asset_${sha256.convert(utf8.encode(id))}';

  bool isCompleted(String id, String fingerprint) {
    final item = _box.get(_assetKey(id));
    return item is Map &&
        item['fingerprint'] == fingerprint &&
        item['done'] == true;
  }

  DeviceSyncMedia? prepared(String id, String fingerprint) {
    final item = _box.get(_assetKey(id));
    if (item is! Map || item['fingerprint'] != fingerprint) return null;
    try {
      final data = Map<String, dynamic>.from(item['media'] as Map);
      return DeviceSyncMedia(
        localID: data['localID'] as String,
        sha256: data['sha256'] as String,
        size: data['size'] as int,
        kind: DeviceSyncMediaKind.values.byName(data['kind'] as String),
        name: data['name'] as String?,
        capturedAt: data['capturedAt'] as int,
        contentType: data['contentType'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMedia(String id, String fingerprint, DeviceSyncMedia media,
          {bool done = false, bool Function()? isCurrent}) =>
      _write(
          () => _box.put(_assetKey(id), {
                'fingerprint': fingerprint,
                'done': done,
                'media': {
                  'localID': media.localID,
                  'sha256': media.sha256,
                  'size': media.size,
                  'kind': media.kind.name,
                  'name': media.name,
                  'capturedAt': media.capturedAt,
                  'contentType': media.contentType,
                },
              }),
          isCurrent: isCurrent);

  Future<void> enqueueLocation(DeviceSyncLocation point,
          {bool Function()? isCurrent}) =>
      _write(() async {
        // Bound offline retry data; never accumulate a continuous location history.
        final keys = _box.keys
            .where((k) => k is String && k.startsWith('point_'))
            .toList();
        if (keys.length >= 100 &&
            !_box.containsKey('point_${point.clientID}')) {
          await _box.delete(keys.first);
        }
        _checkCurrent(isCurrent);
        await _box.put('point_${point.clientID}', {
          'clientID': point.clientID,
          'latitude': point.latitude,
          'longitude': point.longitude,
          'accuracy': point.accuracy,
          'recordedAt': point.recordedAt,
        });
      }, isCurrent: isCurrent);

  List<DeviceSyncLocation> get pendingLocations {
    final result = <DeviceSyncLocation>[];
    for (final key
        in _box.keys.where((k) => k is String && k.startsWith('point_'))) {
      try {
        final value = _box.get(key) as Map;
        result.add(DeviceSyncLocation(
          clientID: value['clientID'] as String,
          latitude: (value['latitude'] as num).toDouble(),
          longitude: (value['longitude'] as num).toDouble(),
          accuracy: (value['accuracy'] as num).toDouble(),
          recordedAt: value['recordedAt'] as int,
        ));
      } catch (_) {/* Ignore invalid local records; never send them. */}
      if (result.length == 100) break;
    }
    return result;
  }

  Future<void> removeLocations(Iterable<String> ids,
          {bool Function()? isCurrent}) =>
      _write(() => _box.deleteAll(ids.map((id) => 'point_$id')),
          isCurrent: isCurrent);

  Future<void> clearLocations({bool Function()? isCurrent}) => _write(
      () => _box.deleteAll(
            _box.keys
                .where((k) => k is String && k.startsWith('point_'))
                .toList(),
          ),
      isCurrent: isCurrent);

  void _checkCurrent(bool Function()? current) {
    if (current != null && !current()) {
      throw StateError('Device sync write retired');
    }
  }

  Future<void> _write(Future<void> Function() operation,
      {bool Function()? isCurrent}) {
    final next = _writes.then((_) {
      _checkCurrent(isCurrent);
      return operation();
    });
    _writes = next.catchError((Object _) {});
    return next;
  }
}
