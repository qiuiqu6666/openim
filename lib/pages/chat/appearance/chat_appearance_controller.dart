import 'dart:async';

import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../mine/settings/chat_background_local_service.dart';

/// Owns the chat's font scale and resolved local background.
class ChatAppearanceController {
  ChatAppearanceController({
    required String Function() otherID,
    required bool Function() isClosed,
  })  : _otherID = otherID,
        _isClosed = isClosed;

  final String Function() _otherID;
  final bool Function() _isClosed;
  final scaleFactor = Config.textScaleFactor.obs;
  final background = ''.obs;
  bool _initialized = false;
  bool _closed = false;
  int _reloadGeneration = 0;

  void initialize() {
    if (_closed || _isClosed() || _initialized) return;
    _initialized = true;
    scaleFactor.value = DataSp.getChatFontSizeFactor();
    unawaited(reload());
  }

  Future<void> reload() async {
    if (_closed || _isClosed()) return;
    final id = _otherID();
    final generation = ++_reloadGeneration;
    bool active() =>
        !_closed &&
        !_isClosed() &&
        generation == _reloadGeneration &&
        id == _otherID();

    var direct = ChatBackgroundLocalService.direct(id);
    if (direct != null && !await ChatBackgroundLocalService.isUsable(direct)) {
      if (!active()) return;
      // A settings change may have replaced the value during the file check.
      if (ChatBackgroundLocalService.direct(id) != direct) {
        await reload();
        return;
      }
      await ChatBackgroundLocalService.clear(id);
      if (!active()) return;
      direct = null;
    }

    var value = direct ?? ChatBackgroundLocalService.global();
    if (value != null && !await ChatBackgroundLocalService.isUsable(value)) {
      if (!active()) return;
      if (ChatBackgroundLocalService.global() != value) {
        await reload();
        return;
      }
      await ChatBackgroundLocalService.clear(
          ChatBackgroundLocalService.globalConversationId);
      if (!active()) return;
      value = null;
    }
    if (active()) background.value = value ?? '';
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _reloadGeneration++;
  }
}
