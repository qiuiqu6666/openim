import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'chat_message_arrival_tokens.dart';

/// Only live receive events can request an entrance. History and receipts never
/// derive an entrance from list differences, and the view owns the tickers.
class ChatMessageArrivalController extends ChangeNotifier {
  ChatMessageArrivalController({required this.currentUserID});

  final String Function() currentUserID;
  final _pending = <String>{};
  final _entering = <String>{};
  final _cancelled = <String>{};
  bool _closed = false;

  void register(Message message, {required bool enabled}) {
    final id = message.clientMsgID;
    final type = message.contentType;
    if (_closed ||
        !enabled ||
        id == null ||
        id.isEmpty ||
        message.sendID == currentUserID() ||
        type == null ||
        type == MessageType.typing ||
        type >= 1000 ||
        _entering.length >= ChatMessageArrivalTokens.maxConcurrent ||
        !_entering.add(id)) {
      return;
    }
    _pending.add(id);
    notifyListeners();
  }

  List<String> takePending(Set<String> ids) {
    final result = _pending.where(ids.contains).toList(growable: false);
    _pending.removeAll(result);
    return result;
  }

  void retain(Set<String> ids) {
    for (final id in _entering.where((id) => !ids.contains(id)).toList()) {
      finish(id);
    }
  }

  bool isEntering(String id) => !_closed && _entering.contains(id);
  bool get hasEntering => !_closed && _entering.isNotEmpty;
  bool isCancelled(String id) => _cancelled.contains(id);

  void finish(String id, {bool notify = false}) {
    if (_closed) return;
    _pending.remove(id);
    _cancelled.remove(id);
    final changed = _entering.remove(id);
    if (changed && notify) notifyListeners();
  }

  void cancel() {
    if (_closed || _entering.isEmpty) return;
    _entering.removeAll(_pending);
    _pending.clear();
    // Already laid-out rows keep the read barrier until the view paints their
    // full size. Pending rows have never exposed a clipped layout.
    _cancelled.addAll(_entering);
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _pending.clear();
    _entering.clear();
    _cancelled.clear();
    super.dispose();
  }
}
