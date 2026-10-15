import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/member_actions/chat_member_action_sources.dart';

import 'support/revocation_fixture.dart';

void main() {
  for (final confirmed in [false, true]) {
    test('recall waits for explicit confirmation $confirmed', () async {
      final answer = Completer<bool>();
      var prompts = 0;
      final f = RevocationFixture(confirm: () {
        prompts++;
        return answer.future;
      });
      final task = f.controller.revokeMessage(f.message());
      await f.controller.revokeMessage(f.message());
      expect(prompts, 1);
      expect(f.reads, isEmpty);
      expect(f.requests, isEmpty);
      answer.complete(confirmed);
      await task;
      expect(f.requests.length, confirmed ? 1 : 0);
      expect(f.removed.length, confirmed ? 1 : 0);
    });
  }
  for (final change in ['closed', 'account', 'message', 'role', 'time']) {
    test('recall revalidates $change after confirmation', () async {
      final answer = Completer<bool>();
      final f = RevocationFixture(confirm: () => answer.future);
      final message = f.message();
      final task = f.controller.revokeMessage(message);
      switch (change) {
        case 'closed':
          f.closed = true;
        case 'account':
          f.account = 'other';
        case 'message':
          f.messageCurrent = false;
        case 'role':
          f.selfRole = GroupRoleLevel.member;
        case 'time':
          message.sendID = f.account;
          message.sendTime = 0;
      }
      answer.complete(true);
      await task;
      expect(f.requests, isEmpty);
      expect(f.removed, isEmpty);
    });
  }
  for (final age in [121, 3600, 86400]) {
    test('confirmed owner can recall departed sender after $age seconds',
        () async {
      final f = RevocationFixture()
        ..selfRole = GroupRoleLevel.owner
        ..senderRole = null;
      f.group!.ownerUserID = f.account;
      f.onRead = () async => ChatMemberActionSnapshot(
          group: f.group, self: f.snapshot.self, target: null, isJoined: true);
      final message = f.message(ageSeconds: age);
      expect(f.controller.canRevoke(message), isTrue);
      await f.controller.revokeMessage(message);
      expect(f.requests, [('sg_group', 'message')]);
      expect(f.removed, ['message']);
      expect(f.feedback, isEmpty);
    });
  }
  test('owner mismatch and demotion still reject a departed sender recall',
      () async {
    final f = RevocationFixture()
      ..selfRole = GroupRoleLevel.owner
      ..senderRole = null;
    expect(f.controller.canRevoke(f.message()), isFalse);
    f.group!.ownerUserID = f.account;
    f.onRead = () async => ChatMemberActionSnapshot(
        group: f.group,
        self: GroupMembersInfo(
            groupID: f.groupID,
            userID: f.account,
            roleLevel: GroupRoleLevel.member),
        target: null,
        isJoined: true);
    await f.controller.revokeMessage(f.message());
    expect(f.requests, isEmpty);
    expect(f.removed, isEmpty);
  });
  for (final self in [
    GroupRoleLevel.owner,
    GroupRoleLevel.admin,
    GroupRoleLevel.member
  ]) {
    for (final sender in [
      GroupRoleLevel.owner,
      GroupRoleLevel.admin,
      GroupRoleLevel.member
    ]) {
      test('group role matrix: $self revokes $sender', () async {
        final f = RevocationFixture()
          ..selfRole = self
          ..senderRole = sender;
        if (self == GroupRoleLevel.owner) f.group!.ownerUserID = f.account;
        final allowed =
            self == GroupRoleLevel.owner && sender != GroupRoleLevel.owner ||
                self == GroupRoleLevel.admin && sender == GroupRoleLevel.member;
        final message = f.message();
        expect(f.controller.canRevoke(message), allowed);
        await f.controller.revokeMessage(message);
        expect(f.requests, allowed ? [('sg_group', 'message')] : isEmpty);
        expect(f.removed, allowed ? ['message'] : isEmpty);
      });
    }
  }

  for (final group in [false, true]) {
    for (final age in [119, 120, 121]) {
      test('own message: group=$group, age=$age keeps two-minute rule',
          () async {
        final f = RevocationFixture();
        if (!group) f.groupID = null;
        final message = f.message(sender: f.account, ageSeconds: age);
        expect(f.controller.canRevoke(message), age < 120);
        await f.controller.revokeMessage(message);
        expect(f.requests.length, age < 120 ? 1 : 0);
        expect(f.reads, isEmpty);
      });
    }
  }

  test('single-chat peer messages never gain group moderation rights',
      () async {
    final f = RevocationFixture()..groupID = null;
    expect(f.controller.canRevoke(f.message()), isFalse);
    await f.controller.revokeMessage(f.message());
    expect(f.requests, isEmpty);
  });

  test('unknown roles, stale owner and known owner identity fail closed', () {
    final f = RevocationFixture();
    f.senderRole = null;
    expect(f.controller.canRevoke(f.message()), isFalse);
    f.senderRole = GroupRoleLevel.member;
    f.selfRole = null;
    expect(f.controller.canRevoke(f.message()), isFalse);
    f.selfRole = GroupRoleLevel.owner;
    expect(f.controller.canRevoke(f.message()), isFalse);
    f.selfRole = GroupRoleLevel.admin;
    expect(f.controller.canRevoke(f.message(sender: 'owner')), isFalse);
  });

  test('only live successful content in this group can be recalled', () {
    final f = RevocationFixture();
    final invalid = [
      f.message()..status = MessageStatus.sending,
      f.message()..status = MessageStatus.failed,
      f.message()..status = MessageStatus.deleted,
      f.message()..contentType = MessageType.revokeMessageNotification,
      f.message()..contentType = MessageType.typing,
      f.message()..contentType = null,
      f.message()..clientMsgID = '',
      f.message()..sendID = null,
      f.message()..groupID = 'other-group',
      f.message()..sessionType = ConversationType.single,
    ];
    for (final message in invalid) {
      expect(f.controller.canRevoke(message), isFalse);
    }
    f.group!.status = 2;
    expect(f.controller.canRevoke(f.message()), isFalse);
    f.group!.status = 0;
    f.joined = false;
    expect(f.controller.canRevoke(f.message()), isFalse);
  });

  test('fund cards stay protected, ordinary custom and quote/media are allowed',
      () {
    final f = RevocationFixture();
    for (final type in [
      MessageType.custom,
      MessageType.quote,
      MessageType.picture,
      MessageType.voice
    ]) {
      expect(f.controller.canRevoke(f.message()..contentType = type), isTrue);
    }
    final fund = f.message()
      ..contentType = MessageType.custom
      ..customElem = CustomElem(
          data: jsonEncode({
        'orderID': 'order',
        'biz': 'transfer',
        'currency': 'USDT',
        'amount': '1.000001',
        'status': 'open',
      }));
    expect(f.controller.canRevoke(fund), isFalse);
    f.selfRole = GroupRoleLevel.owner;
    f.group!.ownerUserID = f.account;
    expect(f.controller.canRevoke(fund), isFalse);
  });

  for (final change in [
    'self-demoted',
    'sender-promoted',
    'left',
    'wrong-group',
    'wrong-self',
    'missing-sender'
  ]) {
    test('fresh SDK snapshot blocks $change despite a previously visible menu',
        () async {
      final f = RevocationFixture();
      expect(f.controller.canRevoke(f.message()), isTrue);
      final snapshot = f.snapshot;
      f.onRead = () async {
        if (change == 'self-demoted') {
          snapshot.self!.roleLevel = GroupRoleLevel.member;
        }
        if (change == 'sender-promoted') {
          snapshot.target!.roleLevel = GroupRoleLevel.admin;
        }
        if (change == 'wrong-group') snapshot.target!.groupID = 'other';
        if (change == 'wrong-self') snapshot.self!.userID = 'other';
        return ChatMemberActionSnapshot(
          group: snapshot.group,
          self: snapshot.self,
          target: change == 'missing-sender' ? null : snapshot.target,
          isJoined: change != 'left',
        );
      };
      await f.controller.revokeMessage(f.message());
      expect(f.requests, isEmpty);
      expect(f.removed, isEmpty);
      expect(f.feedback, hasLength(1));
    });
  }

  for (final phase in ['reading', 'revoking']) {
    for (final exit in ['closed', 'account', 'conversation', 'group']) {
      test('$exit during $phase discards late results and feedback', () async {
        final f = RevocationFixture();
        final read = Completer<ChatMemberActionSnapshot>();
        final revoke = Completer<void>();
        final snapshot = f.snapshot;
        f.onRead =
            () => phase == 'reading' ? read.future : Future.value(snapshot);
        f.onRevoke = () => revoke.future;
        final task = f.controller.revokeMessage(f.message());
        await Future<void>.delayed(Duration.zero);
        if (exit == 'closed') f.closed = true;
        if (exit == 'account') f.account = 'new-account';
        if (exit == 'conversation') f.conversation = 'other-conversation';
        if (exit == 'group') f.groupID = 'other-group';
        if (phase == 'reading') read.complete(snapshot);
        if (phase == 'revoking') revoke.completeError(StateError('offline'));
        await task;
        expect(f.requests.length, phase == 'reading' ? 0 : 1);
        expect(f.removed, isEmpty);
        expect(f.feedback, isEmpty);
      });
    }
  }

  test('role events during lookup invalidate the snapshot', () async {
    final f = RevocationFixture();
    final pending = Completer<ChatMemberActionSnapshot>();
    f.onRead = () => pending.future;
    final task = f.controller.revokeMessage(f.message());
    f.revision++;
    pending.complete(f.snapshot);
    await task;
    expect(f.requests, isEmpty);
    expect(f.feedback.single, contains('已变化'));
  });

  test('a revoked/deleted target while lookup is pending does not dispatch',
      () async {
    final f = RevocationFixture();
    f.onRead = () async {
      f.messageCurrent = false;
      return f.snapshot;
    };
    await f.controller.revokeMessage(f.message());
    expect(f.requests, isEmpty);
  });

  test('double taps share one operation; success waits for SDK and clears once',
      () async {
    final f = RevocationFixture();
    final pending = Completer<void>();
    f.onRevoke = () => pending.future;
    final task = f.controller.revokeMessage(f.message());
    await Future<void>.delayed(Duration.zero);
    await f.controller.revokeMessage(f.message());
    expect(f.reads, [('group', 'admin', 'member')]);
    expect(f.requests, hasLength(1));
    expect(f.removed, isEmpty);
    pending.complete();
    await task;
    expect(f.removed, ['message']);
  });

  for (final phase in ['reading', 'revoking']) {
    test('$phase failure preserves message and permits retry', () async {
      final f = RevocationFixture();
      if (phase == 'reading') {
        f.onRead = () async => throw StateError('offline');
      } else {
        f.onRevoke = () async => throw PlatformException(
            code: '${SDKErrorCode.insufficientPermissions}');
      }
      await f.controller.revokeMessage(f.message());
      expect(f.removed, isEmpty);
      expect(f.feedback, hasLength(1));
      expect(f.feedback.single, isNot(contains('StateError')));
      f.onRead = null;
      f.onRevoke = null;
      await f.controller.revokeMessage(f.message());
      expect(f.removed, ['message']);
    });
  }
}
