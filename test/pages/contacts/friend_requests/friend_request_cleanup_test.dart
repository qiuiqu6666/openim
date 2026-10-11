import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/contacts/friend_requests/friend_requests_logic.dart';
import 'package:openim/pages/contacts/friend_requests/friend_requests_view.dart';
import 'package:openim/pages/contacts/request_history/data/request_history_store.dart';
import 'package:openim/pages/contacts/request_history/widgets/request_history_swipe_row.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IM extends GetxController implements IMController {
  @override
  final friendApplicationChangedSubject =
      PublishSubject<FriendApplicationInfo>();

  @override
  void onClose() {
    friendApplicationChangedSubject.close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends GetxController implements HomeLogic {
  @override
  void getUnhandledFriendApplicationCount() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FriendApplicationInfo _request(int time) => FriendApplicationInfo(
      fromUserID: 'sender-$time',
      toUserID: 'me',
      fromNickname: 'Friend $time',
      createTime: time,
      reqMsg: 'Hello',
      handleResult: 1,
    );

void main() {
  const sdk = MethodChannel('flutter_openim_sdk');
  late List<FriendApplicationInfo> rows;
  late _IM im;

  setUp(() async {
    Get.reset();
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'me',
      'imToken': 'test-im',
      'chatToken': 'test-chat',
    }));
    OpenIM.iMManager.userID = 'me';
    im = _IM();
    Get.put<IMController>(im);
    Get.put<HomeLogic>(_Home());
    rows = [_request(2), _request(1)];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      switch (call.method) {
        case 'getFriendApplicationListAsRecipient':
          return jsonEncode(rows.map((row) => row.toJson()).toList());
        case 'getFriendApplicationListAsApplicant':
          return '[]';
        default:
          throw StateError('Unexpected SDK mutation: ${call.method}');
      }
    });
  });

  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    Get.reset();
    Styles.isDark = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    await DataSp.removeLoginCertificate();
  });

  Future<FriendRequestsLogic> open(WidgetTester tester,
      {bool dark = false, bool english = false}) async {
    Styles.isDark = dark;
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final logic = Get.put(FriendRequestsLogic());
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        locale: english ? const Locale('en', 'US') : const Locale('zh', 'CN'),
        translations: TranslationService(),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: EasyLoading.init(
            builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(english ? 1.4 : 1)),
                  child: child!,
                )),
        home: FriendRequestsPage(),
      ),
    ));
    await tester.pumpAndSettle();
    return logic;
  }

  for (final dark in [false, true]) {
    testWidgets('friend requests swipe, refresh and clear ($dark)',
        (tester) async {
      final logic = await open(tester, dark: dark);
      expect(
          tester
              .getCenter(find.text(
                  Get.locale?.languageCode == 'en' ? 'New Friends' : '新的朋友'))
              .dx,
          closeTo(187.5, .01));
      await tester.drag(
          find.byType(RequestHistorySwipeRow).first, const Offset(-240, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StrRes.delete).first);
      await tester.pumpAndSettle();
      expect(find.text('Friend 2'), findsNothing);
      await logic.loadRequests();
      await tester.pumpAndSettle();
      expect(logic.applicationList.map((row) => row.createTime), [1]);
      await tester.tap(find.byKey(const ValueKey('friend-requests-edit')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('friend-requests-select-all')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('friend-requests-delete-selected')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(CustomDialog), matching: find.text(StrRes.delete)));
      await tester.pumpAndSettle();
      expect(find.text('暂无新联系人'), findsOneWidget);
      rows.insert(0, _request(3));
      im.friendApplicationChangedSubject.add(rows.first);
      await tester.pumpAndSettle();
      expect(logic.applicationList.map((row) => row.createTime), [3]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('English large text keeps edit and centered title usable',
      (tester) async {
    await open(tester, english: true, dark: true);
    expect(find.text(StrRes.edit), findsOneWidget);
    expect(
        tester
            .getCenter(find.text(
                Get.locale?.languageCode == 'en' ? 'New Friends' : '新的朋友'))
            .dx,
        closeTo(187.5, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('old account page cannot clear another session', (tester) async {
    final logic = await open(tester);
    OpenIM.iMManager.userID = 'someone-else';
    await logic.clearRequests();
    expect(
        RequestHistoryStore('me', RequestHistoryKind.friend)
            .isHidden(RequestHistoryEntry.friend(rows.first)),
        isFalse);
    expect(logic.applicationList, hasLength(2));
  });

  testWidgets('batch edit deletes only selected rows and survives SDK reload',
      (tester) async {
    final logic = await open(tester);
    await tester.tap(find.byKey(const ValueKey('friend-requests-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friend 1'));
    await tester.pumpAndSettle();
    expect(logic.selected.length, 1);
    await tester
        .tap(find.byKey(const ValueKey('friend-requests-delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(CustomDialog), matching: find.text(StrRes.delete)));
    await tester.pumpAndSettle();
    expect(logic.applicationList.map((row) => row.createTime), [2]);
    expect(logic.editing.value, isFalse);
    await logic.loadRequests();
    await tester.pumpAndSettle();
    expect(logic.applicationList.map((row) => row.createTime), [2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'received pending requests precede history and sent requests have own section',
      (tester) async {
    rows = [
      _request(4),
      _request(1)..handleResult = 0,
      FriendApplicationInfo(
          fromUserID: 'me',
          toUserID: 'peer',
          toNickname: 'Sent request',
          createTime: 5,
          handleResult: 0),
    ];
    await open(tester);
    expect(find.text('对方添加我'), findsOneWidget);
    expect(find.text('我添加对方'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Friend 1')).dy,
        lessThan(tester.getTopLeft(find.text('Friend 4')).dy));
    expect(tester.getTopLeft(find.text('Friend 4')).dy,
        lessThan(tester.getTopLeft(find.text('我添加对方')).dy));
    expect(find.text('验证'), findsOneWidget);
    expect(find.text(StrRes.waitingForVerification), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection cannot delete after account switch', (tester) async {
    final logic = await open(tester);
    logic.toggleEditing();
    logic.toggleAll();
    OpenIM.iMManager.userID = 'someone-else';
    await logic.deleteSelected();
    expect(logic.applicationList, hasLength(2));
    expect(
        RequestHistoryStore('me', RequestHistoryKind.friend)
            .isHidden(RequestHistoryEntry.friend(rows.first)),
        isFalse);
  });
}
