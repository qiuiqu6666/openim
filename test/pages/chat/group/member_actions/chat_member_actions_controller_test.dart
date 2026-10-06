import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/member_actions/chat_member_action_policy.dart';
import 'package:openim/pages/chat/group/member_actions/chat_member_action_sources.dart';
import 'package:openim/pages/chat/group/member_actions/chat_member_actions_controller.dart';

class _Harness {
  _Harness({ChatMemberActionLoading? runLoading}) {
    controller = ChatMemberActionsController(
      groupID: () => id,
      currentUserID: () => account,
      isSessionInactive: () => inactive,
      isJoined: () => joined,
      groupRevision: () => revision,
      sendingMuted: () => muted,
      latestMember: (id) => cached[id],
      latestGroup: () => cachedGroup,
      isKnownRemoved: leftMembers.contains,
      runLoading: runLoading,
      nowSeconds: () => now,
      sources: ChatMemberActionSources(
        read: (id, selfID, targetID) async {
          reads.add((id, selfID, targetID));
          if (read != null) return read!();
          return snapshot;
        },
        mute: (id, targetID, seconds) async {
          writes.add(('mute', id, targetID, seconds));
          if (write != null) await write!();
        },
        remove: (id, targetID) async {
          writes.add(('remove', id, targetID, 0));
          if (write != null) await write!();
        },
      ),
      mention: mentions.add,
      sendExclusiveRedPacket: (member) async {
        packets.add(member);
        if (packet != null) await packet!(member);
      },
      memberUpdated: (member) {
        updated.add(member);
        cached[member.userID!] = member;
        revision++;
      },
      memberRemoved: (member) {
        removed.add(member);
        cached.remove(member.userID);
        leftMembers.add(member.userID!);
        revision++;
      },
      showFeedback: feedback.add,
    );
  }

  String? id = 'group';
  String account = 'me';
  bool inactive = false, joined = true, muted = false;
  int now = 1000, revision = 0;
  GroupInfo group =
      GroupInfo(groupID: 'group', ownerUserID: 'owner', status: 0);
  GroupInfo? cachedGroup;
  GroupMembersInfo self = GroupMembersInfo(
      groupID: 'group', userID: 'me', roleLevel: GroupRoleLevel.admin);
  GroupMembersInfo? target = GroupMembersInfo(
      groupID: 'group',
      userID: 'other',
      nickname: '最新群昵称',
      roleLevel: GroupRoleLevel.member);
  ChatMemberActionSnapshot get snapshot => ChatMemberActionSnapshot(
        group: GroupInfo.fromJson(group.toJson()),
        self: GroupMembersInfo.fromJson(self.toJson()),
        target:
            target == null ? null : GroupMembersInfo.fromJson(target!.toJson()),
        isJoined: joined,
      );

  late final ChatMemberActionsController controller;
  Future<ChatMemberActionSnapshot> Function()? read;
  Future<void> Function()? write;
  Future<void> Function(GroupMembersInfo)? packet;
  Future<ChatMemberAction?> Function()? choose;
  Future<bool> Function()? confirmation;
  ChatMemberAction? action = ChatMemberAction.mention;
  bool approved = true;
  final reads = <(String, String, String)>[];
  final writes = <(String, String, String, int)>[];
  final menus = <List<ChatMemberAction>>[];
  final confirmations = <ChatMemberAction>[];
  final names = <String>[];
  final feedback = <String>[];
  final mentions = <Message>[];
  final packets = <GroupMembersInfo>[];
  final updated = <GroupMembersInfo>[];
  final removed = <GroupMembersInfo>[];
  final cached = <String, GroupMembersInfo>{};
  final leftMembers = <String>{};

  Future<void> open([Message? message]) => controller.open(
        message ??
            (Message()
              ..sendID = 'other'
              ..senderNickname = '旧昵称'),
        showMenu: (actions, name) async {
          menus.add(actions);
          names.add(name);
          return choose == null ? action : choose!();
        },
        confirm: (action, name) async {
          confirmations.add(action);
          return confirmation == null ? approved : confirmation!();
        },
      );
}

void main() {
  test(
      'admin avatar menu resolves real member name and mentions through composer',
      () async {
    final h = _Harness();
    await h.open();
    expect(h.menus.single, [
      ChatMemberAction.mention,
      ChatMemberAction.exclusiveRedPacket,
      ChatMemberAction.mute,
      ChatMemberAction.remove,
    ]);
    expect(h.names, ['最新群昵称']);
    expect(h.mentions.single.sendID, 'other');
    expect(h.mentions.single.senderNickname, '最新群昵称');
    expect(h.reads, [('group', 'me', 'other'), ('group', 'me', 'other')]);
    expect(h.confirmations, isEmpty);
    expect(h.writes, isEmpty);
  });

  test('mute then unmute follows accepted values despite stale SDK cache',
      () async {
    final h = _Harness()..action = ChatMemberAction.mute;
    await h.open();
    expect(h.updated.single.muteEndTime,
        h.now + ChatMemberActionsController.muteSeconds);
    expect(h.feedback, ['已禁言']);
    expect(h.target!.muteEndTime, isNull);
    h.action = ChatMemberAction.unmute;
    await h.open();
    expect(h.menus.last, [
      ChatMemberAction.mention,
      ChatMemberAction.exclusiveRedPacket,
      ChatMemberAction.unmute,
      ChatMemberAction.remove,
    ]);
    expect(h.updated.last.muteEndTime, 0);
    expect(h.writes, [
      ('mute', 'group', 'other', ChatMemberActionsController.muteSeconds),
      ('mute', 'group', 'other', 0),
    ]);
    expect(h.feedback, ['已禁言', '已解除禁言']);
  });

  test('authoritative later member event supersedes accepted mute', () async {
    final h = _Harness()..action = ChatMemberAction.mute;
    await h.open();
    h.cached['other'] = GroupMembersInfo.fromJson(h.target!.toJson())
      ..muteEndTime = 0;
    h.revision++;
    h.action = null;
    await h.open();
    expect(h.menus.last, contains(ChatMemberAction.mute));
    expect(h.menus.last, isNot(contains(ChatMemberAction.unmute)));
  });

  test('confirmed removal publishes member deletion only after SDK success',
      () async {
    final h = _Harness()..action = ChatMemberAction.remove;
    final finished = Completer<void>();
    h.write = () => finished.future;
    final pending = h.open();
    await Future<void>.delayed(Duration.zero);
    expect(h.confirmations, [ChatMemberAction.remove]);
    expect(h.removed, isEmpty);
    finished.complete();
    await pending;
    expect(h.removed.single.userID, 'other');
    expect(h.writes, [('remove', 'group', 'other', 0)]);
    expect(h.feedback, ['已移除群聊']);
  });

  test('cancel menu or confirmation never writes or mentions', () async {
    final h = _Harness()..action = null;
    await h.open();
    h.action = ChatMemberAction.mute;
    h.approved = false;
    await h.open();
    expect(h.reads.length, 2);
    expect(h.writes, isEmpty);
    expect(h.updated, isEmpty);
    expect(h.mentions, isEmpty);
  });

  test('changed actor role while dialog opens blocks management', () async {
    final h = _Harness()..action = ChatMemberAction.remove;
    h.confirmation = () async {
      h.self.roleLevel = GroupRoleLevel.member;
      h.revision++;
      return true;
    };
    await h.open();
    expect(h.writes, isEmpty);
    expect(h.feedback.single, contains('权限'));
  });

  test('promoted target or externally muted target invalidates selected mute',
      () async {
    for (final promote in [true, false]) {
      final h = _Harness()..action = ChatMemberAction.mute;
      h.confirmation = () async {
        if (promote) {
          h.target!.roleLevel = GroupRoleLevel.admin;
        } else {
          h.target!.muteEndTime = h.now + 60;
        }
        return true;
      };
      await h.open();
      expect(h.writes, isEmpty);
      expect(h.feedback.single, contains('状态已变化'));
    }
  });

  test('target leaves while menu open blocks even mention', () async {
    final h = _Harness();
    h.choose = () async {
      h.target = null;
      return ChatMemberAction.mention;
    };
    await h.open();
    expect(h.mentions, isEmpty);
    expect(h.writes, isEmpty);
  });

  test('permission update during SDK query invalidates that response',
      () async {
    final h = _Harness();
    final reading = Completer<ChatMemberActionSnapshot>();
    h.read = () => reading.future;
    final pending = h.open();
    h.revision++;
    reading.complete(h.snapshot);
    await pending;
    expect(h.menus, isEmpty);
    expect(h.feedback.single, contains('信息已变化'));
  });

  test('closing, leaving or switching account while loading cannot show menu',
      () async {
    for (final change in ['close', 'leave', 'account', 'group', 'inactive']) {
      final h = _Harness();
      final reading = Completer<ChatMemberActionSnapshot>();
      h.read = () => reading.future;
      final pending = h.open();
      switch (change) {
        case 'close':
          h.controller.close();
        case 'leave':
          h.joined = false;
        case 'account':
          h.account = 'different-account';
        case 'group':
          h.id = 'different-group';
        case 'inactive':
          h.inactive = true;
      }
      reading.complete(h.snapshot);
      await pending;
      expect(h.menus, isEmpty, reason: change);
      expect(h.feedback, isEmpty, reason: change);
    }
  });

  test('closing while confirmation is open cannot mutate', () async {
    final h = _Harness()..action = ChatMemberAction.mute;
    h.confirmation = () async {
      h.controller.close();
      return true;
    };
    await h.open();
    expect(h.writes, isEmpty);
    expect(h.updated, isEmpty);
  });

  test('closing during write prevents late broadcast or toast', () async {
    final h = _Harness()..action = ChatMemberAction.mute;
    final writing = Completer<void>();
    h.write = () => writing.future;
    final pending = h.open();
    await Future<void>.delayed(Duration.zero);
    expect(h.writes.length, 1);
    h.controller.close();
    writing.complete();
    await pending;
    expect(h.updated, isEmpty);
    expect(h.feedback, isEmpty);
  });

  test('duplicate long press shares one workflow through query and menu',
      () async {
    final h = _Harness();
    final menu = Completer<ChatMemberAction?>();
    h.choose = () => menu.future;
    final pending = h.open();
    await Future<void>.delayed(Duration.zero);
    await h.open();
    expect(h.menus.length, 1);
    expect(h.reads.length, 1);
    menu.complete(ChatMemberAction.mention);
    await pending;
    expect(h.mentions.length, 1);
  });

  test('SDK failure produces feedback without fake updates and permits retry',
      () async {
    final h = _Harness()..action = ChatMemberAction.mute;
    h.write = () async => throw StateError('denied');
    await h.open();
    expect(h.updated, isEmpty);
    expect(h.feedback.single, contains('denied'));
    h.write = null;
    await h.open();
    expect(h.updated.length, 1);
  });

  test('failed snapshot query cannot open misleading menu', () async {
    final h = _Harness();
    h.read = () async => throw StateError('offline');
    await h.open();
    expect(h.menus, isEmpty);
    expect(h.feedback.single, contains('offline'));
  });

  test('muted admin retains moderation while muted ordinary member has no menu',
      () async {
    final h = _Harness()
      ..muted = true
      ..action = null;
    h.self.muteEndTime = h.now + 60;
    await h.open();
    expect(h.menus.single, [ChatMemberAction.mute, ChatMemberAction.remove]);
    h.self.roleLevel = GroupRoleLevel.member;
    await h.open();
    expect(h.menus.length, 1);
    expect(h.feedback.single, '当前无法操作该群成员');
  });

  test('self avatar, direct chat and invalid session do not query SDK',
      () async {
    final h = _Harness();
    await h.open(Message()..sendID = 'me');
    await h.open(Message());
    h.id = null;
    await h.open();
    h.id = 'group';
    h.joined = false;
    await h.open();
    expect(h.reads, isEmpty);
  });

  test(
      'menu callback cannot request an action missing from displayed permissions',
      () async {
    final h = _Harness()..action = ChatMemberAction.remove;
    h.self.roleLevel = GroupRoleLevel.member;
    await h.open();
    expect(h.writes, isEmpty);
    expect(h.confirmations, isEmpty);
  });

  test(
      'promotion during confirmation blocks write even if SDK read stays stale',
      () async {
    final h = _Harness()..action = ChatMemberAction.remove;
    h.confirmation = () async {
      h.cached['other'] = GroupMembersInfo.fromJson(h.target!.toJson())
        ..roleLevel = GroupRoleLevel.admin;
      h.revision++;
      return true;
    };
    await h.open();
    expect(h.writes, isEmpty);
    expect(h.reads.length, 1);
    h.action = null;
    await h.open();
    expect(h.menus.last,
        [ChatMemberAction.mention, ChatMemberAction.exclusiveRedPacket]);
    expect(h.target!.roleLevel, GroupRoleLevel.member);
  });

  test('cached actor demotion or blocked group cannot grant stale SDK actions',
      () async {
    final h = _Harness()..action = null;
    h.cached['me'] = GroupMembersInfo.fromJson(h.self.toJson())
      ..roleLevel = GroupRoleLevel.member;
    await h.open();
    expect(h.menus.single,
        [ChatMemberAction.mention, ChatMemberAction.exclusiveRedPacket]);
    h.cachedGroup = GroupInfo(groupID: 'group', status: 1);
    await h.open();
    expect(h.menus.length, 1);
    expect(h.writes, isEmpty);
  });

  test(
      'latest mute event controls option while SDK still returns old mute time',
      () async {
    final h = _Harness()..action = null;
    h.cached['other'] = GroupMembersInfo.fromJson(h.target!.toJson())
      ..muteEndTime = h.now + 60;
    await h.open();
    expect(h.menus.single, contains(ChatMemberAction.unmute));
    expect(h.menus.single, isNot(contains(ChatMemberAction.mute)));
  });

  test('target event during pending mute cannot be overwritten by old callback',
      () async {
    final h = _Harness()..action = ChatMemberAction.mute;
    final writing = Completer<void>();
    h.write = () => writing.future;
    final pending = h.open();
    await Future<void>.delayed(Duration.zero);
    final updated = GroupMembersInfo.fromJson(h.target!.toJson())
      ..roleLevel = GroupRoleLevel.admin
      ..nickname = '新管理员'
      ..muteEndTime = 0;
    h.cached['other'] = updated;
    h.revision++;
    writing.complete();
    await pending;
    expect(h.updated, isEmpty);
    expect(h.cached['other'], same(updated));
    expect(h.cached['other']!.roleLevel, GroupRoleLevel.admin);
    expect(h.feedback, ['操作已完成']);
  });

  test('leave and rejoin during pending removal cannot replay old deletion',
      () async {
    final h = _Harness()..action = ChatMemberAction.remove;
    final writing = Completer<void>();
    h.write = () => writing.future;
    final pending = h.open();
    await Future<void>.delayed(Duration.zero);
    h.joined = false;
    h.revision++;
    h.joined = true;
    h.revision++;
    writing.complete();
    await pending;
    expect(h.removed, isEmpty);
  });

  test('confirmed or event deletion cannot resurrect member from SDK cache',
      () async {
    final h = _Harness()..action = ChatMemberAction.remove;
    await h.open();
    expect(h.leftMembers, contains('other'));
    h.action = null;
    await h.open();
    expect(h.menus.length, 1);
    expect(h.feedback.last, '该用户已退出群聊');
    h.leftMembers.clear();
    await h.open();
    expect(h.menus.length, 2);
  });

  test(
      'event after confirmation while loading starts cannot use stale decision',
      () async {
    late _Harness h;
    var loads = 0;
    Future<T> loading<T>(Future<T> Function() action) async {
      await Future<void>.delayed(Duration.zero);
      if (++loads == 2) h.revision++;
      return action();
    }

    h = _Harness(runLoading: loading)..action = ChatMemberAction.remove;
    await h.open();
    expect(h.writes, isEmpty);
    expect(h.feedback.single, contains('状态已变化'));
  });

  test(
      'exclusive packet opens directly with revalidated member and no mutation',
      () async {
    var loading = false;
    Future<T> runLoading<T>(Future<T> Function() action) async {
      loading = true;
      try {
        return await action();
      } finally {
        loading = false;
      }
    }

    final h = _Harness(runLoading: runLoading)
      ..action = ChatMemberAction.exclusiveRedPacket;
    h.target!.faceURL = 'https://example.test/member.png';
    h.packet = (member) async {
      expect(loading, isFalse);
      expect(member.userID, 'other');
      expect(member.groupID, 'group');
      expect(member.nickname, '最新群昵称');
      expect(member.faceURL, 'https://example.test/member.png');
    };
    await h.open();
    expect(h.packets, hasLength(1));
    expect(h.confirmations, isEmpty);
    expect(h.writes, isEmpty);
    expect(h.mentions, isEmpty);
    expect(h.reads, hasLength(2));
  });

  test('exclusive packet checks member presence and speaking before navigation',
      () async {
    for (final change in ['left', 'muted', 'closed']) {
      final h = _Harness()..action = ChatMemberAction.exclusiveRedPacket;
      h.choose = () async {
        switch (change) {
          case 'left':
            h.target = null;
          case 'muted':
            h.muted = true;
          case 'closed':
            h.controller.close();
        }
        return ChatMemberAction.exclusiveRedPacket;
      };
      await h.open();
      expect(h.packets, isEmpty, reason: change);
      expect(h.writes, isEmpty, reason: change);
    }
  });

  test('repeated long press while exclusive packet page is open cannot reopen',
      () async {
    final h = _Harness()..action = ChatMemberAction.exclusiveRedPacket;
    final page = Completer<void>();
    h.packet = (_) => page.future;
    final pending = h.open();
    await Future<void>.delayed(Duration.zero);
    await h.open();
    expect(h.packets, hasLength(1));
    page.complete();
    await pending;
    await h.open();
    expect(h.packets, hasLength(2));
  });

  test('event between second read and mutation loading cannot write old target',
      () async {
    late _Harness h;
    var loads = 0;
    Future<T> loading<T>(Future<T> Function() action) async {
      await Future<void>.delayed(Duration.zero);
      if (++loads == 3) h.revision++;
      return action();
    }

    h = _Harness(runLoading: loading)..action = ChatMemberAction.remove;
    await h.open();
    expect(h.writes, isEmpty);
    expect(h.feedback.single, contains('状态已变化'));
  });

  test('member deletion after final read but before loading ends blocks packet',
      () async {
    late _Harness h;
    var loads = 0;
    Future<T> loading<T>(Future<T> Function() action) async {
      final result = await action();
      if (++loads == 2) {
        h.leftMembers.add('other');
        h.revision++;
      }
      return result;
    }

    h = _Harness(runLoading: loading)
      ..action = ChatMemberAction.exclusiveRedPacket;
    await h.open();
    expect(h.packets, isEmpty);
    expect(h.feedback.single, contains('状态已变化'));
  });

  test(
      'exclusive packet uses visible message name if member nickname is absent',
      () async {
    final h = _Harness()..action = ChatMemberAction.exclusiveRedPacket;
    h.target!.nickname = ' ';
    await h.open();
    expect(h.packets.single.nickname, '旧昵称');
    expect(h.packets.single.userID, 'other');
    expect(h.target!.nickname, ' ');
  });
}
