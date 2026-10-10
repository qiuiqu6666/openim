import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/group_identity/legacy_group_conversation_migration.dart';
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

// A failed old-history read makes cleanup return without hiding anything. List
// deduplication must not depend on that optional cleanup succeeding.
class _UnavailableHistory extends LegacyGroupConversationMigration {
  var attempts = 0;
  @override
  Future<void> run(
      {required bool Function() isActive,
      required void Function(ConversationInfo) onHidden}) async {
    attempts++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late _Home home;
  late List<ConversationInfo> local;
  late _UnavailableHistory migration;

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
    migration = _UnavailableHistory();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      expect(call.method, 'getConversationListSplit');
      return jsonEncode(local.map((e) => e.toJson()).toList());
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    Get.reset();
  });

  test('refresh deduplicates while old history remains unavailable', () async {
    final logic = ConversationLogic(groupMigration: migration);
    await logic.onRefresh();
    expect(logic.list.map((e) => e.conversationID), ['sg_@${fixture.group}']);
    expect(migration.attempts, 1);
    // Local storage is untouched. Repeated stale snapshots remain collapsed.
    expect(local, hasLength(2));
    await logic.onRefresh();
    expect(logic.list, hasLength(1));
    logic.onClose();
  });

  test('cached first page is deduplicated on login', () async {
    final logic = ConversationLogic(groupMigration: migration);
    home.conversationsAtFirstPage.addAll(local);
    await logic.getFirstPage();
    expect(logic.list.map((e) => e.conversationID), ['sg_@${fixture.group}']);
    expect(home.conversationsAtFirstPage, hasLength(2));
    logic.onClose();
  });

  test('replacement arriving after first page immediately collapses old row',
      () async {
    final logic = ConversationLogic(groupMigration: migration);
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
    var logic = ConversationLogic(groupMigration: migration);
    await logic.onRefresh();
    logic.onClose();
    logic = ConversationLogic(groupMigration: migration);
    await logic.onRefresh();
    expect(logic.list.single.conversationID, 'sg_@${fixture.group}');
    logic.onClose();
  });
}
