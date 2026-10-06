import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_counterparty_source.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';
import 'package:openim/pages/wallet/record/wallet_record_detail_screen.dart';
import 'package:openim/pages/wallet/record/wallet_record_screen.dart';
import 'package:openim/pages/wallet/widgets/wallet_99chat_tokens.dart';
import 'package:openim_common/openim_common.dart' show Styles;
import '../../../../support/media/deferred_thumbnail_http.dart';
import '../support/wallet_record_test_support.dart';
import 'support/wallet_journal_test_support.dart';
import 'support/wallet_journal_detail_expectations.dart';

// Optional actual-widget screenshots, using only fixture records.
// --dart-define=WALLET_JOURNAL_PREVIEW_DIR=E:/openim/artifacts/wallet-journals
const _directory = String.fromEnvironment('WALLET_JOURNAL_PREVIEW_DIR');
const _detailDirectory =
    String.fromEnvironment('WALLET_JOURNAL_DETAIL_PREVIEW_DIR');
const _listOnly = bool.fromEnvironment('WALLET_JOURNAL_PREVIEW_LIST_ONLY');
const _avatarUrl = 'https://fixture.example.test/wallet-avatar.png';

class _PreviewRepository extends JournalTestRepository
    implements
        WalletJournalCounterpartySource,
        WalletJournalCounterpartyProfileSource {
  @override
  Future<Map<String, String>> getNicknames(Set<String> userIDs) async => {
        if (userIDs.contains('im_fixture_friend')) 'im_fixture_friend': '测试好友',
      };

  @override
  Future<Map<String, WalletJournalCounterpartyProfile>> getProfiles(
          Set<String> userIDs) async =>
      {
        if (userIDs.contains('im_fixture_friend'))
          'im_fixture_friend': const WalletJournalCounterpartyProfile(
              nickname: '测试好友', faceURL: _avatarUrl),
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized()
      .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  setUpAll(() async {
    if (_directory.isEmpty && _detailDirectory.isEmpty) return;
    for (final font in const {
      'WalletJournalPreviewCjk': 'C:/Windows/Fonts/msyh.ttc',
      'WalletJournalPreviewJa': 'C:/Windows/Fonts/msgothic.ttc',
      'WalletJournalPreviewKo': 'C:/Windows/Fonts/malgun.ttf',
      'MaterialIcons':
          'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final file = File(font.value);
      if (file.existsSync()) {
        await (FontLoader(font.key)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes()))))
            .load();
      }
    }
  });
  for (final brightness in Brightness.values) {
    for (final locale in walletRecordLocales) {
      testWidgets(
          'export business receipts ${locale.toLanguageTag()} ${brightness.name}',
          skip: _directory.isEmpty, (tester) async {
        final boundary = GlobalKey();
        final entries = _businessEntries();
        final repository = JournalTestRepository()
          ..respond = (_) async => journalTestPage(entries);
        await _pump(tester, boundary, repository, brightness, locale: locale);
        await settleWalletRecordImages(tester);
        await tester.runAsync(() async {
          final context = tester.element(find.byType(WalletRecordScreen));
          await Future.wait([
            precacheImage(
                const AssetImage('lib/pages/wallet/widgets/assets/trx.png'),
                context),
            precacheImage(
                const AssetImage('lib/pages/wallet/widgets/assets/usdt.webp'),
                context),
          ]);
        });
        await tester.pumpAndSettle();
        final titles = _businessTitles[locale.toLanguageTag()]!;
        for (var index = 0; index < entries.length; index++) {
          final entry = entries[index];
          final row = walletRecordKey('wallet-record-${entry.id}');
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          expect(find.text(titles[index]), findsOneWidget);
          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(
              tester
                  .widget<RawImage>(find.descendant(
                      of: walletRecordKey('wallet-journal-detail-coin'),
                      matching: find.byType(RawImage)))
                  .image,
              isNotNull);
          expect(
              tester
                  .widget<WalletRecordDetailScreen>(
                      find.byType(WalletRecordDetailScreen))
                  .item
                  .journal,
              same(entry));
          expect(
              tester
                  .widget<Text>(walletRecordKey('wallet-journal-detail-title'))
                  .data,
              titles[index]);
          expect(
              tester
                  .widget<Text>(
                      walletRecordKey('wallet-journal-detail-transaction-type'))
                  .data,
              titles[index]);
          expect(walletRecordKey('wallet-journal-direction-explanation'),
              findsNothing);
          expect(find.textContaining('冻结'), findsNothing);
          expect(find.textContaining('解冻'), findsNothing);
          expectCompactJournalDetail();
          expect(tester.takeException(), isNull);
          await _export(tester, boundary,
              '${entry.id}-${locale.toLanguageTag()}-${brightness.name}.png');
          Navigator.of(tester.element(find.byType(WalletRecordDetailScreen)))
              .pop();
          await tester.pumpAndSettle();
        }
        expect(repository.queries, hasLength(1));
      });
    }
    _networkTest('export fixture journals and refund ${brightness.name}',
        skip: _directory.isEmpty, (tester) async {
      final client = DeferredThumbnailHttpClient()..install();
      client.bytes.complete((await tester.runAsync(_avatarFixture))!);
      final boundary = GlobalKey();
      final repository = _PreviewRepository()
        ..respond = (_) async => journalTestPage(_entries());
      await _pump(tester, boundary, repository, brightness);
      await settleWalletRecordImages(tester);
      await _imageFrames(tester);
      final transferAvatar =
          walletRecordKey('wallet-record-counterparty-avatar-fixture-received');
      expect(
          tester
              .widget<RawImage>(find.descendant(
                  of: transferAvatar, matching: find.byType(RawImage)))
              .image,
          isNotNull);
      expect(walletRecordKey('wallet-record-fixture-refund'), findsOneWidget);
      expect(walletRecordKey('wallet-record-source-notice'), findsNothing);
      expect(repository.depositCalls, 0);
      expect(repository.withdrawCalls, 0);
      expect(find.text('转账-测试好友'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _export(
          tester, boundary, 'fixture-journals-${brightness.name}.png');
      if (_listOnly) return;
      await tester.tap(walletRecordKey('wallet-record-fixture-refund'));
      await tester.pumpAndSettle();
      expect(find.byType(WalletRecordDetailScreen), findsOneWidget);
      expect(
          tester
              .widget<Text>(walletRecordKey('wallet-journal-detail-title'))
              .data,
          '红包退回');
      expect(walletRecordKey('wallet-journal-direction-explanation'),
          findsNothing);
      expect(find.textContaining('解冻'), findsNothing);
      expectCompactJournalDetail();
      expect(tester.takeException(), isNull);
      await _export(tester, boundary, 'fixture-refund-${brightness.name}.png');
    });

    _networkTest('export the transfer detail reference card ${brightness.name}',
        skip: _detailDirectory.isEmpty, (tester) async {
      final client = DeferredThumbnailHttpClient()..install();
      client.bytes.complete((await tester.runAsync(_avatarFixture))!);
      final boundary = GlobalKey();
      final repository = _PreviewRepository()
        ..respond = (_) async => journalTestPage([_transferEntry()]);
      await _pump(tester, boundary, repository, brightness);
      await settleWalletRecordImages(tester);
      await tester
          .tap(walletRecordKey('wallet-record-fixture-transfer-detail'));
      await tester.pumpAndSettle();
      await _imageFrames(tester);
      await tester.pumpAndSettle();
      expect(find.text('余额明细详情'), findsOneWidget);
      expect(walletRecordKey('wallet-journal-detail-card'), findsOneWidget);
      expectCompactJournalDetail();
      expect(walletRecordKey('wallet-journal-counterparty-avatar'),
          findsOneWidget);
      expect(
          tester
              .widget<Text>(walletRecordKey('wallet-journal-detail-title'))
              .data,
          '转账-测试好友');
      expect(client.requests, greaterThanOrEqualTo(1));
      expect(
          tester
              .widget<RawImage>(find.descendant(
                  of: walletRecordKey('wallet-journal-counterparty-avatar'),
                  matching: find.byType(RawImage)))
              .image,
          isNotNull);
      expect(tester.takeException(), isNull);
      await _export(
          tester, boundary, 'fixture-transfer-detail-${brightness.name}.png',
          directory: _detailDirectory);
    });
  }
}

Future<void> _imageFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void _networkTest(String name, Future<void> Function(WidgetTester) body,
    {required bool skip}) {
  testWidgets(name, skip: skip, (tester) async {
    try {
      await body(tester);
    } finally {
      DeferredThumbnailHttpClient.restore();
    }
  });
}

Future<void> _pump(WidgetTester tester, GlobalKey boundary,
    JournalTestRepository repository, Brightness brightness,
    {Locale locale = const Locale('zh', 'CN')}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final previousLocale = Get.locale;
  Get.locale = locale;
  addTearDown(() => Get.locale = previousLocale);
  Styles.isDark = brightness == Brightness.dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: locale,
      supportedLocales: walletRecordLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: ThemeData(
          brightness: brightness,
          fontFamily: 'WalletJournalPreviewCjk',
          fontFamilyFallback: const [
            'WalletJournalPreviewJa',
            'WalletJournalPreviewKo',
          ],
          colorScheme: ColorScheme.fromSeed(
              seedColor: AppTokens.accent,
              brightness: brightness,
              surface: AppTokens.appSurface(Styles.isDark)),
          scaffoldBackgroundColor: AppTokens.appBackground(Styles.isDark)),
      builder: (_, child) => RepaintBoundary(key: boundary, child: child!),
      home: WalletRecordScreen(repository: repository),
    ),
  ));
  await tester.pumpAndSettle();
}

const _businessTitles = {
  'zh-CN': ['提现申请', '提现退回', '发出拼手气红包', '红包退回'],
  'zh-TW': ['提現申請', '提現退回', '發出拼手氣紅包', '紅包退回'],
  'en-US': [
    'Withdrawal request',
    'Withdrawal returned',
    'Sent lucky red packet',
    'Red packet returned',
  ],
  'ja-JP': ['出金申請', '出金返金', '運試し紅包を送信', '紅包返金'],
  'ko-KR': ['출금 신청', '출금 반환', '행운 레드패킷 보내기', '레드패킷 반환'],
};

List<WalletJournalEntry> _businessEntries() => [
      for (final event in const [
        ('withdraw-apply', 'USDT', 'withdraw', 'freeze', '11', '提现申请（冻结）'),
        ('withdraw-return', 'TRX', 'withdraw', 'unfreeze', '2', '提现失败退回 · 解冻'),
        ('packet-send', 'USDT', 'packet_lucky', 'freeze', '10', '发红包（冻结）'),
        ('packet-return', 'USDT', 'packet_lucky', 'unfreeze', '8', '红包退回 · 解冻'),
      ])
        WalletJournalEntry.fromJson({
          'id': 'fixture-${event.$1}',
          'currency': event.$2,
          'bizType': event.$3,
          'type': event.$3 == 'withdraw'
              ? event.$4 == 'freeze'
                  ? 'withdraw_freeze'
                  : 'withdraw_refund'
              : event.$4 == 'freeze'
                  ? 'packet_freeze'
                  : 'packet_refund',
          'title': event.$6,
          'direction': event.$4,
          'amount': event.$5,
          'availableDelta': event.$4 == 'freeze' ? '-${event.$5}' : event.$5,
          'frozenDelta': event.$4 == 'freeze' ? event.$5 : '-${event.$5}',
          'assetDelta': '0',
          'beforeAvailable': null,
          'afterAvailable': null,
          'createdAt': DateTime.utc(2026, 10, 6, 5, 59).millisecondsSinceEpoch,
          'bizID': 'fixture-${event.$1}:event',
          'orderID': 'fo_fixture_business_balance_order',
          'counterpartyID': '',
          'groupID': '',
          'remark': '',
          'reason': '',
          'orderStatus': '',
          'chainTxID': '',
          'toAddress':
              event.$3 == 'withdraw' ? 'TFixtureWithdrawalAddress' : '',
        }),
    ];

List<WalletJournalEntry> _entries() {
  final base = DateTime.utc(2026, 10, 6, 4, 40).millisecondsSinceEpoch;
  WalletJournalEntry entry(String id, String title, String direction,
          String amount, String available, String frozen, String asset,
          {String currency = 'USDT',
          String bizType = 'packet_normal',
          String type = 'packet_refund',
          String? before,
          String? after,
          int minute = 0,
          bool groupOrder = false}) =>
      WalletJournalEntry.fromJson({
        'id': 'fixture-$id',
        'currency': currency,
        'bizType': bizType,
        'type': type,
        'title': title,
        'direction': direction,
        'amount': amount,
        'availableDelta': available,
        'frozenDelta': frozen,
        'assetDelta': asset,
        'beforeAvailable': before,
        'afterAvailable': after,
        'createdAt': base - minute * 60000,
        'bizID': 'fixture-$id:event',
        'orderID': groupOrder ? 'fo_fixture_same_packet_order' : '',
        'counterpartyID': bizType == 'transfer' ? 'im_fixture_friend' : '',
        'groupID': groupOrder ? '@fixture_group' : '',
        'remark': groupOrder ? '恭喜发财，大吉大利' : '',
        'reason': bizType == 'admin_adjust' ? '预览夹具：人工调整记录' : '',
        'orderStatus': groupOrder ? 'refunded' : '',
        'chainTxID': '',
      });
  return [
    entry('refund', '红包退回', 'unfreeze', '8', '8', '-8', '0', groupOrder: true),
    entry('settlement', '红包领取扣款', 'expense', '2', '0', '-2', '-2',
        type: 'packet_settlement', minute: 1, groupOrder: true),
    entry('freeze', '发出群红包', 'freeze', '10', '-10', '10', '0',
        type: 'packet_freeze',
        before: '20',
        after: '10',
        minute: 2,
        groupOrder: true),
    entry('received', '收到转账', 'income', '0.123456', '0.123456', '0', '0.123456',
        bizType: 'transfer', type: 'transfer_received', minute: 3),
    entry('adjust', '人工调整', 'income', '99.99', '99.99', '0', '99.99',
        currency: 'BI99',
        bizType: 'admin_adjust',
        type: 'admin_adjust',
        before: '200',
        after: '299.99',
        minute: 4),
    entry('withdraw', '提现扣款', 'expense', '5.321094', '-5.321094', '0',
        '-5.321094',
        currency: 'TRX',
        bizType: 'withdraw',
        type: 'withdraw_settlement',
        minute: 5),
    entry('deposit', '链上充值', 'income', '123.123456', '123.123456', '0',
        '123.123456',
        bizType: 'deposit', type: 'deposit', minute: 6),
  ];
}

Future<void> _export(WidgetTester tester, GlobalKey boundary, String name,
    {String? directory}) async {
  final render =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = Directory(directory ?? _directory)
        ..createSync(recursive: true);
      await File('${output.path}/$name')
          .writeAsBytes(bytes!.buffer.asUint8List());
      await File('${output.path}/preview-notes.txt').writeAsString(
          '实际 WalletRecordScreen / WalletRecordDetailScreen Flutter Widget；所有资金记录及对方用户资料均为测试夹具 fixture，未调用真实 API、真实账号或资金。提现申请、提现退回、发红包、红包退回的业务详情覆盖简体中文、繁体中文、英文、日文、韩文及亮暗主题，逻辑390×844，输出780×1688，使用 Microsoft YaHei、MS Gothic、Malgun Gothic 测试字体。后台原始标题包含冻结/解冻，用户界面仅显示本地化业务名称；数据仍保留原始方向及0资产变化。其他红包夹具同单保留申请10、实际扣款2、退回8三条独立事件，收入支出按assetDelta显示；USDT/TRX保留6位小数，BI99显示99币。详情保留原币金额、时间、业务类型、流水ID、备注和关联账单入口；不显示更多明细、商品说明、付款方式及余额。转账昵称和头像均为模拟资料，列表未知余额--。');
    } finally {
      image.dispose();
    }
  });
}

WalletJournalEntry _transferEntry() => WalletJournalEntry.fromJson({
      'id': 'fixture-transfer-detail',
      'currency': 'USDT',
      'bizType': 'transfer',
      'type': 'transfer_sent',
      'title': '转账支出',
      'direction': 'expense',
      'amount': '3320',
      'availableDelta': '-3320',
      'frozenDelta': '0',
      'assetDelta': '-3320',
      'beforeAvailable': '3366.59',
      'afterAvailable': '46.59',
      'createdAt': DateTime.utc(2026, 10, 6, 4, 40).millisecondsSinceEpoch,
      'bizID': 'fixture-transfer-order:sent',
      'orderID': 'fo_fixture_transfer_order',
      'counterpartyID': 'im_fixture_friend',
      'groupID': '',
      'remark': '转账给测试好友',
      'reason': '',
      'orderStatus': 'completed',
      'chainTxID': '',
    });

Future<List<int>> _avatarFixture() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(
      const Offset(96, 96), 96, Paint()..color = const Color(0xFF198BFF));
  canvas.drawCircle(
      const Offset(96, 66), 32, Paint()..color = const Color(0xFFEFF8FF));
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(38, 111, 116, 85), const Radius.circular(48)),
      Paint()..color = const Color(0xFFB5DFFF));
  final picture = recorder.endRecording();
  final image = await picture.toImage(192, 192);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
