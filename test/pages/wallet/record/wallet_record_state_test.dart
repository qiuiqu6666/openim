import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';

import 'fixtures/wallet_record_fixtures.dart';
import 'support/wallet_record_test_support.dart';

void main() {
  testWidgets(
      'loading waits for both record sources and merges one request each',
      (tester) async {
    final deposits = Completer<List<WalletRecordDto>>();
    final withdrawals = Completer<List<WalletRecordDto>>();
    final repository = RecordTestRepository();
    repository.respondDeposits = () => deposits.future;
    repository.respondWithdrawals = () => withdrawals.future;
    await pumpWalletRecords(tester, repository: repository);
    expect(walletRecordKey('wallet-record-loading'), findsOneWidget);
    expectRecordRequests(repository, 1);
    deposits.complete([walletRecordFixtures[5]]);
    await tester.pump();
    expect(walletRecordKey('wallet-record-loading'), findsOneWidget);
    withdrawals.complete([walletRecordFixtures[2]]);
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-loading'), findsNothing);
    expect(walletRecordKey('wallet-record-october-incoming'), findsOneWidget);
    expect(walletRecordKey('wallet-record-october-outgoing'), findsOneWidget);
    expectRecordRequests(repository, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unavailable backend shows honest empty records and remains refreshable',
      (tester) async {
    await pumpWalletRecords(tester,
        repository: const UnavailableWalletRepository());
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-empty'), findsOneWidget);
    expect(find.text('暂无记录'), findsOneWidget);
    expect(walletRecordKey('wallet-record-error'), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.textContaining('28.50'), findsNothing);
    await refreshWalletRecords(tester);
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty response can be retried by pulling once for both sources',
      (tester) async {
    final repository = RecordTestRepository(records: []);
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-empty'), findsOneWidget);
    expectRecordRequests(repository, 1);
    repository.records = [walletRecordFixtures[5]];
    await refreshWalletRecords(tester);
    await tester.pumpAndSettle();
    expectRecordRequests(repository, 2);
    expect(walletRecordKey('wallet-record-empty'), findsNothing);
    expect(walletRecordKey('wallet-record-october-incoming'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one failed source shows retry and reloads both sources once',
      (tester) async {
    final repository = RecordTestRepository()
      ..respondWithdrawals = () => Future.error(StateError('test failure'));
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-error'), findsOneWidget);
    expect(walletRecordKey('wallet-record-retry'), findsOneWidget);
    expect(walletRecordKey('wallet-record-empty'), findsNothing);
    expectRecordRequests(repository, 1);
    repository.respondWithdrawals = null;
    await tester.tap(walletRecordKey('wallet-record-retry'));
    await tester.pumpAndSettle();
    expectRecordRequests(repository, 2);
    expect(walletRecordKey('wallet-record-error'), findsNothing);
    expect(walletRecordKey('wallet-record-october-incoming'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'error state also allows pull-to-refresh without a separate retry tap',
      (tester) async {
    final repository = RecordTestRepository()
      ..respondDeposits = () => Future.error(StateError('test failure'));
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-error'), findsOneWidget);
    repository.respondDeposits = null;
    await refreshWalletRecords(tester);
    await tester.pumpAndSettle();
    expectRecordRequests(repository, 2);
    expect(walletRecordKey('wallet-record-error'), findsNothing);
    expect(walletRecordKey('wallet-record-october-incoming'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pulling loaded records retains direction filter and performs one reload',
      (tester) async {
    final repository = RecordTestRepository();
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    await tester.tap(walletRecordKey('wallet-record-tab-expenditure'));
    await tester.pumpAndSettle();
    await refreshWalletRecords(tester);
    await tester.pumpAndSettle();
    expectRecordRequests(repository, 2);
    expect(walletRecordKey('wallet-record-october-incoming'), findsNothing);
    expect(walletRecordKey('wallet-record-october-outgoing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final fail in [false, true]) {
    testWidgets(
        'completing a ${fail ? 'failed' : 'successful'} load after disposal is safe',
        (tester) async {
      final deposits = Completer<List<WalletRecordDto>>();
      final withdrawals = Completer<List<WalletRecordDto>>();
      final repository = RecordTestRepository();
      repository.respondDeposits = () => deposits.future;
      repository.respondWithdrawals = () => withdrawals.future;
      await pumpWalletRecords(tester, repository: repository);
      expect(walletRecordKey('wallet-record-loading'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      if (fail) {
        deposits.completeError(StateError('disposed test failure'));
      } else {
        deposits.complete(walletRecordFixtures);
      }
      withdrawals.complete([]);
      await tester.pumpAndSettle();
      expectRecordRequests(repository, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
