import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/secondary/calls/data/call_records_api.dart';
import 'package:openim/pages/mine/secondary/calls/data/call_records_repository.dart';
import 'package:openim_common/openim_common.dart';

import '../recent_call_test_support.dart';

CallRecords _row(String id, int updatedAt, {String status = 'completed'}) =>
    callFixture(
        room: id,
        peer: 'im_peer',
        nickname: '',
        success: status == 'completed',
        state: status,
        duration: status == 'completed' ? 42 : 0)
      ..endedAt = 0
      ..updatedAt = updatedAt;

String _notice(CallRecords row, {String owner = 'self'}) => jsonEncode({
      'key': 'callRecordChanged',
      'sendUserID': owner,
      'recvUserID': owner,
      'data': jsonEncode({
        'callID': row.callID,
        'mediaType': row.type,
        'roomType': row.roomType,
        'direction': row.incomingCall ? 'in' : 'out',
        'status': row.status,
        'peerUserID': row.userID,
        'groupID': row.groupID,
        'duration': row.duration,
        'startedAt': row.startedAt,
        'endedAt': row.endedAt,
        'updatedAt': row.updatedAt,
      }),
    });

class _Api extends CallRecordsApi {
  @override
  String get baseUrl => 'https://calls.test';

  final cursors = <int>[];
  final tokens = <String>[];
  final reported = <CallRecords>[];
  Future<CallRecordsPage> Function(int cursor)? onPage;
  Future<CallRecords> Function(CallRecords row)? onReport;

  @override
  Future<CallRecordsPage> page(
      {required int syncAt, int limit = 200, required String token}) async {
    cursors.add(syncAt);
    tokens.add(token);
    return onPage != null
        ? onPage!(syncAt)
        : CallRecordsPage(records: const [], syncAt: syncAt);
  }

  @override
  Future<CallRecords> report(CallRecords record,
      {required String token}) async {
    reported.add(record.copy());
    tokens.add(token);
    return onReport != null
        ? onReport!(record)
        : (record.copy()..updatedAt = 50);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecentCallMemoryBox box;
  late CacheController cache;
  late _Api api;
  late String account;
  late String token;
  late CallRecordsRepository repo;

  CallRecordsRepository create() => CallRecordsRepository(
      cache: cache,
      api: api,
      accountIDProvider: () => account,
      tokenProvider: () => token,
      profileResolver: (rows) async => rows,
      limit: 2);

  setUp(() {
    account = 'self';
    token = 'captured-chat-token';
    box = RecentCallMemoryBox();
    cache = CacheController(
        accountIDProvider: () => account, boxOpener: () async => box);
    api = _Api();
    repo = create();
  });
  tearDown(() => repo.dispose());

  test('overfull timestamp page continues and commits watermark with rows',
      () async {
    api.onPage = (cursor) async {
      if (cursor != 0) throw StateError('second page offline');
      return CallRecordsPage(records: [
        _row('call_0001', 10),
        _row('call_0002', 10),
        _row('call_0003', 10),
      ], syncAt: 10);
    };
    await repo.refresh();
    expect(api.cursors, [0, 10]);
    expect(repo.syncAt, 10);
    expect(cache.callRecordList, hasLength(3));
    api.onPage = (_) async => const CallRecordsPage(records: [], syncAt: 20);
    await repo.refresh();
    expect(api.cursors, [0, 10, 10]);
    expect(api.tokens.every((value) => value == token), isTrue);
    expect(cache.callRecordList, hasLength(3));
    expect(repo.syncAt, 20);
    expect(
        (await cache.callRecordsSyncSnapshot(accountID: account)).syncAt, 20);
    expect(box.writes, 2);
    final reopened = CacheController(
        accountIDProvider: () => account, boxOpener: () async => box);
    await reopened.initCallRecords();
    expect(reopened.callRecordList, hasLength(3));
    expect((await reopened.callRecordsSyncSnapshot(accountID: account)).syncAt,
        20);
  });

  test('newer push wins against late pull and hidden call cannot revive',
      () async {
    final newest = _row('call_0001', 40);
    await repo.handleNotification(_notice(newest));
    expect((await cache.callRecordsSyncSnapshot(accountID: account)).syncAt, 0);
    api.onPage = (_) async => CallRecordsPage(
        records: [_row('call_0001', 10, status: 'missed')], syncAt: 10);
    await repo.refresh();
    expect(cache.callRecordList.single.success, isTrue);
    expect(cache.callRecordList.single.updatedAt, 40);
    await repo
        .handleNotification(_notice(_row('call_0001', 20, status: 'missed')));
    expect(cache.callRecordList.single.updatedAt, 40);
    await cache.deleteCallRecordsBatch(cache.callRecordList.toList());
    await repo.handleNotification(_notice(_row('call_0001', 50)));
    expect(cache.callRecordList, isEmpty);
    final reopened = CacheController(
        accountIDProvider: () => account, boxOpener: () async => box);
    await reopened.initCallRecords();
    expect(reopened.callRecordList, isEmpty);
    expect((await reopened.callRecordsSyncSnapshot(accountID: account)).syncAt,
        10);
    expect(await repo.handleNotification(_notice(newest, owner: 'other')),
        isFalse);
  });

  test('invalid nonadvancing or skipped timestamp page never advances cache',
      () async {
    for (final bad in [
      CallRecordsPage(records: [_row('call_0001', 0)], syncAt: 10),
      CallRecordsPage(records: [_row('call_0001', 20)], syncAt: 10),
      CallRecordsPage(
          records: [_row('call_0001', 10), _row('call_0002', 10)], syncAt: 0),
    ]) {
      api.onPage = (_) async => bad;
      await repo.refresh();
      expect(cache.callRecordList, isEmpty);
      expect(
          (await cache.callRecordsSyncSnapshot(accountID: account)).syncAt, 0);
      expect(cache.callRecordsError.value, isNotNull);
    }
  });

  test('failed atomic cache commit preserves watermark and can retry same page',
      () async {
    api.onPage = (_) async =>
        CallRecordsPage(records: [_row('call_0001', 10)], syncAt: 10);
    box.beforePut = (_, __) async => throw StateError('disk full');
    await repo.refresh();
    expect(repo.syncAt, 0);
    expect(cache.callRecordList, isEmpty);
    box.beforePut = null;
    await repo.refresh();
    expect(api.cursors, [0, 0]);
    expect(cache.callRecordList.single.callID, 'call_0001');
    expect(repo.syncAt, 10);
  });

  test('late page after token rotation or disposal cannot publish or persist',
      () async {
    for (final rotate in [true, false]) {
      repo.dispose();
      repo = create();
      final waiting = Completer<CallRecordsPage>();
      final started = Completer<void>();
      api.onPage = (_) {
        started.complete();
        return waiting.future;
      };
      final refresh = repo.refresh();
      await started.future;
      if (rotate) {
        token = 'next-chat-token';
      } else {
        repo.dispose();
      }
      waiting.complete(
          CallRecordsPage(records: [_row('call_0001', 10)], syncAt: 10));
      await refresh;
      expect(cache.callRecordList, isEmpty);
      expect(box.writes, 0);
    }
  });

  test('local report returns before network and durable queue retries same ID',
      () async {
    final pending = Completer<CallRecords>();
    final started = Completer<void>();
    api.onReport = (row) {
      if (!started.isCompleted) started.complete();
      return pending.future;
    };
    final local = _row('call_0001', 0);
    await repo.recordCall(local, accountID: account);
    await started.future;
    expect(cache.callRecordList.single.callID, 'call_0001');
    expect(
        (await cache.callRecordsSyncSnapshot(accountID: account))
            .pendingRecords,
        hasLength(1));
    pending.completeError(StateError('network down'));
    await repo.refresh();
    expect(
        (await cache.callRecordsSyncSnapshot(accountID: account))
            .pendingRecords,
        hasLength(1));
    repo.dispose();
    cache = CacheController(
        accountIDProvider: () => account, boxOpener: () async => box);
    repo = create();
    api.onReport = (row) async => row.copy()..updatedAt = 50;
    await repo.refresh();
    expect(api.reported.map((row) => row.callID).toSet(), {'call_0001'});
    expect(
        (await cache.callRecordsSyncSnapshot(accountID: account))
            .pendingRecords,
        isEmpty);
    expect(cache.callRecordList.single.updatedAt, 50);
  });

  test('older report acknowledgement does not consume a newer same-call draft',
      () async {
    final submitted = _row('call_0001', 0)..duration = 42;
    await cache.queueCallReport(submitted, accountID: account);
    await cache.queueCallReport(submitted.copy()..duration = 88,
        accountID: account);
    await cache.acknowledgeCallReport(
        submitted, submitted.copy()..updatedAt = 50,
        accountID: account);
    final pending = await cache.callRecordsSyncSnapshot(accountID: account);
    expect(pending.pendingRecords.single.duration, 88);
    api.onReport = (row) async => row.copy()..updatedAt = 60;
    await repo.refresh();
    expect(api.reported.single.callID, submitted.callID);
    expect(api.reported.single.duration, 88);
    expect(cache.callRecordList.single.duration, 88);
  });

  test('incoming remains local while group calls are readable without a peer',
      () async {
    await repo.recordCall(_row('call_0001', 0)..incomingCall = true,
        accountID: account);
    await repo.refresh();
    expect(api.reported, isEmpty);
    final group = _row('call_0002', 20)
      ..roomType = 'group'
      ..groupID = 'group_1'
      ..userID = '';
    expect(await repo.handleNotification(_notice(group)), isTrue);
    expect(cache.callRecordList.any((row) => row.groupID == 'group_1'), isTrue);
  });
}
