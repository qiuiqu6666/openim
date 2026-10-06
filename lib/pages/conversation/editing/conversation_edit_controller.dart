// Selection flow adapted from 99chat's lib/src/conversation.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: use caller-supplied OpenIM actions and page-owned lifecycle guards.
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
  final _selectedIds = <String>{};

  bool get editing => _editing;
  bool get busy => _busy;
  Set<String> get selectedIds => Set<String>.unmodifiable(_selectedIds);

  void toggleEditing() {
    if (_disposed || _busy) return;
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
  /// feedback. Disposal prevents any subsequent action from starting.
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

    _busy = true;
    notifyListeners();
    try {
      for (final conversation in targets) {
        if (_disposed) return;
        await action(conversation);
      }
      if (_disposed) return;
      _editing = false;
      _selectedIds.clear();
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _editing = false;
    _busy = false;
    _selectedIds.clear();
    super.dispose();
  }
}
