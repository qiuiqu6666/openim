import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../composer/ai_assistant_capability.dart';
import '../composer/ai_assistant_draft.dart';
import '../data/ai_assistant_api.dart';
import '../history/ai_assistant_history_map.dart';
import '../models/ai_assistant_models.dart';
import '../storage/ai_assistant_welcome_store.dart';
import 'ai_assistant_reply.dart';

typedef AiAssistantSession = ({String userID, String token});

AiAssistantSession currentAiSession() => (
      userID: OpenIM.iMManager.userID.isNotEmpty
          ? OpenIM.iMManager.userID
          : DataSp.userID ?? '',
      token: DataSp.chatToken ?? '',
    );

/// Owns real history, drafts and one live turn. Widgets own focus and scrolling.
class AiAssistantController extends ChangeNotifier {
  AiAssistantController(
      {AiAssistantApi? api,
      AiAssistantSession Function()? sessionProvider,
      bool? serviceEnabled})
      : api = api ?? AiAssistantApi(),
        serviceEnabled = serviceEnabled ?? api != null,
        _sessionProvider = sessionProvider ?? currentAiSession {
    _owner = _sessionProvider();
  }
  final AiAssistantApi api;
  final bool serviceEnabled;
  final AiAssistantSession Function() _sessionProvider;
  late final AiAssistantSession _owner;
  final messages = <AiAssistantMessage>[];
  final drafts = <AiAssistantDraftItem>[];
  AiAssistantReply? reply;
  String? selectedTool;
  AiAssistantException? error;
  bool welcomeVisible = false, guideVisible = false;
  bool historyLoaded = false, historyLoading = false, hasMore = false;
  bool clearing = false;
  String? _cursor;
  bool _closed = false, _initialized = false, _expired = false;
  int _historyGeneration = 0;
  CancelToken? _historyCancel;
  bool get replying => reply != null && !reply!.terminal;
  bool get current => !_closed && !_expired && _owner == _sessionProvider();

  void checkSession() {
    if (_closed || _expired || current) return;
    _expired = true;
    _historyGeneration++;
    _historyCancel?.cancel('session_boundary');
    reply?.token.cancel('session_boundary');
    reply?.finish(copyAiMessage(reply!.visible.value, status: 'interrupted'));
    messages.clear();
    drafts.clear();
    selectedTool = null;
    historyLoading = false;
    historyLoaded = true;
    hasMore = false;
    guideVisible = welcomeVisible = false;
    error = null;
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized || !current) return;
    _initialized = true;
    final welcome = await AiAssistantWelcomeStore.isDismissed(_owner.userID);
    final guide = await AiAssistantWelcomeStore.isGuideDismissed(_owner.userID);
    if (!current) return;
    welcomeVisible = !welcome;
    guideVisible = !guide;
    notifyListeners();
    await loadHistory();
  }

  Future<void> dismissGuide() async {
    if (!current) return;
    guideVisible = false;
    notifyListeners();
    await AiAssistantWelcomeStore.dismissGuide(_owner.userID);
  }

  Future<void> dismissWelcome() async {
    if (!current) return;
    welcomeVisible = false;
    notifyListeners();
    await AiAssistantWelcomeStore.dismiss(_owner.userID);
  }

  Future<void> loadHistory({bool older = false}) async {
    if (!serviceEnabled) {
      if (current) {
        historyLoaded = true;
        notifyListeners();
      }
      return;
    }
    if (!current ||
        historyLoading ||
        replying ||
        clearing ||
        (older && !hasMore)) {
      return;
    }
    final generation = ++_historyGeneration;
    _historyCancel = CancelToken();
    historyLoading = true;
    error = null;
    notifyListeners();
    try {
      final page = await api.history(
          limit: older ? 50 : 100,
          cursor: older ? _cursor : null,
          cancelToken: _historyCancel);
      if (!current || generation != _historyGeneration) return;
      final records = page.items
          .map(AiAssistantHistoryMap.toMessage)
          .map((message) => message.status == 'streaming'
              ? copyAiMessage(message,
                  status: 'interrupted', outputKind: AiAssistantOutputKind.text)
              : message)
          .toList();
      if (!older) messages.clear();
      final ids = messages.map((message) => message.serverId).toSet();
      messages.insertAll(
          0,
          records.where((message) =>
              message.serverId == null || !ids.contains(message.serverId)));
      hasMore = page.hasMore;
      _cursor = page.nextCursor;
    } on AiAssistantException catch (exception) {
      if (current && generation == _historyGeneration) error = exception;
    } catch (_) {
      if (current && generation == _historyGeneration) {
        error = const AiAssistantException('SERVICE_UNAVAILABLE', '助手服务暂不可用');
      }
    } finally {
      if (current && generation == _historyGeneration) {
        historyLoading = false;
        historyLoaded = true;
        notifyListeners();
      }
    }
  }

  void selectTool(String? tool) {
    if (!current) return;
    selectedTool = selectedTool == tool ? null : tool;
    notifyListeners();
  }

  bool addCard(AiAssistantCardRef card) {
    if (!current || drafts.length >= 8) return false;
    if (drafts.any((draft) =>
        draft.card?.id == card.id && draft.card?.kind == card.kind)) {
      return false;
    }
    drafts.add(AiAssistantDraftItem.card(card));
    notifyListeners();
    return true;
  }

  bool addFiles(List<AiAssistantFileRef> files) {
    if (!current || drafts.length + files.length > 8) return false;
    drafts.addAll(files.map(AiAssistantDraftItem.file));
    notifyListeners();
    return true;
  }

  void removeDraft(int index) {
    if (!current || index < 0 || index >= drafts.length) return;
    drafts.removeAt(index);
    notifyListeners();
  }

  Future<bool> send(String text, {String languageCode = 'zh'}) async {
    if (!current || replying || clearing) return false;
    if (!serviceEnabled) {
      error = AiAssistantException(
          'SERVICE_UNAVAILABLE',
          languageCode == 'zh'
              ? 'AI 服务尚未接入'
              : 'AI service is not connected yet');
      notifyListeners();
      return false;
    }
    final planned = AiAssistantSendPlanner.plan(
        tool: selectedTool,
        text: text,
        cards: drafts
            .map((draft) => draft.card)
            .whereType<AiAssistantCardRef>()
            .toList(),
        files: drafts
            .map((draft) => draft.file)
            .whereType<AiAssistantFileRef>()
            .toList());
    if (planned is AiAssistantSendError) {
      error = AiAssistantException(
          'INVALID_INPUT', planned.localize(languageCode: languageCode));
      notifyListeners();
      return false;
    }
    final plan = planned as AiAssistantSendPlan;
    _historyGeneration++;
    _historyCancel?.cancel('new_turn');
    historyLoading = false;
    reply?.dispose();
    final user = AiAssistantMessage(
        role: AiAssistantRole.user,
        time: _time(),
        text: plan.displayText.isEmpty ? null : plan.displayText,
        files: plan.files,
        cards: plan.cards,
        capability: plan.capability);
    final assistant = AiAssistantMessage(
        role: AiAssistantRole.assistant,
        time: '',
        outputKind: AiAssistantOutputKind.thinking,
        capability: plan.capability,
        status: 'streaming');
    final turn =
        reply = AiAssistantReply(user, assistant, isCurrent: () => current);
    messages.addAll([user, assistant]);
    drafts.clear();
    selectedTool = null;
    error = null;
    historyLoaded = true;
    notifyListeners();
    unawaited(_runReply(turn, plan));
    return true;
  }

  bool _active(AiAssistantReply turn) {
    if (!current) {
      checkSession();
      return false;
    }
    return identical(reply, turn) && !turn.terminal && !turn.token.isCancelled;
  }

  Future<void> _runReply(
      AiAssistantReply turn, AiAssistantSendPlan plan) async {
    try {
      final uploaded = <AiAssistantFileRef>[];
      for (final file in plan.files) {
        if (!_active(turn)) return;
        if ((file.fileId ?? '').isNotEmpty) {
          uploaded.add(file);
          continue;
        }
        final result = await api.uploadFile(
            fileName: file.name,
            path: file.localPath,
            bytes: file.bytes,
            mimeType: file.mimeType,
            cancelToken: turn.token);
        if (!_active(turn)) return;
        uploaded.add(AiAssistantFileRef(
            name: result.fileName,
            sizeLabel: file.sizeLabel,
            kind: file.kind,
            localPath: file.localPath,
            bytes: file.bytes,
            fileId: result.fileId,
            mimeType: result.contentType,
            sizeBytes: result.sizeBytes));
      }
      if (!_active(turn)) return;
      if (uploaded.isNotEmpty) {
        final index = messages.indexOf(turn.user);
        turn.user = copyAiMessage(turn.user, files: uploaded);
        if (index >= 0) messages[index] = turn.user;
        notifyListeners();
      }
      await for (final event in api.streamChat(
          capability: plan.capability,
          content: plan.content,
          analyze: plan.analyze,
          fileIds: uploaded.map((file) => file.fileId!).toList(),
          cancelToken: turn.token)) {
        if (!_active(turn)) return;
        switch (event.kind) {
          case AiAssistantStreamKind.meta:
            final index = messages.indexOf(turn.user);
            turn.user = copyAiMessage(turn.user, serverId: event.userMessageId);
            if (index >= 0) messages[index] = turn.user;
            turn.visible.value = copyAiMessage(turn.visible.value,
                serverId: event.assistantMessageId);
          case AiAssistantStreamKind.delta:
            turn.append(event.text);
          case AiAssistantStreamKind.done:
            turn.publish();
            _finish(
                turn,
                copyAiMessage(turn.visible.value,
                    time: _time(),
                    status: 'complete',
                    serverId: event.assistantMessageId,
                    imageUrl: event.imageUrl.isEmpty ? null : event.imageUrl,
                    outputKind: event.imageUrl.isEmpty
                        ? AiAssistantOutputKind.text
                        : AiAssistantOutputKind.image));
            return;
          case AiAssistantStreamKind.error:
            throw AiAssistantException(event.code, event.message);
        }
      }
      if (_active(turn)) {
        turn.publish();
        _finish(
            turn,
            copyAiMessage(turn.visible.value,
                time: _time(),
                status: 'interrupted',
                outputKind: AiAssistantOutputKind.text));
      }
    } on AiAssistantException catch (exception) {
      if (!_active(turn)) return;
      turn.publish();
      error = exception;
      _finish(
          turn,
          copyAiMessage(turn.visible.value,
              time: _time(),
              text: turn.text.isEmpty ? exception.message : null,
              status: 'failed',
              failed: true,
              outputKind: AiAssistantOutputKind.text));
    } catch (_) {
      if (!_active(turn)) return;
      turn.publish();
      error = const AiAssistantException('SERVICE_UNAVAILABLE', '助手服务暂不可用');
      _finish(
          turn,
          copyAiMessage(turn.visible.value,
              time: _time(),
              text: turn.text.isEmpty ? error!.message : null,
              status: 'failed',
              failed: true,
              outputKind: AiAssistantOutputKind.text));
    }
  }

  void _finish(AiAssistantReply turn, AiAssistantMessage result) {
    if (!current || !identical(turn, reply)) return;
    if (messages.isNotEmpty) messages[messages.length - 1] = result;
    turn.finish(result);
    notifyListeners();
  }

  void stopReply() {
    final turn = reply;
    if (turn == null || !_active(turn)) return;
    turn.publish();
    final result = copyAiMessage(turn.visible.value,
        time: _time(),
        status: 'stopped',
        outputKind: AiAssistantOutputKind.text);
    _finish(turn, result);
    if (turn.text.isEmpty && messages.isNotEmpty) {
      messages.removeLast();
      notifyListeners();
    }
  }

  Future<bool> clearHistory() async {
    if (!current || clearing || replying) return false;
    if (!serviceEnabled) {
      messages.clear();
      notifyListeners();
      return true;
    }
    clearing = true;
    _historyGeneration++;
    _historyCancel?.cancel('clear_history');
    historyLoading = false;
    error = null;
    notifyListeners();
    try {
      await api.deleteHistory();
      if (!current) return false;
      messages.clear();
      hasMore = false;
      _cursor = null;
      return true;
    } on AiAssistantException catch (exception) {
      if (current) error = exception;
      return false;
    } finally {
      if (current) {
        clearing = false;
        notifyListeners();
      }
    }
  }

  String _time() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _closed = true;
    _historyGeneration++;
    _historyCancel?.cancel('dispose');
    reply?.dispose();
    super.dispose();
  }
}
