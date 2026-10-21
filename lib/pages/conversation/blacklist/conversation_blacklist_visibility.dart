import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Blacklisting changes visibility only; SDK conversation order stays intact.
class ConversationBlacklistVisibility {
  ConversationBlacklistVisibility({
    required this.load,
    required this.isActive,
    required this.changed,
  });

  final Future<List<BlacklistInfo>> Function() load;
  final bool Function() isActive;
  final void Function() changed;
  Set<String> _blocked = {};
  int _generation = 0;

  bool allows(ConversationInfo row) =>
      !row.isSingleChat || !_blocked.contains(row.userID);

  void setBlocked(String userID, bool blocked) {
    if (!isActive()) return;
    ++_generation;
    final updated = blocked ? _blocked.add(userID) : _blocked.remove(userID);
    if (updated) changed();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    try {
      final entries = await load();
      if (!isActive() || generation != _generation) return;
      _blocked = {
        for (final entry in entries)
          if (_id(entry) case final String id) id,
      };
      changed();
    } catch (_) {
      // Keep the last confirmed visibility; a later SDK sync retries the read.
    }
  }

  static String? _id(BlacklistInfo entry) {
    for (final id in [entry.blockUserID, entry.userID]) {
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }
}
