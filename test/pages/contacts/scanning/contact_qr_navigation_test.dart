import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'package:openim/pages/contacts/scanning/contact_qr_navigation.dart';
import 'package:openim/pages/contacts/scanning/contact_qr_result.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late _Host h;

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': 'test-token',
      'imToken': 'test-im-token',
    }));
    OpenIM.iMManager.userID = 'self';
    h = _Host();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, h.nativeCall);
  });

  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    Get.reset();
  });

  for (final sdkID in ['123456', '@123456']) {
    testWidgets('opens the resolved SDK group ID $sdkID with QR join source',
        (tester) async {
      await h.mount(tester);
      h.lookup = () async => jsonEncode([
            {'groupID': sdkID, 'groupName': 'Group'}
          ]);
      final pending = openScannedContact(
        parseContactQrResult('https://99chat.vip?group=@123456')!,
        isActive: () => true,
      );
      await tester.pumpAndSettle();
      expect(h.requests, [
        ['@123456', '123456']
      ]);
      expect(h.groups, [
        {'groupID': sdkID, 'joinGroupMethod': JoinGroupMethod.qrcode}
      ]);
      expect(h.users, isEmpty);
      Get.back<void>();
      await tester.pumpAndSettle();
      await pending;
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('legacy group invitation uses its original ID', (tester) async {
    await h.mount(tester);
    h.lookup = () async => '[{"groupID":"legacy"}]';
    final pending = openScannedContact(
      parseContactQrResult('io.openim.app/joinGroup/legacy')!,
      isActive: () => true,
    );
    await tester.pumpAndSettle();
    expect(h.requests, [
      ['legacy']
    ]);
    expect(h.groups.single['groupID'], 'legacy');
    Get.back<void>();
    await tester.pumpAndSettle();
    await pending;
  });

  for (final source in ['qrcode', 'link']) {
    testWidgets(
        'friend $source still opens user profile with invitation fields',
        (tester) async {
      await h.mount(tester);
      final pending = openScannedContact(
        parseContactQrResult(
            'openim://user/peer?source=$source&inviteCode=fi_test')!,
        isActive: () => true,
      );
      await tester.pumpAndSettle();
      expect(h.users.single['userID'], 'peer');
      expect(h.users.single['addSource'],
          source == 'link' ? FriendAddSource.link : FriendAddSource.qrcode);
      expect(h.users.single['friendAddFields'], {'inviteCode': 'fi_test'});
      expect(h.users.single['forceCanAdd'], isTrue);
      expect(h.requests, isEmpty);
      expect(h.groups, isEmpty);
      Get.back<void>();
      await tester.pumpAndSettle();
      await pending;
      expect(tester.takeException(), isNull);
    });
  }

  for (final failure in [false, true]) {
    testWidgets('missing or failed group lookup stays on entry page: $failure',
        (tester) async {
      await h.mount(tester);
      h.lookup = () async {
        if (failure) throw PlatformException(code: 'network');
        return '[]';
      };
      await openScannedContact({'groupID': '@missing'}, isActive: () => true);
      await tester.pumpAndSettle();
      expect(h.groups, isEmpty);
      expect(h.users, isEmpty);
      expect(find.text('Entry'), findsOneWidget);
      expect(find.text(failure ? '读取群资料失败，请重试' : '未找到该群聊'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await EasyLoading.dismiss(animation: false);
      await tester.pumpAndSettle();
    });
  }

  for (final reason in ['closed', 'account', 'token']) {
    testWidgets('late group lookup cannot navigate after $reason changes',
        (tester) async {
      await h.mount(tester);
      final reply = Completer<String>();
      h.lookup = () => reply.future;
      var active = true;
      final pending =
          openScannedContact({'groupID': '@123456'}, isActive: () => active);
      await tester.pump();
      expect(h.requests, hasLength(1));
      if (reason == 'closed') {
        active = false;
      } else if (reason == 'account') {
        OpenIM.iMManager.userID = 'other';
      } else {
        await DataSp.removeLoginCertificate();
      }
      reply.complete('[{"groupID":"123456"}]');
      await pending;
      await tester.pumpAndSettle();
      expect(h.groups, isEmpty);
      expect(find.text('Entry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('inactive entry makes no group request', (tester) async {
    await h.mount(tester);
    await openScannedContact({'groupID': '@123456'}, isActive: () => false);
    expect(h.requests, isEmpty);
    expect(h.groups, isEmpty);
  });
}

class _Host {
  final requests = <List<String>>[];
  final groups = <Map<String, dynamic>>[];
  final users = <Map<String, dynamic>>[];
  Future<String> Function() lookup = () async => '[]';

  Future<dynamic> nativeCall(MethodCall call) async {
    switch (call.method) {
      case 'getGroupsInfo':
        requests.add(List<String>.from((call.arguments as Map)['groupIDList']));
        return lookup();
      case 'getUsersInfo':
        return '[]';
      default:
        throw StateError('Unexpected SDK call: ${call.method}');
    }
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      builder: EasyLoading.init(),
      home: const Scaffold(body: Text('Entry')),
      getPages: [
        GetPage<dynamic>(
          name: AppRoutes.groupProfilePanel,
          page: () {
            groups.add(Map<String, dynamic>.from(Get.arguments as Map));
            return const Scaffold(body: Text('Group profile'));
          },
        ),
        GetPage<dynamic>(
          name: AppRoutes.userProfilePanel,
          page: () {
            users.add(Map<String, dynamic>.from(Get.arguments as Map));
            return const Scaffold(body: Text('Friend profile'));
          },
        ),
      ],
    ));
    await tester.pumpAndSettle();
  }
}
