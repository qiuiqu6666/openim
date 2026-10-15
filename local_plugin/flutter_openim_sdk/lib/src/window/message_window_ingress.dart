import 'dart:async';
import 'dart:collection';
import '../models/message.dart';
import '../models/message_window.dart';
import '../enum/message_status.dart';

/// A bounded presentation consumer of already persisted SDK events. Overflow
/// discards only this volatile copy and asks the owner to re-read durable data.
/// Each owner belongs to one account session/conversation and is never reused.
class MessageWindowIngress {
  MessageWindowIngress(
      {required this.conversationID,
      required this.publish,
      required this.recover,
      this.batchDelay = const Duration(milliseconds: 16),
      this.capacity = 200});
  final String conversationID;
  final void Function(List<Message>) publish;
  final void Function() recover;
  final Duration batchDelay;
  final int capacity;
  final _pending = SplayTreeMap<int, Message>();
  Timer? _timer;
  int? _through;
  int _generation = 0;
  bool _closed = false, _recovering = false;
  int get pendingCount => _pending.length;
  bool get active => _through != null;

  void accept(MessageWindow window) {
    if (_closed ||
        window.conversationID != conversationID ||
        !window.canPublish) {
      return;
    }
    if (_through == null || window.targetWatermark > _through!) {
      _through = window.targetWatermark;
    }
    _pending.removeWhere((seq, _) => seq <= _through!);
    _recovering = false;
    _schedule();
  }

  bool receive(Message message) {
    if (_closed || _through == null || (message.seq ?? 0) <= 0) return false;
    final seq = message.seq!;
    if (seq <= _through!) {
      return true; // covered replay, never insert old history
    }
    _pending[seq] = message;
    if (_pending.length > capacity) {
      _pending.clear();
      _requestRecovery();
    } else {
      _schedule();
    }
    return true;
  }

  void _schedule() {
    if (_closed || _timer != null || _pending.isEmpty || _through == null) {
      return;
    }
    final generation = _generation;
    _timer = Timer(batchDelay, () {
      _timer = null;
      if (_closed || generation != _generation) return;
      final batch = <Message>[];
      while (_pending.containsKey(_through! + 1)) {
        _through = _through! + 1;
        batch.add(_pending.remove(_through)!);
      }
      if (batch.isNotEmpty) publish(batch);
      if (_pending.isNotEmpty) _requestRecovery();
    });
  }

  void _requestRecovery() {
    if (_recovering || _closed) return;
    _recovering = true;
    recover();
  }

  void remove(String? id) {
    // Keep the sequence as coverage; the owner filters its durable tombstone.
    // Removing it here would turn a known deletion into a permanent hole.
    if (id == null) return;
    for (final message in _pending.values) {
      if (message.clientMsgID == id) message.status = MessageStatus.deleted;
    }
  }

  void close() {
    _closed = true;
    reset();
  }

  void reset() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _through = null;
    _recovering = false;
  }
}
