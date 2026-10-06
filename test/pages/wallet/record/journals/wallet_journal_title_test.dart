import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/wallet/host/wallet_i18n.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_presentation.dart';
import 'package:openim/pages/wallet/record/wallet_record_detail_screen.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';
import 'package:openim/pages/wallet/record/wallet_record_screen.dart';
import 'package:openim/pages/wallet/record/widgets/wallet_record_row.dart';

import 'support/wallet_journal_test_support.dart';

void main() {
  setUp(() {
    final old = Get.locale;
    Get.locale = const Locale('zh', 'CN');
    addTearDown(() => Get.locale = old);
  });
  for (final packet in const [
    (biz: 'packet_normal', label: '普通红包'),
    (biz: 'packet_lucky', label: '拼手气红包'),
    (biz: 'packet_exclusive', label: '专属红包'),
  ]) {
    for (final type in const [
      'packet_sent',
      'packet_freeze',
      'packet_received'
    ]) {
      final verb = type == 'packet_received' ? '收到' : '发出';
      test('${packet.biz} $type uses exact named packet title', () {
        final entry = _entry(packet.biz, type, title: '后台通用红包标题');
        expect(
            walletJournalTitle(entry, AppI18n.current), '$verb${packet.label}');
      });
    }
    test('${packet.biz} settlement retains actual posted deduction', () {
      final entry = _entry(packet.biz, 'packet_settlement', title: '红包领取扣款');
      expect(walletJournalTitle(entry, AppI18n.current), '红包领取扣款');
    });
    test('${packet.biz} refund displays its business meaning', () {
      final entry = _entry(packet.biz, 'packet_refund', title: '红包退回 · 解冻');
      expect(walletJournalTitle(entry, AppI18n.current), '红包退回');
    });
  }
  for (final biz in const ['transfer', 'group_transfer']) {
    for (final type in const ['transfer_sent', 'transfer_received']) {
      test('$biz $type uses real nickname and trims it', () {
        final entry = _entry(biz, type, title: '带有内部ID的旧标题');
        expect(
            walletJournalTitle(entry, AppI18n.current,
                counterpartyNickname: '  小雨  '),
            '转账-小雨');
        expect(
            walletJournalTitle(entry, AppI18n.current,
                counterpartyNickname: '阿秋 🎈'),
            '转账-阿秋 🎈');
      });
      test('$biz $type without nickname never falls back to an internal ID',
          () {
        final entry = _entry(biz, type, title: '转账-im_should_never_show');
        expect(walletJournalTitle(entry, AppI18n.current), '转账');
        expect(
            walletJournalTitle(entry, AppI18n.current,
                counterpartyNickname: '  '),
            '转账');
      });
    }
  }
  test('unknown packet business uses a generic packet title', () {
    final entry = _entry('packet_future', 'packet_freeze', title: '新红包事件');
    expect(walletJournalTitle(entry, AppI18n.current), '发出红包');
  });
  test('non-transfer event keeps its own title despite an available nickname',
      () {
    final entry = _entry('live_tip', 'live_tip_received', title: '收到直播打赏');
    expect(
        walletJournalTitle(entry, AppI18n.current, counterpartyNickname: '小雨'),
        '收到直播打赏');
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'withdrawal and packet events remain separate clickable receipts with business labels in $brightness',
        (tester) async {
      final events = [
        (
          entry: _entry('withdraw', 'withdraw_freeze',
              id: 'withdraw-apply', title: '提现申请（冻结）', amount: '11'),
          title: '提现申请',
          amount: '11 USDT',
        ),
        (
          entry: _entry('withdraw', 'withdraw_refund',
              id: 'withdraw-return', title: '提现失败退回 · 解冻', currency: 'TRX'),
          title: '提现退回',
          amount: '2 TRX',
        ),
        (
          entry: _entry('packet_lucky', 'packet_freeze',
              id: 'packet-send', title: '发红包（冻结）', amount: '10'),
          title: '发出拼手气红包',
          amount: '10 USDT',
        ),
        (
          entry: _entry('packet_lucky', 'packet_refund',
              id: 'packet-return', title: '红包退回 · 解冻', amount: '8'),
          title: '红包退回',
          amount: '8 USDT',
        ),
      ];
      final repository = JournalTestRepository()
        ..respond = (_) async =>
            journalTestPage(events.map((event) => event.entry).toList());
      await _pump(tester,
          brightness: brightness,
          child: WalletRecordScreen(repository: repository));
      expect(repository.queries, hasLength(1));
      for (final event in events) {
        expect(find.byKey(ValueKey('wallet-record-${event.entry.id}')),
            findsOneWidget);
      }
      expect(find.textContaining('冻结'), findsNothing);
      expect(find.textContaining('解冻'), findsNothing);
      for (final event in events) {
        final row = find.byKey(ValueKey('wallet-record-${event.entry.id}'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        final receipt = tester.widget<WalletRecordDetailScreen>(
            find.byType(WalletRecordDetailScreen));
        expect(receipt.item.journal, same(event.entry));
        _expectDetailTitle(tester, event.title);
        expect(
            tester
                .widget<Text>(
                    find.byKey(const ValueKey('wallet-record-detail-amount')))
                .data!
                .replaceAll('\u200B', ''),
            event.amount);
        expect(
            tester
                .widget<Text>(find.byKey(
                    const ValueKey('wallet-journal-detail-transaction-type')))
                .data,
            event.title);
        expect(find.textContaining('冻结'), findsNothing);
        expect(find.textContaining('解冻'), findsNothing);
        expect(
            find.byKey(const ValueKey('wallet-journal-direction-explanation')),
            findsNothing);
        expect(event.entry.assetDeltaUnits, BigInt.zero);
        Navigator.of(tester.element(find.byType(WalletRecordDetailScreen)))
            .pop();
        await tester.pumpAndSettle();
      }
      expect(repository.queries, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('row and detail both receive resolved nickname in $brightness',
        (tester) async {
      final record = _record(
          _entry('group_transfer', 'transfer_received', title: '收到群转账'),
          nickname: ' 小雨 ');
      await _pump(tester,
          brightness: brightness,
          child: Scaffold(body: WalletRecordRow(item: record, onTap: () {})));
      expect(find.text('转账-小雨'), findsOneWidget);
      expect(find.textContaining('im_should_never_show'), findsNothing);
      await _pump(tester,
          brightness: brightness,
          child: WalletRecordDetailScreen(item: record));
      _expectDetailTitle(tester, '转账-小雨');
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        'packet row and receipt show the business without reserve terminology in $brightness',
        (tester) async {
      final record =
          _record(_entry('packet_lucky', 'packet_freeze', title: '冻结群红包'));
      await _pump(tester,
          brightness: brightness,
          child: Scaffold(body: WalletRecordRow(item: record, onTap: () {})));
      expect(find.text('发出拼手气红包'), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-journal-direction-event')),
          findsNothing);
      expect(find.textContaining('冻结'), findsNothing);
      await _pump(tester,
          brightness: brightness,
          child: WalletRecordDetailScreen(item: record));
      _expectDetailTitle(tester, '发出拼手气红包');
      expect(
          tester
              .widget<Text>(find.byKey(
                  const ValueKey('wallet-journal-detail-transaction-type')))
              .data,
          '发出拼手气红包');
      expect(find.byKey(const ValueKey('wallet-journal-direction-explanation')),
          findsNothing);
      expect(find.textContaining('冻结'), findsNothing);
      expect(record.journal!.direction, 'freeze');
      expect(record.journal!.assetDeltaUnits, BigInt.zero);
      expect(tester.takeException(), isNull);
    });
  }
}

void _expectDetailTitle(WidgetTester tester, String title) {
  final field = find.byKey(const ValueKey('wallet-journal-detail-title'));
  expect(field, findsOneWidget);
  expect(tester.widget<Text>(field).data, title);
  expect(find.byKey(const ValueKey('wallet-journal-detail-description')),
      findsNothing);
}

WalletJournalEntry _entry(String biz, String type,
    {required String title,
    String id = 'event',
    String amount = '2',
    String currency = 'USDT'}) {
  final direction = switch (type) {
    'packet_freeze' || 'withdraw_freeze' => 'freeze',
    'packet_refund' || 'withdraw_refund' => 'unfreeze',
    'packet_sent' || 'packet_settlement' || 'transfer_sent' => 'expense',
    _ => 'income',
  };
  final available =
      direction == 'expense' || direction == 'freeze' ? '-$amount' : amount;
  final frozen = direction == 'freeze'
      ? amount
      : direction == 'unfreeze'
          ? '-$amount'
          : '0';
  final asset =
      direction == 'freeze' || direction == 'unfreeze' ? '0' : available;
  return WalletJournalEntry(
    id: id,
    currency: currency,
    bizType: biz,
    type: type,
    title: title,
    direction: direction,
    amount: amount,
    availableDelta: available,
    frozenDelta: frozen,
    assetDelta: asset,
    beforeAvailable: null,
    afterAvailable: null,
    createdAt: 1791244800000,
    bizID: 'biz-event',
    orderID: '',
    counterpartyID: 'im_should_never_show',
    groupID: '',
    remark: '',
    reason: '',
    orderStatus: '',
    chainTxID: '',
  );
}

WalletRecordDto _record(WalletJournalEntry entry, {String nickname = ''}) =>
    WalletRecordDto(
      id: entry.id,
      type: WalletRecordType.transfer,
      status: WalletRecordStatus.success,
      title: entry.title,
      subTitle: '',
      amount: entry.amount,
      coin: entry.currency,
      income: entry.direction == 'income',
      network: '',
      fee: '',
      payer: '',
      payee: '',
      addr: '',
      hash: '',
      block: '',
      time: '',
      orderNo: '',
      memo: '',
      journal: entry,
      counterpartyNickname: nickname,
    );

Future<void> _pump(WidgetTester tester,
    {required Widget child, required Brightness brightness}) async {
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
      theme: ThemeData(brightness: brightness),
      home: child,
    ),
  ));
  await tester.pumpAndSettle();
}
