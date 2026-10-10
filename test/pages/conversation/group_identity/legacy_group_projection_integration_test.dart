import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'legacy_group_conversation_projection_test.dart' as fixture;

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void onClose() {
    close();
    super.onClose();
  }
}

class _Home extends GetxController implements HomeLogic {
  @override
  final conversationsAtFirstPage = <ConversationInfo>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late _Home home;
  late List<ConversationInfo> local;
  late List<String> sdkMethods;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    Get.put<AppController>(_App());
    Get.put<IMController>(_IM());
    home = _Home();
    Get.put<HomeLogic>(home);
    local = [fixture.row(fixture.group), fixture.row('@${fixture.group}')];
    sdkMethods = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      expect(call.method, 'getConversationListSplit');
      sdkMethods.add(call.method);
      return jsonEncode(local.map((e) => e.toJson()).toList());
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    Get.reset();
  });

  test('refresh deduplicates without reading or hiding old group history',
      () async {
    final logic = ConversationLogic();
    await logic.onRefresh();
    expect(logic.list.map((e) => e.conversationID), ['sg_@${fixture.group}']);
    // Local storage is untouched. Repeated stale snapshots remain collapsed.
    expect(local, hasLength(2));
    await logic.onRefresh();
    expect(logic.list, hasLength(1));
    expect(sdkMethods, everyElement('getConversationListSplit'));
    expect(sdkMethods, isNot(contains('getAdvancedHistoryMessageList')));
    expect(sdkMethods, isNot(contains('hideConversation')));
    logic.onClose();
  });

  test('cached first page is deduplicated on login', () async {
    final logic = ConversationLogic();
    home.conversationsAtFirstPage.addAll(local);
    await logic.getFirstPage();
    expect(logic.list.map((e) => e.conversationID), ['sg_@${fixture.group}']);
    expect(home.conversationsAtFirstPage, hasLength(2));
    logic.onClose();
  });

  test('replacement arriving after first page immediately collapses old row',
      () async {
    final logic = ConversationLogic();
    home.conversationsAtFirstPage.add(local.first);
    await logic.getFirstPage();
    expect(logic.list.single.conversationID, 'sg_${fixture.group}');
    logic.onChanged([local.last]);
    expect(logic.list.single.conversationID, 'sg_@${fixture.group}');
    logic.onChanged([local.first]);
    expect(logic.list.single.conversationID, 'sg_@${fixture.group}');
    logic.onClose();
  });

  test('restart reconstructs projection from persistent SDK rows', () async {
    var logic = ConversationLogic();
    await logic.onRefresh();
    logic.onClose();
    logic = ConversationLogic();
    await logic.onRefresh();
    expect(logic.list.single.conversationID, 'sg_@${fixture.group}');
    logic.onClose();
  });

  test(
      'repeated stale native snapshots remain collapsed without maintenance writes',
      () async {
    final logic = ConversationLogic();
    for (var i = 0; i < 10; i++) {
      await logic.onRefresh();
      expect(logic.list.map((row) => row.conversationID),
          ['sg_@${fixture.group}']);
      expect(local, hasLength(2));
    }
    expect(sdkMethods, hasLength(10));
    expect(sdkMethods, everyElement('getConversationListSplit'));
    logic.onClose();
  });
}
