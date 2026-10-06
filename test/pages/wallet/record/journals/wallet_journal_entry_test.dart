import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_page.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_query.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_record_mapper.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';

Map<String, dynamic> journalTestJson({String id = 'event-refund'}) => {
      'id': id,
      'currency': 'USDT',
      'bizType': 'packet_normal',
      'type': 'packet_refund',
      'title': '红包退回',
      'direction': 'unfreeze',
      'amount': '8',
      'availableDelta': '8',
      'frozenDelta': '-8',
      'assetDelta': '0',
      'beforeAvailable': null,
      'afterAvailable': null,
      'createdAt': 1791244800000,
      'bizID': 'packet-order:refund',
      'orderID': 'packet-order',
      'counterpartyID': '',
      'groupID': '@group',
      'remark': '恭喜发财，大吉大利',
      'reason': '',
      'orderStatus': 'refunded',
      'chainTxID': '',
    };

void main() {
  test('refund preserves nullable old balances and all original event fields',
      () {
    final entry = WalletJournalEntry.fromJson(journalTestJson());
    expect(entry.id, 'event-refund');
    expect(entry.currency, 'USDT');
    expect(entry.bizType, 'packet_normal');
    expect(entry.type, 'packet_refund');
    expect(entry.title, '红包退回');
    expect(entry.direction, 'unfreeze');
    expect(entry.amount, '8');
    expect(entry.availableDelta, '8');
    expect(entry.frozenDelta, '-8');
    expect(entry.assetDelta, '0');
    expect(entry.beforeAvailable, isNull);
    expect(entry.afterAvailable, isNull);
    expect(entry.createdAt, 1791244800000);
    expect(entry.bizID, 'packet-order:refund');
    expect(entry.orderID, 'packet-order');
    expect(entry.counterpartyID, isEmpty);
    expect(entry.groupID, '@group');
    expect(entry.remark, '恭喜发财，大吉大利');
    expect(entry.reason, isEmpty);
    expect(entry.orderStatus, 'refunded');
    expect(entry.chainTxID, isEmpty);
    expect(entry.availableDeltaUnits, BigInt.from(8000000));
    expect(entry.frozenDeltaUnits, -BigInt.from(8000000));
    expect(entry.assetDeltaUnits, BigInt.zero);
  });

  test(
      'chain transaction fields preserve the event hash and historical addresses',
      () {
    final entry = WalletJournalEntry.fromJson(journalTestJson()
      ..addAll({
        'chainTxID': 'event-chain-hash',
        'fromAddress': 'historical-source-address',
        'toAddress': 'historical-destination-address',
      }));
    expect(entry.chainTxID, 'event-chain-hash');
    expect(entry.fromAddress, 'historical-source-address');
    expect(entry.toAddress, 'historical-destination-address');
  });

  test('old journal responses without address fields keep empty addresses', () {
    final json = journalTestJson();
    expect(json.containsKey('fromAddress'), isFalse);
    expect(json.containsKey('toAddress'), isFalse);
    final entry = WalletJournalEntry.fromJson(json);
    expect(entry.fromAddress, isEmpty);
    expect(entry.toAddress, isEmpty);
  });

  test('present address fields require strings while empty strings are valid',
      () {
    final empty = WalletJournalEntry.fromJson(
        journalTestJson()..addAll({'fromAddress': '', 'toAddress': ''}));
    expect(empty.fromAddress, isEmpty);
    expect(empty.toAddress, isEmpty);
    for (final field in ['fromAddress', 'toAddress']) {
      for (final value in [null, 42, true, <String>[]]) {
        expect(
            () =>
                WalletJournalEntry.fromJson(journalTestJson()..[field] = value),
            throwsFormatException,
            reason: '$field: $value');
      }
    }
  });

  test('group packet lifecycle separates freeze, settlement and returned funds',
      () {
    final events = [
      journalTestJson(id: 'freeze')
        ..addAll({
          'type': 'packet_freeze',
          'direction': 'freeze',
          'amount': '10',
          'availableDelta': '-10',
          'frozenDelta': '10',
          'assetDelta': '0',
        }),
      journalTestJson(id: 'settlement')
        ..addAll({
          'type': 'packet_settlement',
          'direction': 'expense',
          'amount': '2',
          'availableDelta': '0',
          'frozenDelta': '-2',
          'assetDelta': '-2',
        }),
      journalTestJson(),
    ].map(WalletJournalEntry.fromJson).toList();
    expect(events.map((event) => event.direction),
        ['freeze', 'expense', 'unfreeze']);
    expect(events.map((event) => event.orderID).toSet(), {'packet-order'});
    expect(events.map((event) => event.id).toSet(), hasLength(3));
    expect(events.map((event) => event.assetDeltaUnits),
        [BigInt.zero, BigInt.from(-2000000), BigInt.zero]);
    expect(events.every((event) => !event.toWalletRecord().income), isTrue);
  });

  test('large decimals retain raw precision beyond double and int capacities',
      () {
    for (final currency in ['USDT', 'TRX', 'BI99']) {
      final decimal = currency == 'BI99'
          ? '123456789012345678901234567890.12'
          : '123456789012345678901234567890.123456';
      final entry = WalletJournalEntry.fromJson(journalTestJson()
        ..addAll({
          'currency': currency,
          'bizType': 'admin_adjust',
          'type': 'admin_adjust',
          'direction': 'income',
          'amount': decimal,
          'availableDelta': decimal,
          'frozenDelta': '0',
          'assetDelta': decimal,
          'beforeAvailable': '-0.01',
          'afterAvailable': decimal,
        }));
      expect(entry.amount, decimal);
      expect(entry.assetDelta, decimal);
      expect(entry.beforeAvailable, '-0.01');
      expect(entry.afterAvailable, decimal);
      expect(entry.amountUnits, BigInt.parse(decimal.replaceAll('.', '')));
      expect(entry.toWalletRecord().amount, decimal);
      expect(entry.toWalletRecord().coin, currency == 'BI99' ? '99' : currency);
    }
  });

  test(
      'posted events retain their identity and do not adopt current order state',
      () {
    final entry = WalletJournalEntry.fromJson(journalTestJson()
      ..addAll({
        'counterpartyID': 'im_internal_uid',
        'chainTxID': 'real-chain-hash',
        'orderStatus': 'withdraw_failed',
        'reason': '人工核对补回',
      }));
    final record = entry.toWalletRecord();
    expect(record.journal, same(entry));
    expect(record.id, entry.id);
    expect(record.hash, 'real-chain-hash');
    expect(record.orderNo, 'packet-order');
    expect(record.serverOrderId, 'packet-order');
    expect(record.time, '1791244800000');
    expect(record.status, WalletRecordStatus.success);
    expect(record.title, '红包退回');
    expect(record.payer, isEmpty);
    expect(record.payee, isEmpty);
    expect(record.memo, '人工核对补回');
    expect(record.subTitle, '人工核对补回');
    expect(record.rpMsg, '恭喜发财，大吉大利');
    expect(record.groupId, '@group');
  });

  test('neutral permits zero while all five directions follow exact deltas',
      () {
    for (final (direction, available, frozen, asset) in [
      ('income', '0.000001', '0', '0.000001'),
      ('expense', '-0.000001', '0', '-0.000001'),
      ('freeze', '-0.000001', '0.000001', '0'),
      ('unfreeze', '0.000001', '-0.000001', '0'),
      ('neutral', '0', '0', '0'),
    ]) {
      final entry = WalletJournalEntry.fromJson(journalTestJson()
        ..addAll({
          'direction': direction,
          'amount': direction == 'neutral' ? '0' : '0.000001',
          'availableDelta': available,
          'frozenDelta': frozen,
          'assetDelta': asset,
        }));
      expect(entry.direction, direction);
      expect(entry.toWalletRecord().income, direction == 'income');
    }
  });

  test(
      'malformed or inconsistent decimals and directions fail without rounding',
      () {
    for (final patch in <Map<String, dynamic>>[
      {'amount': 8},
      {'amount': '-8'},
      {'amount': '0'},
      {'amount': '1e3'},
      {'amount': '8.0000001'},
      {'amount': ' 8'},
      {'currency': '99'},
      {'currency': 'BI99', 'amount': '8.001'},
      {'assetDelta': '0.000001'},
      {'direction': 'income'},
      {'direction': 'expense'},
      {'direction': 'freeze'},
      {'direction': 'neutral'},
      {'beforeAvailable': 0},
      {'afterAvailable': '1.0000001'},
      {'createdAt': 1791244800000.0},
      {'id': ''},
      {'type': null},
    ]) {
      expect(
          () => WalletJournalEntry.fromJson(journalTestJson()..addAll(patch)),
          throwsFormatException,
          reason: '$patch');
    }
  });

  test(
      'query keeps identical filters across cursors and excludes user identity',
      () {
    const query = WalletJournalQuery(
      currency: 'BI99',
      bizType: 'transfer',
      type: 'transfer_received',
      direction: 'income',
      startTime: 1791216000000,
      endTime: 1791302400000,
      limit: 100,
    );
    final expected = {
      'currency': 'BI99',
      'bizType': 'transfer',
      'type': 'transfer_received',
      'direction': 'income',
      'startTime': 1791216000000,
      'endTime': 1791302400000,
      'limit': 100,
    };
    expect(query.toQueryParameters(), expected);
    expect(query.withCursor('opaque-cursor').toQueryParameters(),
        {...expected, 'cursor': 'opaque-cursor'});
    expect(
        query.withCursor('opaque-cursor').withCursor(null).toQueryParameters(),
        expected);
    expect(const WalletJournalQuery().toQueryParameters(), {'limit': 20});
  });

  test('query validates documented page size, currency and direction enums',
      () {
    for (final query in [
      const WalletJournalQuery(limit: 0),
      const WalletJournalQuery(limit: 101),
      const WalletJournalQuery(currency: '99'),
      const WalletJournalQuery(direction: 'received'),
    ]) {
      expect(query.toQueryParameters, throwsFormatException);
    }
  });

  test(
      'query preserves opaque cursor and timestamps without unstated constraints',
      () {
    const query = WalletJournalQuery(
        startTime: -1, endTime: -1, cursor: 'opaque +/= value');
    expect(query.toQueryParameters(), {
      'startTime': -1,
      'endTime': -1,
      'cursor': 'opaque +/= value',
      'limit': 20
    });
    expect(query.withCursor('').toQueryParameters(),
        {'startTime': -1, 'endTime': -1, 'limit': 20});
    final entry =
        WalletJournalEntry.fromJson(journalTestJson()..['createdAt'] = -1);
    expect(entry.createdAt, -1);
  });

  test('page preserves server event order and same-order events, with no total',
      () {
    final page = WalletJournalPage.fromJson({
      'items': [journalTestJson(id: 'z'), journalTestJson(id: 'a')],
      'limit': 20,
      'hasMore': true,
      'nextCursor': 'opaque',
    });
    expect(page.items.map((item) => item.id), ['z', 'a']);
    expect(page.items.map((item) => item.orderID),
        ['packet-order', 'packet-order']);
    expect(page.nextCursor, 'opaque');
    expect(() => page.items.clear(), throwsUnsupportedError);
    expect(
        WalletJournalPage.fromJson({
          'items': [],
          'limit': 20,
          'hasMore': false,
          'nextCursor': '',
        }).items,
        isEmpty);
  });

  test('empty intermediate page and terminal redundant cursor follow metadata',
      () {
    final intermediate = WalletJournalPage.fromJson({
      'items': [],
      'limit': 20,
      'hasMore': true,
      'nextCursor': 'next',
    });
    expect(intermediate.items, isEmpty);
    expect(intermediate.hasMore, isTrue);
    expect(intermediate.nextCursor, 'next');
    final terminal = WalletJournalPage.fromJson({
      'items': [],
      'limit': 20,
      'hasMore': false,
      'nextCursor': 'unused',
    });
    expect(terminal.hasMore, isFalse);
    expect(terminal.nextCursor, 'unused');
  });

  test('page rejects missing or unusable cursor metadata and malformed items',
      () {
    for (final patch in <Map<String, dynamic>>[
      {'items': null},
      {
        'items': [null]
      },
      {'limit': 0},
      {'limit': 101},
      {'hasMore': null},
      {'nextCursor': null},
      {'hasMore': true, 'nextCursor': ''},
    ]) {
      expect(
          () => WalletJournalPage.fromJson({
                'items': [journalTestJson()],
                'limit': 20,
                'hasMore': false,
                'nextCursor': '',
                ...patch,
              }),
          throwsFormatException,
          reason: '$patch');
    }
  });
}
