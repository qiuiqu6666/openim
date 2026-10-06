import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';
import 'package:openim/pages/wallet/record/wallet_record_detail_screen.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';
import 'package:openim/pages/wallet/record/widgets/wallet_record_row.dart';
import 'package:openim/pages/wallet/widgets/wallet_99chat_tokens.dart';

import 'support/wallet_journal_detail_expectations.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scenario in const [
      (
        direction: 'income',
        amount: '8',
        available: '2.123456',
        frozen: '0',
        asset: '2.123456',
        display: '+2.123456 USDT',
        title: '用户资金事件'
      ),
      (
        direction: 'expense',
        amount: '8',
        available: '0',
        frozen: '-2.123456',
        asset: '-2.123456',
        display: '-2.123456 USDT',
        title: '用户资金事件'
      ),
      (
        direction: 'freeze',
        amount: '10',
        available: '-10',
        frozen: '10',
        asset: '0',
        display: '10 USDT',
        title: '用户资金事件 · 冻结'
      ),
      (
        direction: 'unfreeze',
        amount: '8',
        available: '8',
        frozen: '-8',
        asset: '0',
        display: '8 USDT',
        title: '用户资金事件 · 解冻'
      ),
      (
        direction: 'neutral',
        amount: '0',
        available: '0',
        frozen: '0',
        asset: '0',
        display: '0 USDT',
        title: '用户资金事件 · 无资产变动'
      ),
    ]) {
      testWidgets(
          '${scenario.direction} row shows original asset meaning in $brightness',
          (tester) async {
        final entry = _entry(
          direction: scenario.direction,
          amount: scenario.amount,
          available: scenario.available,
          frozen: scenario.frozen,
          asset: scenario.asset,
          orderStatus: 'pending',
        );
        final record = _record(entry, status: WalletRecordStatus.pending);
        var tapped = false;
        await _pump(tester,
            brightness: brightness,
            child: Scaffold(
              body: WalletRecordRow(item: record, onTap: () => tapped = true),
            ));
        expect(
            _text(tester, 'wallet-record-amount-event-id'), scenario.display);
        expect(find.text(scenario.title), findsOneWidget);
        expect(_text(tester, 'wallet-record-balance-event-id'), '可用余额 --');
        expect(find.text('处理中'), findsNothing,
            reason:
                'The current order state must not replace the posted event.');
        await tester.tap(find.byKey(const ValueKey('wallet-record-event-id')));
        expect(tapped, isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'compact unfreeze detail explains the event without exposing current order status in $brightness',
        (tester) async {
      final entry = _entry(
          direction: 'unfreeze',
          amount: '8',
          available: '8',
          frozen: '-8',
          asset: '0',
          orderStatus: 'refunded',
          orderID: 'foaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          counterpartyID: 'im_internal_counterparty',
          remark: '恭喜发财，大吉大利',
          reason: '人工复核说明');
      await _pump(tester,
          brightness: brightness,
          child: WalletRecordDetailScreen(item: _record(entry)));
      expect(_text(tester, 'wallet-record-detail-amount'), '8 USDT');
      expect(_text(tester, 'wallet-journal-detail-title'), '用户资金事件 · 解冻');
      expect(find.text('冻结余额转回可用余额，资产总数量不变，不计入收入。'), findsOneWidget);
      expectCompactJournalDetail();
      expect(find.text('订单当前状态'), findsNothing);
      expect(find.text('对方用户ID'), findsNothing);
      expect(find.text('99号ID'), findsNothing);
      expect(_text(tester, 'wallet-journal-detail-transaction-type'), '解冻');
      expect(_text(tester, 'wallet-journal-detail-counterparty-user'), '--');
      expect(_text(tester, 'wallet-journal-detail-remark'), '恭喜发财，大吉大利');
      expect(find.text('已发出'), findsNothing);
      expect(find.text('已收到'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'BI99 row and detail retain exact two-decimal currency in $brightness',
        (tester) async {
      final entry = _entry(
          currency: 'BI99',
          direction: 'income',
          amount: '10.01',
          available: '10.01',
          asset: '10.01',
          before: '100.99',
          after: '111.00');
      await _pump(tester,
          brightness: brightness,
          child: Scaffold(
              body: WalletRecordRow(item: _record(entry), onTap: () {})));
      expect(_text(tester, 'wallet-record-amount-event-id'), '+10.01 99币');
      expect(_text(tester, 'wallet-record-balance-event-id'), '可用余额 111 99币');
      await _pump(tester,
          brightness: brightness,
          child: WalletRecordDetailScreen(item: _record(entry)));
      expect(_text(tester, 'wallet-record-detail-amount'), '+10.01 99币');
      expectCompactJournalDetail();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'long TRX quantities keep six decimals at large text in $brightness',
        (tester) async {
      const quantity = '123456789012345678.123456';
      final entry = _entry(
          currency: 'TRX',
          direction: 'income',
          amount: quantity,
          available: quantity,
          asset: quantity,
          before: '0',
          after: quantity);
      await _pump(tester,
          brightness: brightness,
          size: const Size(320, 700),
          textScale: 3,
          child: WalletRecordDetailScreen(item: _record(entry)));
      expect(_text(tester, 'wallet-record-detail-amount'), '+$quantity TRX');
      expectCompactJournalDetail();
      final amount = find.byKey(const ValueKey('wallet-record-detail-amount'));
      final rect = tester.getRect(amount);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      await tester.ensureVisible(
          find.byKey(const ValueKey('wallet-journal-detail-journal-id')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'journal timestamp is strictly Unix milliseconds and event copy retains its full ID',
      (tester) async {
    const millis = 999000000000;
    final entry = _entry(
        id: '670203000000000000000001-full-ledger-event-ID',
        createdAt: millis,
        orderID: 'foaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(tester, child: WalletRecordDetailScreen(item: _record(entry)));
    final local =
        DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final expected =
        '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    expect(_text(tester, 'wallet-journal-detail-time'), expected);
    expect(_text(tester, 'wallet-journal-detail-journal-id'), entry.id);
    expectCompactJournalDetail();
    final copy = find.byKey(const ValueKey('wallet-journal-copy-journal-id'));
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pump();
    expect(copied, entry.id);
    expect(tester.takeException(), isNull);
  });
}

String _text(WidgetTester tester, String key) => tester
    .widget<Text>(find.byKey(ValueKey(key)))
    .data!
    .replaceAll('\u200B', '');

WalletJournalEntry _entry({
  String id = 'event-id',
  String currency = 'USDT',
  String direction = 'income',
  String amount = '8',
  String available = '8',
  String frozen = '0',
  String asset = '8',
  String? before,
  String? after,
  String orderStatus = '',
  String orderID = '',
  String counterpartyID = '',
  String remark = '',
  String reason = '',
  int createdAt = 1791244800000,
}) =>
    WalletJournalEntry.fromJson({
      'id': id,
      'currency': currency,
      'bizType': 'admin_adjust',
      'type': 'admin_adjust',
      'title': '用户资金事件',
      'direction': direction,
      'amount': amount,
      'availableDelta': available,
      'frozenDelta': frozen,
      'assetDelta': asset,
      'beforeAvailable': before,
      'afterAvailable': after,
      'createdAt': createdAt,
      'bizID': 'biz-event',
      'orderID': orderID,
      'counterpartyID': counterpartyID,
      'groupID': '',
      'remark': remark,
      'reason': reason,
      'orderStatus': orderStatus,
      'chainTxID': '',
    });

WalletRecordDto _record(WalletJournalEntry entry,
        {WalletRecordStatus status = WalletRecordStatus.success}) =>
    WalletRecordDto(
      id: entry.id,
      type: WalletRecordType.transfer,
      status: status,
      title: entry.title,
      subTitle: '',
      amount: entry.amount,
      coin: entry.currency == 'BI99' ? '99' : entry.currency,
      income: entry.direction == 'income',
      network: '',
      fee: '',
      payer: '',
      payee: '',
      addr: '',
      hash: '',
      block: '',
      time: '',
      orderNo: entry.orderID,
      memo: '',
      journal: entry,
    );

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  Brightness brightness = Brightness.light,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: ThemeData(
          brightness: brightness,
          colorScheme: ColorScheme.fromSeed(
              seedColor: AppTokens.accent, brightness: brightness)),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: child,
    ),
  ));
  await tester.pumpAndSettle();
}
