import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/record/filters/wallet_record_filters.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_controller.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_filters.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_page.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_query.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_record_mapper.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_source.dart';
import 'package:openim/services/fund_api.dart';

void main() {
  test(
      'cursor pagination keeps identical filters and deduplicates event ID, not order ID',
      () async {
    final source = _Source();
    final controller = _controller(source,
        query: const WalletJournalQuery(
            currency: 'USDT',
            bizType: 'transfer',
            type: 'transfer_received',
            direction: 'income',
            startTime: 1000,
            endTime: 2000,
            limit: 2));
    final head = controller.refresh();
    source.pending[0]
        .complete(_page(['003', '002'], cursor: ' opaque cursor A '));
    await head;
    final more = controller.loadMore();
    expect(source.queries.last.toQueryParameters(), {
      'currency': 'USDT',
      'bizType': 'transfer',
      'type': 'transfer_received',
      'direction': 'income',
      'startTime': 1000,
      'endTime': 2000,
      'limit': 2,
      'cursor': ' opaque cursor A ',
    });
    source.pending[1].complete(_page(['002', '001']));
    await more;
    expect(_ids(controller), ['003', '002', '001']);
    expect(controller.records.every((record) => record.orderNo == 'same-order'),
        isTrue);
    expect(controller.hasMore, isFalse);
    expect(controller.nextCursor, isEmpty);
  });

  test('head and more requests are each deduplicated while pending', () async {
    final source = _Source();
    final controller = _controller(source);
    final head = controller.refresh();
    expect(identical(controller.refresh(), head), isTrue);
    expect(source.queries, hasLength(1));
    source.pending[0].complete(_page(['head'], cursor: 'A'));
    await head;
    final more = controller.loadMore();
    expect(identical(controller.loadMore(), more), isTrue);
    expect(source.queries, hasLength(2));
    source.pending[1].complete(_page(['tail']));
    await more;
  });

  test('refresh invalidates an older more response and its loading state',
      () async {
    final source = _Source();
    final controller = _controller(source);
    await _head(source, controller, ['old-head'], cursor: 'A');
    final staleMore = controller.loadMore();
    final freshHead = controller.refresh();
    expect(controller.refreshing, isTrue);
    expect(controller.loadingMore, isFalse);
    source.pending[2].complete(_page(['fresh-head'], cursor: 'fresh-cursor'));
    await freshHead;
    source.pending[1].complete(_page(['stale-tail'], cursor: 'stale-cursor'));
    await staleMore;
    expect(_ids(controller), ['fresh-head']);
    expect(controller.nextCursor, 'fresh-cursor');
    expect(controller.hasMore, isTrue);
    expect(controller.busy, isFalse);
    expect(controller.moreError, isNull);
  });

  test('filter change interrupts a head and ignores its late failure',
      () async {
    final source = _Source();
    final controller = _controller(source);
    final oldHead = controller.refresh();
    final newHead = controller.updateQuery(
        const WalletJournalQuery(currency: 'TRX', direction: 'expense'));
    expect(source.queries.last.toQueryParameters(),
        {'currency': 'TRX', 'direction': 'expense', 'limit': 20});
    source.pending[1].complete(_page(['new'], currency: 'TRX'));
    await newHead;
    source.pending[0]
        .completeError(const FundApiException(503, 'old filter unavailable'));
    await oldHead;
    expect(_ids(controller), ['new']);
    expect(controller.error, isNull);
    expect(controller.busy, isFalse);
  });

  test('filter change clears old records and cursor and interrupts more',
      () async {
    final source = _Source();
    final controller = _controller(source);
    await _head(source, controller, ['old'], cursor: 'A');
    final oldMore = controller.loadMore();
    final newHead = controller.updateQuery(const WalletJournalQuery(
        currency: 'BI99', type: 'packet_refund', cursor: 'must-be-cleared'));
    expect(controller.records, isEmpty);
    expect(controller.nextCursor, isEmpty);
    expect(controller.hasMore, isFalse);
    expect(controller.loadingMore, isFalse);
    expect(source.queries.last.toQueryParameters(),
        {'currency': 'BI99', 'type': 'packet_refund', 'limit': 20});
    source.pending[1].complete(_page(['old-tail'], cursor: 'B'));
    await oldMore;
    expect(controller.refreshing, isTrue);
    expect(controller.records, isEmpty);
    source.pending[2].complete(_page(['new'], currency: 'BI99'));
    await newHead;
    expect(_ids(controller), ['new']);
    expect(controller.busy, isFalse);
  });

  test(
      'semantically identical query ignores supplied cursor and keeps active head',
      () async {
    final source = _Source();
    final controller =
        _controller(source, query: const WalletJournalQuery(currency: 'USDT'));
    final head = controller.refresh();
    final same = controller.updateQuery(
        const WalletJournalQuery(currency: 'USDT', cursor: 'external-cursor'));
    expect(identical(head, same), isTrue);
    expect(source.queries, hasLength(1));
    expect(controller.query.cursor, isNull);
    source.pending[0].complete(_page(['head']));
    await same;
  });

  test(
      'more failure retains rows and cursor, shows Chinese error, and retries same page',
      () async {
    final source = _Source();
    final controller = _controller(source);
    await _head(source, controller, ['head'], cursor: 'A');
    final failed = controller.loadMore();
    source.pending[1].completeError(StateError('network-private-message'));
    await failed;
    expect(_ids(controller), ['head']);
    expect(controller.nextCursor, 'A');
    expect(controller.hasMore, isTrue);
    expect(controller.error, isNull);
    expect(controller.moreError, '资金请求失败，请稍后重试');
    expect(controller.moreError, isNot(contains('network-private-message')));
    final retry = controller.loadMore();
    expect(source.queries.last.cursor, 'A');
    source.pending[2].complete(_page(['tail']));
    await retry;
    expect(_ids(controller), ['head', 'tail']);
    expect(controller.moreError, isNull);
  });

  test('failed refresh preserves previous history and clears error after retry',
      () async {
    final source = _Source();
    final controller = _controller(source);
    await _head(source, controller, ['old'], cursor: 'A');
    final refresh = controller.refresh();
    source.pending[1].completeError(
        const FundApiException(500, 'private-service-diagnostics'));
    await refresh;
    expect(_ids(controller), ['old']);
    expect(controller.error, '资金服务暂时不可用，请稍后重试');
    expect(controller.busy, isFalse);
    final retry = controller.refresh();
    expect(source.queries.last.cursor, isNull);
    source.pending[2].complete(_page(['replacement']));
    await retry;
    expect(_ids(controller), ['replacement']);
    expect(controller.error, isNull);
  });

  test('unchanged next cursor rejects page atomically and can retry', () async {
    final source = _Source();
    final controller = _controller(source);
    await _head(source, controller, ['head'], cursor: 'A');
    final more = controller.loadMore();
    source.pending[1].complete(_page(['must-not-merge'], cursor: 'A'));
    await more;
    expect(_ids(controller), ['head']);
    expect(controller.nextCursor, 'A');
    expect(controller.moreError, '资金明细数据异常，请重试');
    final retry = controller.loadMore();
    source.pending[2].complete(_page(['tail']));
    await retry;
    expect(_ids(controller), ['head', 'tail']);
  });

  test('cursor cycle A to B to A is rejected before merging or advancing',
      () async {
    final source = _Source();
    final controller = _controller(source);
    await _head(source, controller, ['head'], cursor: 'A');
    final firstMore = controller.loadMore();
    source.pending[1].complete(_page(['middle'], cursor: 'B'));
    await firstMore;
    final cyclicMore = controller.loadMore();
    source.pending[2].complete(_page(['cycle'], cursor: 'A'));
    await cyclicMore;
    expect(_ids(controller), ['head', 'middle']);
    expect(controller.nextCursor, 'B');
    expect(controller.moreError, '资金明细数据异常，请重试');
  });

  test('synchronous first-page failure allows a real retry request', () async {
    final source = _Source()..throwOnNextCall = true;
    final controller = _controller(source);
    await controller.refresh();
    expect(controller.busy, isFalse);
    expect(controller.error, isNotNull);
    final retry = controller.refresh();
    expect(source.queries, hasLength(2));
    source.pending.last.complete(_page(['recovered']));
    await retry;
    expect(_ids(controller), ['recovered']);
    expect(controller.error, isNull);
  });

  test('synchronous more failure allows a real retry request', () async {
    final source = _Source();
    final controller = _controller(source);
    await _head(source, controller, ['head'], cursor: 'A');
    source.throwOnNextCall = true;
    await controller.loadMore();
    expect(controller.busy, isFalse);
    expect(controller.moreError, isNotNull);
    final retry = controller.loadMore();
    expect(source.queries, hasLength(3));
    expect(source.queries.last.cursor, 'A');
    source.pending.last.complete(_page(['tail']));
    await retry;
    expect(_ids(controller), ['head', 'tail']);
    expect(controller.moreError, isNull);
  });

  test(
      'journal parameter errors point to query filters rather than payment fields',
      () async {
    final source = _Source();
    final controller = _controller(source);
    final failed = controller.refresh();
    source.pending[0]
        .completeError(const FundApiException(1001, 'private-invalid-query'));
    await failed;
    expect(controller.error, '资金明细查询参数无效，请检查筛选条件后重试');
    expect(controller.error, isNot(contains('收款人')));
  });

  test('account change rejects late head data and blocks further requests',
      () async {
    final source = _Source();
    var sameAccount = true;
    final controller = _controller(source, isCurrentAccount: () => sameAccount);
    final head = controller.refresh();
    sameAccount = false;
    source.pending[0].complete(_page(['wrong-owner'], cursor: 'A'));
    await head;
    expect(controller.records, isEmpty);
    expect(controller.nextCursor, isEmpty);
    expect(controller.hasMore, isFalse);
    expect(controller.busy, isFalse);
    await controller.refresh();
    await controller.loadMore();
    expect(source.queries, hasLength(1));
  });

  test('account change during more clears already-loaded records', () async {
    final source = _Source();
    var sameAccount = true;
    final controller = _controller(source, isCurrentAccount: () => sameAccount);
    await _head(source, controller, ['old-owner'], cursor: 'A');
    final more = controller.loadMore();
    sameAccount = false;
    source.pending[1].completeError(StateError('old account network failure'));
    await more;
    expect(controller.records, isEmpty);
    expect(controller.nextCursor, isEmpty);
    expect(controller.hasMore, isFalse);
    expect(controller.moreError, isNull);
  });

  test('disposed controller never publishes its pending response', () async {
    final source = _Source();
    final controller = WalletJournalController(
        source: source,
        query: const WalletJournalQuery(),
        isCurrentAccount: () => true);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final head = controller.refresh();
    expect(notifications, 1);
    controller.dispose();
    source.pending[0].complete(_page(['late'], cursor: 'A'));
    await head;
    expect(notifications, 1);
    expect(controller.records, isEmpty);
    await controller.refresh();
    await controller.loadMore();
    expect(source.queries, hasLength(1));
  });

  test(
      'selection maps raw currency, event filters, direction and half-open month into API query',
      () {
    final now = DateTime(2026, 10, 6, 12);
    final selection = WalletRecordSelection(
        coin: '99',
        direction: WalletRecordDirection.income,
        journalBizType: 'packet_normal',
        journalType: 'packet_received',
        journalDirection: 'freeze',
        month: DateTime(2026, 9));
    final query = walletJournalQueryForSelection(selection, now: now);
    expect(query.toQueryParameters(), {
      'currency': 'BI99',
      'bizType': 'packet_normal',
      'type': 'packet_received',
      'direction': 'income',
      'startTime': DateTime(2026, 9).millisecondsSinceEpoch,
      'endTime': DateTime(2026, 10).millisecondsSinceEpoch,
      'limit': 20,
    });
    final fixed = walletJournalQueryForSelection(selection,
        now: now, fixedBizType: 'deposit');
    expect(fixed.bizType, 'deposit');
    expect(fixed.cursor, isNull);
  });

  test(
      'journal calendar grouping reads milliseconds even before year 2001 and at epoch zero',
      () {
    for (final millis in [0, 999000000000]) {
      final entry = _entry('event', createdAt: millis);
      final expected =
          DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
      final record = entry.toWalletRecord();
      expect(walletRecordDateTime(record), expected);
      final groups = walletRecordGroupMonths([record]);
      expect(groups.single.month, DateTime(expected.year, expected.month));
      final selection =
          WalletRecordSelection(month: DateTime(expected.year, expected.month));
      expect(selection.matches(record, now: DateTime(2026, 10, 6)), isTrue);
    }
  });
}

class _Source implements WalletJournalSource {
  final queries = <WalletJournalQuery>[];
  final pending = <Completer<WalletJournalPage>>[];
  bool throwOnNextCall = false;

  @override
  Future<WalletJournalPage> getJournalPage(WalletJournalQuery query) {
    queries.add(query);
    if (throwOnNextCall) {
      throwOnNextCall = false;
      throw StateError('synchronous transport failure');
    }
    final completer = Completer<WalletJournalPage>();
    pending.add(completer);
    return completer.future;
  }
}

WalletJournalController _controller(
  _Source source, {
  WalletJournalQuery query = const WalletJournalQuery(),
  bool Function()? isCurrentAccount,
}) {
  final controller = WalletJournalController(
      source: source,
      query: query,
      isCurrentAccount: isCurrentAccount ?? () => true);
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _head(
    _Source source, WalletJournalController controller, List<String> ids,
    {String cursor = ''}) async {
  final head = controller.refresh();
  source.pending.last.complete(_page(ids, cursor: cursor));
  await head;
}

List<String> _ids(WalletJournalController controller) =>
    controller.records.map((record) => record.id).toList();

WalletJournalPage _page(List<String> ids,
        {String cursor = '', String currency = 'USDT'}) =>
    WalletJournalPage(
      items: ids.map((id) => _entry(id, currency: currency)).toList(),
      limit: 20,
      hasMore: cursor.isNotEmpty,
      nextCursor: cursor,
    );

WalletJournalEntry _entry(String id,
        {String currency = 'USDT', int createdAt = 1791244800000}) =>
    WalletJournalEntry(
      id: id,
      currency: currency,
      bizType: 'transfer',
      type: 'transfer_received',
      title: '收到转账',
      direction: 'income',
      amount: '1',
      availableDelta: '1',
      frozenDelta: '0',
      assetDelta: '1',
      beforeAvailable: null,
      afterAvailable: null,
      createdAt: createdAt,
      bizID: 'biz-$id',
      orderID: 'same-order',
      counterpartyID: '',
      groupID: '',
      remark: '',
      reason: '',
      orderStatus: '',
      chainTxID: '',
    );
