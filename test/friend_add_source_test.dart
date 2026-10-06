import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio previous;
  late Dio client;
  final requests = <RequestOptions>[];
  var reject = false;
  var switchAccount = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'applicant',
      'chatToken': 'test-chat-token',
      'imToken': 'test-im-token',
    }));
    requests.clear();
    reject = false;
    switchAccount = false;
    previous = http.dio;
    client = Dio();
    client.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) async {
      requests.add(request);
      if (switchAccount && request.path.endsWith('friend-grants')) {
        await DataSp.putLoginCertificate(LoginCertificate.fromJson({
          'userID': 'other',
          'chatToken': 'other-token',
        }));
      }
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: reject
              ? {
                  'errCode': 20020,
                  'errMsg': 'FriendGrantRejected',
                  'errDlt': 'too frequent'
                }
              : {
                  'errCode': 0,
                  'data': request.path.endsWith('friend-grants')
                      ? {'friendGrant': 'fg_test', 'expireAt': 9999999999999}
                      : request.path.endsWith('friend-invites')
                          ? {'inviteCode': 'fi_test', 'expireAt': 9999999999999}
                          : {},
                }));
    }));
    http.dio = client;
  });
  tearDown(() {
    http.dio = previous;
    client.close();
  });

  for (final entry in [
    (keyword: 'abcdefgh12', account: '@abcdefgh12'),
    (keyword: '@abcdefgh12', account: 'abcdefgh12'),
    (keyword: '0012345678', account: '@0012345678'),
    (keyword: '@0012345678', account: '0012345678'),
    (keyword: ' @0012345678 ', account: ' @0012345678 '),
  ]) {
    test('public account ${entry.keyword} takes priority over phone', () {
      expect(
          friendSearchSource(
              entry.keyword,
              UserFullInfo(
                  userID: 'im_target',
                  account: entry.account,
                  phoneNumber: entry.keyword.trim())),
          FriendAddSource.account);
    });
  }

  test('public account-shaped input cannot be reclassified as a phone', () {
    expect(
        friendSearchSource(
            '0012345678',
            UserFullInfo(
                userID: 'im_target',
                account: '@abcdefgh12',
                phoneNumber: '0012345678')),
        FriendAddSource.search);
  });

  for (final keyword in ['Alice', 'im_target', 'm00000001', 'notmatched1']) {
    test('nickname or internal ID $keyword cannot exchange a friend grant',
        () async {
      final source = friendSearchSource(
          keyword,
          UserFullInfo(
              userID: keyword, nickname: keyword, account: '@abcdefgh12'));
      expect(source, FriendAddSource.search);
      await expectLater(
          FriendAddRequest.send(
              userID: keyword,
              reason: 'hello',
              source: source,
              fields: {'account': '@abcdefgh12'}),
          throwsA(isA<PlatformException>()));
      expect(requests, isEmpty);
    });
  }

  test('email and phone queries retain their friend grant source', () {
    final profile = UserFullInfo(
        userID: 'im_target',
        account: '@abcdefgh12',
        email: 'alice@example.com',
        phoneNumber: '18828838848');
    expect(friendSearchSource('alice@example.com', profile),
        FriendAddSource.email);
    expect(friendSearchSource('18828838848', profile), FriendAddSource.phone);
    expect(friendSearchSource('+886912345678', profile), FriendAddSource.phone);
  });

  final fields = <FriendAddSource, Map<String, String>>{
    FriendAddSource.account: {'account': '@abcdefgh12'},
    FriendAddSource.phone: {'areaCode': '+86', 'phoneNumber': '18828838848'},
    FriendAddSource.email: {'email': 'a@example.com'},
    FriendAddSource.qrcode: {'inviteCode': 'fi_qr'},
    FriendAddSource.link: {'inviteCode': 'fi_link'},
    FriendAddSource.card: {'inviteCode': 'fi_card'},
    FriendAddSource.group: {},
    FriendAddSource.manage: {},
  };
  for (final entry in fields.entries) {
    final groupEntry = entry.key == FriendAddSource.group ||
        entry.key == FriendAddSource.manage;
    final expected = {
      'source': entry.key.name,
      ...entry.value,
      if (groupEntry) 'groupID': 'g',
      if (groupEntry) 'targetUserID': 'im_original_target',
    };
    test('complete ${entry.key} entry exposes the same request input', () {
      final supplied = {
        ...entry.value,
        'source': 'account',
        'userID': 'forged',
        'nickname': 'fake',
        'groupID': 'forged-group',
        'targetUserID': '@forged-account',
      };
      expect(
          FriendAddRequest.canSend(
            userID: 'im_original_target',
            source: entry.key,
            groupID: 'g',
            fields: supplied,
          ),
          isTrue);
      expect(
          FriendAddRequest.input(
            userID: 'im_original_target',
            source: entry.key,
            groupID: 'g',
            fields: supplied,
          ),
          expected);
      expect(supplied['targetUserID'], '@forged-account');
      expect(requests, isEmpty);
    });

    final requiredKeys =
        groupEntry ? ['groupID', 'targetUserID'] : entry.value.keys.toList();
    for (final key in requiredKeys) {
      test('${entry.key} without $key cannot send or issue a grant', () async {
        final supplied = {...entry.value}..remove(key);
        // Explicit group context must also defeat forged values in fields.
        if (groupEntry) {
          supplied.addAll({
            'groupID': 'forged-group',
            'targetUserID': 'forged-target',
          });
        }
        final target = key == 'targetUserID' ? ' ' : 'im_original_target';
        final groupID = key == 'groupID' ? null : 'g';
        expect(
            FriendAddRequest.canSend(
              userID: target,
              source: entry.key,
              groupID: groupID,
              fields: supplied,
            ),
            isFalse);
        expect(
            FriendAddRequest.input(
              userID: target,
              source: entry.key,
              groupID: groupID,
              fields: supplied,
            ),
            isNull);
        await expectLater(
            FriendAddRequest.send(
              userID: target,
              reason: '',
              source: entry.key,
              groupID: groupID,
              fields: supplied,
            ),
            throwsA(isA<PlatformException>()
                .having((error) => error.code, 'code', 'FriendGrantRequired')));
        expect(requests, isEmpty);
      });
    }

    test('grant exchange and apply for ${entry.key}', () async {
      await FriendAddRequest.send(
          userID: 'im_original_target',
          reason: 'hello',
          source: entry.key,
          groupID: 'g',
          fields: {
            ...entry.value,
            'userID': 'forged',
            'nickname': 'fake',
            'groupID': 'forged-group',
            'targetUserID': '@forged-account',
          });
      expect(requests, hasLength(2));
      expect(requests[0].path, endsWith('/chat/friend-grants'));
      expect(requests[0].headers['token'], 'test-chat-token');
      expect(requests[0].contentType, Headers.jsonContentType);
      expect(requests[0].headers['operationID'], isNotEmpty);
      expect(requests[0].data['source'], entry.key.name);
      expect(requests[0].data, expected);
      expect(requests[0].data.containsKey('userID'), false);
      expect(requests[0].data.containsKey('nickname'), false);
      expect(
          requests[0].data.containsKey('targetUserID'),
          entry.key == FriendAddSource.group ||
              entry.key == FriendAddSource.manage);
      expect(requests[1].path, endsWith('/chat/friend-apply'));
      expect(requests[1].data, {'friendGrant': 'fg_test', 'message': 'hello'});
    });
  }
  test('entry validation trims only and introduces no format requirements', () {
    for (final entry in {
      FriendAddSource.account: {'account': ' arbitrary account '},
      FriendAddSource.phone: {'areaCode': ' area ', 'phoneNumber': ' phone '},
      FriendAddSource.email: {'email': ' arbitrary email '},
      FriendAddSource.qrcode: {'inviteCode': ' arbitrary invite '},
      FriendAddSource.link: {'inviteCode': ' arbitrary invite '},
      FriendAddSource.card: {'inviteCode': ' arbitrary invite '},
    }.entries) {
      expect(
          FriendAddRequest.input(
            userID: 'im_target',
            source: entry.key,
            fields: entry.value,
          ),
          {
            'source': entry.key.name,
            for (final field in entry.value.entries)
              field.key: field.value.trim(),
          });
    }
    expect(requests, isEmpty);
  });
  test('blank required entry fields are incomplete', () {
    for (final source in [
      FriendAddSource.account,
      FriendAddSource.phone,
      FriendAddSource.email,
      FriendAddSource.qrcode,
      FriendAddSource.link,
      FriendAddSource.card,
      FriendAddSource.group,
      FriendAddSource.manage,
    ]) {
      expect(
          FriendAddRequest.canSend(
            userID: ' ',
            groupID: ' ',
            source: source,
            fields: {
              for (final key in fields[source]!.keys) key: ' ',
            },
          ),
          isFalse);
    }
    expect(requests, isEmpty);
  });
  for (final source in [
    FriendAddSource.chat,
    FriendAddSource.search,
    FriendAddSource.uid,
  ]) {
    test('$source remains unsupported even with complete other entry fields',
        () async {
      const supplied = {
        'account': '@abcdefgh12',
        'areaCode': '+86',
        'phoneNumber': '18828838848',
        'email': 'a@example.com',
        'inviteCode': 'fi_test',
        'groupID': 'g',
        'targetUserID': 'im_target',
      };
      expect(
          FriendAddRequest.canSend(
            userID: 'im_target',
            source: source,
            groupID: 'g',
            fields: supplied,
          ),
          isFalse);
      expect(
          FriendAddRequest.input(
            userID: 'im_target',
            source: source,
            groupID: 'g',
            fields: supplied,
          ),
          isNull);
      await expectLater(
          FriendAddRequest.send(
            userID: 'im_target',
            reason: '',
            source: source,
            groupID: 'g',
            fields: supplied,
          ),
          throwsA(isA<PlatformException>()
              .having((error) => error.code, 'code', 'FriendGrantRequired')));
      expect(requests, isEmpty);
    });
  }
  test('friend add errors explain actionable entry and invitation recovery',
      () {
    expect(
        friendAddErrorMessage(PlatformException(code: 'FriendGrantRequired'),
            chinese: true),
        '请通过对方的聊天号、二维码或名片添加好友');
    expect(
        friendAddErrorMessage(PlatformException(code: 'FriendGrantRequired'),
            chinese: false),
        'Please add this person using their chat number, QR code or contact card.');
    expect(friendAddErrorMessage((20013, ''), chinese: true),
        '添加邀请无效或已过期，请重新进入添加入口');
    expect(friendAddErrorMessage((20013, ''), chinese: false),
        'The friend invitation is invalid or expired. Reopen the entry.');
  });
  test('rejection never submits an application and is translated', () async {
    reject = true;
    await expectLater(
        FriendAddRequest.send(
            userID: 'target',
            reason: '',
            source: FriendAddSource.account,
            fields: fields[FriendAddSource.account]!),
        throwsA(anything));
    expect(requests, hasLength(1));
    expect(friendAddErrorMessage((20020, 'too frequent'), chinese: true),
        '操作过于频繁，请稍后重试');
    expect(
        friendAddErrorMessage(PlatformException(code: '20044'), chinese: true),
        '对方不允许通过此方式添加');
  });
  test('account switch never consumes another accounts grant', () async {
    switchAccount = true;
    await expectLater(
        FriendAddRequest.send(
            userID: 'target',
            reason: '',
            source: FriendAddSource.account,
            fields: fields[FriendAddSource.account]!),
        throwsA(isA<PlatformException>()));
    expect(requests, hasLength(1));
  });
  test('unsupported entries and incomplete group context never issue grants',
      () async {
    for (final source in [
      FriendAddSource.uid,
      FriendAddSource.search,
      FriendAddSource.chat,
      FriendAddSource.group
    ]) {
      await expectLater(
          FriendAddRequest.send(userID: 'target', reason: '', source: source),
          throwsA(isA<PlatformException>()));
    }
    expect(requests, isEmpty);
  });
  test('invite URL keeps source and rejects legacy user-only links', () {
    expect(
        parseFriendInvite(
            'openim://user/target?source=qrcode&inviteCode=fi_test')?['source'],
        'qrcode');
    expect(
        parseFriendInvite(
            'openim://user/target?source=link&inviteCode=fi_test')?['source'],
        'link');
    expect(parseFriendInvite('openim://user/target'), isNull);
    expect(
        parseFriendInvite(
            'openim://user/target?source=card&inviteCode=fi_test'),
        isNull);
  });
  test('card invite preserves source and target', () async {
    final extension = await createFriendCardExtension('target');
    expect(friendCardInviteCode(extension), 'fi_test');
    expect(requests.single.data, {'source': 'card', 'targetUserID': 'target'});
  });
}
