import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' show GetMaterialApp;
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing friend add permissions default to allowed', () {
    final info = UserFullInfo.fromJson({'userID': '123', 'allowAddFriend': 1});

    expect(info.allowAddByUserID, 1);
    expect(info.allowAddByAccount, 1);
    expect(info.allowAddByPhone, 1);
    expect(info.allowAddByEmail, 1);
    expect(info.allowAddByQRCode, 1);
    expect(info.allowAddByGroup, 1);
    expect(info.allowAddByCard, 1);
  });

  test('friend add permissions survive model serialization', () {
    final info = UserFullInfo.fromJson({
      'allowAddFriend': 0,
      'allowAddByUserID': 2,
      'allowAddByPhone': 1,
      'allowAddByEmail': 2,
      'allowAddByQRCode': 1,
      'allowAddByGroup': 2,
      'allowAddByCard': 1,
    });

    final json = info.toJson();
    expect(json['allowAddFriend'], 0);
    expect(json['allowAddByUserID'], 2);
    expect(json['allowAddByPhone'], 1);
    expect(json['allowAddByEmail'], 2);
    expect(json['allowAddByQRCode'], 1);
    expect(json['allowAddByGroup'], 2);
    expect(json['allowAddByCard'], 1);
  });

  testWidgets(
      'falls back only for legacy wrapper parsing and verifies the result',
      (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await DataSp.init();
      final previousDio = http.dio;
      final client = Dio();
      final updates = <Map<String, dynamic>>[];
      client.interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) {
        if (request.path.endsWith('/user/update')) {
          updates.add(Map<String, dynamic>.from(request.data as Map));
          handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: updates.length == 1
                ? {
                    'errCode': 1001,
                    'errMsg':
                        'json: cannot unmarshal number into Go value of type wrapperspb.Int32Value',
                  }
                : {'errCode': 0, 'data': {}},
          ));
        } else {
          handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {
              'errCode': 0,
              'data': {
                'users': [
                  {'userID': '123', 'allowAddByPhone': 2}
                ]
              },
            },
          ));
        }
      }));
      http.dio = client;
      try {
        await Apis.updateFriendAddPermission(
          userID: '123',
          field: 'allowAddByPhone',
          value: 2,
        );
        expect(updates, hasLength(2));
        expect(updates.first['allowAddByPhone'], 2);
        expect(updates.last['allowAddByPhone'], {'value': 2});
        expect(
            updates.every((request) => request.containsKey('platform')), true);
      } finally {
        http.dio = previousDio;
      }
    });
  });
}
