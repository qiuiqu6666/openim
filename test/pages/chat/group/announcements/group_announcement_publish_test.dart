import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group/announcements/group_announcement_error_message.dart';
import 'package:openim/pages/chat/group_setup/group_announcement_page.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim_common/openim_common.dart';

class _AnnouncementLogic implements GroupSetupLogic {
  @override
  final groupInfo = GroupInfo(groupID: 'group', notification: '原来的公告').obs;
  final canEdit = true.obs;
  @override
  bool get isOwnerOrAdmin => canEdit.value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _nativeTimeout = PlatformException(
  code: '10000',
  message: 'Network error ApiPost http.Client.Do failed: context deadline '
      'exceeded (Client.Timeout exceeded while awaiting headers)\n'
      '${List.filled(60, 'github.com/openimsdk/internal/group/server_api.go:45').join('\n')}',
  details: {'internal': 'do not show native details'},
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late _AnnouncementLogic logic;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) respond;
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
    logic = _AnnouncementLogic();
    calls = [];
    respond = (_) async => throw _nativeTimeout;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return respond(call);
    });
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    Get.reset();
  });

  test('native deadlines use a short localized timeout message', () {
    expect(groupAnnouncementPublishErrorMessage(_nativeTimeout), '请求超时，请稍后重试');
    expect(
        groupAnnouncementPublishErrorMessage(
            PlatformException(code: '${SDKErrorCode.networkWaitTimeoutError}')),
        '请求超时，请稍后重试');
    expect(groupAnnouncementPublishErrorMessage(TimeoutException('internal')),
        '请求超时，请稍后重试');
    Get.locale = const Locale('en', 'US');
    expect(groupAnnouncementPublishErrorMessage(_nativeTimeout),
        'The request timed out. Please try again.');
  });

  test('known permissions/network and unknown errors never expose SDK details',
      () {
    expect(
        groupAnnouncementPublishErrorMessage(
            PlatformException(code: '1002', message: 'internal stack')),
        StrRes.groupAcPermissionTips);
    expect(
        groupAnnouncementPublishErrorMessage(
            PlatformException(code: '10000', message: 'connection refused')),
        StrRes.networkError);
    for (final error in [
      PlatformException(code: '500', message: _nativeTimeout.message),
      PlatformException(code: '10005', details: 'native stack'),
      StateError('secret response body'),
    ]) {
      expect(groupAnnouncementPublishErrorMessage(error), '公告发布失败，请稍后重试');
    }
  });

  for (final dark in [false, true]) {
    testWidgets('timeout keeps draft and allows retry without overflow / $dark',
        (tester) async {
      await _mount(tester, logic, dark: dark, textScale: 2, keyboard: 300);
      await tester.enterText(find.byType(TextField), '新的公告内容');
      await tester.pump();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'setGroupInfo');
      final request = Map<String, dynamic>.from(calls.single.arguments as Map);
      expect((request['groupInfo'] as Map)['notification'], '新的公告内容');
      expect(find.text('请求超时，请稍后重试'), findsOneWidget);
      expect(find.textContaining('github.com'), findsNothing);
      expect(find.byType(GroupAnnouncementPage), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '新的公告内容');
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull);
      expect(logic.groupInfo.value.notification, '原来的公告');
      expect(tester.takeException(), isNull);
      await EasyLoading.dismiss(animation: false);
      await tester.pump();
    });
  }

  testWidgets('stale taps share submission, failure can retry, success returns',
      (tester) async {
    final pending = Completer<Object?>();
    respond = (_) => pending.future;
    await _mount(tester, logic);
    await tester.enterText(find.byType(TextField), '  新公告  ');
    await tester.pump();
    final send =
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;
    send();
    send();
    await tester.pump();
    expect(calls, hasLength(1));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    final context = tester.element(find.byType(GroupAnnouncementPage));
    await Navigator.of(context).maybePop();
    await tester.pump();
    expect(find.byType(GroupAnnouncementPage), findsOneWidget);
    pending.completeError(_nativeTimeout);
    await tester.pumpAndSettle();
    expect(logic.groupInfo.value.notification, '原来的公告');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '  新公告  ');
    respond = (_) async => '""';
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(logic.groupInfo.value.notification, '新公告');
    expect(find.byType(GroupAnnouncementPage), findsNothing);
    expect(find.text('群设置测试入口'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
  });

  testWidgets('leaving before native completion does not update disposed page',
      (tester) async {
    final pending = Completer<Object?>();
    respond = (_) => pending.future;
    await _mount(tester, logic);
    await tester.enterText(find.byType(TextField), '新公告');
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete('""');
    await tester.pump();
    expect(logic.groupInfo.value.notification, '原来的公告');
    expect(EasyLoading.isShow, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(WidgetTester tester, _AnnouncementLogic logic,
    {bool dark = false, double textScale = 1, double keyboard = 0}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  final loading = EasyLoading.instance;
  final mask = loading.maskType;
  final interactions = loading.userInteractions;
  final animation = loading.animationStyle;
  final customAnimation = loading.customAnimation;
  configureEasyLoadingInteractions();
  final loadingBuilder = EasyLoading.init();
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: loadingBuilder(context, child),
      ),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                GroupAnnouncementPage(logic: logic))),
                    child: const Text('群设置测试入口'),
                  ))),
    ),
  ));
  await tester.tap(find.text('群设置测试入口'));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox());
    loading
      ..maskType = mask
      ..userInteractions = interactions
      ..animationStyle = animation
      ..customAnimation = customAnimation;
  });
}
