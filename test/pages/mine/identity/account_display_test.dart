import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/mine/mine_logic.dart';
import 'package:openim/pages/mine/mine_view.dart';
import 'package:openim/pages/mine/settings/pages/profile_info_page.dart';
import 'package:openim/pages/mine/settings/pages/qr_profile_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/settings_home_page.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _internalId = 'im_internal_user_123';
const _account = 'qiutest99';

class _IM extends GetxController implements IMController {
  @override
  final userInfo = UserFullInfo(userID: _internalId, nickname: '').obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Mine extends GetxController implements MineLogic {
  _Mine(this.imLogic);

  @override
  final IMController imLogic;

  @override
  final settingsStore = SettingsDraftStore();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void onClose() {
    settingsStore.dispose();
    super.onClose();
  }
}

Widget _host(Widget child, {bool dark = false}) => ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: EasyLoading.init(),
        home: child,
      ),
    );

Future<void> _mount(WidgetTester tester, Widget child,
    {bool dark = false, bool settle = true}) async {
  Styles.isDark = dark;
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(child, dark: dark));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _dismissToast(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await EasyLoading.dismiss(animation: false);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.testMode = true;
  });

  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    Get.reset();
    Styles.isDark = false;
  });

  for (final dark in [false, true]) {
    testWidgets(
        'my page follows account updates without showing SDK ID ($dark)',
        (tester) async {
      final im = _IM();
      Get.put<MineLogic>(_Mine(im));
      await _mount(tester, MinePage(onWalletTap: () {}),
          dark: dark, settle: false);

      expect(find.text('99号ID: --'), findsOneWidget);
      expect(find.textContaining(_internalId), findsNothing);

      im.userInfo.value = UserFullInfo(
        userID: _internalId,
        account: '  $_account  ',
        nickname: '',
      );
      await tester.pump();

      expect(find.text('99号ID: $_account'), findsOneWidget);
      expect(find.text(_account), findsOneWidget);
      expect(find.textContaining(_internalId), findsNothing);

      im.userInfo.value = UserFullInfo(
        userID: _internalId,
        account: '  ',
        nickname: '',
      );
      await tester.pump();
      expect(find.text('99号ID: --'), findsOneWidget);
      expect(find.textContaining(_internalId), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'profile displays and copies account, never a missing ID ($dark)',
        (tester) async {
      final store = SettingsDraftStore();
      addTearDown(store.dispose);
      final copied = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await _mount(
        tester,
        ProfileInfoPage(
          nickname: '秋的测试号',
          userId: _internalId,
          account: '  $_account  ',
          avatarUrl: '',
          store: store,
        ),
        dark: dark,
      );
      expect(find.text(_account), findsOneWidget);
      expect(find.textContaining(_internalId), findsNothing);
      await tester.tap(find.text('99号ID'));
      await tester.pump();
      expect(copied, [_account]);
      await _dismissToast(tester);

      await tester.pumpWidget(_host(
        ProfileInfoPage(
          key: const ValueKey('missing-account'),
          nickname: '秋的测试号',
          userId: _internalId,
          account: '  ',
          avatarUrl: '',
          store: store,
        ),
        dark: dark,
      ));
      await tester.pumpAndSettle();
      expect(find.text('--'), findsOneWidget);
      expect(find.textContaining(_internalId), findsNothing);
      await tester.tap(find.text('99号ID'));
      await tester.pump();
      expect(copied, [_account]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('QR shows account and copied invitation keeps SDK ID ($dark)',
        (tester) async {
      final sources = <FriendAddSource>[];
      final copied = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      Future<String> invite(FriendAddSource source) async {
        sources.add(source);
        return 'fi_account_test';
      }

      await _mount(
        tester,
        QrProfilePage(
          nickname: '  ',
          userId: '  $_internalId  ',
          account: '  $_account  ',
          avatarUrl: '',
          inviteFactory: invite,
        ),
        dark: dark,
      );
      expect(find.text(_account), findsOneWidget);
      expect(find.text('99号ID: $_account'), findsOneWidget);
      expect(find.textContaining(_internalId), findsNothing);
      expect(sources, [FriendAddSource.qrcode]);
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.ensureVisible(find.text('复制链接'));
      await tester.tap(find.text('复制链接'));
      await _dismissToast(tester);
      expect(sources, [FriendAddSource.qrcode, FriendAddSource.link]);
      expect(copied.single, startsWith('你好，我是$_account\n'));
      final uri = Uri.parse(copied.single.split('我的好友邀请：').last);
      expect(uri.scheme, 'openim');
      expect(uri.host, 'user');
      expect(uri.pathSegments, [_internalId]);
      expect(uri.queryParameters,
          {'inviteCode': 'fi_account_test', 'source': 'link'});

      await tester.pumpWidget(_host(
        QrProfilePage(
          key: const ValueKey('missing-account'),
          nickname: '',
          userId: _internalId,
          avatarUrl: '',
          inviteFactory: invite,
        ),
        dark: dark,
      ));
      await tester.pumpAndSettle();
      expect(find.text('99号ID: --'), findsOneWidget);
      expect(find.text('99Chat'), findsNWidgets(2));
      expect(find.textContaining(_internalId), findsNothing);
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.ensureVisible(find.text('复制链接'));
      await tester.tap(find.text('复制链接'));
      await _dismissToast(tester);
      expect(copied.last, startsWith('你好，我是99Chat\n'));
      expect(Uri.parse(copied.last.split('我的好友邀请：').last).pathSegments,
          [_internalId]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'settings profile entry passes account and internal ID separately',
      (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await _mount(
      tester,
      SettingsHomePage(
        store: store,
        profileName: '秋的测试号',
        profileId: _internalId,
        profileAccount: _account,
      ),
    );
    await tester.tap(find.text('个人资料'));
    await tester.pumpAndSettle();

    final profile =
        tester.widget<ProfileInfoPage>(find.byType(ProfileInfoPage));
    expect(profile.userId, _internalId);
    expect(profile.account, _account);
    expect(find.text(_account), findsOneWidget);
    expect(find.textContaining(_internalId), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
