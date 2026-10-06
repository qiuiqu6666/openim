import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

class RetentionWrite {
  RetentionWrite(this.call);
  final MethodCall call;
  final result = Completer<Object?>();
  Map<String, dynamic> get request =>
      Map<String, dynamic>.from(call.arguments['req'] as Map);
  void succeed() => result.complete(null);
  void fail() => result
      .completeError(PlatformException(code: 'NETWORK', message: '设置失败，请重试'));
}

class RetentionSdkFixture {
  RetentionSdkFixture({ConversationInfo? conversation})
      : server = conversation ?? retentionConversation();
  static const channel = MethodChannel('flutter_openim_sdk');
  ConversationInfo server;
  final writes = <RetentionWrite>[];
  final reads = <MethodCall>[];
  bool failNextRead = false;
  Completer<String>? _nextRead;
  final _heldReads = <Completer<String>>[];

  Completer<String> holdNextRead() {
    final read = Completer<String>();
    _heldReads.add(read);
    _nextRead = read;
    return read;
  }

  void releaseRead(Completer<String> read) =>
      read.complete(jsonEncode([server.toJson()]));

  Future<void> initialize() async {
    OpenIM.iMManager.userID = 'setup-owner';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'setup-owner');
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'setup-owner',
      'imToken': 'setup-im-token',
      'chatToken': 'setup-chat-token',
    }));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setConversation') {
        final write = RetentionWrite(call);
        writes.add(write);
        return write.result.future;
      }
      if (call.method == 'getMultipleConversation') {
        reads.add(call);
        if (failNextRead) {
          failNextRead = false;
          throw PlatformException(code: 'NETWORK', message: '读取失败，请重试');
        }
        final pending = _nextRead;
        if (pending != null) {
          _nextRead = null;
          return pending.future;
        }
        return jsonEncode([server.toJson()]);
      }
      return null;
    });
  }

  Future<void> dispose() async {
    for (final write in writes) {
      if (!write.result.isCompleted) write.succeed();
    }
    for (final read in _heldReads) {
      if (!read.isCompleted) releaseRead(read);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await DataSp.removeLoginCertificate();
  }
}

ConversationInfo retentionConversation(
        {bool group = false,
        bool burn = false,
        int burnSeconds = 30,
        bool delete = false,
        int deleteSeconds = 86400}) =>
    ConversationInfo(
      conversationID: group ? 'sg-retention' : 'si-retention',
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      userID: group ? null : 'peer-user',
      groupID: group ? 'group' : null,
      showName: group ? '测试群' : '测试好友',
      unreadCount: 0,
      isPrivateChat: burn,
      burnDuration: burnSeconds,
      isMsgDestruct: delete,
      msgDestructTime: deleteSeconds,
    );
