import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

/// Session-scoped visibility only. History and SDK unread reconciliation remain
/// intact. Publish complete snapshots and let newer callbacks win over reads.
class ConversationMembership {
  ConversationMembership({required this.fetchPage, required this.isActive});

  final Future<List<GroupInfo>> Function(int offset, int count) fetchPage;
  final bool Function() isActive;
  final revision = 0.obs;
  Set<String>? _joined;
  final _events = <String, bool>{};
  final _versions = <String, int>{};
  int _version = 0;
  Future<void>? _pending;

  bool allows(ConversationInfo row) {
    revision.value;
    if (!row.isGroupChat) return true;
    final id = row.groupID;
    return _events[id] ?? (_joined == null || _joined!.contains(id));
  }

  void changed(String? id, bool joined) {
    if (!isActive() || id == null || id.isEmpty) return;
    _events[id] = joined;
    _versions[id] = ++_version;
    revision.value++;
  }

  Future<void> refresh() => _pending ??= _read().whenComplete(() {
        _pending = null;
      });

  Future<void> _read() async {
    // Existing events are already reflected by the next SDK snapshot; only
    // callbacks arriving during this read must override that snapshot.
    final started = _version;
    final joined = <String>{};
    try {
      var offset = 0;
      const count = 200;
      while (isActive()) {
        final page = await fetchPage(offset, count);
        if (!isActive()) return;
        joined.addAll(page.map((g) => g.groupID).whereType<String>());
        offset += page.length;
        if (page.length < count) {
          _joined = joined;
          _events.removeWhere((id, _) => _versions[id]! <= started);
          _versions.removeWhere((_, version) => version <= started);
          revision.value++;
          return;
        }
      }
    } catch (_) {
      // A failed/partial query is not evidence that the user left any group.
    }
  }
}
