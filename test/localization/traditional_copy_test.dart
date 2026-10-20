import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/app.dart';
import 'package:openim/pages/customer_service/content/customer_service_content.dart';
import 'package:openim/pages/mine/settings/pages/display_theme_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim/pages/mine/widgets/mine_profile_localization.dart';
import 'package:openim/pages/moments/presentation/moments_text.dart';
import 'package:openim/widgets/auth/auth_copy.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/exchange/widgets/wallet_exchange_form.dart';
import 'package:openim/pages/chat/history_search/context/search_context_strings.dart';
import 'package:openim/pages/group_features/sangong/report_center/widgets/report_widgets.dart';
import 'package:openim_common/localization.dart';
import 'package:openim_common/media_localization.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/res/localization/traditional_copy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  test('application routes compile with localized presentation', () {
    expect(const ChatApp(), isA<Widget>());
  });

  test('script and region resolution preserve explicit simplified Chinese', () {
    for (final locale in [
      const Locale('zh', 'TW'),
      const Locale('zh', 'HK'),
      const Locale('zh', 'MO'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    ]) {
      expect(AppCopy.text('订单详情', locale: locale), '訂單詳情');
    }
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('en', 'US'),
      const Locale.fromSubtags(
          languageCode: 'zh', scriptCode: 'Hans', countryCode: 'HK'),
    ]) {
      expect(AppCopy.text('订单详情', locale: locale), '订单详情');
    }
  });

  test('templates preserve user data, money and placeholder-like values', () {
    Get.locale = const Locale('zh', 'TW');
    expect(
      AppCopy.format('已发送 {#0}/{#1} 项。', ['张三{#1}', '12.3400']),
      '已傳送 张三{#1}/12.3400 項。',
    );
    expect(AppCopy.text('张三说：请给我转账 12.3400 USDT'), '张三说：请给我转账 12.3400 USDT');
    expect(AppCopy.error(StateError('无法读取所选相册文件，请重试')),
        'Bad state: 無法讀取所選相簿檔案，請重試');
  });

  test('catalog preserves all template placeholders and format markers', () {
    final placeholder = RegExp(r'\{#\d+\}|@[a-zA-Z_][a-zA-Z_0-9]*|%s');
    for (final entry in traditionalCopy.entries) {
      expect(placeholder.allMatches(entry.value).map((m) => m[0]).toList(),
          placeholder.allMatches(entry.key).map((m) => m[0]).toList(),
          reason: entry.key);
    }
  });

  test('album and camera use traditional delegates for all supported regions',
      () {
    for (final locale in [
      const Locale('zh', 'TW'),
      const Locale('zh', 'HK'),
      const Locale('zh', 'MO'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    ]) {
      expect(AppMediaCopy.assetsFor(locale).confirm, '確認');
      final camera = AppMediaCopy.cameraFor(locale);
      expect(camera.confirm, '確認');
      expect(camera.sActionStopRecordingHint, '停止錄影');
      expect(camera.sCameraPreviewLabel(CameraLensDirection.back), '後置畫面預覽');
      expect(camera.sFlashModeLabel(FlashMode.off), '閃光模式: 關閉');
    }
    expect(AppMediaCopy.assetsFor(const Locale('zh', 'CN')).confirm, '确认');
    expect(AppMediaCopy.cameraFor(const Locale('zh', 'CN')).confirm, '确认');
    expect(AppMediaCopy.cameraFor(const Locale('en', 'US')).confirm, 'Confirm');
  });

  testWidgets(
      'shared helpers respect context and auth respects selected locale',
      (tester) async {
    Get.locale = const Locale('zh', 'TW');
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(builder: (context) {
        pageContext = context;
        return const SizedBox();
      }),
    ));
    for (final translate in [
      settingsText,
      momentsText,
      customerServiceText,
      mineText,
    ]) {
      expect(translate(pageContext, zh: '订单详情', en: 'Order details'), '訂單詳情');
    }
    expect(authText('登录', 'Login'), '登入');
    expect(contextText(pageContext, 'title'), '聊天記錄上下文');
    expect(reportPhase('settled'), '已結算');
    expect(ledgerLabel('user_transfer_out'), '向下級劃出');
    Get.locale = const Locale('en', 'US');
    expect(authText('登录', 'Login'), 'Login');
  });

  testWidgets('appearance language selector includes, saves and displays Hant',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLanguage(1);
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en', 'US')
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: DisplayThemePage(store: store),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多语言选择'));
    await tester.pumpAndSettle();
    expect(find.text('繁體中文'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('繁體中文'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(DataSp.getLanguage(), 3);
    expect(Get.locale, const Locale('zh', 'TW'));
    expect(find.text('繁體中文'), findsOneWidget);
    expect(find.text('介面與顯示'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'exchange translates labels without changing values in $brightness',
        (tester) async {
      Get.locale = const Locale('zh', 'TW');
      final amount = TextEditingController(text: '12.3400');
      addTearDown(amount.dispose);
      var reversed = 0;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
            body: WalletExchangeForm(
          from: FundCurrency.usdt,
          to: FundCurrency.bi99,
          amountController: amount,
          available: '98.7654',
          locked: false,
          onFrom: (_) {},
          onTo: (_) {},
          onReverse: () => reversed++,
          onAmountChanged: () {},
        )),
      ));
      expect(find.text('轉出'), findsOneWidget);
      expect(find.byTooltip('交換幣種'), findsOneWidget);
      final dropdown = tester.widget<DropdownButton<FundCurrency>>(
          find.byKey(const ValueKey('wallet-swap-from')));
      expect(dropdown.value, FundCurrency.usdt);
      expect(amount.text, '12.3400');
      await tester.tap(find.byKey(const ValueKey('wallet-swap-reverse')));
      expect(reversed, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
