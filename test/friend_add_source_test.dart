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
    test('grant exchange and apply for ${entry.key}', () async {
      await FriendAddRequest.send(
          userID: 'target',
          reason: 'hello',
          source: entry.key,
          groupID: 'g',
          fields: {...entry.value, 'userID': 'forged', 'nickname': 'fake'});
      expect(requests, hasLength(2));
      expect(requests[0].path, endsWith('/chat/friend-grants'));
      expect(requests[0].headers['token'], 'test-chat-token');
      expect(requests[0].contentType, Headers.jsonContentType);
      expect(requests[0].headers['operationID'], isNotEmpty);
      expect(requests[0].data['source'], entry.key.name);
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
