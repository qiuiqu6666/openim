import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'favorite_api.dart';
import '../pages/favorites/data/favorite_sync_state.dart';
import '../pages/favorites/data/favorite_change_synchronizer.dart';
import '../pages/favorites/data/favorite_mutation_outbox.dart';
import '../pages/favorites/data/favorite_mutation_replayer.dart';
import '../pages/favorites/data/favorite_archive_retry_recovery.dart';
import '../pages/favorites/data/favorite_media_upload.dart';

export 'favorite_api.dart';
export '../pages/favorites/data/favorite_mutation_outbox.dart';

/// Private cloud favorites. Only server-confirmed items enter the live list.
/// Metadata caches are an account-scoped preview and are always refreshed.
class FavoriteRepository extends ChangeNotifier {
  FavoriteRepository(
      {FavoriteApi? api,
      String? Function()? userIDProvider,
      FavoriteMutationOutbox? outbox,
      this.cacheWriter,
      this.pollInterval = const Duration(seconds: 2),
      this.cacheEnabled = true})
      : api = api ?? FavoriteApi(),
        outbox = outbox ?? FavoriteMutationOutbox(),
        _userIDProvider = userIDProvider ?? (() => DataSp.userID);
  static final FavoriteRepository instance = FavoriteRepository();
  final FavoriteApi api;
  final FavoriteMutationOutbox outbox;
  final String? Function() _userIDProvider;
  final Duration pollInterval;
  final bool cacheEnabled;

  /// Optional storage fault hook. Production uses SharedPreferences directly.
  final Future<bool> Function(String key, String value)? cacheWriter;
  Future<void> _cacheWrites = Future<void>.value();
  final List<FavoriteItem> _items = [];
  final List<FavoriteTag> _tags = [];
  final Set<String> _deletedIDs = {};
  final Map<String, FavoriteItem> _details = {};
  final Map<String, String> _requestIDs = {};
  final Map<String, FavoriteMediaTask> _mediaTasks = {};
  final Set<String> _archiveIDs = {};
  String? _accountKey;
  String? _token;
  int _generation = 0;
  int _queryGeneration = 0;
  int _savingCount = 0;
  bool _disposed = false;
  Future<void>? _cacheLoad;
  Future<void>? _outboxLoad;
  final Map<String, FavoriteMutationEntry> _pendingRecovery = {};
  final Set<String> _activeMutationKeys = {};
  final Set<String> _blockedMutationKeys = {};
  String? replayError;
  List<FavoriteMutationEntry> get pendingRecovery {
    _switchSessionIfNeeded();
    return List.unmodifiable(_pendingRecovery.values);
  }

  CancelToken _sessionCancel = CancelToken();
  CancelToken? _listCancel;
  CancelToken? _pollCancel;
  CancelToken? _tagCancel;
  Timer? _pollTimer;
  bool _pollInFlight = false;
  int _pollAttempts = 0;
  String? _nextCursor;
  int? _listBaseline;
  FavoriteQuota? _quota;
  Future<FavoriteQuota>? _capabilityRequest;
  bool _capabilitiesLoading = false;
  String? _capabilityError;
  FavoriteSyncState _syncState = const FavoriteSyncState();
  Future<void>? _syncRequest;
  bool syncing = false;
  String? syncError;
  String _query = '';
  FavoriteKind? _kind;
  String? _tagID;
  bool loading = false;
  bool loadingMore = false;
  bool loadingTags = false;
  String? error;
  String? tagError;
  bool isCached = false;
  double? uploadProgress;

  List<FavoriteItem> get items {
    _switchSessionIfNeeded();
    return available ? List.unmodifiable(_items) : const [];
  }

  FavoriteQuota? get quota {
    _switchSessionIfNeeded();
    return _quota;
  }

  bool get available {
    _switchSessionIfNeeded();
    return _quota?.available == true;
  }

  bool get capabilitiesLoading {
    _switchSessionIfNeeded();
    return _capabilitiesLoading;
  }

  String? get capabilityError {
    _switchSessionIfNeeded();
    return _capabilityError;
  }

  int get syncAt {
    _switchSessionIfNeeded();
    return _syncState.syncAt;
  }

  Future<FavoriteQuota> ensureCapabilities({bool force = false}) async {
    final scope = await _ensureSession();
    if (_capabilityRequest != null) return _capabilityRequest!;
    if (!force && _quota != null) return _quota!;
    final request = _fetchCapabilities(scope);
    _capabilityRequest = request;
    try {
      return await request;
    } finally {
      if (isSessionCurrent(scope) && identical(_capabilityRequest, request)) {
        _capabilityRequest = null;
      }
    }
  }

  Future<FavoriteQuota> _fetchCapabilities(String scope) async {
    _capabilitiesLoading = true;
    _capabilityError = null;
    _quota = null;
    _notify();
    try {
      final result = await api.getQuota(cancelToken: _sessionCancel);
      _guard(scope);
      _quota = result;
      if (!result.available) stopPolling();
      return result;
    } catch (failure) {
      if (isSessionCurrent(scope)) {
        _quota = null;
        _capabilityError =
            failure is FavoriteApiException ? failure.message : '无法取得收藏能力，请重试';
      }
      rethrow;
    } finally {
      if (isSessionCurrent(scope)) {
        _capabilitiesLoading = false;
        _notify();
      }
    }
  }

  Future<void> requireAvailable() async {
    final result = await ensureCapabilities();
    if (!result.available) {
      throw const FavoriteApiException('FAVORITES_UNAVAILABLE', '收藏与快捷发送暂未开放');
    }
  }

  /// Notifications, reconnect and foreground calls share one delta request.
  /// Notification bodies are only hints; all records come from authenticated API.
  Future<void> syncChanges() async {
    final scope = await _ensureSession();
    await requireAvailable();
    _guard(scope);
    if (_syncRequest != null) return _syncRequest!;
    final request = _runSync(scope);
    _syncRequest = request;
    try {
      await request;
    } finally {
      if (isSessionCurrent(scope) && identical(_syncRequest, request)) {
        _syncRequest = null;
      }
    }
  }

  Future<void> _runSync(String scope) async {
    syncing = true;
    syncError = null;
    _notify();
    var changed = false;
    try {
      await FavoriteChangeSynchronizer(api).run(
          updatedAfter: _syncState.syncAt,
          cancelToken: _sessionCancel,
          commit: (page) async {
            _guard(scope);
            final previous = _syncState;
            _syncState = previous.apply(page);
            try {
              await _saveCache(scope, strict: true);
            } catch (_) {
              if (isSessionCurrent(scope)) _syncState = previous;
              rethrow;
            }
            _guard(scope);
            for (final event in page.events) {
              final removedVersion = _syncState.tombstones[event.id] ?? 0;
              if (removedVersion >= event.version &&
                  event.operation == 'delete') {
                _deletedIDs.add(event.id);
                _items.removeWhere((item) =>
                    item.id == event.id && item.version <= removedVersion);
                if ((_details[event.id]?.version ?? 0) <= removedVersion) {
                  _details.remove(event.id);
                }
                _archiveIDs.remove(event.id);
              } else if (event.item != null) {
                _merge(event.item!);
                _trackArchives([event.item!]);
              }
            }
            changed = changed || page.events.isNotEmpty;
            _notify();
          },
          rebuild: () async {
            _guard(scope);
            // Keep pending UUIDs and completed uploads; only rebuild cloud cache.
            final previous = _syncState;
            _syncState = const FavoriteSyncState();
            try {
              await _saveCache(scope, strict: true, clearItems: true);
            } catch (_) {
              if (isSessionCurrent(scope)) _syncState = previous;
              rethrow;
            }
            _guard(scope);
            _items.clear();
            _details.clear();
            _deletedIDs.clear();
            _archiveIDs.clear();
            stopPolling();
            _nextCursor = null;
            _listBaseline = null;
            changed = true;
          });
      if (changed) await refresh();
      await replayPendingMutations();
      _guard(scope);
    } catch (failure) {
      if (isSessionCurrent(scope) &&
          !(failure is FavoriteApiException && failure.isCancelled)) {
        syncError =
            failure is FavoriteApiException ? failure.message : '收藏同步失败，请重试';
      }
      rethrow;
    } finally {
      if (isSessionCurrent(scope)) {
        syncing = false;
        _notify();
      }
    }
  }

  List<FavoriteTag> get tags {
    _switchSessionIfNeeded();
    return List.unmodifiable(_tags);
  }

  bool get saving => _savingCount > 0;
  bool get hasMore => _nextCursor != null;
  String get query => _query;
  FavoriteKind? get filterKind => _kind;
  String? get filterTagID => _tagID;
  String get accountNamespace {
    final user = _userIDProvider();
    return user == null || user.isEmpty ? '' : 'favorites:${api.baseUrl}:$user';
  }

  String get sessionScope {
    _switchSessionIfNeeded();
    return '$_generation:${_accountKey ?? ''}';
  }

  bool isSessionCurrent(String scope) =>
      !_disposed &&
      _accountKey == accountNamespace &&
      _token == api.sessionToken &&
      scope == '$_generation:${_accountKey ?? ''}';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _switchSessionIfNeeded() {
    final key = accountNamespace;
    final token = api.sessionToken;
    if (_accountKey == key && _token == token) return;
    _sessionCancel.cancel();
    _listCancel?.cancel();
    _tagCancel?.cancel();
    stopPolling();
    _generation++;
    _queryGeneration++;
    _accountKey = key;
    _token = token;
    _sessionCancel = CancelToken();
    _items.clear();
    _tags.clear();
    _deletedIDs.clear();
    _details.clear();
    _requestIDs.clear();
    _mediaTasks.clear();
    _archiveIDs.clear();
    _nextCursor = null;
    _listBaseline = null;
    _quota = null;
    _capabilityRequest = null;
    _capabilitiesLoading = false;
    _capabilityError = null;
    _syncState = const FavoriteSyncState();
    _syncRequest = null;
    syncing = false;
    syncError = null;
    _query = '';
    _kind = null;
    _tagID = null;
    loading = false;
    loadingMore = false;
    loadingTags = false;
    _savingCount = 0;
    error = null;
    tagError = null;
    isCached = false;
    uploadProgress = null;
    _cacheLoad = null;
    _outboxLoad = null;
    _pendingRecovery.clear();
    _activeMutationKeys.clear();
    _blockedMutationKeys.clear();
    replayError = null;
  }

  void resetSession() {
    _accountKey = null;
    _token = null;
    _switchSessionIfNeeded();
    _notify();
  }

  Future<String> _ensureSession() async {
    final scope = sessionScope;
    if (_accountKey == null ||
        _accountKey!.isEmpty ||
        _token == null ||
        _token!.isEmpty) {
      throw const FavoriteApiException('AUTH_INVALID', '请先登录');
    }
    _cacheLoad ??= _loadCache(scope);
    await _cacheLoad;
    _guard(scope);
    _outboxLoad ??= _loadOutbox(scope);
    final reading = _outboxLoad;
    try {
      await reading;
    } catch (_) {
      if (isSessionCurrent(scope) && identical(_outboxLoad, reading)) {
        _outboxLoad = null;
      }
      rethrow;
    }
    _guard(scope);
    return scope;
  }

  Future<void> _loadOutbox(String scope) async {
    try {
      final entries = await outbox.list(accountNamespace);
      final confirmed = await outbox.readConfirmed(accountNamespace);
      _guard(scope);
      for (final entry in confirmed.entries) {
        if (_requestIDs[entry.key] == entry.value) {
          _requestIDs.remove(entry.key);
        }
      }
      for (final entry in entries) {
        _requestIDs[entry.key] = entry.clientRequestID;
        _pendingRecovery[entry.key] = entry;
      }
    } on FavoriteApiException {
      rethrow;
    } catch (_) {
      throw const FavoriteApiException(
          'LOCAL_SAVE_FAILED', '无法读取待提交收藏，请检查设备存储后重试');
    }
  }

  FavoriteMutationEntry _pending(
          String key,
          FavoriteMutationOperation operation,
          String request,
          Map<String, dynamic> body,
          {String? itemID}) =>
      FavoriteMutationEntry(
          key: _actionKey(key),
          operation: operation,
          clientRequestID: request,
          itemID: itemID,
          body: {'clientRequestID': request, ...body});

  Future<void> _putPending(String scope, FavoriteMutationEntry entry) async {
    _guard(scope);
    try {
      await outbox.put(accountNamespace, entry);
    } catch (_) {
      throw const FavoriteApiException(
          'LOCAL_SAVE_FAILED', '无法保存本次操作，请检查设备存储后重试');
    }
    _guard(scope);
    _pendingRecovery[entry.key] = entry;
  }

  Future<bool> _removePending(String scope, String key,
      {String? confirmedRequestID}) async {
    _guard(scope);
    try {
      if (confirmedRequestID == null) {
        await outbox.remove(accountNamespace, key);
      } else {
        await outbox.complete(accountNamespace, key, confirmedRequestID);
      }
    } catch (_) {
      if (isSessionCurrent(scope)) replayError = '收藏结果已确认，待提交记录清理失败，将安全复核';
      return false;
    }
    _guard(scope);
    _pendingRecovery.remove(key);
    _blockedMutationKeys.remove(key);
    if (_pendingRecovery.isEmpty) replayError = null;
    return true;
  }

  bool _terminalFailure(FavoriteApiException failure) =>
      !failure.isUncertain &&
      !failure.isCancelled &&
      (failure.code == 1001 ||
          (failure.code is int &&
              (failure.code as int) >= 20050 &&
              (failure.code as int) <= 20067 &&
              !{20061, 20065, 20066}.contains(failure.code)));

  Future<void> replayPendingMutations() async {
    final scope = await _ensureSession();
    await requireAvailable();
    _guard(scope);
    var changed = false;
    for (final entry in _pendingRecovery.values.toList()) {
      if (_activeMutationKeys.contains(entry.key) ||
          _blockedMutationKeys.contains(entry.key)) {
        continue;
      }
      _guard(scope);
      _activeMutationKeys.add(entry.key);
      try {
        final result = await FavoriteMutationReplayer(api,
                guard: () => _guard(scope),
                onArchiveRetryAcknowledged: (entry, ack) =>
                    _acknowledgeArchiveRetry(scope, entry, ack))
            .replay(entry, _sessionCancel);
        _guard(scope);
        if (result.item != null) {
          _merge(result.item!);
          _trackArchives([result.item!]);
        }
        if (result.deletedID != null) {
          _markDeleted(result.deletedID!, result.deletedVersion!);
        }
        if (result.batch != null) {
          final requests = entry.body['items'] as List;
          for (final item in result.batch!.items) {
            if (item.deleted) {
              final sent = requests
                  .map(favoriteJsonMap)
                  .firstWhere((value) => value['id'] == item.id);
              _markDeleted(item.id, (sent['expectedVersion'] as int) + 1);
            } else if (item.currentItem != null) {
              _merge(item.currentItem!);
            }
          }
        }
        if (await _removePending(scope, entry.key,
            confirmedRequestID: entry.clientRequestID)) {
          _requestIDs.remove(entry.key);
        }
        await _saveCache(scope);
        changed = true;
      } catch (failure) {
        if (!isSessionCurrent(scope)) rethrow;
        if (failure is FavoriteApiException && failure.isVersionConflict) {
          _blockedMutationKeys.add(entry.key);
          replayError = '待恢复的收藏编辑发生版本冲突，原编辑内容已保留，请确认后处理';
          if (failure.currentItem != null) _merge(failure.currentItem!);
        } else if (failure is FavoriteApiException &&
            _terminalFailure(failure)) {
          var invalidatedMedia = false;
          if (await _removePending(scope, entry.key,
              confirmedRequestID: entry.clientRequestID)) {
            _requestIDs.remove(entry.key);
            if (failure.code == 20056) {
              try {
                invalidatedMedia =
                    await _invalidateRejectedMediaCreate(scope, entry);
              } on FavoriteApiException catch (checkpointFailure) {
                replayError = checkpointFailure.message;
                rethrow;
              }
            }
          }
          replayError =
              invalidatedMedia ? _rejectedMediaMessage : failure.message;
          await _saveCache(scope);
        } else {
          replayError = failure is FavoriteApiException
              ? failure.message
              : '收藏操作结果待确认，待提交内容已保留';
          rethrow;
        }
      } finally {
        if (isSessionCurrent(scope)) _activeMutationKeys.remove(entry.key);
      }
    }
    if (changed) await refresh();
    _notify();
  }

  /// Call only after the user reviewed the current record and a replacement
  /// edit was confirmed. Unknown writes and unrelated pending actions survive.
  Future<void> resolveConflictingEdits(String itemID,
      {required int throughVersion}) async {
    final scope = await _ensureSession();
    _guard(scope);
    for (final entry in _pendingRecovery.values.toList()) {
      if (entry.operation != FavoriteMutationOperation.update ||
          entry.itemID != itemID ||
          !_blockedMutationKeys.contains(entry.key) ||
          entry.body['expectedVersion'] is! int ||
          (entry.body['expectedVersion'] as int) > throughVersion) {
        continue;
      }
      if (await _removePending(scope, entry.key,
          confirmedRequestID: entry.clientRequestID)) {
        if (_requestIDs[entry.key] == entry.clientRequestID) {
          _requestIDs.remove(entry.key);
        }
      }
    }
    if (_pendingRecovery.isEmpty) replayError = null;
    await _saveCache(scope);
    _notify();
  }

  void _markDeleted(String id, int version) {
    _items.removeWhere((item) => item.id == id);
    _deletedIDs.add(id);
    _details.remove(id);
    _archiveIDs.remove(id);
    _syncState = _syncState.delete(id, version);
  }

  void _guard(String scope) {
    if (!isSessionCurrent(scope)) {
      throw const FavoriteApiException('SESSION_CHANGED', '账号已切换，请重新操作',
          isCancelled: true);
    }
  }

  Future<void> _loadCache(String scope) async {
    final key = _accountKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!isSessionCurrent(scope)) return;
      final raw = prefs.getString('$key:metadata:v1');
      if (raw == null) return;
      final cache = favoriteJsonMap(jsonDecode(raw));
      if (cacheEnabled && cache['sync'] is Map) {
        _syncState = FavoriteSyncState.fromJson(favoriteJsonMap(cache['sync']));
        _deletedIDs.addAll(_syncState.tombstones.keys);
      }
      if (cacheEnabled && cache['items'] is List) {
        final parsed = (cache['items'] as List)
            .map((json) => FavoriteItem.fromJson(favoriteJsonMap(json)))
            .toList();
        if (!isSessionCurrent(scope)) return;
        _items
          ..clear()
          ..addAll(_latestItems(parsed));
        isCached = parsed.isNotEmpty;
      }
      if (cache['requests'] is Map) {
        final requests = favoriteJsonMap(cache['requests']);
        for (final entry in requests.entries) {
          if (entry.value is String &&
              RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key)) {
            _requestIDs[entry.key] = entry.value as String;
          }
        }
      }
      if (cache['mediaTasks'] is Map) {
        for (final entry in favoriteJsonMap(cache['mediaTasks']).entries) {
          final task = favoriteJsonMap(entry.value);
          if (task['uploadID'] is String) {
            _mediaTasks[entry.key] = FavoriteMediaTask.fromJson(task);
          }
        }
      }
      _notify();
    } catch (_) {/* Corrupt or unavailable caches never replace the cloud. */}
  }

  Future<void> _saveCache(String scope,
      {bool strict = false, bool clearItems = false}) {
    final write = _cacheWrites.then(
        (_) => _writeCache(scope, strict: strict, clearItems: clearItems));
    // A rejected strict write blocks only that operation, not future retries.
    _cacheWrites = write.catchError((Object _) {});
    return write;
  }

  Future<void> _writeCache(String scope,
      {required bool strict, required bool clearItems}) async {
    if (!isSessionCurrent(scope)) {
      if (strict) _guard(scope);
      return;
    }
    final key = _accountKey;
    final metadata = clearItems
        ? <Map<String, dynamic>>[]
        : cacheEnabled && _query.isEmpty && _kind == null && _tagID == null
            ? _items.map((item) => item.toCacheJson()).toList()
            : null;
    final requests = Map<String, String>.from(_requestIDs);
    final mediaTasks = <String, dynamic>{
      for (final entry in _mediaTasks.entries)
        if (entry.value.toCacheJson() != null)
          entry.key: entry.value.toCacheJson()
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!isSessionCurrent(scope)) {
        if (strict) _guard(scope);
        return;
      }
      List<dynamic> values = metadata ?? [];
      if (metadata == null) {
        final old = prefs.getString('$key:metadata:v1');
        if (old != null) {
          final parsed = favoriteJsonMap(jsonDecode(old));
          if (parsed['items'] is List) values = parsed['items'] as List;
        }
      }
      if (!isSessionCurrent(scope)) {
        if (strict) _guard(scope);
        return;
      }
      values = values
          .where((value) => !_deletedIDs.contains(favoriteJsonMap(value)['id']))
          .toList();
      final storageKey = '$key:metadata:v1';
      final value = jsonEncode({
        'items': values,
        'requests': requests,
        'mediaTasks': mediaTasks,
        if (cacheEnabled) 'sync': _syncState.toJson()
      });
      final success = await (cacheWriter?.call(storageKey, value) ??
          prefs.setString(storageKey, value));
      if (strict && !success) {
        throw const FavoriteApiException(
            'LOCAL_SAVE_FAILED', '无法保存本次操作，请检查设备存储后重试');
      }
      if (strict) _guard(scope);
    } catch (failure) {
      if (failure is FavoriteApiException && failure.isCancelled) rethrow;
      if (strict) {
        throw const FavoriteApiException(
            'LOCAL_SAVE_FAILED', '无法保存本次操作，请检查设备存储后重试');
      }
      // A metadata cache failure cannot undo a confirmed server mutation.
    }
  }

  String _actionKey(String key) => sha256.convert(utf8.encode(key)).toString();
  String _request(String key, String? explicit) {
    final hash = _actionKey(key);
    if (explicit != null) return _requestIDs[hash] = explicit;
    return _requestIDs.putIfAbsent(hash, FavoriteApi.newRequestID);
  }

  void _forgetRequest(String key) => _requestIDs.remove(_actionKey(key));
  void _captureError(Object failure, String scope) {
    if (!isSessionCurrent(scope)) return;
    if (failure is FavoriteApiException && failure.isCancelled) return;
    error =
        failure is FavoriteApiException ? failure.message : '收藏数据暂不可用，请刷新后重试';
  }

  void _captureTagError(Object failure, String scope) {
    if (!isSessionCurrent(scope) ||
        (failure is FavoriteApiException && failure.isCancelled)) {
      return;
    }
    tagError =
        failure is FavoriteApiException ? failure.message : '标签暂不可用，请稍后重试';
  }

  /// Passing query explicitly also makes kind:null clear the active filter.
  /// A plain refresh() retains the user's current query and filter.
  Future<void> refresh(
      {String? query, FavoriteKind? kind, String? tagID}) async {
    String scope;
    try {
      scope = await _ensureSession();
      await requireAvailable();
      _guard(scope);
    } catch (failure) {
      error = failure is FavoriteApiException ? failure.message : '请先登录';
      _notify();
      return;
    }
    final nextQuery = query ?? _query;
    final nextKind = query != null ? kind : kind ?? _kind;
    final nextTagID = query != null ? tagID : tagID ?? _tagID;
    final changed =
        nextQuery != _query || nextKind != _kind || nextTagID != _tagID;
    _query = nextQuery;
    _kind = nextKind;
    _tagID = nextTagID;
    if (changed) {
      _items.clear();
      isCached = false;
    }
    _listCancel?.cancel();
    final cancel = _listCancel = CancelToken();
    final requestGeneration = ++_queryGeneration;
    loading = true;
    loadingMore = false;
    error = null;
    _nextCursor = null;
    _notify();
    try {
      final page = await api.list(
          query: _query, kind: _kind, tagID: _tagID, cancelToken: cancel);
      if (!isSessionCurrent(scope) || requestGeneration != _queryGeneration) {
        return;
      }
      _items
        ..clear()
        ..addAll(_latestItems(page.items));
      _nextCursor = page.nextCursor;
      _listBaseline = page.syncAt;
      isCached = false;
      _trackArchives(page.items);
      await _saveCache(scope);
    } catch (failure) {
      if (requestGeneration == _queryGeneration) _captureError(failure, scope);
    } finally {
      if (isSessionCurrent(scope) && requestGeneration == _queryGeneration) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    final scope = await _ensureSession();
    await requireAvailable();
    _guard(scope);
    final cursor = _nextCursor;
    if (cursor == null || loading || loadingMore) return;
    final generation = _queryGeneration;
    final cancel = _listCancel ??= CancelToken();
    loadingMore = true;
    error = null;
    _notify();
    try {
      final page = await api.list(
          query: _query,
          kind: _kind,
          tagID: _tagID,
          cursor: cursor,
          baseline: _listBaseline,
          cancelToken: cancel);
      if (!isSessionCurrent(scope) || generation != _queryGeneration) return;
      final ids = _items.map((item) => item.id).toSet();
      _items.addAll(
          _latestItems(page.items).where((item) => !ids.contains(item.id)));
      _nextCursor = page.nextCursor;
      _trackArchives(page.items);
      await _saveCache(scope);
    } catch (failure) {
      if (generation == _queryGeneration) _captureError(failure, scope);
    } finally {
      if (isSessionCurrent(scope) && generation == _queryGeneration) {
        loadingMore = false;
        _notify();
      }
    }
  }

  Future<FavoriteItem> getDetail(String id) async {
    final scope = await _ensureSession();
    await requireAvailable();
    _guard(scope);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        _requireLiveItem(id);
        final item = await api.getDetail(id, cancelToken: _sessionCancel);
        _guard(scope);
        _requireLiveItem(id);
        final known = _newestKnown(id);
        if (known != null && known.version > item.version) {
          final complete = _details[id];
          if (complete?.content != null && complete!.version >= known.version) {
            return complete;
          }
          // A delta/list may have arrived while the detail was in flight. Get
          // the current body once; never return the obsolete body to an editor.
          if (attempt == 0) continue;
          throw FavoriteApiException(20061, '收藏已更新，请重新加载', currentItem: known);
        }
        _merge(item);
        _trackArchives([item]);
        _notify();
        return item;
      }
      throw StateError('Unreachable favorite detail state');
    } catch (failure) {
      _captureError(failure, scope);
      _notify();
      rethrow;
    }
  }

  void _requireLiveItem(String id) {
    if (_deletedIDs.contains(id) || _syncState.tombstones.containsKey(id)) {
      throw const FavoriteApiException(20050, '收藏不存在或无法访问');
    }
  }

  FavoriteItem? _newestKnown(String id) {
    FavoriteItem? result;
    for (final item in [
      _details[id],
      _syncState.items[id],
      _items.where((item) => item.id == id).firstOrNull
    ]) {
      if (item != null && (result == null || item.version > result.version)) {
        result = item;
      }
    }
    return result;
  }

  void _merge(FavoriteItem item) {
    if (_syncState.tombstones.containsKey(item.id) ||
        _deletedIDs.contains(item.id)) {
      return;
    }
    final old = _details[item.id];
    if ((_newestKnown(item.id)?.version ?? 0) > item.version) return;
    if (item.content != null) {
      _details[item.id] = item;
    } else if (old != null && old.version < item.version) {
      _details.remove(item.id);
    }
    _syncState = _syncState.remember(item);
    final index = _items.indexWhere((value) => value.id == item.id);
    if (index >= 0 && _items[index].version <= item.version) {
      if (item.status == FavoriteStatus.deleted) {
        _items.removeAt(index);
      } else {
        _items[index] = item;
      }
    }
  }

  Iterable<FavoriteItem> _latestItems(Iterable<FavoriteItem> values) => values
          .where((item) =>
              !_syncState.tombstones.containsKey(item.id) &&
              !_deletedIDs.contains(item.id))
          .map((item) {
        final newer = _details[item.id];
        final known = _syncState.items[item.id];
        final best =
            newer != null && newer.version > item.version ? newer : item;
        return known != null && known.version > best.version ? known : best;
      });

  Future<T> _mutation<T>(String key, String? clientRequestID,
      Future<T> Function(String, CancelToken) write,
      {bool tagOperation = false,
      FavoriteMutationEntry Function(String)? pending}) async {
    final scope = await _ensureSession();
    await requireAvailable();
    _guard(scope);
    final hashedKey = _actionKey(key);
    if (_activeMutationKeys.contains(hashedKey)) {
      throw const FavoriteApiException('TASK_BUSY', '这项收藏操作正在处理中，请稍后重试');
    }
    final requestID = _request(key, clientRequestID);
    _activeMutationKeys.add(hashedKey);
    _savingCount++;
    if (tagOperation) {
      tagError = null;
    } else {
      error = null;
    }
    _notify();
    try {
      await _saveCache(scope, strict: true);
      _guard(scope);
      if (pending != null) await _putPending(scope, pending(requestID));
      final result = await write(requestID, _sessionCancel);
      _guard(scope);
      if (await _removePending(scope, hashedKey,
          confirmedRequestID: requestID)) {
        _forgetRequest(key);
      }
      if (result is FavoriteItem) {
        _merge(result);
        _trackArchives([result]);
      }
      await _saveCache(scope);
      // Queries and ordering remain authoritative; no local search fabrication.
      await refresh();
      _guard(scope);
      return result;
    } catch (failure) {
      if (failure is FavoriteApiException && isSessionCurrent(scope)) {
        if (failure.isVersionConflict) {
          _blockedMutationKeys.add(hashedKey);
          replayError = '收藏编辑发生版本冲突，原编辑内容已保留，请确认后处理';
          if (failure.currentItem != null) _merge(failure.currentItem!);
        } else if (_terminalFailure(failure)) {
          if (await _removePending(scope, hashedKey,
              confirmedRequestID: requestID)) {
            _forgetRequest(key);
          }
          await _saveCache(scope);
        }
      }
      if (tagOperation) {
        _captureTagError(failure, scope);
      } else {
        _captureError(failure, scope);
      }
      _notify();
      rethrow;
    } finally {
      if (isSessionCurrent(scope)) {
        _activeMutationKeys.remove(hashedKey);
        _savingCount--;
        uploadProgress = null;
        _notify();
      }
    }
  }

  Future<FavoriteItem> createFromMessage(
      {required FavoriteSource source, String? clientRequestID}) {
    final locator = {
      'conversationID': source.conversationID,
      'clientMsgID': source.clientMsgID,
      'sequence': source.sequence
    };
    final key = 'message:${jsonEncode(locator)}';
    return _mutation(
        key,
        clientRequestID,
        (request, cancel) => api.createFromMessage(
            source: source, clientRequestID: request, cancelToken: cancel),
        pending: (request) => _pending(
            key,
            FavoriteMutationOperation.createMessage,
            request,
            {'origin': 'message', 'source': locator}));
  }

  Future<FavoriteItem> createNote(String text,
      {String title = '', String? clientRequestID}) {
    if (text.trim().isEmpty) throw ArgumentError('收藏正文不能为空');
    if (utf8.encode(text).length > 64 * 1024) {
      throw const FavoriteApiException(20058, '文字超过大小限制');
    }
    final content = FavoriteContent(
        kind: FavoriteKind.note,
        blocks: [FavoriteBlock(id: 'b1', type: 'text', text: text)]);
    final key = 'note:${jsonEncode({'title': title, 'text': text})}';
    return _mutation(
        key,
        clientRequestID,
        (request, cancel) => api.create(
            kind: FavoriteKind.note,
            content: content,
            title: title,
            clientRequestID: request,
            cancelToken: cancel),
        pending: (request) =>
            _pending(key, FavoriteMutationOperation.create, request, {
              'origin': 'userCreated',
              'kind': FavoriteKind.note.wireName,
              'title': title,
              'content': {
                'blocks': content.blocks.map((block) => block.toJson()).toList()
              }
            }));
  }

  Future<FavoriteItem> updateNote(String id, String text,
      {int? expectedVersion, String? title, String? clientRequestID}) async {
    final scope = await _ensureSession();
    if (text.trim().isEmpty) throw ArgumentError('收藏正文不能为空');
    if (utf8.encode(text).length > 64 * 1024) {
      throw const FavoriteApiException(20058, '文字超过大小限制');
    }
    final item = _details[id] ?? await getDetail(id);
    _guard(scope);
    if (item.kind != FavoriteKind.note && item.kind != FavoriteKind.text) {
      throw const FavoriteApiException('UNSUPPORTED_CONTENT', '该收藏不支持文字编辑');
    }
    if (item.content == null ||
        item.blocks.any((block) => block.type != 'text')) {
      throw const FavoriteApiException(
          'UNSUPPORTED_CONTENT', '图文笔记暂不支持文字编辑，请保留原内容');
    }
    final version = expectedVersion ?? item.version;
    final content = FavoriteContent(
        kind: item.kind,
        blocks: [FavoriteBlock(id: 'b1', type: 'text', text: text)]);
    final key =
        'update:$id:$version:${jsonEncode({'title': title, 'text': text})}';
    return _mutation(
        key,
        clientRequestID,
        (request, cancel) => api.update(id,
            expectedVersion: version,
            title: title,
            content: content,
            clientRequestID: request,
            cancelToken: cancel),
        pending: (request) => _pending(
            key,
            FavoriteMutationOperation.update,
            request,
            {
              'expectedVersion': version,
              if (title != null) 'title': title,
              'content': {
                'blocks': content.blocks.map((block) => block.toJson()).toList()
              }
            },
            itemID: id));
  }

  Future<void> delete(String id,
      {int? expectedVersion, String? clientRequestID}) async {
    final scope = await _ensureSession();
    // An explicit snapshot version is enough to issue the idempotent delete.
    // Fetching an already-deleted detail first would incorrectly reject it.
    final version = expectedVersion ??
        _newestKnown(id)?.version ??
        (await getDetail(id)).version;
    _guard(scope);
    final key = 'delete:$id:$version';
    await _mutation<void>(key, clientRequestID, (request, cancel) async {
      await api.delete(id,
          expectedVersion: version,
          clientRequestID: request,
          cancelToken: cancel);
      _guard(scope);
      _markDeleted(id, version + 1);
    },
        pending: (request) => _pending(key, FavoriteMutationOperation.delete,
            request, {'expectedVersion': version},
            itemID: id));
  }

  Future<FavoriteBatchDeleteResult> deleteMany(List<FavoriteItem> items,
      {String? clientRequestID}) async {
    final scope = await _ensureSession();
    final selection = List<FavoriteItem>.unmodifiable(items);
    final action = 'batch-delete:${jsonEncode(selection.map((item) => {
          'id': item.id,
          'expectedVersion': item.version
        }).toList())}';
    return _mutation(action, clientRequestID, (request, cancel) async {
      final result = await api.batchDelete(selection,
          clientRequestID: request, cancelToken: cancel);
      _guard(scope);
      final resolved = <FavoriteDeleteResult>[];
      for (final entry in result.items) {
        if (entry.deleted) {
          final selected = selection.firstWhere((item) => item.id == entry.id);
          _markDeleted(entry.id, selected.version + 1);
          resolved.add(entry);
        } else if (entry.currentItem != null) {
          _merge(entry.currentItem!);
          resolved.add(entry);
        } else {
          FavoriteItem? latest;
          try {
            latest = await getDetail(entry.id);
            _guard(scope);
            if (entry.version != null && latest.version < entry.version!) {
              latest = null;
            }
          } catch (_) {
            _guard(scope);
            // The partial delete is already confirmed. A failed read must not
            // turn it into an unknown write or discard the conflict snapshot.
          }
          resolved.add(FavoriteDeleteResult(
              id: entry.id,
              status: entry.status,
              version: entry.version,
              currentItem: latest));
        }
      }
      return FavoriteBatchDeleteResult(items: List.unmodifiable(resolved));
    },
        pending: (request) =>
            _pending(action, FavoriteMutationOperation.batchDelete, request, {
              'items': selection
                  .map((item) =>
                      {'id': item.id, 'expectedVersion': item.version})
                  .toList()
            }));
  }

  Future<void> refreshTags() async {
    tagError = '标签功能暂未开放';
    _notify();
  }

  Future<FavoriteTag> createTag(String name, {String? clientRequestID}) async =>
      throw const FavoriteApiException('UNSUPPORTED_CONTENT', '标签功能暂未开放');

  Future<FavoriteTag> updateTag(String id, String name,
          {int? expectedVersion, String? clientRequestID}) async =>
      throw const FavoriteApiException('UNSUPPORTED_CONTENT', '标签功能暂未开放');

  Future<void> deleteTag(String id,
          {int? expectedVersion, String? clientRequestID}) async =>
      throw const FavoriteApiException('UNSUPPORTED_CONTENT', '标签功能暂未开放');

  Future<FavoriteItem> updateTags(String id, List<String> tagIDs,
          {int? expectedVersion, String? clientRequestID}) async =>
      throw const FavoriteApiException('UNSUPPORTED_CONTENT', '标签功能暂未开放');
  Future<FavoriteItem> createLink(String url,
      {String title = '', String? clientRequestID}) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FavoriteApiException(
          'INVALID_LINK', '请输入有效的 http 或 https 链接');
    }
    final content = FavoriteContent(kind: FavoriteKind.link, blocks: [
      FavoriteBlock(
          id: 'b1',
          type: 'link',
          data: {'url': uri.toString(), if (title.isNotEmpty) 'title': title})
    ]);
    final key = 'link:${uri.toString()}:$title';
    return _mutation(
        key,
        clientRequestID,
        (request, cancel) => api.create(
            kind: FavoriteKind.link,
            content: content,
            title: title,
            clientRequestID: request,
            cancelToken: cancel),
        pending: (request) =>
            _pending(key, FavoriteMutationOperation.create, request, {
              'origin': 'userCreated',
              'kind': FavoriteKind.link.wireName,
              'title': title,
              'content': {
                'blocks': content.blocks.map((block) => block.toJson()).toList()
              }
            }));
  }

  Future<FavoriteItem> retryArchive(String id, {String? clientRequestID}) {
    final key = 'retry-archive:$id';
    return _mutation(key, clientRequestID, (request, cancel) async {
      _pollAttempts = 0;
      final scope = sessionScope;
      _guard(scope);
      var entry = _pendingRecovery[_actionKey(key)];
      if (entry == null) {
        entry = _pending(
            key, FavoriteMutationOperation.retryArchive, request, {},
            itemID: id);
        await _putPending(scope, entry);
      } else if (entry.clientRequestID != request) {
        throw const FavoriteApiException('TASK_BUSY', '请先确认上一次归档重试结果');
      }
      return FavoriteArchiveRetryRecovery(api).recover(entry, cancel,
          guard: () => _guard(scope),
          acknowledge: (ack) => _acknowledgeArchiveRetry(scope, entry!, ack));
    });
  }

  Future<void> _acknowledgeArchiveRetry(String scope,
      FavoriteMutationEntry entry, FavoriteArchiveRetryAck ack) async {
    _guard(scope);
    // Keep the in-process proof even if storage fails. The original durable
    // intent and UUID survive, and a subsequent retry reads detail first.
    _pendingRecovery[entry.key] = entry.acknowledgeArchiveRetry(ack);
    try {
      await outbox.acknowledgeArchiveRetry(
          accountNamespace, entry.key, entry.clientRequestID, ack);
    } catch (_) {
      _guard(scope);
      throw const FavoriteApiException(
          'ARCHIVE_RETRY_ACK_SAVE_FAILED', '服务端已接受归档重试，设备未能保存确认记录，请刷新收藏确认结果');
    }
    _guard(scope);
  }

  static const _rejectedMediaMessage = '上传原件已失效，请再次添加以重新上传';

  /// Retire only the exact completed upload used by a conclusively rejected
  /// create. Its durable outbox identity must already be acknowledged first.
  Future<bool> _invalidateRejectedMediaCreate(
      String scope, FavoriteMutationEntry entry) async {
    _guard(scope);
    if (entry.operation != FavoriteMutationOperation.create ||
        entry.body['origin'] != 'userCreated' ||
        entry.body['clientRequestID'] != entry.clientRequestID ||
        _pendingRecovery.containsKey(entry.key) ||
        _requestIDs.containsKey(entry.key)) {
      return false;
    }
    final kind = entry.body['kind'];
    final uploadIDs = entry.body['uploadIDs'];
    final content = entry.body['content'];
    if (!{'image', 'video', 'audio', 'file'}.contains(kind) ||
        uploadIDs is! List ||
        uploadIDs.length != 1 ||
        uploadIDs.single is! String ||
        content is! Map) {
      return false;
    }
    final blocks = content['blocks'];
    if (blocks is! List || blocks.length != 1 || blocks.single is! Map) {
      return false;
    }
    final block = blocks.single as Map;
    if (block['type'] != kind || block['assetID'] is! String) return false;
    final matching = _mediaTasks.entries.where((candidate) {
      final task = candidate.value;
      return candidate.key.startsWith('media:$kind:') &&
          _actionKey(candidate.key) == entry.key &&
          task.uploadID == uploadIDs.single &&
          task.asset?.id == block['assetID'];
    }).toList();
    if (matching.length != 1) return false;
    final key = matching.single.key;
    final task = matching.single.value;
    final initKey = _actionKey('$key:init');
    final completeKey = _actionKey('$key:complete');
    final initID = _requestIDs[initKey];
    final completeID = _requestIDs[completeKey];
    // Replays already hold this lock; release only a lock acquired here.
    final ownsLock = _activeMutationKeys.add(entry.key);
    _savingCount++;
    _mediaTasks.remove(key);
    _forgetRequest('$key:init');
    _forgetRequest('$key:complete');
    try {
      // Never upload or issue a changed create during this failed operation.
      await _saveCache(scope, strict: true);
      _guard(scope);
      task
        ..asset = null
        ..session = null
        ..uploadID = null
        ..uploaded = false;
      return true;
    } catch (checkpointFailure) {
      if (isSessionCurrent(scope)) {
        _mediaTasks[key] = task;
        if (initID != null) _requestIDs[initKey] = initID;
        if (completeID != null) _requestIDs[completeKey] = completeID;
        _captureError(checkpointFailure, scope);
      }
      rethrow;
    } finally {
      if (isSessionCurrent(scope)) {
        if (ownsLock) _activeMutationKeys.remove(entry.key);
        _savingCount--;
        _notify();
      }
    }
  }

  Future<FavoriteItem> createMedia(
      {required FavoriteKind kind,
      required String filePath,
      String? fileName,
      String? mimeType,
      String? clientRequestID}) async {
    if (!{
      FavoriteKind.image,
      FavoriteKind.video,
      FavoriteKind.audio,
      FavoriteKind.file
    }.contains(kind)) {
      throw ArgumentError('Invalid favorite media kind');
    }
    final scope = await _ensureSession();
    await requireAvailable();
    _guard(scope);
    final name = fileName ?? filePath.split(RegExp(r'[/\\]')).last;
    final declaredMime = mimeType ?? _mime(name, kind);
    final baseKey = 'media:${kind.wireName}:$filePath:$name';
    final original = File(filePath);
    String key;
    if (await original.exists()) {
      int size;
      Digest hash;
      try {
        size = await original.length();
        hash = await sha256.bind(original.openRead()).first;
      } on FileSystemException {
        _guard(scope);
        throw const FavoriteApiException(20056, '本地原文件不可用，请重新选择图片或文件');
      }
      _guard(scope);
      final legacyKey = '$baseKey:$size:$hash';
      // A corrected MIME declaration is a different init body and must not
      // reuse its UUID. Existing completed checkpoints can still be resumed.
      final legacy = _mediaTasks[legacyKey];
      key = legacy?.asset?.mimeType == declaredMime
          ? legacyKey
          : '$legacyKey:${sha256.convert(utf8.encode(declaredMime))}';
    } else {
      final recoverable = _mediaTasks.keys
          .where((value) =>
              value.startsWith('$baseKey:') &&
              _mediaTasks[value]!.uploadID != null &&
              (_mediaTasks[value]!.uploaded ||
                  _mediaTasks[value]!.asset != null))
          .toList();
      if (recoverable.length != 1) {
        throw const FavoriteApiException(20056, '本地原文件不可用，请重新选择图片或文件');
      }
      key = recoverable.single;
    }
    final task = _mediaTasks.putIfAbsent(key, () => FavoriteMediaTask());
    var rejectedCompletedAsset = false;
    FavoriteMutationEntry? completedCreate;
    late FavoriteItem result;
    try {
      result = await _mutation<FavoriteItem>(key, clientRequestID,
          (request, cancel) async {
        final asset = await FavoriteMediaUploader(api).complete(
            task: task,
            file: File(filePath),
            fileName: name,
            mimeType: declaredMime,
            kind: kind,
            cancel: cancel,
            requestID: (suffix) => _request('$key:$suffix', null),
            forgetRequest: (suffix) => _forgetRequest('$key:$suffix'),
            restoreRequest: (suffix, request) =>
                _requestIDs[_actionKey('$key:$suffix')] = request,
            checkpoint: () => _saveCache(scope, strict: true),
            guard: () => _guard(scope),
            onProgress: (sent, total) {
              if (isSessionCurrent(scope)) {
                uploadProgress = total > 0 ? sent / total : null;
                _notify();
              }
            });

        if (kind == FavoriteKind.video && asset.coverAssetID == null) {
          throw const FormatException('Missing favorite video cover');
        }
        final content = FavoriteContent(kind: kind, blocks: [
          FavoriteBlock(
              id: 'b1',
              type: kind.wireName,
              assetID: asset.id,
              data: {
                'fileName': name,
                if (kind == FavoriteKind.video && asset.coverAssetID != null)
                  'coverAssetID': asset.coverAssetID
              })
        ]);
        completedCreate =
            _pending(key, FavoriteMutationOperation.create, request, {
          'origin': 'userCreated',
          'kind': kind.wireName,
          'title': name,
          'content': {
            'blocks': content.blocks.map((block) => block.toJson()).toList()
          },
          'uploadIDs': [task.uploadID!]
        });
        await _putPending(scope, completedCreate!);
        _guard(scope);
        try {
          return await api.create(
              kind: kind,
              content: content,
              title: name,
              uploadIDs: [task.uploadID!],
              clientRequestID: request,
              cancelToken: cancel);
        } on FavoriteApiException catch (failure) {
          rejectedCompletedAsset = failure.code == 20056 &&
              !failure.isUncertain &&
              !failure.isCancelled;
          rethrow;
        }
      });
    } on FavoriteApiException catch (failure) {
      // Retire the confirmed rejected create first. Unknown results and a
      // failed outbox acknowledgement must retain their exact body and UUID.
      if (rejectedCompletedAsset &&
          failure.code == 20056 &&
          isSessionCurrent(scope) &&
          completedCreate != null &&
          await _invalidateRejectedMediaCreate(scope, completedCreate!)) {
        error = _rejectedMediaMessage;
        _notify();
        throw const FavoriteApiException(20056, _rejectedMediaMessage);
      }
      rethrow;
    }
    if (isSessionCurrent(scope) &&
        !_pendingRecovery.containsKey(_actionKey(key))) {
      _mediaTasks.remove(key);
      _forgetRequest('$key:init');
      _forgetRequest('$key:complete');
      await _saveCache(scope);
    }
    return result;
  }

  static String _mime(String name, FavoriteKind kind) {
    final extension = name.split('.').last.toLowerCase();
    const types = {
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'amr': 'audio/amr',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'pdf': 'application/pdf'
    };
    return types[extension] ?? 'application/octet-stream';
  }

  Future<FavoritePreparedSend> prepareForSend(String id,
      {required String expectedContentRevision,
      required String sendAttemptID,
      required String clientRequestID}) async {
    final scope = await _ensureSession();
    await requireAvailable();
    _guard(scope);
    try {
      final value = await api.prepareForSend(id,
          expectedContentRevision: expectedContentRevision,
          sendAttemptID: sendAttemptID,
          clientRequestID: clientRequestID,
          cancelToken: _sessionCancel);
      _guard(scope);
      return value;
    } catch (failure) {
      _captureError(failure, scope);
      _notify();
      rethrow;
    }
  }

  Future<FavoriteDownload> assetAccess(String id, String assetID) async {
    final scope = await _ensureSession();
    await requireAvailable();
    _guard(scope);
    try {
      final value =
          await api.assetAccess(id, assetID, cancelToken: _sessionCancel);
      _guard(scope);
      return value;
    } catch (failure) {
      _captureError(failure, scope);
      _notify();
      rethrow;
    }
  }

  void _trackArchives(Iterable<FavoriteItem> items) {
    for (final item in _latestItems(items)) {
      if (item.status == FavoriteStatus.pendingArchive) {
        if (!_archiveIDs.contains(item.id)) _pollAttempts = 0;
        _archiveIDs.add(item.id);
      } else {
        _archiveIDs.remove(item.id);
      }
    }
    if (_archiveIDs.isNotEmpty &&
        _pollTimer == null &&
        !_pollInFlight &&
        _pollAttempts < 60) {
      _pollTimer = Timer(pollInterval, () {
        _pollTimer = null;
        unawaited(_pollArchives());
      });
    }
  }

  Future<void> _pollArchives() async {
    if (_disposed || _archiveIDs.isEmpty || _pollInFlight || !available) return;
    final scope = sessionScope;
    final cancel = _pollCancel = CancelToken();
    _pollInFlight = true;
    _pollAttempts++;
    bool changed = false;
    Object? pollFailure;
    try {
      for (final id in _archiveIDs.toList()) {
        try {
          final item = await api.getDetail(id, cancelToken: cancel);
          _guard(scope);
          if (cancel.isCancelled) return;
          _merge(item);
          final current = _newestKnown(id);
          if (_deletedIDs.contains(id) ||
              (current ?? item).status != FavoriteStatus.pendingArchive) {
            _archiveIDs.remove(id);
            changed = true;
          }
        } catch (failure) {
          _guard(scope);
          if (cancel.isCancelled) return;
          if (failure is FavoriteApiException && failure.code == 20050) {
            _markDeleted(id, (_newestKnown(id)?.version ?? 0) + 1);
            changed = true;
          } else {
            pollFailure = failure;
          }
        }
      }
      if (changed) await refresh();
      if (pollFailure != null) _captureError(pollFailure, scope);
    } catch (failure) {
      _captureError(failure, scope);
    } finally {
      if (isSessionCurrent(scope) && identical(cancel, _pollCancel)) {
        _pollInFlight = false;
        _pollCancel = null;
        if (_pollAttempts >= 60 && _archiveIDs.isNotEmpty) {
          error = '收藏仍在保存，请稍后刷新查看';
        }
        _notify();
        _trackArchives(const []);
      }
    }
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollCancel?.cancel();
    _pollCancel = null;
    _pollInFlight = false;
    _pollAttempts = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionCancel.cancel();
    _listCancel?.cancel();
    _tagCancel?.cancel();
    stopPolling();
    super.dispose();
  }
}
