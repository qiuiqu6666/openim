import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/contacts/presence_store.dart';

void main() {
  setUpAll(() {
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
  });
  tearDownAll(Get.reset);
  test('visible last seen uses elapsed time and handles future timestamps', () {
    final now = DateTime(2026, 10, 1, 12);
    for (final entry in {
      const Duration(seconds: -20): '刚刚在线',
      const Duration(seconds: 59): '刚刚在线',
      const Duration(minutes: 1): '1分钟前在线',
      const Duration(minutes: 30): '30分钟前在线',
      const Duration(hours: 1): '1小时前在线',
      const Duration(days: 1): '1天前在线',
      const Duration(days: 7): '1周前在线',
      const Duration(days: 30): '1个月前在线',
    }.entries) {
      expect(
          UserPresence(false, now.subtract(entry.key).millisecondsSinceEpoch)
              .labelAt(now),
          entry.value);
    }
  });
  test('hidden last seen uses coarse ranges at each boundary', () {
    final now = DateTime(2026, 10, 1, 12);
    for (final entry in {
      0: '最近曾在线',
      1: '1天前在线',
      2: '1周内曾上线',
      6: '1周内曾上线',
      7: '一周前曾在线',
      13: '一周前曾在线',
      14: '一月内曾上线',
      29: '一月内曾上线',
      30: '很久没上线',
    }.entries) {
      expect(
          UserPresence(
                  false,
                  now
                      .subtract(Duration(days: entry.key))
                      .millisecondsSinceEpoch,
                  showLastSeen: false)
              .labelAt(now),
          entry.value);
    }
    expect(
        UserPresence(false, null, showLastSeen: false).labelAt(now), '最近曾在线');
  });
  test('hidden friend is grey and vague, self still sees real status', () {
    final hidden = UserPresence(true, 1790849179579, showLastSeen: false);
    expect(hidden.displayOnline, false);
    expect(hidden.label, '最近曾在线');
    final self = UserPresence(true, null, showLastSeen: false, isSelf: true);
    expect(self.displayOnline, true);
    expect(self.label, '在线');
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  test('presence batches unique IDs and hides unavailable or online timestamps',
      () async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(
        LoginCertificate.fromJson({'userID': 'me', 'chatToken': 'chat'}));
    final client = Dio();
    final sizes = <int>[];
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      final ids = request.data['userIDs'] as List;
      sizes.add(ids.length);
      expect(request.headers['token'], 'chat');
      handler.resolve(Response(requestOptions: request, data: {
        'errCode': 0,
        'data': {
          'users': [
            for (final id in ids)
              {
                'userID': id,
                'online': id == 'u0',
                'showLastSeen': id != 'u3',
                'lastSeenAt': id == 'u1' ? null : 1790849179579
              },
          ]
        }
      }));
    }));
    final store = PresenceStore(client: client);
    await store.refresh([...List.generate(201, (i) => 'u$i'), 'u0']);
    expect(sizes, [200, 1]);
    expect(store.users['u0']!.online, true);
    expect(store.users['u0']!.lastSeenAt, isNull);
    expect(store.users['u1']!.label, '离线');
    expect(store.users['u2']!.label, isNot(contains(':')));
    expect(store.users['u3']!.hidden, true);
    expect(store.users['u3']!.lastSeenAt, 1790849179579);
    await store.refresh([]);
    expect(sizes, [200, 1]);
    store.stopWatching('u2');
    expect(store.users['u2']!.lastSeenAt, 1790849179579);
    store.dispose();
    final restored = PresenceStore(client: client);
    expect(restored.users['u2']!.lastSeenAt, 1790849179579);
    expect(restored.users['u3']!.hidden, true);
    expect(restored.users['u3']!.lastSeenAt, 1790849179579);
    restored.dispose();
  });

  test('offline updates keep the last known time for profiles and contacts',
      () async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(
        LoginCertificate.fromJson({'userID': 'me', 'chatToken': 'chat'}));
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, data: {
        'errCode': 0,
        'data': {
          'users': [
            {
              'userID': 'friend',
              'online': false,
              'showLastSeen': true,
              'lastSeenAt': null,
            }
          ]
        }
      }));
    }));
    final store = PresenceStore(client: client);
    final known = DateTime.now()
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    store.users['friend'] = UserPresence(false, known);
    await store.refresh(['friend']);
    expect(store.users['friend']!.lastSeenAt, known);
    store.markOffline('friend');
    expect(store.users['friend']!.lastSeenAt, known);

    store.users['friend'] = UserPresence(true, null);
    store.markOffline('friend');
    expect(store.users['friend']!.label, '刚刚在线');
    store.dispose();
  });
}
