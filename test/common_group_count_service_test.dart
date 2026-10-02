import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/services/common_group_count_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(
        LoginCertificate.fromJson({'userID': 'me', 'chatToken': 'chat'}));
  });
  test('count uses Chat token and an encoded peer, in a single request',
      () async {
    final requests = <RequestOptions>[];
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      h.resolve(Response(requestOptions: r, data: {
        'errCode': 0,
        'data': {'total': 32865}
      }));
    }));
    expect(
        await CommonGroupCountService(client: client).count('peer/id'), 32865);
    expect(requests.length, 1);
    expect(requests.single.path,
        endsWith('/chat/users/peer%2Fid/common-groups/count'));
    expect(requests.single.headers['token'], 'chat');
    expect(requests.single.headers['operationID'], isNotEmpty);
  });
  test('list forwards opaque cursor and parses the complete group card',
      () async {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      expect(r.queryParameters, {'limit': 30, 'cursor': 'opaque+cursor='});
      h.resolve(Response(requestOptions: r, data: {
        'errCode': 0,
        'data': {
          'items': [
            {
              'groupID': 'g',
              'groupName': 'Group',
              'faceURL': '',
              'memberCount': 256
            }
          ],
          'nextCursor': '',
          'hasMore': false,
        }
      }));
    }));
    final page = await CommonGroupCountService(client: client)
        .list('peer', cursor: 'opaque+cursor=');
    expect(page.items.single.groupName, 'Group');
    expect(page.items.single.memberCount, 256);
    expect(page.hasMore, false);
  });
  test('business errors and invalid counts are never shown as zero', () async {
    final client = Dio();
    var body = <String, dynamic>{'errCode': 1001};
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(Response(requestOptions: r, data: body));
    }));
    final service = CommonGroupCountService(client: client);
    await expectLater(
        service.count('peer'), throwsA(isA<CommonGroupsException>()));
    body = {
      'errCode': 0,
      'data': {'total': -1}
    };
    await expectLater(service.count('peer'), throwsFormatException);
    body = {
      'errCode': 0,
      'data': {'total': 0}
    };
    expect(await service.count('peer'), 0);
    await expectLater(service.list('peer', limit: 101), throwsArgumentError);
  });
  test('nonadvancing cursor is rejected to prevent repeated pages', () async {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(Response(requestOptions: r, data: {
        'errCode': 0,
        'data': {
          'items': [],
          'nextCursor': 'same',
          'hasMore': true,
        }
      }));
    }));
    await expectLater(
        CommonGroupCountService(client: client).list('peer', cursor: 'same'),
        throwsFormatException);
  });
}
