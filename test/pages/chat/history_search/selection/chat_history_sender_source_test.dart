import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  const officialEx = '{"accountType":"official"}';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late OpenIMChatHistorySenderSource source;
  late List<MethodCall> calls;

  setUp(() {
    OpenIM.iMManager.userID = 'me';
    source = OpenIMChatHistorySenderSource();
    calls = [];
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('display name prefers a trimmed nickname and retains the alias fallback',
      () {
    for (final nickname in <String?>[null, '', '  ']) {
      final sender = ChatHistorySender(
          userID: 'person', displayName: ' 原备注 ', nickname: nickname);
      expect(sender.name, ' 原备注 ');
    }
    const sender = ChatHistorySender(
        userID: 'person', displayName: '备注', nickname: '  昵称  ');
    expect(sender.name, '昵称');
    expect(sender.displayName, '备注');
    expect(sender.userID, 'person');
  });

  test('single chat resolves only this conversation and its two participants',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getMultipleConversation') {
        return jsonEncode([
          {
            'conversationID': 'single',
            'unreadCount': 0,
            'userID': 'peer',
            'conversationType': ConversationType.single,
            'showName': '备注',
            'ex': '{"conversationSetting":true}',
          }
        ]);
      }
      if (call.method == 'getUsersInfo') {
        return jsonEncode([
          {'userID': 'me', 'nickname': '本人'},
          {
            'userID': 'peer',
            'nickname': '朋友',
            'faceURL': 'https://example.com/a.png',
            'ex': officialEx,
          },
          {'userID': 'stranger', 'nickname': '其他会话成员'},
        ]);
      }
      fail('Unexpected SDK call: ${call.method}');
    });
    final page = await source.load(
        conversationID: 'single', query: '', offset: 0, count: 50);
    expect(calls.first.arguments['conversationIDList'], ['single']);
    expect(calls.last.arguments['userIDList'], ['me', 'peer']);
    expect(page.items.map((m) => m.userID), ['me', 'peer']);
    expect(page.items.map((m) => m.displayName), ['本人', '备注']);
    expect(page.items.map((m) => m.name), ['本人', '朋友']);
    expect(page.items.last.nickname, '朋友');
    expect(page.items.last.faceURL, 'https://example.com/a.png');
    expect(page.items.last.ex, officialEx);
    expect(page.items.first.ex, isNull);
    expect(calls.map((call) => call.method),
        ['getMultipleConversation', 'getUsersInfo']);
    expect(page.nextOffset, 2);
    expect(page.hasMore, isFalse);
    final filtered = await source.load(
        conversationID: 'single', query: '备注', offset: 0, count: 50);
    expect(filtered.items.single.userID, 'peer');
    final byNickname = await source.load(
        conversationID: 'single', query: ' 朋友 ', offset: 0, count: 1);
    expect(byNickname.items.single.userID, 'peer');
    expect(byNickname.items.single.displayName, '备注');
    expect(byNickname.nextOffset, 1);
    expect(byNickname.hasMore, isFalse);
  });

  test('group paging and nickname search retain exact group and SDK cursors',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getMultipleConversation') {
        return jsonEncode([
          {'conversationID': 'group-chat', 'groupID': 'group', 'unreadCount': 0}
        ]);
      }
      if (call.method == 'getUsersInfo') {
        return jsonEncode([
          {'userID': 'u1', 'nickname': ' 林同学 '},
          {'userID': 'u2', 'nickname': '别群昵称'},
          {'userID': 'extra', 'nickname': '额外资料'},
        ]);
      }
      return jsonEncode([
        {'groupID': 'group', 'userID': 'u1', 'nickname': '小林'},
        {'groupID': 'group', 'userID': 'u1', 'nickname': '重复'},
        {'groupID': 'wrong-group', 'userID': 'u2', 'nickname': '别群成员'},
      ]);
    });
    final page = await source.load(
        conversationID: 'group-chat', query: '', offset: 150, count: 3);
    final list =
        calls.singleWhere((call) => call.method == 'getGroupMemberList');
    expect(list.method, 'getGroupMemberList');
    expect(list.arguments['groupID'], 'group');
    expect(list.arguments['filter'], 0);
    expect(list.arguments['offset'], 150);
    expect(list.arguments['count'], 3);
    expect(page.items.map((m) => m.userID), ['u1']);
    expect(page.items.single.displayName, '小林');
    expect(page.items.single.name, '林同学');
    expect(calls.last.method, 'getUsersInfo');
    expect(calls.last.arguments['userIDList'], ['u1']);
    expect(page.nextOffset, 153);
    expect(page.hasMore, isTrue);

    await source.load(
        conversationID: 'group-chat', query: ' 小林 ', offset: 50, count: 50);
    final search =
        calls.singleWhere((call) => call.method == 'searchGroupMembers');
    expect(search.method, 'searchGroupMembers');
    final parameters = search.arguments['searchParam'];
    expect(parameters['groupID'], 'group');
    expect(parameters['keywordList'], ['小林']);
    expect(parameters['isSearchUserID'], isFalse);
    expect(parameters['isSearchMemberNickname'], isTrue);
    expect(parameters['offset'], 50);
    expect(parameters['count'], 50);
  });

  test(
      'group profiles enrich only valid page IDs and preserve missing profiles',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getMultipleConversation') {
        return jsonEncode([
          {'conversationID': 'group-chat', 'groupID': 'group', 'unreadCount': 0}
        ]);
      }
      if (call.method == 'getUsersInfo') {
        expect(call.arguments['userIDList'], ['u1', 'u2', 'u3']);
        return jsonEncode([
          {'userID': 'u1', 'nickname': '公开昵称', 'ex': officialEx},
          {'userID': 'u3', 'nickname': '  '},
          {'userID': 'outside', 'nickname': '不属于本页'},
        ]);
      }
      return jsonEncode([
        {'groupID': 'group', 'userID': '', 'nickname': '无ID'},
        {'groupID': 'group', 'userID': '  ', 'nickname': '空白ID'},
        {
          'groupID': 'group',
          'userID': 'u1',
          'nickname': '群备注',
          'faceURL': 'group-avatar',
          'ex': '{"memberSetting":true}',
        },
        {'groupID': 'group', 'userID': 'u1', 'nickname': '重复ID'},
        {'groupID': 'another', 'userID': 'outside', 'nickname': '别群'},
        {'groupID': 'group', 'userID': 'u2', 'nickname': '资料缺失'},
        {'groupID': 'group', 'userID': 'u3', 'nickname': '资料空昵称'},
      ]);
    });
    final page = await source.load(
        conversationID: 'group-chat', query: '', offset: 50, count: 7);
    expect(page.items.map((sender) => sender.userID), ['u1', 'u2', 'u3']);
    expect(page.items.map((sender) => sender.name), ['公开昵称', '资料缺失', '资料空昵称']);
    expect(page.items.first.displayName, '群备注');
    expect(page.items.first.faceURL, 'group-avatar');
    expect(page.items.first.ex, officialEx,
        reason: 'Official identity comes from the existing public profile.');
    expect(page.items[1].nickname, isNull);
    expect(page.items[1].ex, isNull);
    expect(calls.map((call) => call.method),
        ['getMultipleConversation', 'getGroupMemberList', 'getUsersInfo']);
    expect(page.nextOffset, 57);
    expect(page.hasMore, isTrue);
  });

  test(
      'profile failure falls back to group cards without losing the raw cursor',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getMultipleConversation') {
        return jsonEncode([
          {'conversationID': 'group-chat', 'groupID': 'group', 'unreadCount': 0}
        ]);
      }
      if (call.method == 'getUsersInfo') {
        throw PlatformException(code: 'PROFILE_UNAVAILABLE');
      }
      return jsonEncode([
        {'groupID': 'group', 'userID': 'u1', 'nickname': '群名片'},
        {'groupID': 'group', 'userID': 'u1', 'nickname': '重复'},
      ]);
    });
    final page = await source.load(
        conversationID: 'group-chat', query: '', offset: 50, count: 2);
    expect(page.items.single.name, '群名片');
    expect(page.items.single.nickname, isNull);
    expect(page.nextOffset, 52);
    expect(page.hasMore, isTrue);
  });

  for (final fails in [false, true]) {
    test(
        'profile ${fails ? 'failure' : 'response'} cannot cross an account switch',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getMultipleConversation') {
          return jsonEncode([
            {
              'conversationID': 'group-chat',
              'groupID': 'group',
              'unreadCount': 0
            }
          ]);
        }
        if (call.method == 'getUsersInfo') {
          OpenIM.iMManager.userID = 'another-account';
          if (fails) throw PlatformException(code: 'PROFILE_UNAVAILABLE');
          return jsonEncode([
            {'userID': 'u1', 'nickname': '公开昵称'}
          ]);
        }
        return jsonEncode([
          {'groupID': 'group', 'userID': 'u1', 'nickname': '群名片'},
        ]);
      });
      await expectLater(
          source.load(
              conversationID: 'group-chat', query: '', offset: 0, count: 50),
          throwsStateError);
    });
  }

  test('an invalid group page advances the cursor without fetching profiles',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getMultipleConversation') {
        return jsonEncode([
          {'conversationID': 'group-chat', 'groupID': 'group', 'unreadCount': 0}
        ]);
      }
      if (call.method == 'getGroupMemberList') {
        return jsonEncode([
          {'groupID': 'group', 'userID': ''},
          {'groupID': 'group', 'userID': '  '},
          {'groupID': 'another', 'userID': 'outside'},
        ]);
      }
      fail('Unexpected SDK call: ${call.method}');
    });
    final page = await source.load(
        conversationID: 'group-chat', query: '', offset: 5, count: 3);
    expect(page.items, isEmpty);
    expect(page.nextOffset, 8);
    expect(page.hasMore, isTrue);
    expect(calls.map((call) => call.method),
        ['getMultipleConversation', 'getGroupMemberList']);
  });

  test('does not query members for a mismatched conversation', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return jsonEncode([
        {
          'conversationID': 'another',
          'groupID': 'another-group',
          'unreadCount': 0
        }
      ]);
    });
    await expectLater(
        source.load(conversationID: 'wanted', query: '', offset: 0, count: 50),
        throwsStateError);
    expect(calls.map((c) => c.method), ['getMultipleConversation']);
  });

  test('switching account during metadata lookup prevents member loading',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      OpenIM.iMManager.userID = 'other-account';
      return jsonEncode([
        {'conversationID': 'wanted', 'groupID': 'group', 'unreadCount': 0}
      ]);
    });
    await expectLater(
        source.load(conversationID: 'wanted', query: '', offset: 0, count: 50),
        throwsStateError);
    expect(calls.map((c) => c.method), ['getMultipleConversation']);
  });

  test('a departed group does not expose its member directory', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return jsonEncode([
        {
          'conversationID': 'wanted',
          'groupID': 'group',
          'isNotInGroup': true,
          'unreadCount': 0
        }
      ]);
    });
    await expectLater(
        source.load(conversationID: 'wanted', query: '', offset: 0, count: 50),
        throwsStateError);
    expect(calls, hasLength(1));
  });
}
