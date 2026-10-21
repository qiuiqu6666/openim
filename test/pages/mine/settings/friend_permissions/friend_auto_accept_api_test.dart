import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart' show GetMaterialApp;
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/mine/settings/friend_permissions/friend_auto_accept_api.dart';

void main() {
  for (final scenario in [
    'enabled',
    'disabled',
    'unsupported',
    'mismatch',
    'switched'
  ]) {
    testWidgets('auto approval API $scenario', (tester) async {
      await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await DataSp.init();
        OpenIM.iMManager.userID = 'owner';
        final previous = http.dio;
        final client = Dio();
        final requests = <RequestOptions>[];
        final enabled = scenario != 'disabled';
        client.interceptors
            .add(InterceptorsWrapper(onRequest: (request, handler) {
          requests.add(request);
          final write = request.path.endsWith('/user/update');
          if (write && scenario == 'switched') {
            OpenIM.iMManager.userID = 'other';
          }
          handler.resolve(
              Response(requestOptions: request, statusCode: 200, data: {
            'errCode': 0,
            'data': write
                ? {}
                : {
                    'users': [
                      {
                        'userID': 'owner',
                        if (scenario != 'unsupported')
                          'autoAcceptFriend':
                              scenario == 'mismatch' ? !enabled : enabled
                      }
                    ]
                  }
          }));
        }));
        http.dio = client;
        try {
          final save = FriendAutoAcceptApi.setEnabled(enabled);
          if (['unsupported', 'mismatch', 'switched'].contains(scenario)) {
            await expectLater(save, throwsStateError);
          } else {
            await save;
          }
          expect(requests.first.data['autoAcceptFriend'], enabled);
          expect(requests.first.data['userID'], 'owner');
          expect(requests.first.data.keys,
              unorderedEquals(['userID', 'autoAcceptFriend', 'platform']));
          expect(requests.length, scenario == 'switched' ? 1 : 2);
        } finally {
          http.dio = previous;
          OpenIM.iMManager.userID = 'owner';
        }
      });
    });
  }
}
