import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/secondary/share_app_sheet.dart';
import 'package:openim/pages/mine/secondary/favorites_page.dart';
import 'package:openim/pages/mine/secondary/favorites_draft_store.dart';
import 'package:openim/pages/mine/settings/pages/qr_profile_page.dart';
import 'package:openim/pages/mine/settings/pages/about_us_page.dart';
import 'package:openim/pages/mine/settings/settings_home_page.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim/pages/mine/settings/pages/account_security_page.dart';
import 'package:openim/pages/mine/settings/pages/add_friend_privacy_page.dart';
import 'package:openim/pages/mine/settings/pages/change_password_page.dart';
import 'package:openim/pages/mine/settings/pages/change_phone_page.dart';
import 'package:openim/pages/mine/settings/pages/change_trade_password_page.dart';
import 'package:openim/pages/mine/settings/pages/friend_permission_page.dart';
import 'package:openim/pages/mine/settings/pages/feedback_page.dart';
import 'package:openim/pages/mine/settings/pages/profile_info_page.dart';
import 'package:openim/pages/mine/settings/pages/login_devices_page.dart';
import 'package:openim/pages/mine/settings/pages/legal_document_page.dart';
import 'package:openim/pages/mine/settings/pages/font_size_page.dart';
import 'package:openim/pages/mine/settings/pages/moments_permission_page.dart';
import 'package:openim/pages/mine/settings/pages/node_switch_page.dart';
import 'package:openim/pages/mine/settings/pages/trade_password_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
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

  testWidgets('99chat account-security information architecture is preserved',
      (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(AccountSecurityPage(
      store: store,
      service: const StubSettingsService(),
      phoneNumber: '13800138000',
    )));
    await tester.pump();

    expect(find.text('修改密码'), findsOneWidget);
    expect(find.text('支付密码'), findsOneWidget);
    expect(find.text('修改手机号码'), findsOneWidget);
    expect(find.text('登录设备'), findsOneWidget);
  });

  testWidgets('change-password phone-bound layout matches 99chat structure',
      (tester) async {
    await tester.pumpWidget(_host(const ChangePasswordPage(
      service: StubSettingsService(),
      phoneNumber: '13800138000',
    )));

    expect(find.text('绑定手机号'), findsOneWidget);
    expect(find.text('验证码'), findsOneWidget);
    expect(find.text('旧密码'), findsNothing);
    expect(find.text('新密码'), findsOneWidget);
    expect(find.text('确认密码'), findsOneWidget);
    expect(find.text('密码需为 8 位以上英文和数字组合'), findsOneWidget);
  });

  testWidgets('change-password unbound layout uses current password',
      (tester) async {
    await tester.pumpWidget(_host(const ChangePasswordPage(
      service: StubSettingsService(),
    )));

    expect(find.text('旧密码'), findsOneWidget);
    expect(find.text('验证码'), findsNothing);
  });

  testWidgets('bound-phone change page keeps 99chat two-step shell',
      (tester) async {
    await tester.pumpWidget(_host(const ChangePhonePage(
      service: StubSettingsService(),
      isBound: true,
      currentPhone: '13800138000',
    )));

    expect(find.text('第 1 步  验证当前手机号'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('138****8000'), findsOneWidget);
  });

  testWidgets('friend permissions keep 99chat group labels and switches',
      (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(FriendPermissionPage(store: store)));

    for (final text in const [
      '加我为好友的方式',
      '添加我的方式',
      '黑名单',
      '最后上线时间',
      '显示在线状态',
      '消息阅读状态',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
  });

  testWidgets('add-friend privacy exposes the five 99chat discovery channels',
      (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(AddFriendPrivacyPage(store: store)));

    for (final text in const ['二维码', '名片', '群聊', '手机号', 'UID']) {
      expect(find.text(text), findsOneWidget);
    }
  });

  testWidgets('moments privacy uses the three 99chat rows', (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(MomentsPermissionPage(store: store)));

    expect(find.text('不让他(她)看'), findsOneWidget);
    expect(find.text('不看他（她）'), findsOneWidget);
    expect(find.text('允许朋友查看朋友圈的范围'), findsOneWidget);
  });

  testWidgets('signed-in devices renders 99chat empty state without fake data',
      (tester) async {
    await tester.pumpWidget(_host(const LoginDevicesPage()));
    expect(find.text('暂无登录设备'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('trade password keeps 99chat six-dot keypad surface',
      (tester) async {
    await tester.pumpWidget(_host(const TradePasswordPage()));
    expect(find.text('设置交易密码'), findsOneWidget);
    expect(find.byKey(const ValueKey('trade-password-pin-dots')), findsOneWidget);
    expect(find.byKey(const ValueKey('trade-password-keypad')), findsOneWidget);
  });

  testWidgets('trade password keypad keeps 99chat 750-design effective scale',
      (tester) async {
    await tester.pumpWidget(_host(const TradePasswordPage()));

    final keypadSize = tester.getSize(
      find.byKey(const ValueKey('trade-password-keypad')),
    );
    expect(keypadSize.height, lessThan(240));
    expect(find.byKey(const ValueKey('trade-password-key-1')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('trade-password-key-1'))).height,
      lessThan(50),
    );
  });

  test('biometric settings entry follows device support, not enrollment state', () {
    expect(
      shouldShowBiometricSettingsEntry(
        platformSupported: true,
        deviceSupported: true,
      ),
      isTrue,
    );
    expect(
      shouldShowBiometricSettingsEntry(
        platformSupported: true,
        deviceSupported: false,
      ),
      isFalse,
    );
  });
  testWidgets('settings scaffold matches 99chat card page geometry',
      (tester) async {
    await tester.pumpWidget(_host(const SettingsScaffold(
      title: '设置',
      children: [SettingsGroup(children: [SettingsCell(title: '测试')])],
    )));

    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect(list.padding, const EdgeInsets.fromLTRB(12, 12, 12, 24));

    final material = tester.widgetList<Material>(find.byType(Material)).firstWhere(
          (item) => item.borderRadius == BorderRadius.circular(AppTokens.rLg),
        );
    expect(material.clipBehavior, Clip.antiAlias);
    expect(AppTokens.rLg, 14);
  });

  testWidgets('embedded settings hides host-owned rows', (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(SettingsHomePage(
      store: store,
      service: const StubSettingsService(),
      embedded: true,
    )));

    expect(find.text('个人资料'), findsNothing);
    expect(find.text('意见反馈'), findsNothing);
    expect(find.text('退出登录'), findsNothing);
    expect(find.text('账号安全'), findsOneWidget);
  });

  testWidgets('about page uses 99chat branding and supports embedded mode',
      (tester) async {
    await tester.pumpWidget(_host(const AboutUsPage(embedded: true)));
    await tester.pump();

    expect(find.text('99chat'), findsOneWidget);
    expect(find.text('© 2026 99chat'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('change payment password path keeps 99chat three-field shell',
      (tester) async {
    await tester.pumpWidget(_host(const ChangeTradePasswordPage(
      service: StubSettingsService(),
      phoneNumber: '13800138000',
    )));

    expect(find.text('修改支付密码'), findsOneWidget);
    expect(find.text('原密码'), findsOneWidget);
    expect(find.text('新密码'), findsOneWidget);
    expect(find.text('确认密码'), findsOneWidget);
    expect(find.text('忘记支付密码？通过短信验证码重置'), findsOneWidget);
  });

  testWidgets('moments visible-range sheet includes last six months',
      (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(MomentsPermissionPage(store: store)));
    await tester.tap(find.text('允许朋友查看朋友圈的范围'));
    await tester.pumpAndSettle();
    expect(find.text('最近半年'), findsOneWidget);
  });

  testWidgets('node page keeps the two 99chat catalog entries without fake status',
      (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(NodeSwitchPage(
      store: store,
      service: const StubSettingsService(),
    )));
    expect(find.text('节点01(CN)'), findsOneWidget);
    expect(find.text('节点02(US)'), findsOneWidget);
    expect(find.text('未知'), findsNWidgets(2));
  });

  testWidgets('profile page exposes the complete 99chat mobile information chain',
      (tester) async {
    final store = SettingsDraftStore()
      ..setProfileNickname('Alice')
      ..setProfileSignature('Hello');
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(ProfileInfoPage(
      nickname: 'Alice',
      userId: '990001',
      avatarUrl: '',
      phoneNumber: '13800138000',
      gender: 1,
      birth: DateTime(2000, 1, 2).millisecondsSinceEpoch,
      store: store,
      service: const StubSettingsService(),
    )));

    for (final text in const [
      '头像',
      '名字',
      '性别',
      '生日',
      '手机号',
      '99号ID',
      '我的二维码',
      '朋友圈',
      '个性签名',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('查看我的动态'), findsOneWidget);
    expect(find.text('2000-01-02'), findsOneWidget);
  });

  testWidgets('feedback page keeps 99chat hero form and diagnostics state',
      (tester) async {
    await tester.pumpWidget(_host(const FeedbackPage(
      service: StubSettingsService(),
    )));

    expect(find.textContaining('您的意见'), findsOneWidget);
    expect(find.text('反馈类型'), findsOneWidget);
    expect(find.text('反馈内容'), findsOneWidget);
    expect(find.text('相关截图（选填）'), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-diagnostics')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-submit')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-hero-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-success')), findsNothing);
  });

  testWidgets('settings responsive matches 99chat form-factor classification',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(const SettingsScaffold(
      title: '设置',
      children: [
        SettingsGroup(children: [SettingsCell(title: '桌面行')]),
      ],
    )));

    final context = tester.element(find.text('桌面行'));
    expect(SettingsResponsive.isDesktop(context), isTrue);
    expect(SettingsResponsive.listRowMinHeight(context), 52);
  });


  testWidgets('share app sheet matches 99chat action surface', (tester) async {
    await tester.pumpWidget(_host(const Scaffold(
      body: ShareAppSheet(website: 'https://example.com/download'),
    )));

    expect(find.text('分享应用'), findsOneWidget);
    expect(find.text('99chat'), findsOneWidget);
    expect(find.text('https://example.com/download'), findsOneWidget);
    expect(find.text('发送给朋友'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
  });



  testWidgets('feedback hero keeps the 99chat blue wave backdrop', (tester) async {
    await tester.pumpWidget(_host(const FeedbackPage(
      service: StubSettingsService(),
    )));
    expect(find.byKey(const ValueKey('feedback-hero-backdrop')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-hero-image')), findsOneWidget);
  });

  test('profile QR share uses branded WeChat/QQ assets and native Android chooser', () {
    final dartSource = File(
      'lib/pages/mine/settings/pages/qr_profile_page.dart',
    ).readAsStringSync();
    final androidSource = File(
      'android/app/src/main/java/io/openim/MainActivity.java',
    ).readAsStringSync();

    expect(dartSource, contains("assets/images/vx .png"));
    expect(dartSource, contains('assets/images/qq.png'));
    expect(dartSource, contains('assets/images/ivnbg.webp'));
    expect(File('assets/images/qq.png').lengthSync(), 6106);
    expect(File('assets/images/ivnbg.webp').lengthSync(), 753960);
    expect(dartSource, contains('width: 28'));
    expect(dartSource, contains('height: 28'));
    expect(dartSource, contains('const SizedBox(height: 9)'));
    expect(dartSource, contains('fontSize: 12'));
    expect(dartSource, contains('const spacing = 14.0'));
    expect(dartSource, contains("MethodChannel('openim_system_share')"));
    expect(androidSource, contains('Intent.createChooser'));
    expect(androidSource, contains('Intent.EXTRA_EXCLUDE_COMPONENTS'));
    expect(androidSource, contains('bluetooth'));
  });

  testWidgets('profile QR page exposes 99chat branded card and action surface',
      (tester) async {
    await tester.pumpWidget(_host(const QrProfilePage(
      nickname: 'Alice',
      userId: '990001',
      avatarUrl: '',
    )));

    expect(find.text('扫一扫，添加我为好友'), findsOneWidget);
    expect(find.text('99Chat'), findsOneWidget);
    expect(find.text('保存图片'), findsOneWidget);
    expect(find.text('扫一扫'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-share-actions')), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-bottom-actions')), findsOneWidget);
  });

  testWidgets('favorites page keeps 99chat search filter sort surface',
      (tester) async {
    final store = FavoritesDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(FavoritesPage(store: store)));

    expect(find.byKey(const ValueKey('favorites-search')), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('文字'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.byKey(const ValueKey('favorites-sort')), findsOneWidget);
    expect(find.text('添加收藏'), findsOneWidget);
  });

  test('font size keeps the four 99chat preset scales', () {
    expect(FontSizePage.presets, const <double>[0.9, 1.0, 1.12, 1.24]);
  });

  testWidgets('legal documents ship the 99chat legal body instead of placeholders',
      (tester) async {
    await tester.pumpWidget(_host(const LegalDocumentPage(
      kind: LegalDocumentKind.terms,
    )));
    expect(find.textContaining('生效日期：2026 年 5 月 24 日'), findsOneWidget);
    expect(find.textContaining('support@99chat.app'), findsOneWidget);

    await tester.pumpWidget(_host(const LegalDocumentPage(
      kind: LegalDocumentKind.privacy,
    )));
    expect(find.textContaining('privacy@99chat.app'), findsOneWidget);
  });

  testWidgets('embedded node page does not render a second app bar',
      (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(_host(NodeSwitchPage(
      store: store,
      service: const StubSettingsService(),
      embedded: true,
    )));
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('节点01(CN)'), findsOneWidget);
    expect(find.text('节点02(US)'), findsOneWidget);
  });


test('message sound picker previews selected 99chat sound asset', () {
  final source = File(
    'lib/pages/mine/settings/pages/message_notification_sound_picker_page.dart',
  ).readAsStringSync();
  expect(source, contains("assets/audio/99chat/\$id.wav"));
  expect(source, contains("package: 'openim_common'"));
  expect(source, contains('await _player.play()'));
});

}
