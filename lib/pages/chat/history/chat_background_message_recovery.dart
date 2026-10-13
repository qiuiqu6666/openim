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
  Message? _verificationAnchor;
  Future<bool>? _request;
  Timer? _retry;
  final _visible = <String>{};
  int _revision = 0;
  int _attempts = 0;
  bool _settled = false;
  bool _closed = false;
  bool _rerun = false;
  bool _verifyBeforeRead = false;
  bool _unverifiedGap = false;

  bool get hasCheckpoint => _cursor != null;

  void suspend() {
    if (_closed) return;
    final latest = anchor();
    if (_cursor == null ||
        (_settled &&
            _request == null &&
            !_verifyBeforeRead &&
            !_unverifiedGap &&
            latest != null &&
            !_after(latest, _cursor!))) {
      _cursor = latest;
      _verificationAnchor = latest;
      _visible.clear();
    }
    _settled = false;
    restart(verifyCheckpoint: _unverifiedGap);
  }

  void restart({bool verifyCheckpoint = false}) {
    _attempts = 0;
    _retry?.cancel();
    _retry = null;
    // A successful early local page can contain a newer live row before an
    // older interval is persisted. A fresh native completion must be able to
    // revisit this recovery boundary, including when a read is still in flight.
    // Sequence holes alone cannot prove loss: deleted messages create them too.
    if (verifyCheckpoint && _verificationAnchor != null) {
      _verifyBeforeRead = true;
    }
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
    final verifying = _verifyBeforeRead;
    if (verifying) {
      _cursor = _verificationAnchor;
      _verifyBeforeRead = false;
      _settled = false;
    }
    final revision = _revision;
    final completer = Completer<bool>();
    _request = completer.future;
    ++_attempts;
    _run(revision, verifying: verifying).then((applied) {
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

  Future<bool> _run(int revision, {required bool verifying}) async {
    bool current() => !_closed && revision == _revision && canRead();
    try {
      var pages = 0;
      var sawGap = false;
      while (current()) {
        final cursor = _cursor!;
        final result = await readNewer(count: pageSize, startMsg: cursor);
        if (!current()) return false;
        final page = (result.messageList ?? [])
            .where((message) => _after(message, cursor))
            .toList()
          ..sort(_compare);
        var previousSeq = cursor.seq ?? 0;
        for (final message in page) {
          final seq = message.seq ?? 0;
          if (previousSeq > 0 && seq > previousSeq + 1) {
            // This can be a legal deletion. Preserve the verification
            // boundary without rejecting the page or extending its ordinary
            // retry budget. A wake can finish before native persistence, so
            // even a verification pass must not certify another sparse page.
            sawGap = _unverifiedGap = true;
          }
          previousSeq = seq;
        }
        for (final message in page) {
          apply(message, !_visible.contains(message.clientMsgID));
        }
        if (page.isNotEmpty) _cursor = page.last;
        if (result.isEnd == true) {
          if (verifying) _unverifiedGap = sawGap;
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
    _verificationAnchor = null;
    _request = null;
    _visible.clear();
    _rerun = _settled = _verifyBeforeRead = _unverifiedGap = false;
    restart();
  }

  void close() {
    _closed = true;
    cancel();
  }
}
