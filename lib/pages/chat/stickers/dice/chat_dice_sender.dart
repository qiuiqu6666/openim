import 'dart:math';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Resolves a result once, then delivers the same ordinary SDK custom message.
class ChatDiceSender {
  ChatDiceSender({
    required bool Function() isClosed,
    required bool Function() sendingMuted,
    required bool Function() isInvalidGroup,
    required Future Function(Message) sendMessage,
    Future<Message> Function(int value)? createDice,
    int Function(int max)? randomInt,
    Object? Function()? sessionKey,
  })  : _isClosed = isClosed,
        _sendingMuted = sendingMuted,
        _isInvalidGroup = isInvalidGroup,
        _sendMessage = sendMessage,
        _createDice = createDice ?? _createDiceMessage,
        _randomInt = randomInt ?? _roll,
        _sessionKey = sessionKey ?? _readSession {
    _owner = _sessionKey();
  }

  final bool Function() _isClosed, _sendingMuted, _isInvalidGroup;
  final Future Function(Message) _sendMessage;
  final Future<Message> Function(int) _createDice;
  final int Function(int) _randomInt;
  final Object? Function() _sessionKey;
  late final Object? _owner;
  Future<void>? _sending;
  bool _closed = false;

  bool get _current =>
      !_closed &&
      !_isClosed() &&
      _owner != null &&
      _owner == _sessionKey() &&
      !_sendingMuted() &&
      !_isInvalidGroup();

  static Object? _readSession() {
    final userID = OpenIM.iMManager.userID;
    if (userID.isEmpty) return null;
    return (
      userID,
      OpenIM.iMManager.token,
      DataSp.chatToken,
      DataSp.imToken,
      Config.appAuthUrl,
    );
  }

  static int _roll(int max) => Random.secure().nextInt(max);

  static Future<Message> _createDiceMessage(int value) =>
      OpenIM.iMManager.messageManager.createDiceMessage(value: value);

  Future<void> send() {
    if (!_current) return Future.value();
    final existing = _sending;
    if (existing != null) return existing;
    late final Future<void> work;
    work = _send().whenComplete(() {
      if (identical(_sending, work)) _sending = null;
    });
    return _sending = work;
  }

  Future<void> _send() async {
    try {
      final value = _randomInt(6) + 1;
      // Validate before SDK creation even for an injected random provider.
      DiceMessageData(value: value);
      if (!_current) return;
      final message = await _createDice(value);
      if (!_current) return;
      await _sendMessage(message);
    } catch (_) {
      if (_current) throw const FormatException('表情发送失败，请重试');
    }
  }

  void close() => _closed = true;
}
