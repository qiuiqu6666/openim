import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// One preview operation per chat, from preparation until the viewer closes.
class ChatMediaPreviewSession {
  bool _busy = false;

  Future<void> run(Future<void> Function() open) async {
    if (_busy) return;
    _busy = true;
    try {
      await open();
    } finally {
      _busy = false;
    }
  }

  /// Slow history must not hold the tapped image behind SDK pagination.
  Future<List<Message>> loadHistory(
    Future<List<Message>> Function(bool Function() continueLoading) load, {
    Duration wait = const Duration(milliseconds: 400),
  }) async {
    var loading = true;
    try {
      final history = load(() => loading).then(
        (messages) => messages,
        onError: (Object _, StackTrace __) => <Message>[],
      );
      return await history.timeout(wait, onTimeout: () => []);
    } catch (_) {
      return [];
    } finally {
      loading = false;
    }
  }
}
