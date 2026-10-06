import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_setup/chat_setup_logic.dart';

class ChatSetupFakeLogic extends GetxController implements ChatSetupLogic {
  @override
  final conversationInfo = ConversationInfo(
          conversationID: 'si-retention',
          conversationType: ConversationType.single,
          userID: 'peer-user',
          showName: '好友昵称',
          unreadCount: 0,
          isPinned: false,
          recvMsgOpt: 0)
      .obs;
  @override
  final updating = false.obs;
  @override
  final clearing = false.obs;
  final pinned = <bool>[];
  final muted = <bool>[];
  Completer<void>? pinGate;
  int profiles = 0;
  int groups = 0;
  int searches = 0;
  int backgrounds = 0;
  int clears = 0;
  int reports = 0;

  @override
  bool get isPinned => conversationInfo.value.isPinned == true;
  @override
  bool get isMuted => conversationInfo.value.recvMsgOpt == 2;
  @override
  Future<void> setPinned(bool value) async {
    if (updating.value) return;
    updating.value = true;
    pinned.add(value);
    try {
      await pinGate?.future;
      conversationInfo.value.isPinned = value;
      conversationInfo.refresh();
    } finally {
      updating.value = false;
    }
  }

  @override
  Future<void> setMuted(bool value) async {
    if (updating.value) return;
    muted.add(value);
    conversationInfo.value.recvMsgOpt = value ? 2 : 0;
    conversationInfo.refresh();
  }

  @override
  void viewUserInfo() => profiles++;
  @override
  void createGroup() => groups++;
  @override
  void searchHistory() => searches++;
  @override
  Future<void> setBackground() async => backgrounds++;
  @override
  Future<void> clearHistory() async => clears++;
  @override
  Future<void> reportConversation() async => reports++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
