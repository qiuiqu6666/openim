import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/settings/pages/qr_profile_page.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final clipboard = <Object?>[];

  setUp(() {
    clipboard.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add(call.arguments);
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    await EasyLoading.dismiss(animation: false);
    Get.reset();
    Styles.isDark = false;
  });

  Future<void> mount(
      WidgetTester tester, Future<String> Function(FriendAddSource) invite,
      {bool dark = false}) async {
    Styles.isDark = dark;
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        locale: const Locale('zh', 'CN'),
        translations: TranslationService(),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: EasyLoading.init(),
        home: QrProfilePage(
          nickname: '测试',
          userId: 'im_test',
          account: '@test',
          avatarUrl: '',
          inviteFactory: invite,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets(
        'limited QR and link quietly stop and allow manual retry ($dark)',
        (tester) async {
      final sources = <FriendAddSource>[];
      var blocked = true;
      await mount(tester, (source) async {
        sources.add(source);
        if (blocked) throw (20201, 'risk limit');
        return 'fi_valid';
      }, dark: dark);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('正在生成邀请二维码'), findsNothing);
      expect(find.text('二维码邀请暂不可用，点击重试'), findsNothing);
      expect(find.text('点击生成邀请二维码'), findsOneWidget);
      expect(EasyLoading.isShow, isFalse);
      await tester.ensureVisible(find.text('复制链接'));
      await tester.tap(find.text('复制链接'));
      await tester.pumpAndSettle();
      expect(clipboard, isEmpty);
      expect(find.text('邀请暂不可用，请稍后重试'), findsNothing);
      expect(find.textContaining('已复制'), findsNothing);
      expect(sources, [FriendAddSource.qrcode, FriendAddSource.link]);
      await tester.pump(const Duration(seconds: 61));
      expect(sources, hasLength(2));
      blocked = false;
      await tester.ensureVisible(find.text('点击生成邀请二维码'));
      await tester.tap(find.text('点击生成邀请二维码'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(sources.last, FriendAddSource.qrcode);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ordinary invitation failures still offer recovery',
      (tester) async {
    await mount(tester, (_) async => throw StateError('Network unavailable'));
    expect(find.text('二维码邀请暂不可用，点击重试'), findsOneWidget);
    await tester.ensureVisible(find.text('复制链接'));
    await tester.tap(find.text('复制链接'));
    await tester.pumpAndSettle();
    expect(find.text('邀请暂不可用，请稍后重试'), findsOneWidget);
    expect(clipboard, isEmpty);
    await EasyLoading.dismiss(animation: false);
    await tester.pumpAndSettle();
  });
}
