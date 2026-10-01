import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class PersonalSticker {
  PersonalSticker.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        mediaType = json['mediaType'] as String,
        mediaURL = json['mediaURL'] as String,
        thumbnailURL = json['thumbnailURL'] as String?,
        mimeType = json['mimeType'] as String,
        sizeBytes = (json['sizeBytes'] as num).toInt(),
        width = (json['width'] as num).toInt(),
        height = (json['height'] as num).toInt(),
        durationMs = (json['durationMs'] as num?)?.toInt(),
        sortOrder = (json['sortOrder'] as num).toInt(),
        version = (json['version'] as num).toInt(),
        createdAt = (json['createdAt'] as num).toInt(),
        updatedAt = (json['updatedAt'] as num).toInt();

  final String id;
  final String mediaType;
  final String mediaURL;
  final String? thumbnailURL;
  final String mimeType;
  final int sizeBytes;
  final int width;
  final int height;
  final int? durationMs;
  final int sortOrder;
  final int version;
  final int createdAt;
  final int updatedAt;

  bool get isVideo => mediaType == 'video';
  String get previewURL => isVideo ? thumbnailURL ?? '' : mediaURL;

  Map<String, dynamic> toJson() => {
        'id': id,
        'mediaType': mediaType,
        'mediaURL': mediaURL,
        'thumbnailURL': thumbnailURL,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'width': width,
        'height': height,
        'durationMs': durationMs,
        'sortOrder': sortOrder,
        'version': version,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class PersonalStickerApi {
  PersonalStickerApi({Dio? client}) : client = client ?? dio;
  final Dio client;

  String get _base => '${Config.appAuthUrl}/chat/stickers';

  Options get _options => Options(headers: {
        'token': DataSp.chatToken,
        'operationID': const Uuid().v4(),
        'Content-Type': 'application/json',
      });

  Map<String, dynamic> _data(Response<dynamic> response) {
    final body = Map<String, dynamic>.from(response.data as Map);
    final code = body['errCode'] as int? ?? -1;
    if (code != 0) {
      throw StickerApiException(code, body['errMsg']?.toString() ?? '');
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<({List<PersonalSticker> items, String? nextCursor})> page(
      {String? cursor, int limit = 50}) async {
    final data = _data(await client.get(_base,
        queryParameters: {
          'limit': limit,
          if (cursor != null) 'cursor': cursor,
        },
        options: _options));
    return (
      items: (data['items'] as List)
          .map((item) =>
              PersonalSticker.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      nextCursor: data['nextCursor'] as String?,
    );
  }

  Future<PersonalSticker> create(String mediaURL, String requestID) async {
    final data = _data(await client.post(_base,
        data: {'mediaURL': mediaURL, 'clientRequestID': requestID},
        options: _options));
    return PersonalSticker.fromJson(
        Map<String, dynamic>.from(data['item'] as Map));
  }

  Future<void> delete(String id) async {
    _data(await client.delete('$_base/${Uri.encodeComponent(id)}',
        options: _options));
  }

  Future<void> reorder(List<String> ids) async {
    _data(await client.put('$_base/order',
        data: {'ids': ids}, options: _options));
  }
}

class StickerApiException implements Exception {
  StickerApiException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => message.isEmpty ? 'Sticker error $code' : message;
}

class PersonalStickerStore extends ChangeNotifier {
  PersonalStickerStore({PersonalStickerApi? api})
      : api = api ?? PersonalStickerApi();
  final PersonalStickerApi api;
  final List<PersonalSticker> items = [];
  String? nextCursor;
  bool loading = false;
  bool saving = false;
  String? error;
  String? _accountKey;
  bool _disposed = false;

  String? get _currentKey {
    final userID = DataSp.userID;
    if (userID == null || userID.isEmpty) return null;
    return 'personalStickers:${Config.appAuthUrl}:$userID';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> _ensureAccount() async {
    final key = _currentKey;
    if (key == _accountKey) return key != null;
    _accountKey = key;
    items.clear();
    nextCursor = null;
    loading = false;
    saving = false;
    error = null;
    _notify();
    if (key == null) return false;
    final prefs = await SharedPreferences.getInstance();
    if (_accountKey != key || _disposed) return false;
    try {
      final cached = prefs.getString(key);
      if (cached != null) {
        items.addAll((jsonDecode(cached) as List).map((item) =>
            PersonalSticker.fromJson(Map<String, dynamic>.from(item as Map))));
        _notify();
      }
    } catch (_) {
      items.clear();
    }
    return true;
  }

  Future<void> _save() async {
    final key = _accountKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (key == _accountKey && key == _currentKey && !_disposed) {
      await prefs.setString(
          key, jsonEncode(items.map((item) => item.toJson()).toList()));
    }
  }

  Future<void> refresh() async {
    if (!await _ensureAccount() || loading) return;
    final account = _accountKey;
    loading = true;
    error = null;
    _notify();
    try {
      final page = await api.page();
      if (account != _accountKey || account != _currentKey || _disposed) return;
      items
        ..clear()
        ..addAll(page.items);
      nextCursor = page.nextCursor;
      await _save();
    } catch (e) {
      if (account == _accountKey && account == _currentKey) {
        error = e.toString();
      }
    } finally {
      if (account == _accountKey) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    if (!await _ensureAccount()) return;
    final cursor = nextCursor;
    if (cursor == null || loading) return;
    final account = _accountKey;
    loading = true;
    error = null;
    _notify();
    try {
      final page = await api.page(cursor: cursor);
      if (account != _accountKey || account != _currentKey || _disposed) return;
      final existing = items.map((item) => item.id).toSet();
      items.addAll(page.items.where((item) => !existing.contains(item.id)));
      nextCursor = page.nextCursor;
      await _save();
    } catch (e) {
      if (account == _accountKey && account == _currentKey) {
        error = e.toString();
      }
    } finally {
      if (account == _accountKey) {
        loading = false;
        _notify();
      }
    }
  }

  Future<PersonalSticker> add(String mediaURL, String requestID) async {
    if (!await _ensureAccount()) throw StateError('Not logged in');
    final account = _accountKey;
    saving = true;
    _notify();
    try {
      final item = await api.create(mediaURL, requestID);
      if (account == _accountKey && account == _currentKey && !_disposed) {
        items.removeWhere((old) => old.id == item.id);
        items.insert(0, item);
        await _save();
      }
      return item;
    } finally {
      if (account == _accountKey) {
        saving = false;
        _notify();
      }
    }
  }

  Future<void> remove(PersonalSticker item) async {
    if (!await _ensureAccount()) return;
    final account = _accountKey;
    await api.delete(item.id);
    if (account != _accountKey || account != _currentKey || _disposed) return;
    items.removeWhere((old) => old.id == item.id);
    await _save();
    _notify();
  }

  Future<void> reorder(List<String> ids) async {
    if (!await _ensureAccount()) return;
    final account = _accountKey;
    try {
      await api.reorder(ids);
    } on StickerApiException catch (e) {
      if (e.code == 20025) await refresh();
      rethrow;
    }
    if (account != _accountKey || account != _currentKey || _disposed) return;
    final byID = {for (final item in items) item.id: item};
    items
      ..clear()
      ..addAll(ids.map((id) => byID[id]).whereType<PersonalSticker>());
    await _save();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
