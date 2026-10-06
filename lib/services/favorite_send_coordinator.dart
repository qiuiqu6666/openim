import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../pages/favorites/sending/favorite_prepare_lease.dart';
import 'chat_message_sender.dart';
import 'favorite_message_builder.dart';
import 'favorite_repository.dart';

enum FavoriteSendStatus { success, failed, unknown }

class FavoriteTarget {
  const FavoriteTarget(
      {required this.conversationID,
      this.userID,
      this.groupID,
      this.displayName});
  final String conversationID;
  final String? userID;
  final String? groupID;
  final String? displayName;
  bool get isValid =>
      conversationID.trim().isNotEmpty &&
      (userID?.trim().isNotEmpty == true) !=
          (groupID?.trim().isNotEmpty == true);
  String get key => '$conversationID|${userID ?? ''}|${groupID ?? ''}';
  Map<String, dynamic> toJson() => {
        'conversationID': conversationID,
        if (userID != null) 'userID': userID,
        if (groupID != null) 'groupID': groupID,
        if (displayName != null) 'displayName': displayName
      };
  factory FavoriteTarget.fromJson(Map<String, dynamic> json) => FavoriteTarget(
      conversationID: json['conversationID'] as String,
      userID: json['userID'] as String?,
      groupID: json['groupID'] as String?,
      displayName: json['displayName'] as String?);
}

class FavoriteSendResult {
  const FavoriteSendResult(
      {required this.status,
      this.clientMsgID,
      this.message,
      this.errorCode,
      this.errorMessage,
      this.retryable = false,
      this.sendAttemptID,
      this.sentCount = 0,
      this.totalCount = 1});
  final FavoriteSendStatus status;
  final String? clientMsgID;
  final Message? message;
  final String? errorCode;
  final String? errorMessage;
  final bool retryable;
  final String? sendAttemptID;
  final int sentCount;
  final int totalCount;
  bool get isSuccess => status == FavoriteSendStatus.success;
  factory FavoriteSendResult.success(
          {required Message message,
          String? sendAttemptID,
          int sentCount = 1,
          int totalCount = 1}) =>
      FavoriteSendResult(
          status: FavoriteSendStatus.success,
          message: message,
          clientMsgID: message.clientMsgID,
          sendAttemptID: sendAttemptID,
          sentCount: sentCount,
          totalCount: totalCount);
  factory FavoriteSendResult.failed(
          {String? clientMsgID,
          Message? message,
          String? errorCode,
          String? errorMessage,
          bool retryable = false,
          String? sendAttemptID,
          int sentCount = 0,
          int totalCount = 1}) =>
      FavoriteSendResult(
          status: FavoriteSendStatus.failed,
          clientMsgID: clientMsgID,
          message: message,
          errorCode: errorCode,
          errorMessage: errorMessage,
          retryable: retryable,
          sendAttemptID: sendAttemptID,
          sentCount: sentCount,
          totalCount: totalCount);
  factory FavoriteSendResult.unknown(
          {String? clientMsgID,
          Message? message,
          String? errorCode,
          String? errorMessage,
          String? sendAttemptID,
          int sentCount = 0,
          int totalCount = 1}) =>
      FavoriteSendResult(
          status: FavoriteSendStatus.unknown,
          clientMsgID: clientMsgID,
          message: message,
          errorCode: errorCode,
          errorMessage: errorMessage,
          sendAttemptID: sendAttemptID,
          sentCount: sentCount,
          totalCount: totalCount);
}

class FavoriteSendProgress {
  const FavoriteSendProgress(
      {required this.sendAttemptID,
      required this.stage,
      this.completed = 0,
      this.total = 1});
  final String sendAttemptID;
  final String stage;
  final int completed;
  final int total;
}

typedef FavoriteSendCallback = Future<FavoriteSendResult> Function(
    Message message, FavoriteTarget target);
typedef FavoriteSendProgressCallback = void Function(
    FavoriteSendProgress progress);

abstract class FavoriteSendTaskStore {
  Future<List<Map<String, dynamic>>> load(String namespace);
  Future<void> save(String namespace, List<Map<String, dynamic>> tasks);
}

/// Stores constructed messages before SDK submission, scoped to service/account.
/// Neither download grants nor the private source favorite DTO are persisted.
class PreferencesFavoriteSendTaskStore implements FavoriteSendTaskStore {
  String _key(String namespace) =>
      'favorite.send.tasks.${sha256.convert(utf8.encode(namespace))}';
  @override
  Future<List<Map<String, dynamic>>> load(String namespace) async {
    final value =
        (await SharedPreferences.getInstance()).getString(_key(namespace));
    if (value == null) return [];
    final raw = jsonDecode(value);
    if (raw is! List) {
      throw const FormatException('Invalid favorite send journal');
    }
    return raw.map((value) => Map<String, dynamic>.from(value as Map)).toList();
  }

  @override
  Future<void> save(String namespace, List<Map<String, dynamic>> tasks) async {
    final ok = await (await SharedPreferences.getInstance())
        .setString(_key(namespace), jsonEncode(tasks));
    if (!ok) {
      throw const FavoriteBuildException('TASK_SAVE_FAILED', '无法保存发送状态，请重试',
          retryable: true);
    }
  }
}

class _SendStep {
  _SendStep(this.built,
      {this.state = 'prepared',
      this.errorCode,
      this.errorMessage,
      this.retryable = false});
  final FavoriteBuiltMessage built;
  String state;
  String? errorCode;
  String? errorMessage;
  bool retryable;
  Map<String, dynamic> toJson() => {
        'message': built.message.toJson(),
        'blockID': built.blockID,
        'localPaths': built.localPaths,
        'state': state,
        'errorCode': errorCode,
        'errorMessage': errorMessage,
        'retryable': retryable
      };
  factory _SendStep.fromJson(Map<String, dynamic> json) => _SendStep(
      FavoriteBuiltMessage(
          message: Message.fromJson(
              Map<String, dynamic>.from(json['message'] as Map)),
          blockID: json['blockID'] as String,
          localPaths:
              List<String>.from(json['localPaths'] as List? ?? const [])),
      // A crash after the durable submitting transition may have reached IM.
      state:
          json['state'] == 'submitting' ? 'unknown' : json['state'] as String,
      errorCode: json['errorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
      retryable: json['retryable'] == true);
}

class _SendTask {
  _SendTask(
      {required this.attemptID,
      required this.itemID,
      required this.revision,
      required this.target,
      required this.namespace,
      required this.requestID,
      this.kind,
      Iterable<String> aliasAttemptIDs = const [],
      this.steps = const []})
      : aliasAttemptIDs = aliasAttemptIDs.toSet();
  final String attemptID;
  final String itemID;
  String revision;
  final FavoriteTarget target;
  final String namespace;
  String requestID;
  FavoriteKind? kind;
  final Set<String> aliasAttemptIDs;
  final Set<String> pendingAliasAttemptIDs = {};
  List<_SendStep> steps;
  FavoriteSendResult? result;
  int get sentCount => steps.where((step) => step.state == 'success').length;
  String get key => '$itemID|${target.key}';
  Map<String, dynamic> toJson() => {
        'attemptID': attemptID,
        'itemID': itemID,
        'revision': revision,
        'target': target.toJson(),
        'namespace': namespace,
        'requestID': requestID,
        if (kind != null) 'kind': kind!.wireName,
        'aliasAttemptIDs': aliasAttemptIDs.toList(),
        // Successful attempt tombstones retain idempotency for batch recovery,
        // without keeping sent plaintext/media fields in the pending journal.
        'steps': result?.isSuccess == true && sentCount == steps.length
            ? <Map<String, dynamic>>[]
            : steps.map((step) => step.toJson()).toList(),
        'result': result == null
            ? null
            : {
                'status': result!.status.name,
                'errorCode': result!.errorCode,
                'errorMessage': result!.errorMessage,
                'retryable': result!.retryable,
                'clientMsgID': result!.clientMsgID,
                'sentCount': result!.sentCount,
                'totalCount': result!.totalCount,
              }
      };
  factory _SendTask.fromJson(Map<String, dynamic> json) {
    final task = _SendTask(
        attemptID: json['attemptID'] as String,
        itemID: json['itemID'] as String,
        revision: json['revision'] as String,
        target: FavoriteTarget.fromJson(
            Map<String, dynamic>.from(json['target'] as Map)),
        namespace: json['namespace'] as String,
        requestID: json['requestID'] as String,
        kind: json['kind'] == null
            ? null
            : FavoriteKind.parse(json['kind'] as String),
        aliasAttemptIDs:
            List<String>.from(json['aliasAttemptIDs'] as List? ?? const []),
        steps: (json['steps'] as List)
            .map((raw) =>
                _SendStep.fromJson(Map<String, dynamic>.from(raw as Map)))
            .toList());
    final waiting = task.steps.any((step) => step.state == 'unknown');
    final pending = waiting
        ? task.steps.firstWhere((step) => step.state == 'unknown')
        : null;
    final raw = json['result'] as Map?;
    final allSuccess = task.steps.isNotEmpty &&
            task.sentCount == task.steps.length ||
        raw?['status'] == 'success' && raw?['sentCount'] == raw?['totalCount'];
    task.result = FavoriteSendResult(
        status: waiting
            ? FavoriteSendStatus.unknown
            : allSuccess
                ? FavoriteSendStatus.success
                : FavoriteSendStatus.failed,
        sendAttemptID: task.attemptID,
        sentCount: allSuccess
            ? ((raw?['sentCount'] as int?) ?? task.sentCount)
            : task.sentCount,
        totalCount: allSuccess
            ? ((raw?['totalCount'] as int?) ?? task.steps.length)
            : task.steps.isEmpty
                ? 1
                : task.steps.length,
        clientMsgID: pending?.built.message.clientMsgID ??
            (raw?['clientMsgID'] as String?) ??
            (task.steps.isEmpty
                ? null
                : task.steps.last.built.message.clientMsgID),
        message: pending?.built.message,
        errorCode: waiting
            ? 'SEND_UNCONFIRMED'
            : raw?['errorCode'] as String? ?? 'INTERRUPTED_BEFORE_SEND',
        errorMessage: waiting ? '发送状态待确认，请先核对会话' : '发送尚未完成，可继续本次任务',
        retryable: !waiting &&
            !allSuccess &&
            (raw == null || raw['retryable'] == true));
    return task;
  }
}

class FavoriteSendCoordinator {
  FavoriteSendCoordinator(
      {FavoriteRepository? repository,
      FavoriteMessageBuilder? builder,
      FavoriteSendCallback? sender,
      FavoriteSendCallback? lookup,
      FavoriteSendTaskStore? taskStore})
      : repository = repository ?? FavoriteRepository.instance,
        _builder = builder ?? FavoriteMessageBuilder(),
        _sender = sender ?? ChatMessageSender().send,
        _lookup = lookup ?? ChatMessageSender().lookup,
        _taskStore = taskStore ?? PreferencesFavoriteSendTaskStore();
  final FavoriteRepository repository;
  final FavoriteMessageBuilder _builder;
  final FavoriteSendCallback _sender;
  final FavoriteSendCallback _lookup;
  final FavoriteSendTaskStore _taskStore;
  final Map<String, _SendTask> _tasks = {};
  final Map<String, Future<FavoriteSendResult>> _active = {};
  final Map<String, _SendTask> _activeTasks = {};
  Future<void> _saveTail = Future.value();
  Future<void>? _loading;
  String? _namespace;
  String? _loadedScope;
  bool _loaded = false;
  int _generation = 0;

  void resetSession() {
    // Submitted work cannot be recalled. Its durable submitting state restores
    // as unknown for the old account; only unsubmitted preparation is cancelled.
    _generation++;
    _namespace = null;
    _loadedScope = null;
    _loaded = false;
    _tasks.clear();
    _active.clear();
    _activeTasks.clear();
    _loading = null;
  }

  Future<void> _load(String scope) async {
    final namespace = repository.accountNamespace;
    if (namespace.isEmpty) {
      throw const FavoriteBuildException('LOGIN_REQUIRED', '请先登录后发送');
    }
    if (_namespace == namespace && _loadedScope == scope && _loaded) return;
    if (_namespace != namespace || _loadedScope != scope) {
      resetSession();
      _namespace = namespace;
      _loadedScope = scope;
    }
    if (_loading != null) return _loading;
    final generation = _generation;
    final work = () async {
      final values = await _taskStore.load(namespace);
      if (generation != _generation || !repository.isSessionCurrent(scope)) {
        throw const FavoriteBuildException('SESSION_CHANGED', '登录状态已变化');
      }
      for (final value in values) {
        final task = _SendTask.fromJson(value);
        if (task.namespace == namespace && task.target.isValid) {
          _tasks[task.attemptID] = task;
        }
      }
      _loaded = true;
    }();
    _loading = work;
    try {
      await work;
    } finally {
      if (identical(_loading, work)) _loading = null;
    }
  }

  bool _current(String scope, int generation) =>
      generation == _generation && repository.isSessionCurrent(scope);
  void _guard(String scope, int generation) {
    if (!_current(scope, generation)) {
      throw const FavoriteBuildException('SESSION_CHANGED', '登录状态已变化');
    }
  }

  Future<void> _save(String scope, int generation) {
    _guard(scope, generation);
    final namespace = _namespace!;
    final snapshot = _tasks.values.map((task) => task.toJson()).toList();
    final work = _saveTail.catchError((Object _) {}).then((_) async {
      _guard(scope, generation);
      await _taskStore.save(namespace, snapshot);
      _guard(scope, generation);
    });
    _saveTail = work;
    return work;
  }

  Future<FavoriteSendResult> send(FavoriteItem item, FavoriteTarget target,
      {FavoriteSendCallback? onSend,
      FavoriteSendCallback? lookup,
      String? sendAttemptID,
      FavoriteSendProgressCallback? onProgress}) async {
    if (!target.isValid) {
      return const FavoriteSendResult(
          status: FavoriteSendStatus.failed,
          errorCode: 'INVALID_TARGET',
          errorMessage: '请选择一个有效的发送会话');
    }
    final scope = repository.sessionScope;
    try {
      await _load(scope);
    } catch (error) {
      return _preflightError(error);
    }
    final generation = _generation;
    final key = '${item.id}|${target.key}';
    if (sendAttemptID != null &&
        !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(sendAttemptID)) {
      return const FavoriteSendResult(
          status: FavoriteSendStatus.failed,
          errorCode: 'INVALID_ATTEMPT',
          errorMessage: '发送任务无效');
    }
    final existing =
        sendAttemptID == null ? null : _taskForAttempt(sendAttemptID);
    if (existing != null && existing.key != key) {
      return const FavoriteSendResult(
          status: FavoriteSendStatus.failed,
          errorCode: 'IDEMPOTENCY_CONFLICT',
          errorMessage: '发送任务与内容或目标不匹配');
    }
    if (existing != null) {
      try {
        await _bindAttempt(existing, sendAttemptID, scope, generation);
      } catch (error) {
        return _preflightError(error);
      }
    }
    if (existing?.result?.isSuccess == true) return existing!.result!;
    final active = _active[key];
    if (active != null) {
      final activeTask = _activeTasks[key]!;
      if (existing != null && !identical(existing, activeTask)) {
        return const FavoriteSendResult(
            status: FavoriteSendStatus.failed,
            errorCode: 'TASK_BUSY',
            errorMessage: '同一内容正在发送，请等待当前发送结果',
            retryable: true);
      }
      try {
        await _bindAttempt(activeTask, sendAttemptID, scope, generation);
      } catch (error) {
        return _preflightError(error);
      }
      return active;
    }
    if (sendAttemptID != null) {
      if (existing != null) {
        if (existing.result?.status == FavoriteSendStatus.unknown) {
          return reconcile(existing.attemptID, lookup: lookup ?? _lookup);
        }
        return retry(existing.attemptID,
            onSend: onSend, onProgress: onProgress);
      }
    }
    for (final task in _tasks.values.toList().reversed) {
      if (task.key != key || task.result?.isSuccess == true) continue;
      if (task.result?.status == FavoriteSendStatus.unknown) {
        try {
          await _bindAttempt(task, sendAttemptID, scope, generation);
        } catch (error) {
          return _preflightError(error);
        }
        return reconcile(task.attemptID, lookup: lookup ?? _lookup);
      }
      if (task.sentCount > 0 ||
          task.result?.retryable == true &&
              (item.contentRevision == null ||
                  item.contentRevision == task.revision)) {
        try {
          await _bindAttempt(task, sendAttemptID, scope, generation);
        } catch (error) {
          return _preflightError(error);
        }
        return retry(task.attemptID, onSend: onSend, onProgress: onProgress);
      }
      if (task.result?.status == FavoriteSendStatus.failed) {
        // No accepted block exists and IM definitely rejected this action.
        // A subsequent intentional click may use updated content/permissions.
        _tasks.remove(task.attemptID);
      }
    }
    if (!item.canSend) {
      return const FavoriteSendResult(
          status: FavoriteSendStatus.failed,
          errorCode: 'UNSUPPORTED_CONTENT',
          errorMessage: '该收藏尚未就绪或不支持发送');
    }
    final task = _SendTask(
        attemptID: sendAttemptID ?? const Uuid().v4(),
        itemID: item.id,
        revision: item.contentRevision ?? '',
        target: target,
        namespace: _namespace!,
        requestID: const Uuid().v4());
    task.kind = item.kind;
    _tasks[task.attemptID] = task;
    return _start(task, scope, generation, onSend ?? _sender, onProgress, item);
  }

  Future<FavoriteSendResult> retry(String sendAttemptID,
      {FavoriteSendCallback? onSend,
      FavoriteSendProgressCallback? onProgress}) async {
    final scope = repository.sessionScope;
    try {
      await _load(scope);
    } catch (error) {
      return _preflightError(error);
    }
    final task = _taskForAttempt(sendAttemptID);
    if (task == null) {
      return const FavoriteSendResult(
          status: FavoriteSendStatus.failed,
          errorCode: 'TASK_NOT_FOUND',
          errorMessage: '发送任务已不可用');
    }
    if (task.result?.status != FavoriteSendStatus.failed) {
      return task.result ?? _waiting(task);
    }
    final active = _active[task.key];
    if (active != null) return active;
    return _start(
        task, scope, _generation, onSend ?? _sender, onProgress, null);
  }

  Future<FavoriteSendResult> _start(
      _SendTask task,
      String scope,
      int generation,
      FavoriteSendCallback sender,
      FavoriteSendProgressCallback? progress,
      FavoriteItem? item) {
    final work = _run(task, scope, generation, sender, progress, item);
    _active[task.key] = work;
    _activeTasks[task.key] = task;
    return work.whenComplete(() {
      if (identical(_active[task.key], work)) {
        _active.remove(task.key);
        _activeTasks.remove(task.key);
      }
    });
  }

  _SendTask? _taskForAttempt(String attemptID) {
    final direct = _tasks[attemptID];
    if (direct != null) return direct;
    for (final task in _tasks.values) {
      if (task.aliasAttemptIDs.contains(attemptID)) return task;
    }
    return null;
  }

  Future<void> _bindAttempt(
      _SendTask task, String? attemptID, String scope, int generation) async {
    if (attemptID == null ||
        attemptID == task.attemptID ||
        task.aliasAttemptIDs.contains(attemptID) &&
            !task.pendingAliasAttemptIDs.contains(attemptID)) {
      return;
    }
    // A batch may adopt an existing unresolved manual send. Persist its fixed
    // cell ID before returning any receipt, so a batch-progress crash cannot
    // cause that same cell to manufacture a fresh SDK message after restart.
    task.aliasAttemptIDs.add(attemptID);
    task.pendingAliasAttemptIDs.add(attemptID);
    await _save(scope, generation);
    task.pendingAliasAttemptIDs.remove(attemptID);
  }

  /// Resolve an existing chat bubble to its durable favorite task, including
  /// compact success tombstones. This query never submits a message.
  Future<String?> pendingAttemptForMessage(String clientMsgID) async {
    if (clientMsgID.isEmpty) return null;
    final scope = repository.sessionScope;
    await _load(scope);
    final generation = _generation;
    _guard(scope, generation);
    for (final task in _tasks.values.toList().reversed) {
      if (task.result?.clientMsgID == clientMsgID ||
          task.steps
              .any((step) => step.built.message.clientMsgID == clientMsgID)) {
        return task.attemptID;
      }
    }
    return null;
  }

  Future<FavoriteSendResult> _run(
      _SendTask task,
      String scope,
      int generation,
      FavoriteSendCallback sender,
      FavoriteSendProgressCallback? progress,
      FavoriteItem? item) async {
    void report(String stage, int completed, int total) {
      if (_current(scope, generation)) {
        progress?.call(FavoriteSendProgress(
            sendAttemptID: task.attemptID,
            stage: stage,
            completed: completed,
            total: total));
      }
    }

    try {
      _guard(scope, generation);
      await repository.requireAvailable();
      _guard(scope, generation);
      await _save(scope, generation);
      if (task.steps.isEmpty) {
        report('preparing', 0, 1);
        // A list row can include blocks while still omitting immutable asset
        // metadata. Always resolve the complete authorized detail before build.
        final detail = await repository.getDetail(task.itemID);
        _guard(scope, generation);
        if (!detail.canSend) {
          throw const FavoriteBuildException('UNSUPPORTED_CONTENT', '该收藏无法发送');
        }
        task.kind = detail.kind;
        final revision =
            task.revision.isEmpty ? detail.contentRevision : task.revision;
        if (revision == null ||
            revision.isEmpty ||
            detail.contentRevision != revision) {
          throw const FavoriteBuildException(
              'VERSION_CONFLICT', '收藏已更新，请重新选择内容');
        }
        task.revision = revision;
        await _save(scope, generation);
        // Details supply immutable metadata only. The prepared projection supplies
        // every byte/text actually sent, including plain @/quote body conversion.
        final prepared = await FavoritePrepareLease(repository).prepare(
            favoriteID: task.itemID,
            contentRevision: revision,
            sendAttemptID: task.attemptID,
            clientRequestID: task.requestID,
            renewRequestID: () async {
              task.requestID = const Uuid().v4();
              await _save(scope, generation);
              return task.requestID;
            },
            guard: () => _guard(scope, generation));
        _guard(scope, generation);
        final built = await _builder.build(prepared,
            assets: detail.assets,
            sendAttemptID: task.attemptID,
            namespace: task.namespace,
            isActive: () => _current(scope, generation),
            onProgress: report);
        _guard(scope, generation);
        task.steps = built.map((value) => _SendStep(value)).toList();
        await _save(scope, generation);
      }
      // Legacy journals did not include kind. Resolve them through the real
      // repository before letting already-built materials reach the SDK.
      if (task.kind == null) {
        final detail = await repository.getDetail(task.itemID);
        _guard(scope, generation);
        if (!detail.canSend) {
          throw const FavoriteBuildException('UNSUPPORTED_CONTENT', '该收藏无法发送');
        }
        task.kind = detail.kind;
      }
      if (!{
            FavoriteKind.text,
            FavoriteKind.image,
            FavoriteKind.video,
            FavoriteKind.audio,
            FavoriteKind.file,
            FavoriteKind.note,
            FavoriteKind.link
          }.contains(task.kind) ||
          task.steps.any((step) => !{
                MessageType.text,
                MessageType.picture,
                MessageType.video,
                MessageType.voice,
                MessageType.file
              }.contains(step.built.message.contentType))) {
        throw const FavoriteBuildException(
            'UNSUPPORTED_CONTENT', '该收藏类型暂不支持发送');
      }
      for (final step in task.steps) {
        if (step.state == 'success') continue;
        if (step.state == 'unknown' || step.state == 'submitting') {
          task.result = _waiting(task, step);
          return task.result!;
        }
        _guard(scope, generation);
        await repository.requireAvailable();
        _guard(scope, generation);
        step.state = 'submitting';
        try {
          await _save(scope, generation);
        } catch (_) {
          // This process knows the SDK has not been called. A journal failure
          // is a preparation failure; persisted submitting restores conservatively.
          step.state = 'prepared';
          rethrow;
        }
        _guard(scope, generation);
        report('sending', task.sentCount, task.steps.length);
        late FavoriteSendResult result;
        try {
          result = await sender(step.built.message, task.target);
        } catch (_) {
          result = FavoriteSendResult.unknown(
              clientMsgID: step.built.message.clientMsgID,
              errorCode: 'SEND_UNCONFIRMED',
              errorMessage: '发送状态待确认，请先核对会话');
        }
        if (!_current(scope, generation)) {
          task.result = _waiting(task, step);
          return task.result!;
        }
        if (result.status == FavoriteSendStatus.success &&
            result.clientMsgID != step.built.message.clientMsgID) {
          result = _waiting(task, step);
        }
        step.state = result.status.name;
        step.errorCode = result.errorCode;
        step.errorMessage = result.errorMessage;
        step.retryable = result.retryable;
        if (result.message != null &&
            result.message!.clientMsgID == step.built.message.clientMsgID) {
          step.built.message.update(result.message!);
        }
        task.result = _aggregate(task, result);
        try {
          await _save(scope, generation);
        } catch (_) {
          // If an accepted send cannot be journalled, never turn it into a safe
          // failure. The last durable submitting state restores as unknown.
          step.state = 'unknown';
          task.result = _waiting(task, step);
          return task.result!;
        }
        if (result.status != FavoriteSendStatus.success) return task.result!;
      }
      final message = task.steps.last.built.message;
      task.result = FavoriteSendResult.success(
          message: message,
          sendAttemptID: task.attemptID,
          sentCount: task.sentCount,
          totalCount: task.steps.length);
      await _save(scope, generation);
      report('success', task.sentCount, task.steps.length);
      return task.result!;
    } catch (error) {
      if (task.steps.any(
          (step) => step.state == 'submitting' || step.state == 'unknown')) {
        task.result = _waiting(task);
      } else {
        final result = _preflightError(error);
        if (FavoritePrepareLease.isExpired(result.errorCode)) {
          task.requestID = const Uuid().v4();
        }
        task.result = _aggregate(task, result);
      }
      if (_current(scope, generation)) {
        try {
          await _save(scope, generation);
        } catch (_) {}
      }
      return task.result!;
    }
  }

  /// Lookup is a query callback, never the send callback. No new ID is built and
  /// no remaining block is submitted merely because reconciliation succeeded.
  Future<FavoriteSendResult> reconcile(String sendAttemptID,
      {FavoriteSendCallback? lookup}) async {
    final scope = repository.sessionScope;
    try {
      await _load(scope);
    } catch (error) {
      return _preflightError(error);
    }
    final generation = _generation;
    final task = _taskForAttempt(sendAttemptID);
    if (task == null) {
      return const FavoriteSendResult(
          status: FavoriteSendStatus.failed,
          errorCode: 'TASK_NOT_FOUND',
          errorMessage: '发送任务已不可用');
    }
    if (task.result?.isSuccess == true) return task.result!;
    for (final step in task.steps) {
      if (step.state != 'unknown') continue;
      FavoriteSendResult receipt;
      try {
        receipt = await (lookup ?? _lookup)(step.built.message, task.target);
      } catch (_) {
        receipt = _waiting(task, step);
      }
      _guard(scope, generation);
      if (receipt.status == FavoriteSendStatus.success &&
          receipt.clientMsgID == step.built.message.clientMsgID) {
        step.state = 'success';
        if (receipt.message != null) {
          step.built.message.update(receipt.message!);
        }
      }
    }
    if (task.steps.any((step) => step.state == 'unknown')) {
      task.result = _waiting(task);
    } else if (task.steps.isNotEmpty && task.sentCount == task.steps.length) {
      task.result = FavoriteSendResult.success(
          message: task.steps.last.built.message,
          sendAttemptID: task.attemptID,
          sentCount: task.sentCount,
          totalCount: task.steps.length);
    } else {
      task.result = FavoriteSendResult.failed(
          sendAttemptID: task.attemptID,
          sentCount: task.sentCount,
          totalCount: task.steps.length,
          retryable: true,
          errorCode: 'PARTIAL_READY',
          errorMessage: '已确认发送结果，可继续剩余内容');
    }
    await _save(scope, generation);
    return task.result!;
  }

  static FavoriteSendResult _preflightError(Object error) {
    if (error is FavoriteBuildException) {
      return FavoriteSendResult.failed(
          errorCode: error.code,
          errorMessage: error.message,
          retryable: error.retryable);
    }
    // Business API exceptions expose their safe message/code through the model.
    if (error is FavoriteApiException) {
      return FavoriteSendResult.failed(
          errorCode: error.code.toString(),
          errorMessage: error.message,
          retryable: !error.isCancelled &&
              (error.isUncertain ||
                  {
                    'PREPARE_EXPIRED',
                    'TEMPORARY_UNAVAILABLE',
                    'RATE_LIMITED',
                    '20063',
                    '20065',
                    '20066'
                  }.contains(error.code.toString())));
    }
    return FavoriteSendResult.failed(
        errorCode: 'PREPARE_FAILED',
        errorMessage: '收藏发送准备失败，请重试',
        retryable: true);
  }

  static FavoriteSendResult _aggregate(
          _SendTask task, FavoriteSendResult result) =>
      FavoriteSendResult(
          status: result.status,
          clientMsgID: result.clientMsgID,
          message: result.message,
          errorCode: result.errorCode,
          errorMessage: result.errorMessage,
          retryable: result.retryable,
          sendAttemptID: task.attemptID,
          sentCount: task.sentCount,
          totalCount: task.steps.isEmpty ? 1 : task.steps.length);
  static FavoriteSendResult _waiting(_SendTask task, [_SendStep? step]) {
    if (step == null) {
      for (final candidate in task.steps) {
        if (candidate.state == 'unknown' || candidate.state == 'submitting') {
          step = candidate;
          break;
        }
      }
    }
    return FavoriteSendResult.unknown(
        sendAttemptID: task.attemptID,
        clientMsgID: step?.built.message.clientMsgID,
        message: step?.built.message,
        sentCount: task.sentCount,
        totalCount: task.steps.isEmpty ? 1 : task.steps.length,
        errorCode: 'SEND_UNCONFIRMED',
        errorMessage: '发送状态待确认，请先核对会话，避免重复发送');
  }
}
