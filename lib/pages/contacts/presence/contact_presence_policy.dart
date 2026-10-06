import '../../ai_assistant/navigation/official_account_resolver.dart';
import '../../official_account/models/official_account.dart';
import '../presence_store.dart';

/// Official service accounts are always available in presence displays.
/// SDK/server snapshots and ordinary users' privacy remain unchanged.
abstract final class ContactPresencePolicy {
  static final _official = UserPresence(true, null);

  static UserPresence? resolve({
    required String? userID,
    String? ex,
    UserPresence? presence,
  }) {
    final id = userID?.trim() ?? '';
    if (id == OfficialAccountResolver.assistantUserID ||
        OfficialAccount.hasVerifiedIdentity(userID: id, ex: ex)) {
      return _official;
    }
    return presence;
  }
}
