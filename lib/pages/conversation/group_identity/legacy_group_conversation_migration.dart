import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../../services/legacy_identity/legacy_group_identity.dart';
import '../../../services/legacy_identity/legacy_server_snapshot.dart';

/// Reconciles old SDK caches only after both server and local replacement exist.
/// History stays on the device; no server clear or message deletion is used.
class LegacyGroupConversationMigration {
  LegacyGroupConversationMigration({
    LegacyCleanupSession? Function()? session,
    Future<Set<String>> Function(LegacyCleanupSession)? serverIDs,
    Future<List<ConversationInfo>> Function(int, int)? readPage,
    Future<List<ConversationInfo>> Function(List<String>)? readConversations,
    Future<AdvancedMessage> Function(String, Message?)? readHistory,
    Future<void> Function(String, String)? setDraft,
    Future<void> Function(String)? hide,
  })  : _session = session ?? LegacyServerSnapshot.currentSession,
        _serverIDs = serverIDs ?? LegacyServerSnapshot.serverIDs,
        _readPage = readPage ??
            ((offset, count) => OpenIM.iMManager.conversationManager
                .getConversationListSplit(offset: offset, count: count)),
        _readConversations = readConversations ??
            ((ids) => OpenIM.iMManager.conversationManager
                .getMultipleConversation(conversationIDList: ids)),
        _readHistory = readHistory ??
            ((id, start) => OpenIM.iMManager.messageManager
                .getAdvancedHistoryMessageList(
                    conversationID: id,
                    startMsg: start,
                    count: 100,
                    viewType: GetHistoryViewType.search)),
        _setDraft = setDraft ??
            ((id, text) async => OpenIM.iMManager.conversationManager
                .setConversationDraft(conversationID: id, draftText: text)),
        _hide = hide ??
            ((id) async => OpenIM.iMManager.conversationManager
                .hideConversation(conversationID: id));

  final LegacyCleanupSession? Function() _session;
  final Future<Set<String>> Function(LegacyCleanupSession) _serverIDs;
  final Future<List<ConversationInfo>> Function(int, int) _readPage;
  final Future<List<ConversationInfo>> Function(List<String>)
      _readConversations;
  final Future<AdvancedMessage> Function(String, Message?) _readHistory;
  final Future<void> Function(String, String) _setDraft;
  final Future<void> Function(String) _hide;
  Future<void>? _pending;

  Future<void> run(
      {required bool Function() isActive,
      required void Function(ConversationInfo) onHidden}) {
    if (_pending != null) return _pending!;
    final task = _run(isActive, onHidden);
    _pending = task;
    return task.whenComplete(() {
      if (identical(_pending, task)) _pending = null;
    });
  }

  Future<void> _run(bool Function() isActive,
      void Function(ConversationInfo) onHidden) async {
    final session = _session();
    if (session == null ||
        !LegacyServerSnapshot.allowedServer(session.server)) {
      return;
    }
    bool current() => isActive() && _session() == session;
    try {
      final all = <String, ConversationInfo>{};
      for (var offset = 0; current();) {
        final page = await _readPage(offset, 400);
        if (!current()) return;
        for (final row in page) {
          if (all.containsKey(row.conversationID)) return;
          all[row.conversationID] = row;
        }
        if (page.length < 400) break;
        offset += page.length;
      }
      final candidates = all.values
          .where((row) => _replacement(row, session) != null)
          .toList();
      if (candidates.isEmpty || !current()) return;
      final server = await _serverIDs(session);
      if (!current()) return;
      for (final old in candidates) {
        if (!current()) return;
        final id = old.conversationID;
        final replacement = _replacement(old, session)!;
        if (server.contains(id) ||
            !server.contains(replacement) ||
            !all.containsKey(replacement)) {
          continue;
        }
        try {
          final rows = await _readConversations([id, replacement]);
          if (!current()) return;
          final byID = {for (final row in rows) row.conversationID: row};
          final before = byID[id], next = byID[replacement];
          if (before == null ||
              next == null ||
              _replacement(before, session) != replacement) {
            continue;
          }
          final frozen = jsonEncode(before.toJson());
          // Never hide a conversation containing an unsent/failed local message.
          // If old history cannot be verified, leave it intact for a later retry.
          final seen = <String>{};
          Message? start;
          var safe = true;
          while (current()) {
            final page = await _readHistory(id, start);
            if (!current()) return;
            if ((page.errCode ?? 0) != 0) {
              safe = false;
              break;
            }
            final messages = page.messageList ?? <Message>[];
            for (final msg in messages) {
              if ((msg.seq ?? 0) <= 0 ||
                  msg.clientMsgID == null ||
                  !seen.add(msg.clientMsgID!)) {
                safe = false;
              }
            }
            if (!safe || page.isEnd == true) break;
            if (messages.isEmpty) {
              safe = false;
              break;
            }
            start = messages.first;
          }
          if (!safe) continue;
          final draftCheck = await _readConversations([id, replacement]);
          if (!current()) return;
          final draftByID = {
            for (final row in draftCheck) row.conversationID: row
          };
          if (draftByID[id] == null ||
              draftByID[replacement] == null ||
              jsonEncode(draftByID[id]!.toJson()) != frozen) {
            continue;
          }
          final nextDraft = draftByID[replacement]!.draftText ?? '';
          final draft = before.draftText ?? '';
          if (draft.isNotEmpty && nextDraft.isNotEmpty && nextDraft != draft) {
            continue;
          }
          if (draft.isNotEmpty && nextDraft != draft) {
            await _setDraft(replacement, draft);
            if (!current()) return;
          }
          final latestServer = await _serverIDs(session);
          if (!current()) return;
          if (latestServer.contains(id) ||
              !latestServer.contains(replacement)) {
            continue;
          }
          final latest = await _readConversations([id, replacement]);
          if (!current()) return;
          final finalByID = {for (final row in latest) row.conversationID: row};
          if (finalByID[id] == null ||
              finalByID[replacement] == null ||
              jsonEncode(finalByID[id]!.toJson()) != frozen ||
              (draft.isNotEmpty &&
                  finalByID[replacement]!.draftText != draft)) {
            continue;
          }
          await _hide(id);
          if (!current()) return;
          onHidden(before);
        } catch (_) {
          if (!current()) return;
        }
      }
    } catch (_) {
      // Retry after the next successful SDK sync; uncertainty never clears data.
    }
  }

  String? _replacement(ConversationInfo row, LegacyCleanupSession session) {
    final group = row.groupID;
    if (group == null ||
        row.conversationType != ConversationType.superGroup ||
        row.conversationID != 'sg_$group') {
      return null;
    }
    final target = LegacyGroupIdentity.canonical(group, server: session.server);
    if (target == group) return null;
    if (row.latestMsg != null && (row.latestMsg!.seq ?? 0) <= 0) return null;
    // hideConversation resets its visible timestamp, so completed rows naturally
    // disappear from the SDK list without an account-global completion flag.
    if ((row.latestMsgSendTime ?? 0) <= 0 && (row.draftText ?? '').isEmpty) {
      return null;
    }
    return 'sg_$target';
  }
}
