import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:openim_common/openim_common.dart';

import 'recent_call_test_support.dart';

class _LegacyReader implements BinaryReader {
  _LegacyReader(CallRecords record) : data = [
    8, 1, record.userID, 2, record.nickname, 3, record.faceURL,
    4, record.type, 5, record.success, 6, record.incomingCall,
    7, record.date, 8, record.duration,
  ];
  final List<dynamic> data;
  int index = 0;
  @override
  int readByte() => data[index++] as int;
  @override
  dynamic read([int? typeId]) => data[index++];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old eight-field Hive records and JSON remain readable', () {
    final legacy = callFixture(incoming: true, success: false, state: null)
      ..roomID = null;
    final decoded = CallRecordsAdapter().read(_LegacyReader(legacy));
    expect(decoded.toJson(), legacy.toJson());
    expect(decoded.roomID, isNull);
    expect(decoded.state, isNull);
    expect(decoded.isMissed, isTrue);
    final json = legacy.toJson()..remove('roomID')..remove('state');
    expect(CallRecords.fromJson(json).recordKey, decoded.recordKey);
  });

  test('missed excludes outgoing failures and deliberate local declines', () {
    expect(callFixture(incoming: true, success: false, state: 'timeout').isMissed, isTrue);
    expect(callFixture(incoming: true, success: false, state: 'beCanceled').isMissed, isTrue);
    expect(callFixture(incoming: true, success: false, state: 'reject').isMissed, isFalse);
    expect(callFixture(incoming: false, success: false, state: 'timeout').isMissed, isFalse);
    expect(callFixture(incoming: true, success: true, state: 'timeout').isMissed, isFalse);
  });

  test('initial read waits for Hive rather than freezing an empty list', () async {
    final pending = Completer<Box>();
    final box = RecentCallMemoryBox()..backingMap['account-a'] = [callFixture()];
    final cache = CacheController(accountIDProvider: () => 'account-a', boxOpener: () => pending.future);
    final load = cache.initCallRecords();
    expect(cache.callRecordsLoading.value, isTrue);
    expect(cache.callRecordList, isEmpty);
    pending.complete(box);
    await load;
    expect(cache.callRecordList.single.nickname, '阿明');
    expect(cache.callRecordsLoading.value, isFalse);
  });

  test('account switch during open rejects old writes and reloads only new account', () async {
    String? account = 'account-a';
    final pending = Completer<Box>();
    final box = RecentCallMemoryBox()
      ..backingMap['account-a'] = [callFixture(nickname: '甲')]
      ..backingMap['account-b'] = [callFixture(room: 'room-b', nickname: '乙')];
    final cache = CacheController(accountIDProvider: () => account, boxOpener: () => pending.future);
    final oldLoad = cache.initCallRecords();
    final oldWrite = cache.recordCall(callFixture(room: 'late-a'), accountID: 'account-a');
    account = 'account-b';
    final newLoad = cache.initCallRecords();
    pending.complete(box);
    await Future.wait([oldLoad, oldWrite, newLoad]);
    expect(cache.callRecordList.single.nickname, '乙');
    expect((box.backingMap['account-a'] as List).length, 1);
    await cache.recordCall(callFixture(room: 'late-a-again'), accountID: 'account-a');
    expect(box.writes, 0);
    account = null;
    await cache.initCallRecords();
    expect(cache.callRecordList, isEmpty);
  });

  test('duplicate terminal events cannot downgrade connection or share mutable objects', () async {
    final box = RecentCallMemoryBox();
    final cache = CacheController(accountIDProvider: () => 'account-a', boxOpener: () async => box);
    final first = callFixture(nickname: '', duration: 12);
    final write = cache.recordCall(first, accountID: 'account-a');
    first.nickname = '被调用方修改';
    await write;
    await Future.wait([
      cache.recordCall(callFixture(nickname: '真实昵称', duration: 73), accountID: 'account-a'),
      cache.recordCall(callFixture(success: false, state: 'timeout', duration: 0), accountID: 'account-a'),
    ]);
    expect(cache.callRecordList, hasLength(1));
    expect(cache.callRecordList.single.nickname, '真实昵称');
    expect(cache.callRecordList.single.success, isTrue);
    expect(cache.callRecordList.single.state, 'hangup');
    expect(cache.callRecordList.single.duration, 73);
    cache.callRecordList.single.nickname = '仅修改展示快照';
    await cache.initCallRecords();
    expect(cache.callRecordList.single.nickname, '真实昵称');
  });

  test('serialized record and delete preserve new calls and same-date distinct rooms', () async {
    final box = RecentCallMemoryBox();
    final cache = CacheController(accountIDProvider: () => 'account-a', boxOpener: () async => box);
    final first = callFixture(room: 'first');
    await cache.recordCall(first, accountID: 'account-a');
    final captured = List<CallRecords>.of(cache.callRecordList);
    await Future.wait([
      cache.recordCall(callFixture(room: 'second'), accountID: 'account-a'),
      cache.deleteCallRecordsBatch(captured),
    ]);
    expect(cache.callRecordList.single.roomID, 'second');
    expect((box.backingMap['account-a'] as List).whereType<CallRecords>().single.roomID, 'second');
  });

  test('write failure is returned and next write can retry without stale UI', () async {
    final box = RecentCallMemoryBox();
    box.beforePut = (_, __) async => throw StateError('disk full');
    final cache = CacheController(accountIDProvider: () => 'account-a', boxOpener: () async => box);
    await expectLater(cache.recordCall(callFixture(), accountID: 'account-a'), throwsStateError);
    expect(cache.callRecordList, isEmpty);
    box.beforePut = null;
    await cache.recordCall(callFixture(), accountID: 'account-a');
    expect(cache.callRecordList, hasLength(1));
  });

  test('logout during persist stores in captured account without publishing to new account', () async {
    var account = 'account-a';
    final box = RecentCallMemoryBox()..backingMap['account-b'] = [callFixture(room: 'b', nickname: '乙')];
    final started = Completer<void>();
    final finish = Completer<void>();
    box.beforePut = (_, __) async { started.complete(); await finish.future; };
    final cache = CacheController(accountIDProvider: () => account, boxOpener: () async => box);
    final write = cache.recordCall(callFixture(), accountID: 'account-a');
    await started.future;
    account = 'account-b';
    final load = cache.initCallRecords();
    expect(cache.callRecordList, isEmpty);
    finish.complete();
    await Future.wait([write, load]);
    expect(cache.callRecordList.single.nickname, '乙');
    expect((box.backingMap['account-a'] as List).whereType<CallRecords>().single.userID, 'peer-1');
  });

  test('Hive persists full records across reopen with account isolation', () async {
    final directory = await Directory.systemTemp.createTemp('recent-calls-test-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(CallRecordsAdapter());
    Box<List>? box;
    try {
      box = await Hive.openBox<List>('calls-persistence-test');
      var account = 'account-a';
      final cache = CacheController(accountIDProvider: () => account, boxOpener: () async => box!);
      await cache.recordCall(callFixture()..faceURL = 'https://avatar.test/real.png', accountID: account);
      account = 'account-b';
      await cache.recordCall(callFixture(room: 'b', nickname: '乙', type: 'video'), accountID: account);
      await box.close();
      box = await Hive.openBox<List>('calls-persistence-test');
      final reopened = CacheController(accountIDProvider: () => account, boxOpener: () async => box!);
      await reopened.initCallRecords();
      expect(reopened.callRecordList.single.nickname, '乙');
      account = 'account-a';
      await reopened.initCallRecords();
      expect(reopened.callRecordList.single.roomID, 'room-1');
      expect(reopened.callRecordList.single.state, 'hangup');
      expect(reopened.callRecordList.single.faceURL, 'https://avatar.test/real.png');
      expect(reopened.callRecordList.single.duration, 73);
    } finally {
      if (box?.isOpen == true) await box!.close();
      await directory.delete(recursive: true);
    }
  });
}

