import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_logic.dart';
import 'package:openim/pages/contacts/group_requests/process_group_requests/process_group_requests_logic.dart';
import 'package:openim_common/openim_common.dart';

import 'support/group_requests_test_fixture.dart';

ProcessGroupRequestsLogic _processor(GroupApplicationInfo info) =>
    ProcessGroupRequestsLogic()
      ..applicationInfo = info
      ..handleResult.value = info.handleResult ?? 0;

Future<void> _finishWrite(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 2));
  await tester.pump(const Duration(milliseconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GroupRequestsFixture fixture;

  setUp(() async {
    fixture = GroupRequestsFixture();
    await fixture.initialize();
  });

  tearDown(() async => fixture.dispose());

  testWidgets('each group resolves its actual administrator by handler ID',
      (tester) async {
    final logic = await fixture.mount(tester);
    fixture.recipient = [
      request(
          group: 'group-a', result: 1, handler: 'admin-a', inviter: 'inviter'),
    ];
    fixture.applicant = [
      request(group: 'group-b', time: 200, result: -1, handler: 'admin-b'),
    ];
    fixture.profiles.addAll({
      'admin-a': '  阿秋  ',
      'admin-b': '阿冬',
      'inviter': 'Invitation sender',
    });

    await fixture.refresh(tester, logic);

    expect(logic.list.map((item) => item.groupID), ['group-b', 'group-a']);
    expect(logic.getHandlerNickname(logic.list[0]), '阿冬');
    expect(logic.getHandlerNickname(logic.list[1]), '阿秋');
    expect(logic.getInviterNickname(logic.list[1]), 'Invitation sender');
    expect(
        logic.getHandlerNickname(logic.list[1]), isNot('Applicant nickname'));
    expect(logic.getHandlerNickname(logic.list[1]),
        isNot('Current administrator'));
  });

  testWidgets('inviter and confirmed handler IDs share one deduplicated batch',
      (tester) async {
    final logic = await fixture.mount(tester);
    fixture.recipient = [
      request(time: 1, result: 1, handler: 'shared', inviter: 'shared'),
      request(group: 'group-b', time: 2, result: -1, handler: 'shared'),
      request(group: 'group-c', time: 3, result: 1, handler: 'second'),
      request(group: 'group-d', time: 4, inviter: 'shared'),
      request(group: 'group-e', time: 5, handler: 'pending-handler'),
    ];
    fixture.profiles.addAll({'shared': '共用管理员', 'second': '另一位管理员'});

    await fixture.refresh(tester, logic);

    final calls = fixture.callsFor('getUsersInfo');
    expect(calls, hasLength(1));
    final ids = List<String>.from(calls.single.arguments['userIDList'] as List);
    expect(ids, unorderedEquals(['shared', 'second']));
    expect(ids.toSet().length, ids.length);
    expect(ids, isNot(contains('pending-handler')));
    expect(fixture.callsFor('getGroupMembersInfo'), hasLength(2));
  });

  testWidgets('unhandled or incomplete records never invent a handler nickname',
      (tester) async {
    final logic = await fixture.mount(tester);
    fixture.recipient = [
      request(time: 1, handler: 'known'),
      request(time: 2, result: 2, handler: 'known'),
      request(time: 3, result: 1),
      request(time: 4, result: -1, handler: '   '),
      request(time: 5, result: 1, handler: 'unavailable', inviter: 'inviter'),
      request(time: 6, result: -1, handler: 'blank'),
    ];
    fixture.profiles.addAll({
      'known': 'A known person',
      'inviter': 'Invitation sender',
      'blank': '  ',
    });
    logic.memberList.add(GroupMembersInfo(
        groupID: 'group-a', userID: 'unavailable', nickname: 'Group remark'));

    await fixture.refresh(tester, logic);

    for (final item in logic.list) {
      expect(logic.getHandlerNickname(item), isNull,
          reason: 'Result ${item.handleResult}, handler ${item.handleUserID}');
    }
    final ids = fixture.callsFor('getUsersInfo').single.arguments['userIDList'];
    expect(ids, unorderedEquals(['unavailable', 'inviter', 'blank']));
  });

  testWidgets('a profile outage preserves the newly confirmed application',
      (tester) async {
    fixture.recipient = [request()];
    final logic = await fixture.mount(tester);
    fixture.recipient = [request(result: 1, handler: 'offline-admin')];
    fixture.failProfiles = true;

    await fixture.refresh(tester, logic);

    expect(logic.list, hasLength(1));
    expect(logic.list.single.handleResult, 1);
    expect(logic.list.single.handleUserID, 'offline-admin');
    expect(logic.getHandlerNickname(logic.list.single), isNull);
    expect(tester.takeException(), isNull);
  });

  for (final result in [1, -1]) {
    testWidgets('successful result $result reloads the server handler record',
        (tester) async {
      fixture.recipient = [request()];
      final logic = await fixture.mount(tester);
      final processor = _processor(logic.list.single);
      fixture.profiles['server-admin'] = '服务器确认的处理人';
      fixture.onWrite = () {
        fixture.recipient = [request(result: result, handler: 'server-admin')];
      };

      if (result == 1) {
        processor.approve();
      } else {
        processor.reject();
      }
      await _finishWrite(tester);

      expect(processor.currentHandleResult, result);
      expect(processor.applicationInfo.handleUserID, 'server-admin');
      expect(processor.handlerNickname, '服务器确认的处理人');
      expect(logic.list.single.handleUserID, 'server-admin');
      expect(
          fixture.callsFor('getGroupApplicationListAsRecipient'), hasLength(1));
      final method =
          result == 1 ? 'acceptGroupApplication' : 'refuseGroupApplication';
      expect(fixture.callsFor(method), hasLength(1));
      expect(fixture.home.unreadRefreshes, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('successful result $result survives an older pending snapshot',
        (tester) async {
      fixture.recipient = [request()];
      final logic = await fixture.mount(tester);
      final processor = _processor(logic.list.single);
      logic.userInfoList.add(
          UserInfo(userID: 'current-admin', nickname: 'Current administrator'));

      if (result == 1) {
        processor.approve();
      } else {
        processor.reject();
      }
      await _finishWrite(tester);

      expect(processor.currentHandleResult, result);
      expect(processor.handleResult.value, result);
      expect(processor.applicationInfo.handleResult, result);
      expect(processor.applicationInfo.handleUserID, isNull);
      expect(processor.handlerNickname, isNull);
      expect(logic.list.single.handleResult, result);
      expect(logic.list.single.handleUserID, isNull);
      expect(logic.getHandlerNickname(logic.list.single), isNull);
      expect(fixture.callsFor('getUsersInfo'), isEmpty);

      processor.approve();
      processor.reject();
      await _finishWrite(tester);
      final method =
          result == 1 ? 'acceptGroupApplication' : 'refuseGroupApplication';
      expect(fixture.callsFor(method), hasLength(1));
      expect(
          fixture.callsFor(result == 1
              ? 'refuseGroupApplication'
              : 'acceptGroupApplication'),
          isEmpty);
    });
  }

  testWidgets('an account switch before SDK submission cancels processing',
      (tester) async {
    fixture.recipient = [request()];
    final logic = await fixture.mount(tester);
    final processor = _processor(logic.list.single);

    processor.approve();
    OpenIM.iMManager.userID = 'another-account';
    await _finishWrite(tester);

    expect(fixture.callsFor('acceptGroupApplication'), isEmpty);
    expect(fixture.callsFor('getGroupApplicationListAsRecipient'), isEmpty);
    expect(logic.list.single.handleResult, 0);
    expect(processor.currentHandleResult, 0);
    expect(processor.handlerNickname, isNull);
    expect(fixture.home.unreadRefreshes, 0);
  });

  testWidgets('already processed error uses the other administrator result',
      (tester) async {
    fixture.recipient = [request()];
    final logic = await fixture.mount(tester);
    final processor = _processor(logic.list.single);
    fixture.writeError = PlatformException(
        code: '${SDKErrorCode.groupApplicationHasBeenProcessed}',
        message: 'processed elsewhere');
    fixture.profiles['other-admin'] = '另一位管理员';
    fixture.onWrite = () {
      fixture.recipient = [request(result: -1, handler: 'other-admin')];
    };

    processor.approve();
    await _finishWrite(tester);

    expect(processor.currentHandleResult, -1);
    expect(processor.applicationInfo.handleUserID, 'other-admin');
    expect(processor.handlerNickname, '另一位管理员');
    expect(logic.list.single.handleUserID, 'other-admin');
    expect(logic.getHandlerNickname(logic.list.single), '另一位管理员');
    expect(fixture.callsFor('getUsersInfo').single.arguments['userIDList'],
        ['other-admin']);
    expect(tester.takeException(), isNull);
    expect(find.text(StrRes.groupRequestHandled), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a live callback refreshes the open detail and guards processing',
      (tester) async {
    fixture.recipient = [request()];
    final logic = await fixture.mount(tester);
    final processor = _processor(logic.list.single);
    fixture.recipient = [request(result: 1, handler: 'other-admin')];
    fixture.profiles['other-admin'] = '远端管理员';

    fixture.im.groupApplicationChangedSubject.add(fixture.recipient.single);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();

    expect(processor.currentHandleResult, 1);
    expect(processor.handlerNickname, '远端管理员');
    processor.approve();
    processor.reject();
    await _finishWrite(tester);
    expect(fixture.callsFor('acceptGroupApplication'), isEmpty);
    expect(fixture.callsFor('refuseGroupApplication'), isEmpty);
  });

  testWidgets(
      'detail matches the original request when the same user reapplies',
      (tester) async {
    fixture.recipient = [request(time: 100)];
    final logic = await fixture.mount(tester);
    final processor = _processor(logic.list.single);
    fixture.recipient = [
      request(time: 200, result: 1, handler: 'new-request-admin'),
      request(time: 100, result: -1, handler: 'original-request-admin'),
    ];
    fixture.profiles.addAll({
      'new-request-admin': '新申请处理人',
      'original-request-admin': '原申请处理人',
    });

    await fixture.refresh(tester, logic);

    expect(logic.list.first.reqTime, 200);
    expect(processor.currentHandleResult, -1);
    expect(processor.handlerNickname, '原申请处理人');
  });

  testWidgets('an older reload cannot replace the latest handler result',
      (tester) async {
    final logic = await fixture.mount(tester);
    fixture.holdRecipient = true;
    fixture.profiles.addAll({'old-admin': '旧记录', 'new-admin': '最新处理人'});
    final first = logic.getApplicationList();
    await tester.pump(const Duration(milliseconds: 2));
    final second = logic.getApplicationList();
    await tester.pump(const Duration(milliseconds: 2));
    expect(fixture.recipientReplies, hasLength(2));
    fixture.recipientReplies[1].complete(jsonEncode([
      request(result: -1, handler: 'new-admin').toJson(),
    ]));
    await tester.pumpAndSettle();
    await second;
    fixture.recipientReplies[0].complete(jsonEncode([
      request(result: 1, handler: 'old-admin').toJson(),
    ]));
    await tester.pumpAndSettle();
    await first;

    expect(logic.list.single.handleResult, -1);
    expect(logic.getHandlerNickname(logic.list.single), '最新处理人');
    expect(fixture.callsFor('getUsersInfo'), hasLength(1));
  });

  testWidgets('closing requests discards late results and releases callbacks',
      (tester) async {
    fixture.recipient = [request()];
    final logic = await fixture.mount(tester);
    fixture.holdRecipient = true;
    final pending = logic.getApplicationList();
    await tester.pump(const Duration(milliseconds: 2));
    await Get.delete<GroupRequestsLogic>();
    fixture.recipientReplies.single.complete(jsonEncode([
      request(result: 1, handler: 'late-admin').toJson(),
    ]));
    await tester.pumpAndSettle();
    await pending;

    expect(logic.list.single.handleResult, 0);
    expect(fixture.callsFor('getUsersInfo'), isEmpty);
    final previousCalls = fixture.calls.length;
    fixture.im.groupApplicationChangedSubject.add(request(result: 1));
    await tester.pump(const Duration(milliseconds: 2));
    expect(fixture.calls.length, previousCalls);
    expect(fixture.im.groupApplicationChangedSubject.hasListener, isFalse);
  });

  testWidgets('token rotation discards the previous session handler lookup',
      (tester) async {
    fixture.recipient = [request()];
    final logic = await fixture.mount(tester);
    final processor = _processor(logic.list.single);
    fixture.holdRecipient = true;
    final pending = logic.getApplicationList();
    await tester.pump(const Duration(milliseconds: 2));
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'current-admin',
      'imToken': 'rotated-im-token',
      'chatToken': 'rotated-chat-token',
    }));
    fixture.recipientReplies.single.complete(jsonEncode([
      request(result: 1, handler: 'previous-session-admin').toJson(),
    ]));
    await tester.pumpAndSettle();
    await pending;

    expect(logic.list.single.handleResult, 0);
    expect(fixture.callsFor('getUsersInfo'), isEmpty);
    processor.approve();
    processor.reject();
    await _finishWrite(tester);
    expect(fixture.callsFor('acceptGroupApplication'), isEmpty);
    expect(fixture.callsFor('refuseGroupApplication'), isEmpty);
  });
}
