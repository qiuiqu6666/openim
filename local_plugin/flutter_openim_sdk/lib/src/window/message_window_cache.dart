import '../models/message.dart';

/// Small process-local copies of native proofs. SQLite remains authoritative.
/// Invalidation fences in-flight reads, including logout/login to the same user.
class MessageWindowCache {
  static final shared = MessageWindowCache();
  MessageWindowCache(
      {this.limit = 12,
      this.lifetime = const Duration(seconds: 2),
      DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final int limit;
  final Duration lifetime;
  final DateTime Function() _now;
  final _entries = <(Object, String, int), (DateTime, AdvancedMessage)>{};
  final _pending = <(Object, String, int, int), Future<AdvancedMessage>>{};
  int _revision = 0;

  AdvancedMessage? peek(Object session, String id, int count) {
    final key = (session, id, count);
    final cached = _entries.remove(key);
    if (cached != null && _now().difference(cached.$1) < lifetime) {
      _entries[key] = cached;
      return _copy(cached.$2);
    }
    return null;
  }

  Future<AdvancedMessage> read(Object session, String id, int count,
      Future<AdvancedMessage> Function() load) async {
    final cached = peek(session, id, count);
    if (cached != null) return cached;
    final key = (session, id, count);
    final revision = _revision;
    // Navigation warming and page construction share the same native read.
    // Invalidation changes the key: a new page cannot join an obsolete read.
    final flightKey = (session, id, count, revision);
    final request = _pending[flightKey] ?? Future<AdvancedMessage>.sync(load);
    if (_pending.length < limit) _pending[flightKey] = request;
    late AdvancedMessage page;
    try {
      page = await request;
    } finally {
      if (identical(_pending[flightKey], request)) _pending.remove(flightKey);
    }
    if (revision == _revision &&
        page.window?.canPublish == true &&
        page.window!.conversationID == id &&
        !(page.messageList ?? [])
            .any((m) => m.attachedInfoElem?.isPrivateChat == true)) {
      _entries[key] = (_now(), _copy(page));
      while (_entries.length > limit) {
        _entries.remove(_entries.keys.first);
      }
    }
    // Callers may filter rows; never share the mutable native result.
    return _copy(page);
  }

  static AdvancedMessage _copy(AdvancedMessage page) =>
      AdvancedMessage.fromJson(page.toJson());

  void invalidate([String? id]) {
    _revision++;
    if (id == null) {
      _entries.clear();
    } else {
      _entries.removeWhere((key, _) => key.$2 == id);
    }
  }

  void received(Message message, String self) {
    _revision++;
    String target(Message row) => (row.groupID?.isNotEmpty == true)
        ? 'group:${row.groupID}'
        : 'user:${row.sendID == self ? row.recvID : row.sendID}';
    _entries.removeWhere((_, value) =>
        (value.$2.messageList?.isEmpty ?? true) ||
        value.$2.messageList!.any((row) =>
            row.clientMsgID == message.clientMsgID ||
            target(row) == target(message)));
  }
}
