import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/host/wallet_network_image.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_counterparty_source.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_page.dart';
import 'package:openim/pages/wallet/record/wallet_record_detail_screen.dart';

import '../support/wallet_record_test_support.dart';
import '../../../../support/media/deferred_thumbnail_http.dart';
import 'support/wallet_journal_test_support.dart';
import 'support/wallet_journal_detail_expectations.dart';
import 'wallet_journal_entry_test.dart' show journalTestJson;

void main() {
  _networkTest(
      'a late profile binds the same avatar to its list row and open detail',
      (tester) async {
    const url = 'https://fixture.example.test/counterparty-avatar.png';
    final client = DeferredThumbnailHttpClient()..install();
    client.bytes.complete((await tester.runAsync(
        () => File('lib/pages/wallet/widgets/assets/trx.png').readAsBytes()))!);
    final profiles = Completer<Map<String, WalletJournalCounterpartyProfile>>();
    final repository = _RichCounterpartyRepository(profiles.future);
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    final row = walletRecordKey('wallet-record-transfer-event');
    final initialAvatar =
        walletRecordKey('wallet-record-counterparty-avatar-transfer-event');
    expect(find.descendant(of: initialAvatar, matching: find.text('?')),
        findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    profiles.complete({
      'internal-peer': const WalletJournalCounterpartyProfile(
          nickname: '头像测试好友', faceURL: url),
    });
    await tester.pumpAndSettle();
    for (var frame = 0; frame < 10; frame++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    final detail = find.byType(WalletRecordDetailScreen);
    expectCompactJournalDetail();
    expect(
        tester
            .widget<WalletRecordDetailScreen>(detail)
            .item
            .counterpartyAvatarUrl,
        url);
    expect(
        tester
            .widget<Text>(walletRecordKey('wallet-journal-detail-title'))
            .data,
        '转账-头像测试好友');
    final avatar = walletRecordKey('wallet-journal-counterparty-avatar');
    expect(
        tester
            .widget<AppNetworkImage>(find.descendant(
                of: avatar, matching: find.byType(AppNetworkImage)))
            .url,
        url);
    final coveredAvatar = find.byKey(
        const ValueKey('wallet-record-counterparty-avatar-transfer-event'),
        skipOffstage: false);
    final coveredNetwork = find.descendant(
        of: coveredAvatar,
        matching: find.byType(AppNetworkImage, skipOffstage: false),
        skipOffstage: false);
    expect(tester.widget<AppNetworkImage>(coveredNetwork).url, url);
    expect(
        tester
            .widget<RawImage>(find.descendant(
                of: coveredAvatar,
                matching: find.byType(RawImage, skipOffstage: false),
                skipOffstage: false))
            .image,
        isNotNull);
    expect(client.requests, greaterThanOrEqualTo(1));
    expect(
        tester
            .widget<RawImage>(
                find.descendant(of: avatar, matching: find.byType(RawImage)))
            .image,
        isNotNull);
    Navigator.of(tester.element(detail)).pop();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<AppNetworkImage>(find.descendant(
                of: initialAvatar, matching: find.byType(AppNetworkImage)))
            .url,
        url);
    expect(find.descendant(of: row, matching: find.text('转账-头像测试好友')),
        findsOneWidget);
    expect(repository.profileReads, hasLength(1));
    expect(repository.queries, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an open detail and its list row update when a nickname arrives',
      (tester) async {
    final names = Completer<Map<String, String>>();
    final repository = _CounterpartyRepository()..names = (_) => names.future;
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    final row = walletRecordKey('wallet-record-transfer-event');
    expect(find.descendant(of: row, matching: find.text('转账')), findsOneWidget);
    expect(repository.lookups, [
      {'internal-peer'},
    ]);
    await tester.tap(row);
    await tester.pumpAndSettle();
    final detail = find.byType(WalletRecordDetailScreen);
    expect(detail, findsOneWidget);
    expectCompactJournalDetail();
    expect(
        tester
            .widget<Text>(walletRecordKey('wallet-journal-detail-title'))
            .data,
        '转账');
    names.complete({'internal-peer': '测试好友'});
    await tester.pumpAndSettle();
    final coveredRow = find.byKey(
        const ValueKey('wallet-record-transfer-event'),
        skipOffstage: false);
    expect(
        find.descendant(
            of: coveredRow,
            matching: find.text('转账-测试好友', skipOffstage: false),
            skipOffstage: false),
        findsOneWidget);
    expect(
        tester
            .widget<Text>(walletRecordKey('wallet-journal-detail-title'))
            .data,
        '转账-测试好友');
    expect(
        tester
            .widget<WalletRecordDetailScreen>(detail)
            .item
            .counterpartyNickname,
        '测试好友');
    Navigator.of(tester.element(detail)).pop();
    await tester.pumpAndSettle();
    expect(find.descendant(of: row, matching: find.text('转账-测试好友')),
        findsOneWidget);
    expect(repository.lookups, hasLength(1));
    expect(repository.queries, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'profile failure retains usable rows and a later closed reply is safe',
      (tester) async {
    final lateNames = Completer<Map<String, String>>();
    final repository = _CounterpartyRepository();
    repository.names = (_) => repository.lookups.length == 1
        ? Future.error(StateError('test nickname failure'))
        : lateNames.future;
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    final row = walletRecordKey('wallet-record-transfer-event');
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('转账')), findsOneWidget);
    expect(walletRecordKey('wallet-record-error'), findsNothing);
    await tester.tap(row);
    await tester.pumpAndSettle();
    final detail = find.byType(WalletRecordDetailScreen);
    expect(
        tester
            .widget<Text>(walletRecordKey('wallet-journal-detail-title'))
            .data,
        '转账');
    Navigator.of(tester.element(detail)).pop();
    await tester.pumpAndSettle();
    await refreshWalletRecords(tester);
    await tester.pumpAndSettle();
    expect(repository.lookups, hasLength(2));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(detail, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    lateNames.complete({'internal-peer': '迟回好友'});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repository.queries, hasLength(2));
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

class _CounterpartyRepository extends JournalTestRepository
    implements WalletJournalCounterpartySource {
  _CounterpartyRepository() {
    respond = (_) async => WalletJournalPage(
          items: [
            WalletJournalEntry.fromJson(journalTestJson(id: 'transfer-event')
              ..addAll({
                'bizType': 'transfer',
                'type': 'transfer_sent',
                'title': '转账支出',
                'direction': 'expense',
                'availableDelta': '-8',
                'frozenDelta': '0',
                'assetDelta': '-8',
                'counterpartyID': 'internal-peer',
              })),
          ],
          limit: 20,
          hasMore: false,
          nextCursor: '',
        );
  }

  final List<Set<String>> lookups = [];
  Future<Map<String, String>> Function(Set<String> users)? names;

  @override
  Future<Map<String, String>> getNicknames(Set<String> userIDs) {
    final users = Set<String>.unmodifiable(userIDs);
    lookups.add(users);
    return names?.call(users) ?? Future.value({});
  }
}

class _RichCounterpartyRepository extends _CounterpartyRepository
    implements WalletJournalCounterpartyProfileSource {
  _RichCounterpartyRepository(this.result);
  final Future<Map<String, WalletJournalCounterpartyProfile>> result;
  final List<Set<String>> profileReads = [];

  @override
  Future<Map<String, WalletJournalCounterpartyProfile>> getProfiles(
      Set<String> userIDs) {
    profileReads.add(Set.unmodifiable(userIDs));
    return result;
  }
}
