import 'pending_forward.dart';

/// Keeps unsent forwards across chat routes within the current login session.
class PendingForwardStore {
  static final shared = PendingForwardStore();

  (String, String?)? _session;
  final _conversations = <String, PendingForwardController>{};

  PendingForwardController conversation({
    required String accountID,
    required String? sessionToken,
    required String conversationID,
  }) {
    final session = (accountID, sessionToken);
    if (_session != session) {
      clear();
      _session = session;
    }
    return _conversations.putIfAbsent(
        conversationID, PendingForwardController.new);
  }

  void clear() {
    for (final controller in _conversations.values) {
      controller.draft.value = null;
    }
    _conversations.clear();
    _session = null;
  }
}
