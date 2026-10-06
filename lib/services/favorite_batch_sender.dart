import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'favorite_repository.dart';
import 'favorite_send_coordinator.dart';

typedef FavoriteBatchItemSender = Future<FavoriteSendResult> Function(
    FavoriteItem item, FavoriteTarget target, String attemptID);
typedef FavoriteTargetSelector = Future<List<FavoriteTarget>?> Function();

abstract interface class FavoriteBatchStore {
  Future<Map<String, dynamic>?> load(String key);
  Future<void> save(String key, Map<String, dynamic> value);
  Future<void> remove(String key);
}

class PreferencesFavoriteBatchStore implements FavoriteBatchStore {
  @override
  Future<Map<String, dynamic>?> load(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    return raw == null ? null : favoriteJsonMap(jsonDecode(raw));
  }

  @override
  Future<void> save(String key, Map<String, dynamic> value) async {
    final saved = await (await SharedPreferences.getInstance())
        .setString(key, jsonEncode(value));
    if (!saved) throw StateError('Cannot persist favorite batch');
  }

  @override
  Future<void> remove(String key) async {
    final removed = await (await SharedPreferences.getInstance()).remove(key);
    if (!removed) throw StateError('Cannot clear favorite batch');
  }
}

/// Each destination/item pair has a durable attempt ID before SDK submission.
/// Resuming the same selection uses the original targets and skips accepted
/// pairs, including when the process exited before its completion was saved.
class FavoriteBatchSender {
  FavoriteBatchSender({
    required this.repository,
    required FavoriteBatchItemSender sendItem,
    FavoriteBatchStore? store,
  })  : _sendItem = sendItem,
        _store = store ?? PreferencesFavoriteBatchStore();

  final FavoriteRepository repository;
  final FavoriteBatchItemSender _sendItem;
  final FavoriteBatchStore _store;
  final Map<String, Future<FavoriteSendResult>> _active = {};

  String _key(List<FavoriteItem> items) {
    final ids = items.map((item) => item.id).toList()..sort();
    final digest = sha256
        .convert(utf8.encode(jsonEncode([repository.accountNamespace, ids])));
    return 'favorites:batch:v1:$digest';
  }

  Future<FavoriteSendResult> send(List<FavoriteItem> items,
      {required FavoriteTargetSelector selectTargets}) async {
    if (items.isEmpty ||
        items.length > 100 ||
        items.map((item) => item.id).toSet().length != items.length ||
        items.any((item) => !item.canSend)) {
      return FavoriteSendResult.failed(
          errorCode: 'INVALID_SELECTION', errorMessage: '请选择已就绪且支持发送的收藏');
    }
    final scope = repository.sessionScope;
    final key = _key(items);
    final active = _active[key];
    if (active != null) return active;
    final work = _run(items, scope, key, selectTargets);
    _active[key] = work;
    try {
      return await work;
    } finally {
      if (identical(_active[key], work)) _active.remove(key);
    }
  }

  void resetSession() => _active.clear();

  /// Ends the selection's remaining work. Message tasks and unknown barriers
  /// stay in the coordinator; already accepted messages are never withdrawn.
  Future<void> cancel(List<FavoriteItem> items) async {
    final scope = repository.sessionScope;
    final key = _key(items);
    if (_active.containsKey(key)) {
      throw const FavoriteApiException('TASK_BUSY', '发送尚在进行，请等待结果');
    }
    _guard(scope);
    await _store.remove(key);
    _guard(scope);
  }

  void _guard(String scope) {
    if (!repository.isSessionCurrent(scope)) {
      throw const FavoriteApiException('SESSION_CHANGED', '登录状态已改变');
    }
  }

  Future<FavoriteSendResult> _run(List<FavoriteItem> requested, String scope,
      String key, FavoriteTargetSelector selectTargets) async {
    var completed = 0;
    var total = 1;
    try {
      _guard(scope);
      await repository.requireAvailable();
      _guard(scope);
      var saved = await _store.load(key);
      _guard(scope);
      if (saved == null) {
        final selected = await selectTargets();
        _guard(scope);
        if (selected == null || selected.isEmpty) {
          return FavoriteSendResult.failed(errorCode: 'CANCELLED');
        }
        final targets = <FavoriteTarget>[];
        final keys = <String>{};
        for (final target in selected) {
          if (!target.isValid) throw const FormatException('Invalid target');
          if (keys.add(target.key)) targets.add(target);
        }
        if (targets.length > 100) {
          throw const FormatException('Too many targets');
        }
        saved = {
          'items': requested.map((item) => item.toCacheJson()).toList(),
          'targets': targets.map((target) => target.toJson()).toList(),
          'attempts': [
            for (var i = 0; i < requested.length * targets.length; i++)
              const Uuid().v4()
          ],
          'completed': 0,
        };
        // A failed journal write stops before preparing or submitting messages.
        await _store.save(key, saved);
        _guard(scope);
      }
      final items = (saved['items'] as List)
          .map((value) => FavoriteItem.fromJson(favoriteJsonMap(value)))
          .toList();
      final targets = (saved['targets'] as List)
          .map((value) => FavoriteTarget.fromJson(favoriteJsonMap(value)))
          .toList();
      final attempts = (saved['attempts'] as List).cast<String>();
      completed = saved['completed'] as int;
      total = items.length * targets.length;
      if (total == 0 ||
          attempts.length != total ||
          completed < 0 ||
          completed > total ||
          targets.any((target) => !target.isValid)) {
        throw const FormatException('Invalid saved batch');
      }
      // Item-first ordering ensures each selected favorite finishes for every
      // target before proceeding to the next favorite.
      for (; completed < total;) {
        _guard(scope);
        await repository.requireAvailable();
        _guard(scope);
        final item = items[completed ~/ targets.length];
        final target = targets[completed % targets.length];
        final result = await _sendItem(item, target, attempts[completed]);
        _guard(scope);
        if (!result.isSuccess) {
          if (completed == 0 &&
              result.sentCount == 0 &&
              result.status == FavoriteSendStatus.failed &&
              !result.retryable) {
            // A definite rejection with no accepted block can end this action.
            // In particular, an outdated revision must not lock all subsequent
            // selections to content the server can no longer prepare.
            await _store.remove(key);
            _guard(scope);
            return FavoriteSendResult.failed(
                errorCode: 'BATCH_RESELECT_REQUIRED',
                errorMessage:
                    '${result.errorMessage ?? '发送未完成'}，请刷新收藏后重新选择发送对象',
                totalCount: total);
          }
          return FavoriteSendResult(
              status: result.status,
              clientMsgID: result.clientMsgID,
              message: result.message,
              errorCode: result.errorCode,
              errorMessage: result.errorMessage,
              retryable: result.retryable,
              sendAttemptID: result.sendAttemptID,
              sentCount: completed,
              totalCount: total);
        }
        completed++;
        saved['completed'] = completed;
        await _store.save(key, saved);
        _guard(scope);
      }
      await _store.remove(key);
      _guard(scope);
      return FavoriteSendResult(
          status: FavoriteSendStatus.success,
          sentCount: completed,
          totalCount: total);
    } on FavoriteApiException catch (error) {
      return FavoriteSendResult.failed(
          errorCode: error.code.toString(),
          errorMessage: error.message,
          sentCount: completed,
          totalCount: total);
    } catch (_) {
      // Keep the durable batch intact; retry with the same attempt IDs.
      return FavoriteSendResult.failed(
          errorCode: 'BATCH_RECOVERY_REQUIRED',
          errorMessage: '发送记录暂不可用，请保留当前选择后重试',
          retryable: true,
          sentCount: completed,
          totalCount: total);
    }
  }
}
