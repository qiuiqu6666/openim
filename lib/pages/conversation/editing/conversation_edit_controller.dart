// Selection flow adapted from 99chat's lib/src/conversation.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: use caller-supplied OpenIM actions and page-owned lifecycle guards.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Page-owned editing state; the page supplies its visible conversation scope.
///
/// This controller does not own the SDK or an account session. Callers must
/// validate their captured session before each SDK action, and dispose this
/// controller when its page/session ends.
class ConversationEditController extends ChangeNotifier {
  bool _editing = false;
  bool _busy = false;
  bool _disposed = false;
  Completer<void>? _cancelExecution;
  final _selectedIds = <String>{};

  bool get editing => _editing;
  bool get busy => _busy;
  Set<String> get selectedIds => Set<String>.unmodifiable(_selectedIds);

  void toggleEditing() {
    if (_disposed) return;
    // Done always releases the UI, even if the current SDK action is pending.
    // Its in-flight request may still finish, but no further batch item starts.
    if (_editing) {
      _cancelCurrentExecution();
    } else if (_busy) {
      return;
    }
    _editing = !_editing;
    if (!_editing) _selectedIds.clear();
    notifyListeners();
  }

  void toggleSelection(String conversationId) {
    if (_disposed || _busy || !_editing || conversationId.isEmpty) return;
    if (!_selectedIds.remove(conversationId)) {
      _selectedIds.add(conversationId);
    }
    notifyListeners();
  }

  /// Executes a stable selection against the supplied visible list only.
  ///
  /// No selection acts on the whole supplied scope only for [allWhenEmpty].
  /// The first failure is propagated, retaining selection for the page's error
  /// feedback. Done/disposal release the wait and stop subsequent actions.
  /// An old request's completion cannot finish a newer editing operation.
  Future<void> execute({
    required List<ConversationInfo> conversations,
    required Future<void> Function(ConversationInfo) action,
    bool allWhenEmpty = false,
  }) async {
    if (_disposed || _busy || !_editing) return;
    final scopeIds = conversations.map((info) => info.conversationID).toSet();
    final selection = allWhenEmpty
        ? _selectedIds.intersection(scopeIds)
        : Set<String>.of(_selectedIds);
    if (selection.isEmpty && !allWhenEmpty) return;

    final seen = <String>{};
    final targets = List<ConversationInfo>.unmodifiable(
      List<ConversationInfo>.of(conversations).where((conversation) {
        final id = conversation.conversationID;
        return id.isNotEmpty &&
            (selection.isEmpty || selection.contains(id)) &&
            seen.add(id);
      }),
    );

    final cancelled = Completer<void>();
    _cancelExecution = cancelled;
    bool current() => !_disposed && identical(_cancelExecution, cancelled);
    _busy = true;
    notifyListeners();
    try {
      for (final conversation in targets) {
        if (!current()) return;
        await Future.any<void>([action(conversation), cancelled.future]);
      }
      if (!current()) return;
      _editing = false;
      _selectedIds.clear();
    } catch (_) {
      // Done can invalidate this batch before an already resolved error resumes.
      // Only the active operation may report a failure to its page.
      if (current()) rethrow;
    } finally {
      if (current()) {
        _cancelExecution = null;
        _busy = false;
        notifyListeners();
      }
    }
  }

  void _cancelCurrentExecution() {
    final cancelled = _cancelExecution;
    _cancelExecution = null;
    _busy = false;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelCurrentExecution();
    _editing = false;
    _busy = false;
    _selectedIds.clear();
    super.dispose();
  }
}
