import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/order/wallet_order_events.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_page.dart';
import 'package:openim/pages/wallet/record/wallet_record_screen.dart';

import '../support/wallet_record_test_support.dart';
import 'support/wallet_journal_test_support.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
      'journals load once, retain real dates and bypass deposit history',
      (tester) async {
    final work = Completer<WalletJournalPage>();
    final repository = JournalTestRepository()..respond = (_) => work.future;
    await pumpWalletRecords(tester, repository: repository);
    expect(walletRecordKey('wallet-record-loading'), findsOneWidget);
    expect(walletRecordKey('wallet-record-empty'), findsNothing);
    expect(repository.queries.single.cursor, isNull);
    work.complete(journalTestPage([journalTestEntry('dated-event')]));
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-dated-event'), findsOneWidget);
    expect(walletRecordKey('wallet-record-month-2026-10'), findsOneWidget);
    expect(walletRecordKey('wallet-record-month-unknown'), findsNothing);
    expect(walletRecordKey('wallet-record-source-notice'), findsNothing);
    expect(repository.depositCalls, 0);
    expect(repository.withdrawCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('300 journals paginate without collapsing shared order IDs',
      (tester) async {
    final entries = List.generate(
        300,
        (index) =>
            journalTestEntry('event-${index.toString().padLeft(3, '0')}'));
    final repository = JournalTestRepository();
    repository.respond = (query) async {
      final start = int.parse(query.cursor ?? '0');
      final end = (start + query.limit).clamp(0, entries.length);
      return journalTestPage(entries.sublist(start, end),
          hasMore: end < entries.length, cursor: '$end', limit: query.limit);
    };
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    final seen = <String>{};
    for (var scroll = 0; scroll < 150 && seen.length < 300; scroll++) {
      final rendered = tester.widgetList(find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('wallet-record-event-');
      }));
      for (final row in rendered) {
        final key = (row.key! as ValueKey<String>).value;
        expect(walletRecordKey(key), findsOneWidget,
            reason: 'The shared orderID must not collapse separate events.');
        seen.add(key.replaceFirst('wallet-record-', ''));
      }
      if (seen.length < 300) {
        await tester.drag(
            walletRecordKey('wallet-record-scroll'), const Offset(0, -550));
        await tester.pumpAndSettle();
      }
    }
    expect(seen, hasLength(300));
    final limit = repository.queries.first.limit;
    expect(repository.queries.map((query) => query.cursor).toList(), [
      null,
      for (var start = limit; start < 300; start += limit) '$start',
    ]);
    expect(walletRecordKey('wallet-journal-load-more'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a repeated event ID is removed but same-order events remain',
      (tester) async {
    final repository = JournalTestRepository()
      ..respond = (query) async => query.cursor == null
          ? journalTestPage(
              [journalTestEntry('order-first'), journalTestEntry('repeated')],
              hasMore: true, cursor: 'duplicate-next')
          : journalTestPage(
              [journalTestEntry('repeated'), journalTestEntry('order-last')]);
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    await _loadMore(tester);
    for (final id in ['order-first', 'repeated', 'order-last']) {
      expect(walletRecordKey('wallet-record-$id'), findsOneWidget);
    }
    expect(repository.queries, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling to the end requests the next journal page once',
      (tester) async {
    final more = Completer<WalletJournalPage>();
    final repository = JournalTestRepository();
    repository.respond = (query) => query.cursor == null
        ? Future.value(journalTestPage(
            List.generate(20, (i) => journalTestEntry('scroll-$i')),
            hasMore: true,
            cursor: 'scroll-next'))
        : more.future;
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    for (var attempt = 0;
        attempt < 12 && repository.queries.length == 1;
        attempt++) {
      await tester.drag(
          walletRecordKey('wallet-record-scroll'), const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(repository.queries, hasLength(2));
    expect(repository.queries.last.cursor, 'scroll-next');
    for (var i = 0; i < 3; i++) {
      await tester.drag(
          walletRecordKey('wallet-record-scroll'), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(repository.queries, hasLength(2));
    more.complete(journalTestPage([journalTestEntry('scroll-last')]));
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-scroll-last'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'currency, direction and month queries restart with no old cursor',
      (tester) async {
    final repository = JournalTestRepository()
      ..respond = (query) async => journalTestPage([
            journalTestEntry(query.cursor == null ? 'filtered' : 'next-page',
                currency: 'BI99', direction: query.direction ?? 'income'),
          ], hasMore: query.cursor == null, cursor: 'before-filter');
    await pumpWalletRecords(tester, repository: repository, initialCoin: '99');
    await tester.pumpAndSettle();
    expect(repository.queries.single.currency, 'BI99');
    await _loadMore(tester);
    expect(repository.queries.last.cursor, 'before-filter');
    await tester.tap(walletRecordKey('wallet-record-tab-expenditure'));
    await tester.pumpAndSettle();
    expect(repository.queries.last.direction, 'expense');
    expect(repository.queries.last.currency, 'BI99');
    expect(repository.queries.last.cursor, isNull);
    await tester.tap(walletRecordKey('wallet-record-month-picker-2026-10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-10'));
    await tester.pumpAndSettle();
    final filtered = repository.queries.last;
    expect(filtered.currency, 'BI99');
    expect(filtered.type, isNull);
    expect(filtered.direction, 'expense');
    expect(filtered.cursor, isNull);
    expect(filtered.startTime, DateTime(2026, 10).millisecondsSinceEpoch);
    expect(filtered.endTime, DateTime(2026, 11).millisecondsSinceEpoch);
    await _loadMore(tester);
    expect(repository.queries.last.cursor, 'before-filter');
    expect(repository.queries.last.startTime, filtered.startTime);
    expect(repository.queries.last.endTime, filtered.endTime);
    await tester.tap(walletRecordKey('wallet-record-month-picker-2026-10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部月份'));
    await tester.pumpAndSettle();
    final cleared = repository.queries.last;
    expect(cleared.currency, 'BI99');
    expect(cleared.type, isNull);
    expect(cleared.startTime, isNull);
    expect(cleared.endTime, isNull);
    expect(cleared.direction, 'expense');
    expect(cleared.cursor, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old first page cannot overwrite a newer direction query',
      (tester) async {
    final old = Completer<WalletJournalPage>();
    final current = Completer<WalletJournalPage>();
    final repository = JournalTestRepository()
      ..respond =
          (query) => query.direction == null ? old.future : current.future;
    await pumpWalletRecords(tester, repository: repository);
    await tester.tap(walletRecordKey('wallet-record-tab-income'));
    await tester.pump();
    expect(repository.queries, hasLength(2));
    current.complete(journalTestPage([journalTestEntry('current-income')]));
    await tester.pumpAndSettle();
    old.complete(journalTestPage([journalTestEntry('old-query')]));
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-current-income'), findsOneWidget);
    expect(walletRecordKey('wallet-record-old-query'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late next page cannot append across a filter change',
      (tester) async {
    final more = Completer<WalletJournalPage>();
    final repository = JournalTestRepository();
    repository.respond = (query) {
      if (query.cursor != null) return more.future;
      return Future.value(query.direction == null
          ? journalTestPage([journalTestEntry('before-switch')],
              hasMore: true, cursor: 'old-next')
          : journalTestPage([journalTestEntry('after-switch')]));
    };
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    await _startMore(tester);
    await tester.tap(walletRecordKey('wallet-record-tab-income'));
    await tester.pumpAndSettle();
    more.complete(journalTestPage([journalTestEntry('late-page')]));
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-after-switch'), findsOneWidget);
    expect(walletRecordKey('wallet-record-before-switch'), findsNothing);
    expect(walletRecordKey('wallet-record-late-page'), findsNothing);
    expect(repository.queries.last.cursor, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed next page preserves records and retries its cursor',
      (tester) async {
    var fail = true;
    final repository = JournalTestRepository();
    repository.respond = (query) async {
      if (query.cursor == null) {
        return journalTestPage([journalTestEntry('retained')],
            hasMore: true, cursor: 'retry-next');
      }
      if (fail) throw StateError('test page failure');
      return journalTestPage([journalTestEntry('retry-success')]);
    };
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    await _loadMore(tester);
    expect(walletRecordKey('wallet-record-retained'), findsOneWidget);
    expect(walletRecordKey('wallet-record-error'), findsNothing);
    fail = false;
    await _loadMore(tester);
    expect(repository.queries.map((q) => q.cursor),
        [null, 'retry-next', 'retry-next']);
    expect(walletRecordKey('wallet-record-retained'), findsOneWidget);
    expect(walletRecordKey('wallet-record-retry-success'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed refresh retains filters, rows and next-page cursor',
      (tester) async {
    var failRefresh = false;
    final repository = JournalTestRepository();
    repository.respond = (query) async {
      if (query.cursor != null) {
        return journalTestPage([journalTestEntry('after-refresh')]);
      }
      if (failRefresh) throw StateError('test refresh failure');
      return journalTestPage(
          [journalTestEntry('before-refresh', currency: 'BI99')],
          hasMore: true, cursor: 'retained-next');
    };
    await pumpWalletRecords(tester, repository: repository, initialCoin: '99');
    await tester.pumpAndSettle();
    failRefresh = true;
    await refreshWalletRecords(tester);
    await tester.pumpAndSettle();
    expect(repository.queries, hasLength(2));
    expect(repository.queries.last.currency, 'BI99');
    expect(repository.queries.last.cursor, isNull);
    expect(walletRecordKey('wallet-record-before-refresh'), findsOneWidget);
    expect(walletRecordKey('wallet-record-error'), findsNothing);
    await _loadMore(tester);
    expect(repository.queries.last.currency, 'BI99');
    expect(repository.queries.last.cursor, 'retained-next');
    expect(walletRecordKey('wallet-record-before-refresh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cursor cycle cannot append another copy of the ledger',
      (tester) async {
    final repository = JournalTestRepository()
      ..respond = (query) async => switch (query.cursor) {
            null => journalTestPage([journalTestEntry('cycle-first')],
                hasMore: true, cursor: 'cursor-A'),
            'cursor-A' => journalTestPage([journalTestEntry('cycle-second')],
                hasMore: true, cursor: 'cursor-B'),
            _ => journalTestPage([journalTestEntry('cycle-invalid')],
                hasMore: true, cursor: 'cursor-A'),
          };
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    await _loadMore(tester);
    await _loadMore(tester);
    expect(repository.queries.map((q) => q.cursor),
        [null, 'cursor-A', 'cursor-B']);
    expect(walletRecordKey('wallet-record-cycle-first'), findsOneWidget);
    expect(walletRecordKey('wallet-record-cycle-second'), findsOneWidget);
    expect(walletRecordKey('wallet-record-cycle-invalid'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all includes frozen events, directional queries exclude them',
      (tester) async {
    final entries = [
      journalTestEntry('frozen', direction: 'freeze', type: 'packet_freeze'),
      journalTestEntry('unfrozen',
          direction: 'unfreeze', type: 'packet_refund'),
      journalTestEntry('income', type: 'packet_received'),
      journalTestEntry('expense',
          direction: 'expense', type: 'packet_settlement'),
    ];
    final repository = JournalTestRepository()
      ..respond = (query) async => journalTestPage(entries
          .where((entry) =>
              (query.direction == null || entry.direction == query.direction) &&
              (query.bizType == null || entry.bizType == query.bizType))
          .toList());
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    for (final entry in entries) {
      expect(walletRecordKey('wallet-record-${entry.id}'), findsOneWidget);
    }
    await tester.tap(walletRecordKey('wallet-record-tab-expenditure'));
    await tester.pumpAndSettle();
    expect(repository.queries.last.direction, 'expense');
    expect(walletRecordKey('wallet-record-expense'), findsOneWidget);
    for (final id in ['frozen', 'unfrozen', 'income']) {
      expect(walletRecordKey('wallet-record-$id'), findsNothing);
    }
    await tester.tap(walletRecordKey('wallet-record-tab-income'));
    await tester.pumpAndSettle();
    expect(repository.queries.last.direction, 'income');
    expect(walletRecordKey('wallet-record-income'), findsOneWidget);
    for (final id in ['frozen', 'unfrozen', 'expense']) {
      expect(walletRecordKey('wallet-record-$id'), findsNothing);
    }
    await tester.tap(walletRecordKey('wallet-record-tab-all'));
    await tester.pumpAndSettle();
    expect(repository.queries.last.direction, isNull);
    expect(repository.queries.last.cursor, isNull);
    for (final entry in entries) {
      expect(walletRecordKey('wallet-record-${entry.id}'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  for (final failure in [false, true]) {
    testWidgets(
        'a ${failure ? 'failed' : 'successful'} reply after close is ignored',
        (tester) async {
      final pending = Completer<WalletJournalPage>();
      final repository = JournalTestRepository()
        ..respond = (_) => pending.future;
      await pumpWalletRecords(tester, repository: repository);
      await tester.pumpWidget(const SizedBox.shrink());
      if (failure) {
        pending.completeError(StateError('closed test request'));
      } else {
        pending.complete(journalTestPage([journalTestEntry('closed')]));
      }
      await tester.pumpAndSettle();
      expect(repository.queries, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('session changes reject a late account response and events',
      (tester) async {
    final pending = Completer<WalletJournalPage>();
    final repository = JournalTestRepository()..respond = (_) => pending.future;
    await pumpWalletRecords(tester, repository: repository);
    repository.currentAccount = false;
    pending.complete(journalTestPage([journalTestEntry('previous-owner')]));
    WalletOrderEvents.notifyRecord(accountKey: repository.ownerAccountKey);
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-previous-owner'), findsNothing);
    expect(repository.queries, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('session changes also hide already loaded account records',
      (tester) async {
    final repository = JournalTestRepository()
      ..respond = (_) async => journalTestPage(
          [journalTestEntry('loaded-owner')],
          hasMore: true, cursor: 'old-account-next');
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-loaded-owner'), findsOneWidget);
    repository.currentAccount = false;
    await refreshWalletRecords(tester);
    await tester.pumpAndSettle();
    expect(walletRecordKey('wallet-record-loaded-owner'), findsNothing);
    expect(walletRecordKey('wallet-journal-load-more'), findsNothing);
    expect(repository.queries, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('background and covered routes defer coalesced record updates',
      (tester) async {
    final repository = JournalTestRepository()
      ..respond = (_) async => journalTestPage([journalTestEntry('active')]);
    await pumpWalletRecords(tester, repository: repository);
    await tester.pumpAndSettle();
    WalletOrderEvents.notifyRecord(accountKey: 'test:other');
    await tester.pump();
    expect(repository.queries, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    for (var i = 0; i < 3; i++) {
      WalletOrderEvents.notifyRecord(accountKey: repository.ownerAccountKey);
    }
    await tester.pump();
    expect(repository.queries, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repository.queries, hasLength(2));
    final context = tester.element(find.byType(WalletRecordScreen));
    final navigator = Navigator.of(context);
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered route')))));
    await tester.pumpAndSettle();
    WalletOrderEvents.notifyRecord(accountKey: repository.ownerAccountKey);
    await tester.pump();
    expect(repository.queries, hasLength(2));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(repository.queries, hasLength(3));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _startMore(WidgetTester tester) async {
  final retry = walletRecordKey('wallet-journal-more-retry');
  final regular = walletRecordKey('wallet-journal-load-more');
  final finder = retry.evaluate().isNotEmpty ? retry : regular;
  // Calling the explicit pager control avoids an unrelated auto-scroll fetch
  // while these race/error scenarios deliberately keep a request outstanding.
  final button = tester.widget<ButtonStyleButton>(finder);
  expect(button.onPressed, isNotNull);
  button.onPressed!();
  await tester.pump();
}

Future<void> _loadMore(WidgetTester tester) async {
  await _startMore(tester);
  await tester.pumpAndSettle();
}
