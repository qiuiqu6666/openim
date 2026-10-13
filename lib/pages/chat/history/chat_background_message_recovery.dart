import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'chat_history_read_gate.dart';

/// Remembers the last known message before a reader leaves the chat. A later
/// live callback must never replace this checkpoint: it may be beyond a gap.
class ChatBackgroundMessageRecovery {
  ChatBackgroundMessageRecovery({
    required this.anchor,
    required this.canRead,
    required this.readNewer,
    required this.apply,
    required this.onError,
    this.pageSize = 40,
  });

  final Message? Function() anchor;
  final bool Function() canRead;
  final ChatHistoryReader readNewer;
  final void Function(Message, bool unseen) apply;
  final void Function(Object) onError;
  final int pageSize;
  Message? _cursor;
  Future<bool>? _request;
  Timer? _retry;
  final _visible = <String>{};
  int _revision = 0;
  int _attempts = 0;
  bool _settled = false;
  bool _closed = false;
  bool _rerun = false;

  bool get hasCheckpoint => _cursor != null;

  void suspend() {
    if (_closed) return;
    final latest = anchor();
    if (_cursor == null) {
      _cursor = latest;
      _visible.clear();
    }
    _settled = false;
    restart();
  }

  void restart() {
    _attempts = 0;
    _retry?.cancel();
    _retry = null;
  }

  void observeVisible(Iterable<String> ids) {
    if (hasCheckpoint && (!_settled || _request != null) && canRead()) {
      _visible.addAll(ids);
    }
  }

  void observeLive(Message message) {
    // Advance during healthy foreground traffic only with proof of continuity.
    // A jump from 32 to 133 is precisely the missing interval we must retain.
    if (_settled &&
        _request == null &&
        _cursor != null &&
        (_cursor!.seq ?? 0) > 0 &&
        message.seq == _cursor!.seq! + 1) {
      _cursor = message;
    }
  }

  Future<bool> recover() {
    if (_closed || !hasCheckpoint || !canRead()) return Future.value(false);
    if (_request != null) {
      _rerun = true;
      return _request!;
    }
    _retry?.cancel();
    _retry = null;
    final revision = _revision;
    final completer = Completer<bool>();
    _request = completer.future;
    ++_attempts;
    _run(revision).then((applied) {
      if (revision == _revision) {
        _request = null;
        // Native persistence can finish after the first successful empty read.
        // Recheck finitely even when the latest live message is already shown.
        if (canRead() && (_rerun || _attempts < 3 || !_settled)) {
          final delay = _rerun
              ? Duration.zero
              : Duration(
                  seconds: _attempts == 1
                      ? 1
                      : _attempts == 2
                          ? 3
                          : 30);
          _retry = Timer(delay, () {
            _retry = null;
            unawaited(recover());
          });
        }
        _rerun = false;
      }
      completer.complete(applied);
    });
    return completer.future;
  }

  Future<bool> _run(int revision) async {
    bool current() => !_closed && revision == _revision && canRead();
    try {
      var pages = 0;
      while (current()) {
        final cursor = _cursor!;
        final result = await readNewer(count: pageSize, startMsg: cursor);
        if (!current()) return false;
        final page = (result.messageList ?? [])
            .where((message) => _after(message, cursor))
            .toList()
          ..sort(_compare);
        for (final message in page) {
          apply(message, !_visible.contains(message.clientMsgID));
        }
        if (page.isNotEmpty) _cursor = page.last;
        if (result.isEnd == true) {
          final latest = anchor();
          _settled = latest == null || !_after(latest, _cursor!);
          if (_settled) _visible.clear();
          return _settled;
        }
        if (page.isEmpty) {
          throw StateError('Background message recovery made no progress');
        }
        // Keep very large backlogs responsive, with one native page at a time.
        if (++pages % 25 == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
      }
    } catch (error) {
      if (revision == _revision && !_closed) {
        _settled = false;
        onError(error);
      }
    }
    return false;
  }

  static bool _after(Message message, Message cursor) =>
      message.clientMsgID != cursor.clientMsgID &&
      message.clientMsgID?.isNotEmpty == true &&
      (message.seq ?? 0) > 0 &&
      message.status != MessageStatus.sending &&
      message.status != MessageStatus.failed &&
      _compare(message, cursor) > 0;

  static int _compare(Message a, Message b) {
    if ((a.seq ?? 0) > 0 && (b.seq ?? 0) > 0) {
      return a.seq!.compareTo(b.seq!);
    }
    return (a.sendTime ?? a.createTime ?? 0)
        .compareTo(b.sendTime ?? b.createTime ?? 0);
  }

  void cancel() {
    ++_revision;
    _cursor = null;
    _request = null;
    _visible.clear();
    _rerun = _settled = false;
    restart();
  }

  void close() {
    _closed = true;
    cancel();
  }
}
