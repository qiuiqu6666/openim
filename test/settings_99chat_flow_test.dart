import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/about_us_page.dart';
import 'package:openim/pages/mine/settings/pages/display_theme_page.dart';
import 'package:openim/pages/mine/settings/pages/notification_settings_page.dart';
import 'package:openim/pages/mine/settings/pages/font_size_page.dart';
import 'package:openim/pages/mine/settings/pages/trade_password_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/settings_home_page.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim/pages/mine/widgets/mine_profile_view.dart';
import 'package:openim_common/openim_common.dart';

Widget _host(Widget child) => ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) {
        Styles.isDark = false;
        return MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: child,
        );
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mine keeps 99chat top settings action and routes to settings',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var settingsTapped = false;

    await tester.pumpWidget(_host(MineProfileView(
      nickname: 'OpenIM User',
      userId: 'openim-001',
      avatarUrl: '',
      signature: '未设置',
      onProfileTap: () {},
      onQrTap: () {},
      onFavoritesTap: () {},
      onCallsTap: () {},
      onNotificationsTap: () {},
      onShareAppTap: () {},
      onSettingsTap: () => settingsTapped = true,
      onFeatureTap: (_) {},
      onUnavailableFeatureTap: (_) {},
    )));

    expect(find.byKey(const ValueKey('mine-top-settings')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mine-top-settings')));
    expect(settingsTapped, isTrue);
  });

  testWidgets('settings exposes the full 99chat first-level information architecture',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SettingsDraftStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(_host(SettingsHomePage(
      store: store,
      profileName: 'OpenIM User',
      profileId: 'openim-001',
    )));
    await tester.pumpAndSettle();

    for (final label in const [
      '个人资料',
      '账号安全',
      '朋友权限',
      '朋友圈',
      '界面与显示',
      '储存空间',
      '节点切换',
      '关于我们',
      '意见反馈',
      '当前版本',
      '退出登录',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'missing $label');
    }
  });

  testWidgets('friend-permission switches keep local UI state without network calls',
      (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    expect(store.showOnlineStatus, isTrue);
    store.setShowOnlineStatus(false);
    expect(store.showOnlineStatus, isFalse);
    store.setReadReceipts(false);
    expect(store.readReceipts, isFalse);
  });
  testWidgets('settings account-security row pushes a real secondary page',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SettingsDraftStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(_host(SettingsHomePage(
      store: store,
      profileName: 'OpenIM User',
      profileId: 'openim-001',
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('账号安全'));
    await tester.pumpAndSettle();
    expect(find.text('修改密码'), findsOneWidget);
    expect(find.text('支付密码'), findsOneWidget);
    expect(find.text('登录设备'), findsOneWidget);
  });

  testWidgets('account security reflects an already-bound phone number',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SettingsDraftStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(_host(SettingsHomePage(
      store: store,
      profileName: 'OpenIM User',
      profileId: 'openim-001',
      phoneNumber: '13800138000',
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('账号安全'));
    await tester.pumpAndSettle();
    expect(find.text('修改手机号码'), findsOneWidget);
    expect(find.text('绑定手机号码'), findsNothing);
  });

  testWidgets('payment password uses 99chat pin dots and numeric keypad',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(const TradePasswordPage()));
    await tester.pumpAndSettle();

    expect(find.text('设置交易密码'), findsOneWidget);
    expect(find.text('请输入交易密码'), findsOneWidget);
    expect(find.byKey(const ValueKey('trade-password-pin-dots')), findsOneWidget);
    expect(find.byKey(const ValueKey('trade-password-keypad')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('notification dependent switches retain local draft state',
      (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    expect(store.messageSoundEnabled, isTrue);
    store.updateNotifications(messageSoundEnabled: false);
    expect(store.messageSoundEnabled, isFalse);
    store.updateNotifications(callClosed: false, quickAnswer: false);
    expect(store.callNotifyWhenClosed, isFalse);
    expect(store.quickAnswer, isFalse);
  });


  // Regression coverage for 99chat parity: these rows/pages are intentionally
  // kept as real navigation/UI even while remote data sources stay stubbed.
  testWidgets('notification page mirrors 99chat call-ringtone structure',
  (tester) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = SettingsDraftStore();
  addTearDown(store.dispose);

  await tester.pumpWidget(_host(NotificationSettingsPage(store: store)));
  await tester.pumpAndSettle();

  expect(find.text('语音和视频通话用弹窗快捷接听'), findsOneWidget);
  expect(find.text('语音和视频通话通知'), findsNothing);
  expect(find.text('语音和视频通话来电铃声'), findsOneWidget);
  expect(find.text('默认铃声'), findsNothing);
  });

  testWidgets('about terms and privacy are real secondary pages', (tester) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(const AboutUsPage()));
  await tester.pumpAndSettle();
  await tester.tap(find.text('服务条款'));
  await tester.pumpAndSettle();
  expect(find.text('服务条款'), findsWidgets);
  expect(find.byKey(const ValueKey('settings-legal-document-body')), findsOneWidget);
  });

  testWidgets('font size page uses the 99chat full chat preview shell', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SettingsDraftStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(_host(FontSizePage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('小美'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    expect(find.text('字体大小'), findsNothing);
  });

  testWidgets('message sound row opens the dedicated 99chat picker page', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SettingsDraftStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(_host(NotificationSettingsPage(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('- 默认提示音'));
    await tester.pumpAndSettle();

    expect(find.text('消息提示音'), findsWidgets);
    expect(find.text('默认'), findsOneWidget);
    expect(find.text('清脆'), findsOneWidget);
    expect(find.text('柔和'), findsOneWidget);
    expect(find.text('叮咚'), findsOneWidget);
  });

  testWidgets('appearance language uses an action sheet instead of a pushed page', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SettingsDraftStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(_host(DisplayThemePage(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('多语言选择'));
    await tester.pumpAndSettle();

    expect(find.text('选择语言'), findsOneWidget);
    expect(find.text('跟随系统'), findsWidgets);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  // 99chat settings primitive parity: mobile rows must stay on the product's
  // 56px mobile metrics even on wider Android phones/tablets. Compatibility
  // adaptations must not change the visual contract.
  testWidgets('settings cell keeps 99chat mobile 56px row contract', (tester) async {
    tester.view.physicalSize = const Size(504, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(const SettingsScaffold(
      title: '设置',
      children: [
        SettingsGroup(
          children: [
            SettingsCell(title: '账号安全', showDivider: false),
          ],
        ),
      ],
    )));
    await tester.pumpAndSettle();

    final ink = find.ancestor(
      of: find.text('账号安全'),
      matching: find.byType(Container),
    );
    expect(ink, findsWidgets);
    // The row's outer decorated container is constrained to at least 56px.
    final candidates = tester.widgetList<Container>(ink).where(
          (w) => w.constraints?.minHeight == 56,
        );
    expect(candidates, isNotEmpty);
  });
}
