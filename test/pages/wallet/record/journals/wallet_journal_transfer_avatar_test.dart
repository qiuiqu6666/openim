import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/wallet/host/wallet_network_image.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_record_mapper.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';
import 'package:openim/pages/wallet/record/wallet_record_tokens.dart';
import 'package:openim/pages/wallet/record/widgets/wallet_record_row.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';
import 'package:openim/pages/wallet/widgets/platform_coin_icon.dart';
import 'package:openim/pages/wallet/widgets/wallet_coin_logo.dart';
import 'package:openim_common/openim_common.dart' show Styles;

import '../../../../support/media/deferred_thumbnail_http.dart';
import 'wallet_journal_entry_test.dart' show journalTestJson;

void main() {
  for (final brightness in Brightness.values) {
    _networkTest(
        'all direct and group transfer directions show the peer image $brightness',
        (tester) async {
      final client = DeferredThumbnailHttpClient()..install();
      client.bytes.complete((await tester.runAsync(() =>
          File('lib/pages/wallet/widgets/assets/trx.png').readAsBytes()))!);
      for (final bizType in const ['transfer', 'group_transfer']) {
        for (final type in const ['transfer_sent', 'transfer_received']) {
          final id = '$bizType-$type-${brightness.name}';
          final url = 'https://fixture.example.test/$id.png';
          final entry = _transfer(id: id, bizType: bizType, type: type);
          final record = entry.toWalletRecord(
              counterpartyNickname: '测试好友', counterpartyAvatarUrl: url);
          await _pump(tester, brightness, record);
          await _imageFrames(tester);
          final avatar = _avatar(id);
          final network = find.descendant(
              of: avatar, matching: find.byType(AppNetworkImage));
          expect(tester.widget<AppNetworkImage>(network).url, url);
          expect(find.descendant(of: avatar, matching: find.byType(ClipOval)),
              findsOneWidget);
          expect(
              tester
                  .widget<RawImage>(find.descendant(
                      of: avatar, matching: find.byType(RawImage)))
                  .image,
              isNotNull);
          expect(tester.getSize(avatar),
              const Size.square(WalletRecordTokens.avatar));
          _expectNoLegacyFace(avatar);
          expect(tester.takeException(), isNull);
        }
      }
      expect(client.requests, 4);
    });

    testWidgets(
        'missing transfer avatars use a circular grapheme or question mark $brightness',
        (tester) async {
      for (final data in const [
        (bizType: 'transfer', nickname: '👩‍💻测试好友', first: '👩‍💻'),
        (bizType: 'group_transfer', nickname: '', first: '?'),
      ]) {
        final entry =
            _transfer(id: 'missing', bizType: data.bizType, currency: 'BI99');
        await _pump(tester, brightness,
            entry.toWalletRecord(counterpartyNickname: data.nickname));
        final avatar = _avatar(entry.id);
        final circle = tester.widget<CircleAvatar>(
            find.descendant(of: avatar, matching: find.byType(CircleAvatar)));
        expect(circle.radius, WalletRecordTokens.avatar / 2);
        expect(find.descendant(of: avatar, matching: find.text(data.first)),
            findsOneWidget);
        expect(
            find.descendant(of: avatar, matching: find.byType(AppNetworkImage)),
            findsNothing);
        _expectNoLegacyFace(avatar);
        expect(tester.takeException(), isNull);
      }
    });

    _networkTest(
        'an avatar read failure keeps the group transfer circular placeholder $brightness',
        (tester) async {
      final client = DeferredThumbnailHttpClient()..install();
      final entry = _transfer(
          id: 'failed-${brightness.name}',
          bizType: 'group_transfer',
          type: 'transfer_received',
          currency: 'BI99');
      await _pump(
          tester,
          brightness,
          entry.toWalletRecord(
              counterpartyNickname: '测试好友',
              counterpartyAvatarUrl:
                  'https://fixture.example.test/${entry.id}.png'));
      expect(client.requests, 1);
      client.bytes.completeError(StateError('fixture avatar read failed'));
      await _imageFrames(tester);
      final avatar = _avatar(entry.id);
      expect(find.descendant(of: avatar, matching: find.text('测')),
          findsOneWidget);
      expect(
          tester
              .widget<CircleAvatar>(find.descendant(
                  of: avatar, matching: find.byType(CircleAvatar)))
              .radius,
          WalletRecordTokens.avatar / 2);
      _expectNoLegacyFace(avatar);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'non-transfer events retain their currency and refund art $brightness',
        (tester) async {
      final deposit = WalletJournalEntry.fromJson(journalTestJson(id: 'deposit')
        ..addAll({
          'bizType': 'deposit',
          'type': 'deposit',
          'direction': 'income',
          'availableDelta': '8',
          'frozenDelta': '0',
          'assetDelta': '8',
          'counterpartyID': 'internal-peer',
        }));
      await _pump(
          tester,
          brightness,
          deposit.toWalletRecord(
              counterpartyNickname: '测试好友',
              counterpartyAvatarUrl:
                  'https://fixture.example.test/ignored.png'));
      expect(tester.widget<WalletCoinLogo>(find.byType(WalletCoinLogo)).type,
          CoinType.usdt);
      expect(
          _asset('lib/pages/wallet/widgets/assets/usdt.webp'), findsOneWidget);
      expect(_avatar(deposit.id), findsNothing);
      expect(find.byType(AppNetworkImage), findsNothing);
      final refund = WalletJournalEntry.fromJson(
          journalTestJson(id: 'refund')..['counterpartyID'] = 'internal-peer');
      await _pump(
          tester,
          brightness,
          refund.toWalletRecord(
              counterpartyNickname: '测试好友',
              counterpartyAvatarUrl:
                  'https://fixture.example.test/ignored.png'));
      expect(
          _asset('lib/pages/wallet/record/assets/refund.png'), findsOneWidget);
      expect(_avatar(refund.id), findsNothing);
      expect(find.byType(AppNetworkImage), findsNothing);
      expect(find.byType(WalletCoinLogo), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

void _expectNoLegacyFace(Finder avatar) {
  for (final type in [Icon, WalletCoinLogo, PlatformCoinIcon]) {
    expect(
        find.descendant(of: avatar, matching: find.byType(type)), findsNothing);
  }
}

Finder _asset(String path) => find.byWidgetPredicate((widget) =>
    widget is Image &&
    widget.image is AssetImage &&
    (widget.image as AssetImage).assetName == path);

Finder _avatar(String id) =>
    find.byKey(ValueKey('wallet-record-counterparty-avatar-$id'));

WalletJournalEntry _transfer(
    {required String id,
    String bizType = 'transfer',
    String type = 'transfer_sent',
    String currency = 'USDT'}) {
  final income = type == 'transfer_received';
  return WalletJournalEntry.fromJson(journalTestJson(id: id)
    ..addAll({
      'currency': currency,
      'bizType': bizType,
      'type': type,
      'direction': income ? 'income' : 'expense',
      'availableDelta': income ? '8' : '-8',
      'frozenDelta': '0',
      'assetDelta': income ? '8' : '-8',
      'counterpartyID': 'internal-peer',
      'groupID': bizType == 'group_transfer' ? '@fixture-group' : '',
    }));
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
  await tester.pumpAndSettle();
}

Future<void> _pump(
    WidgetTester tester, Brightness brightness, WalletRecordDto record) async {
  final previousLocale = Get.locale;
  Get.locale = const Locale('zh', 'CN');
  addTearDown(() => Get.locale = previousLocale);
  Styles.isDark = brightness == Brightness.dark;
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate
    ],
    theme: ThemeData(brightness: brightness),
    home: Scaffold(body: WalletRecordRow(item: record, onTap: () {})),
  ));
  await tester.pumpAndSettle();
}
