import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/wallet/host/wallet_network_image.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_record_mapper.dart';
import 'package:openim/pages/wallet/record/journals/widgets/wallet_journal_detail_body.dart';
import 'package:openim/pages/wallet/record/wallet_record_detail_screen.dart';
import 'package:openim/pages/wallet/widgets/wallet_99chat_tokens.dart';
import 'package:openim_common/openim_common.dart' show Styles;

import '../../../../support/media/deferred_thumbnail_http.dart';
import 'support/wallet_journal_detail_expectations.dart';
import 'wallet_journal_entry_test.dart' show journalTestJson;

const _avatarUrl = 'https://fixture.example.test/journal-avatar.png';
const _journalID = '670203000000000000000001-full-ledger-event-ID';

void main() {
  for (final scenario in const [
    (biz: 'deposit', type: 'deposit', label: '转入地址'),
    (biz: 'deposit_reversal', type: 'deposit_reversal', label: '转入地址'),
    (biz: 'withdraw', type: 'withdraw_freeze', label: '提现地址'),
    (biz: 'withdraw', type: 'withdraw_settlement', label: '提现地址'),
    (biz: 'withdraw', type: 'withdraw_refund', label: '提现地址'),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          '${scenario.type} shows historical chain details in $brightness',
          (tester) async {
        String? copied;
        final launches = <MethodCall>[];
        const launcherChannel =
            MethodChannel('plugins.flutter.io/url_launcher');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform,
            (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
        addTearDown(() =>
            messenger.setMockMethodCallHandler(SystemChannels.platform, null));
        messenger.setMockMethodCallHandler(launcherChannel, (call) async {
          launches.add(call);
          return true;
        });
        addTearDown(
            () => messenger.setMockMethodCallHandler(launcherChannel, null));
        const hash =
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
        const address = 'TJournalHistoricalReceivingAddress001';
        final entry = WalletJournalEntry.fromJson(journalTestJson()
          ..addAll({
            'bizType': scenario.biz,
            'type': scenario.type,
            if (scenario.type == 'withdraw_freeze') ...{
              'title': '提现申请（冻结）',
              'direction': 'freeze',
              'availableDelta': '-8',
              'frozenDelta': '8',
            },
            if (scenario.type == 'withdraw_settlement') ...{
              'direction': 'expense',
              'availableDelta': '0',
              'frozenDelta': '-8',
              'assetDelta': '-8',
            },
            if (scenario.type == 'withdraw_refund') 'title': '提现失败退回 · 解冻',
            'chainTxID': hash,
            'fromAddress': 'TOriginalSendingAddress',
            'toAddress': address,
          }));
        await _pump(tester,
            brightness: brightness,
            textScale: 2,
            child: Scaffold(
                body: WalletJournalDetailBody(
                    entry: entry,
                    coinLogo: const Icon(Icons.currency_exchange))));
        expect(_text(tester, 'wallet-journal-detail-chain-tx-id'), hash);
        expect(_text(tester, 'wallet-journal-detail-to-address'), address);
        expect(find.text(scenario.label), findsOneWidget);
        expect(_key('wallet-journal-detail-counterparty-user'), findsNothing);
        expect(
            _key('wallet-journal-detail-counterparty-account'), findsNothing);
        for (final field in ['chain-tx-id', 'to-address']) {
          final copy = _key('wallet-journal-copy-$field');
          await tester.ensureVisible(copy);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(_key('wallet-journal-detail-$field'));
          expect(bounds.right, lessThanOrEqualTo(320));
          await tester.tap(copy);
          await tester.pump();
          expect(copied, field == 'chain-tx-id' ? hash : address);
          expect(launches, isEmpty);
          expect(tester.takeException(), isNull);
        }
        final link = _key('wallet-journal-open-chain-tx-id');
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();
        await tester.tap(link);
        await tester.pump();
        expect(launches, hasLength(1));
        expect(launches.single.method, 'launch');
        final arguments = launches.single.arguments as Map;
        expect(arguments['url'],
            'https://tronscan.org/transaction/$hash/overview');
        expect(arguments['useWebView'], isFalse);
        expect(arguments['useSafariVC'], isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('unbroadcast withdrawal shows address without an invented hash',
      (tester) async {
    final entry = WalletJournalEntry.fromJson(journalTestJson()
      ..addAll({
        'bizType': 'withdraw',
        'type': 'withdraw_freeze',
        'direction': 'freeze',
        'availableDelta': '-8',
        'frozenDelta': '8',
        'toAddress': 'THistoricalWithdrawal'
      }));
    await _pump(tester,
        child: Scaffold(
            body: WalletJournalDetailBody(
                entry: entry, coinLogo: const Icon(Icons.currency_exchange))));
    expect(_key('wallet-journal-detail-chain-tx-id'), findsNothing);
    expect(_text(tester, 'wallet-journal-detail-to-address'),
        'THistoricalWithdrawal');
  });

  testWidgets(
      'missing chain fields are hidden and internal events do not show chain fields',
      (tester) async {
    for (final biz in [
      'deposit',
      'withdraw',
      'transfer',
      'packet_normal',
      'swap'
    ]) {
      final internal = !const {'deposit', 'withdraw'}.contains(biz);
      final entry = WalletJournalEntry.fromJson(journalTestJson()
        ..addAll({
          'bizType': biz,
          'chainTxID': internal ? 'ignored-hash' : '',
          'toAddress': internal ? 'ignored-address' : ''
        }));
      await _pump(tester,
          child: Scaffold(
              body: WalletJournalDetailBody(
                  entry: entry,
                  coinLogo: const Icon(Icons.currency_exchange))));
      expect(_key('wallet-journal-detail-chain-tx-id'), findsNothing);
      expect(_key('wallet-journal-detail-to-address'), findsNothing);
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'one detail card preserves transfer data at 320px 2x $brightness',
        (tester) async {
      final entry = _transfer();
      await _pump(tester,
          brightness: brightness,
          textScale: 2,
          child: WalletRecordDetailScreen(
              item: entry.toWalletRecord(counterpartyNickname: '测试好友')));
      expect(find.text('余额明细详情'), findsOneWidget);
      final card = _key('wallet-journal-detail-card');
      expect(card, findsOneWidget);
      expect(_text(tester, 'wallet-journal-detail-title'), '转账-测试好友');
      expect(_text(tester, 'wallet-record-detail-amount'), '-3320.123456 USDT');
      expect(_text(tester, 'wallet-journal-detail-transaction-type'), '支出');
      expect(_text(tester, 'wallet-journal-detail-counterparty-user'), '测试好友');
      expect(_text(tester, 'wallet-journal-detail-journal-id'), _journalID);
      expect(_text(tester, 'wallet-journal-detail-remark'), '转账备注夹具');
      expectCompactJournalDetail();
      expect(find.text('对方账号'), findsNothing);
      expect(find.textContaining('¥'), findsNothing);
      expect(_key('wallet-journal-detail-asset-delta'), findsNothing);
      expect(_key('wallet-journal-detail-counterparty-id'), findsNothing);
      for (final key in [
        'wallet-record-detail-amount',
        'wallet-journal-detail-journal-id',
        'wallet-journal-detail-remark',
      ]) {
        final field = _key(key);
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(field);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      }
      expect(tester.getRect(card).width, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'packet reserve and return keep exact amounts without ledger terminology in $brightness',
        (tester) async {
      for (final freeze in const [false, true]) {
        final json = journalTestJson();
        if (freeze) {
          json.addAll({
            'type': 'packet_freeze',
            'direction': 'freeze',
            'availableDelta': '-8',
            'frozenDelta': '8',
          });
        }
        final entry = WalletJournalEntry.fromJson(json);
        await _pump(tester,
            brightness: brightness,
            child: WalletRecordDetailScreen(item: entry.toWalletRecord()));
        expect(_text(tester, 'wallet-record-detail-amount'), '8 USDT');
        final title = freeze ? '发出普通红包' : '红包退回';
        expect(_text(tester, 'wallet-journal-detail-title'), title);
        expect(_text(tester, 'wallet-journal-detail-transaction-type'), title);
        expect(_key('wallet-journal-direction-explanation'), findsNothing);
        expect(find.textContaining('冻结'), findsNothing);
        expect(find.textContaining('解冻'), findsNothing);
        expect(entry.assetDeltaUnits, BigInt.zero);
        expect(find.textContaining('¥'), findsNothing);
        expectCompactJournalDetail();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('the associated-order row requires both an order and a callback',
      (tester) async {
    var opened = 0;
    Future<void> mount(String orderID, VoidCallback? onOpenOrder) =>
        _pump(tester,
            child: Scaffold(
                body: WalletJournalDetailBody(
                    entry: _transfer(orderID: orderID),
                    coinLogo: const Icon(Icons.currency_exchange),
                    counterpartyNickname: '测试好友',
                    onOpenOrder: onOpenOrder)));
    await mount('', () => opened++);
    expect(_key('wallet-journal-open-order'), findsNothing);
    await mount('test-order', null);
    expect(_key('wallet-journal-open-order'), findsNothing);
    await mount('test-order', () => opened++);
    final link = _key('wallet-journal-open-order');
    expect(link, findsOneWidget);
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pump();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  _networkTest(
      'a real counterpart avatar URL is used and decode failure falls back',
      (tester) async {
    final client = DeferredThumbnailHttpClient()..install();
    await _pump(tester,
        child: Scaffold(
            body: WalletJournalDetailBody(
                entry: _transfer(),
                coinLogo: const Icon(Icons.currency_exchange),
                counterpartyNickname: '测试好友',
                counterpartyAvatarUrl: _avatarUrl)));
    final avatar = _key('wallet-journal-counterparty-avatar');
    expect(avatar, findsOneWidget);
    final network =
        find.descendant(of: avatar, matching: find.byType(AppNetworkImage));
    expect(tester.widget<AppNetworkImage>(network).url, _avatarUrl);
    expect(client.requests, 1);
    client.bytes.completeError(StateError('fixture avatar failed'));
    await _imageFrames(tester);
    expect(avatar, findsOneWidget);
    expect(
        find.descendant(of: avatar, matching: find.text('测')), findsOneWidget);
    expect(_text(tester, 'wallet-journal-detail-title'), '转账-测试好友');
    expect(tester.takeException(), isNull);
  });

  _networkTest('the supplied avatar image can resolve without any real HTTP',
      (tester) async {
    final client = DeferredThumbnailHttpClient()..install();
    client.bytes.complete((await tester.runAsync(
        () => File('lib/pages/wallet/widgets/assets/trx.png').readAsBytes()))!);
    await _pump(tester,
        child: Scaffold(
            body: WalletJournalDetailBody(
                entry: _transfer(),
                coinLogo: const Icon(Icons.currency_exchange),
                counterpartyNickname: '测试好友',
                counterpartyAvatarUrl: _avatarUrl)));
    await _imageFrames(tester);
    final avatar = _key('wallet-journal-counterparty-avatar');
    expect(avatar, findsOneWidget);
    expect(find.descendant(of: avatar, matching: find.byType(RawImage)),
        findsOneWidget);
    expect(client.requests, 1);
    expect(tester.takeException(), isNull);
  });
}

void _networkTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      DeferredThumbnailHttpClient.restore();
    }
  });
}

Future<void> _imageFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!.replaceAll('\u200B', '');

WalletJournalEntry _transfer({String orderID = 'test-order'}) =>
    WalletJournalEntry.fromJson(journalTestJson(id: _journalID)
      ..addAll({
        'bizType': 'transfer',
        'type': 'transfer_sent',
        'title': '转账支出',
        'direction': 'expense',
        'amount': '3320.123456',
        'availableDelta': '-3320.123456',
        'frozenDelta': '0',
        'assetDelta': '-3320.123456',
        'beforeAvailable': '3366.713456',
        'afterAvailable': '46.59',
        'orderID': orderID,
        'counterpartyID': 'internal-counterparty',
        'groupID': '',
        'remark': '转账备注夹具',
        'orderStatus': 'completed',
      }));

Future<void> _pump(WidgetTester tester,
    {required Widget child,
    Brightness brightness = Brightness.light,
    double textScale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final previousLocale = Get.locale;
  Get.locale = const Locale('zh', 'CN');
  addTearDown(() => Get.locale = previousLocale);
  Styles.isDark = brightness == Brightness.dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
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
