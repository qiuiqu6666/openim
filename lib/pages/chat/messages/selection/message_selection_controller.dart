import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../../../fund/notifications/fund_claim_notice.dart';

/// Selection belongs to this chat's live message window, never to another route
/// or account. Deleting and forwarding keep their existing SDK owners.
class MessageSelectionController extends ChangeNotifier {
  MessageSelectionController({
    required List<Message> Function() messages,
    required bool Function() isClosed,
    required VoidCallback onStart,
    required Future<bool> Function(List<Message>) deleteMessages,
    required Future<bool> Function(List<Message>, {required bool merged})
        forwardMessages,
  })  : _messages = messages,
        _isClosed = isClosed,
        _onStart = onStart,
        _deleteMessages = deleteMessages,
        _forwardMessages = forwardMessages;

  final List<Message> Function() _messages;
  final bool Function() _isClosed;
  final VoidCallback _onStart;
  final Future<bool> Function(List<Message>) _deleteMessages;
  final Future<bool> Function(List<Message>, {required bool merged})
      _forwardMessages;
  final _selected = <String>{};
  Set<String> _knownIDs = {};
  bool _active = false, _busy = false, _disposed = false;
  int _generation = 0;

  bool get active => _active;
  bool get busy => _busy;
  bool get canInteract => !_unavailable && active && !busy;
  Set<String> get selectedIDs => Set.unmodifiable(_selected);
  bool containsSelectableID(String id) =>
      _messages().any((m) => m.clientMsgID == id && canSelect(m));
  int get count => selectedMessages.length;
  bool get _unavailable => _disposed || _isClosed();
  bool isSelected(Message message) => _selected.contains(message.clientMsgID);

  static bool canSelect(Message message) =>
      message.clientMsgID?.isNotEmpty == true &&
      message.contentType != null &&
      message.contentType! > 0 &&
      message.contentType! < 1000 &&
      message.contentType != MessageType.typing &&
      !message.hasExpired &&
      !_isStatusNotice(message) &&
      FundClaimNotice.parse(message) == null;

  static bool _isStatusNotice(Message message) {
    if (message.contentType != MessageType.custom) return false;
    try {
      final data = jsonDecode(message.customElem?.data ?? '');
      return data is Map &&
          const [
            CustomMessageType.deletedByFriend,
            CustomMessageType.blockedByFriend,
            CustomMessageType.removedFromGroup,
            CustomMessageType.groupDisbanded,
          ].contains(data['customType']);
    } catch (_) {
      return false;
    }
  }

  List<Message> get selectedMessages {
    final seen = <String>{};
    return _messages()
        .where((m) =>
            canSelect(m) &&
            _selected.contains(m.clientMsgID) &&
            seen.add(m.clientMsgID!))
        .toList(growable: false);
  }

  bool get allSelected {
    final ids = _messages().where(canSelect).map((m) => m.clientMsgID!).toSet();
    return ids.isNotEmpty && ids.every(_selected.contains);
  }

  void enter(Message initial) {
    if (_unavailable || busy || !canSelect(initial)) return;
    if (!_messages().any((m) => m.clientMsgID == initial.clientMsgID)) return;
    _generation++;
    _selected
      ..clear()
      ..add(initial.clientMsgID!);
    _active = true;
    _knownIDs = _messages().where(canSelect).map((m) => m.clientMsgID!).toSet();
    _onStart();
    notifyListeners();
  }

  void toggle(Message message) {
    if (_unavailable || !active || busy || !canSelect(message)) return;
    if (!_messages().any((m) => m.clientMsgID == message.clientMsgID)) return;
    final id = message.clientMsgID!;
    if (!_selected.remove(id)) _selected.add(id);
    notifyListeners();
  }

  /// A long-press drag applies one contiguous range over its original selection.
  /// Returning toward the anchor restores entries outside the shortened range.
  /// IDs keep the range stable when lazy rows unmount or older history loads.
  void updateDragRange(String anchorID, String endpointID,
      {required Set<String> baseline, required bool selected}) {
    if (!canInteract) return;
    final ids = _messages()
        .where(canSelect)
        .map((m) => m.clientMsgID!)
        .toSet()
        .toList(growable: false);
    final anchor = ids.indexOf(anchorID);
    final endpoint = ids.indexOf(endpointID);
    if (anchor < 0 || endpoint < 0) return;
    final lower = anchor < endpoint ? anchor : endpoint;
    final upper = anchor > endpoint ? anchor : endpoint;
    final next = baseline.intersection(ids.toSet());
    for (var index = lower; index <= upper; index++) {
      if (selected) {
        next.add(ids[index]);
      } else {
        next.remove(ids[index]);
      }
    }
    if (setEquals(next, _selected)) return;
    _selected
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  /// Select all currently loaded messages; newly arriving or paged messages are
  /// left unselected until the user explicitly selects them.
  void toggleAll() {
    if (_unavailable || !active || busy) return;
    if (allSelected) {
      _selected.clear();
    } else {
      _selected.addAll(_messages().where(canSelect).map((m) => m.clientMsgID!));
    }
    notifyListeners();
  }

  void cancel() {
    if (_disposed || !active) return;
    _generation++;
    _active = false;
    _selected.clear();
    notifyListeners();
  }

  /// SDK removal, recall, expiry and timeline replacement invalidate selection.
  void sync() {
    if (_disposed || !active) return;
    if (_isClosed()) {
      cancel();
      return;
    }
    final ids = _messages().where(canSelect).map((m) => m.clientMsgID!).toSet();
    final before = _selected.length;
    _selected.removeWhere((id) => !ids.contains(id));
    final changed = !setEquals(ids, _knownIDs);
    _knownIDs = ids;
    if (before != _selected.length || changed) notifyListeners();
  }

  Future<void> forwardSelected({required bool merged}) =>
      _run((messages) => _forwardMessages(messages, merged: merged));

  Future<void> deleteSelected({
    required Future<bool> Function(int count) confirm,
  }) =>
      _run((messages) async {
        final generation = _generation;
        if (!await confirm(messages.length) ||
            _unavailable ||
            generation != _generation) {
          return false;
        }
        // Never delete an item that has disappeared while the sheet was open.
        final ids = selectedMessages.map((m) => m.clientMsgID).toSet();
        final remaining =
            messages.where((m) => ids.contains(m.clientMsgID)).toList();
        return remaining.isNotEmpty && await _deleteMessages(remaining);
      });

  Future<void> _run(Future<bool> Function(List<Message>) operation) async {
    if (_unavailable || !active || busy) return;
    sync();
    final messages = selectedMessages;
    if (messages.isEmpty) return;
    final generation = _generation;
    _busy = true;
    notifyListeners();
    try {
      final completed = await operation(messages);
      if (!_unavailable && generation == _generation) {
        sync();
        if (completed) cancel();
      }
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _generation++;
    _selected.clear();
    super.dispose();
  }
}
