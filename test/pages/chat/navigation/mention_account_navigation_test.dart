import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim/pages/chat/navigation/chat_message_navigation.dart';
import 'package:openim/pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _MentionSearchTransport implements HttpClientAdapter {
  List<Map<String, dynamic>> users = [];
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    expect(options.uri.toString(), Urls.searchUserFullInfo);
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'errCode': 0,
        'data': {'users': users},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MentionNavigationFixture {
  final usersOpened = <Map<String, dynamic>>[];
  final groupsOpened = <Map<String, dynamic>>[];
  final nativeCalls = <MethodCall>[];
  List<Map<String, dynamic>> groups = [];

  final navigation = ChatMessageNavigation(
    isClosed: () => false,
    isGroupChat: () => false,
    isSingleChat: () => true,
    isAdminOrOwner: () => false,
    groupID: () => null,
    groupInfo: () => null,
  );

  Future<dynamic> nativeCall(MethodCall call) async {
    nativeCalls.add(call);
    switch (call.method) {
      case 'getGroupsInfo':
      case 'searchGroups':
        return jsonEncode(groups);
      case 'getUsersInfo':
        return '[]';
      default:
        throw StateError('Unexpected SDK call: ${call.method}');
    }
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        builder: EasyLoading.init(),
        home: const Scaffold(body: Text('Chat')),
        getPages: [
          GetPage<dynamic>(
            name: AppRoutes.userProfilePanel,
            page: () {
              usersOpened.add(Map<String, dynamic>.from(Get.arguments as Map));
              return const Scaffold(body: Text('User profile'));
            },
          ),
          GetPage<dynamic>(
            name: AppRoutes.groupProfilePanel,
            page: () {
              groupsOpened.add(Map<String, dynamic>.from(Get.arguments as Map));
              return const Scaffold(body: Text('Group profile'));
            },
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String mention) async {
    await tester.runAsync(() => navigation.searchMentionID(mention));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late Dio previousDio;
  late _MentionSearchTransport transport;
  late _MentionNavigationFixture fixture;

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': 'test-chat-token',
      'imToken': 'test-im-token',
    }));
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.token = 'test-im-token';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    previousDio = http.dio;
    transport = _MentionSearchTransport();
    http.dio = Dio()..httpClientAdapter = transport;
    fixture = _MentionNavigationFixture();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, fixture.nativeCall);
  });

  tearDown(() async {
    await LoadingView.singleton.dismiss();
    await EasyLoading.dismiss(animation: false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    http.dio.close(force: true);
    http.dio = previousDio;
    OpenIM.iMManager.userID = '';
    OpenIM.iMManager.token = null;
    await DataSp.removeLoginCertificate();
    Get.reset();
  });

  for (final account in ['ivarf8yuh2', '@ivarf8yuh2', ' ivarf8yuh2 ']) {
    testWidgets('public account "$account" opens its internal SDK user ID',
        (tester) async {
      transport.users = [
        {
          'userID': 'im_target',
          'account': account,
          'nickname': 'Target',
          'faceURL': 'target-face',
        },
      ];
      await fixture.mount(tester);

      await fixture.search(tester, '@ivarf8yuh2');

      expect(fixture.usersOpened, hasLength(1));
      expect(fixture.usersOpened.single['userID'], 'im_target');
      expect(fixture.usersOpened.single['nickname'], 'Target');
      expect(fixture.usersOpened.single['faceURL'], 'target-face');
      expect(fixture.groupsOpened, isEmpty);
      final profileLookup = fixture.nativeCalls
          .singleWhere((call) => call.method == 'getUsersInfo');
      expect((profileLookup.arguments as Map)['userIDList'], ['im_target']);
      expect(transport.requests, isNotEmpty);
      expect(transport.requests.first.headers['token'], 'test-chat-token');
      expect(find.text('mentionIdNotFound'.tr), findsNothing);
    });
  }

  testWidgets('fuzzy account and exact nickname do not open an unrelated user',
      (tester) async {
    transport.users = [
      {
        'userID': 'im_other',
        'account': 'ivarf8yuh2-extra',
        'nickname': 'ivarf8yuh2',
      },
      {
        'userID': 'im_nickname_only',
        'account': 'other12345',
        'nickname': 'ivarf8yuh2',
      },
    ];
    await fixture.mount(tester);

    await fixture.search(tester, '@ivarf8yuh2');

    expect(fixture.usersOpened, isEmpty);
    expect(fixture.groupsOpened, isEmpty);
    expect(fixture.nativeCalls.map((call) => call.method),
        isNot(contains('getUsersInfo')));
    expect(find.text('mentionIdNotFound'.tr), findsOneWidget);
  });

  for (final userID in [null, '', '   ']) {
    testWidgets('matching account with unusable user ID "$userID" is rejected',
        (tester) async {
      transport.users = [
        {'userID': userID, 'account': 'ivarf8yuh2', 'nickname': 'Target'},
      ];
      await fixture.mount(tester);

      await fixture.search(tester, '@ivarf8yuh2');

      expect(fixture.usersOpened, isEmpty);
      expect(fixture.groupsOpened, isEmpty);
      expect(find.text('mentionIdNotFound'.tr), findsOneWidget);
    });
  }

  for (final userID in ['hqBvmIFPZYWn', '@hqBvmIFPZYWn']) {
    testWidgets('legacy internal ID "$userID" remains a valid mention target',
        (tester) async {
      transport.users = [
        {'userID': userID, 'account': 'other12345', 'nickname': 'Legacy'},
      ];
      await fixture.mount(tester);

      await fixture.search(tester, '@hqBvmIFPZYWn');

      expect(fixture.usersOpened, hasLength(1));
      expect(fixture.usersOpened.single['userID'], userID);
      expect(fixture.groupsOpened, isEmpty);
      expect(find.text('mentionIdNotFound'.tr), findsNothing);
    });
  }

  testWidgets('group ID lookup still opens the group profile', (tester) async {
    fixture.groups = [
      {'groupID': 'TGS#2P5XTVUUS', 'groupName': 'Target group'},
    ];
    await fixture.mount(tester);

    await fixture.search(tester, '@TGS#2P5XTVUUS');

    expect(fixture.usersOpened, isEmpty);
    expect(fixture.groupsOpened, hasLength(1));
    expect(fixture.groupsOpened.single['groupID'], 'TGS#2P5XTVUUS');
    expect(
        fixture.groupsOpened.single['joinGroupMethod'], JoinGroupMethod.search);
    expect(find.text('mentionIdNotFound'.tr), findsNothing);
  });

  testWidgets('an exact group ID retains priority over a matching user account',
      (tester) async {
    fixture.groups = [
      {'groupID': 'ivarf8yuh2', 'groupName': 'Target group'},
    ];
    transport.users = [
      {'userID': 'im_target', 'account': 'ivarf8yuh2', 'nickname': 'Target'},
    ];
    await fixture.mount(tester);

    await fixture.search(tester, '@ivarf8yuh2');

    expect(fixture.usersOpened, isEmpty);
    expect(fixture.groupsOpened, hasLength(1));
    expect(fixture.groupsOpened.single['groupID'], 'ivarf8yuh2');
  });
}
