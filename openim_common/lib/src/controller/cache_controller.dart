import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:openim_common/openim_common.dart';

/// The existing per-account Hive call cache, also observed by Recent Calls.
class CacheController extends GetxController {
  CacheController({
    String? Function()? accountIDProvider,
    Future<Box> Function()? boxOpener,
  })  : _accountIDProvider = accountIDProvider ?? _loginAccount,
        _boxOpener = boxOpener;

  final String? Function() _accountIDProvider;
  final Future<Box> Function()? _boxOpener;
  final callRecordList = <CallRecords>[].obs;
  final callRecordsLoading = false.obs;
  final callRecordsError = RxnString();
  Box? callRecordBox;
  Future<Box>? _opening;
  Future<void> _writes = Future<void>.value();
  String? _activeAccount;
  int _viewGeneration = 0;
  bool _closed = false;

  static String? _loginAccount() => DataSp.getLoginCertificate()?.userID;

  String get userID => _accountIDProvider()?.trim() ?? '';

  bool isAccountCurrent(String accountID) =>
      !_closed && accountID.isNotEmpty && userID == accountID;

  Future<Box> _box() async {
    if (_closed) throw StateError('Call cache is closed');
    final ready = callRecordBox;
    if (ready != null && ready.isOpen) return ready;
    final pending = _opening;
    if (pending != null) return pending;
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(CallRecordsAdapter());
    }
    final future = _boxOpener?.call() ?? Hive.openBox<List>('callRecords');
    _opening = future;
    try {
      final opened = await future;
      callRecordBox = opened;
      return opened;
    } finally {
      _opening = null;
    }
  }

  _CallCacheEntry _entry(Box box, String accountID) {
    final stored = box.get(accountID);
    if (stored is! List) return _CallCacheEntry();
    final unique = <String, CallRecords>{};
    for (final record in stored.whereType<CallRecords>()) {
      final previous = unique[record.recordKey];
      unique[record.recordKey] =
          previous == null ? record.copy() : _merge(previous, record);
    }
    final entry = _CallCacheEntry(records: unique.values.toList());
    for (final value in stored.whereType<Map>()) {
      if (value['_callRecordsMeta'] != 1) continue;
      final watermark = value['syncAt'];
      if (watermark is int && watermark >= 0) entry.syncAt = watermark;
      final hidden = value['hidden'];
      if (hidden is List) entry.hidden.addAll(hidden.whereType<String>());
      final pending = value['pending'];
      if (pending is List) {
        for (final record in pending.whereType<CallRecords>()) {
          entry.pending[record.recordKey] = record.copy();
        }
      }
    }
    entry.sort();
    return entry;
  }

  List<CallRecords> _read(Box box, String accountID) =>
      _entry(box, accountID).visible;

  bool _current(String account, bool Function()? isSessionCurrent) =>
      isAccountCurrent(account) && (isSessionCurrent?.call() ?? true);

  Future<void> _commit(Box box, String account, _CallCacheEntry entry,
      {bool Function()? isSessionCurrent}) async {
    entry.sort();
    // One existing account key commits rows, hidden IDs, reports and watermark
    // together. Historical List<CallRecords> values still decode unchanged.
    await box.put(account, entry.encode());
    if (_current(account, isSessionCurrent)) _publish(entry.visible, account);
  }

  Future<CallRecordsSyncSnapshot> callRecordsSyncSnapshot(
      {required String accountID}) async {
    if (!isAccountCurrent(accountID)) return const CallRecordsSyncSnapshot();
    final box = await _box();
    await _writes;
    if (!isAccountCurrent(accountID)) return const CallRecordsSyncSnapshot();
    final entry = _entry(box, accountID);
    return CallRecordsSyncSnapshot(
      syncAt: entry.syncAt,
      pendingRecords:
          entry.pending.values.map((value) => value.copy()).toList(),
    );
  }

  /// Loading waits for Hive and pending writes, fixing the former startup race.
  Future<void> initCallRecords() async {
    if (_closed) return;
    final account = userID;
    final generation = ++_viewGeneration;
    if (_activeAccount != account) {
      _activeAccount = account;
      callRecordList.clear();
    }
    callRecordsError.value = null;
    if (account.isEmpty) {
      callRecordsLoading.value = false;
      return;
    }
    callRecordsLoading.value = true;
    try {
      final box = await _box();
      await _writes;
      if (generation != _viewGeneration || !isAccountCurrent(account)) return;
      callRecordList.assignAll(_read(box, account));
    } catch (error) {
      if (generation == _viewGeneration && isAccountCurrent(account)) {
        callRecordsError.value = error.toString();
      }
    } finally {
      if (!_closed && generation == _viewGeneration) {
        callRecordsLoading.value = false;
      }
    }
  }

  void resetCache() {
    ++_viewGeneration;
    _activeAccount = null;
    callRecordList.clear();
    callRecordsError.value = null;
    unawaited(initCallRecords());
  }

  Future<void> _write(Future<void> Function() operation) {
    final next = _writes.then((_) => operation());
    // An individual error is returned to its caller without poisoning the queue.
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  static CallRecords _merge(CallRecords existing, CallRecords incoming) {
    if (incoming.updatedAt > 0 || existing.updatedAt > 0) {
      final result =
          (incoming.updatedAt >= existing.updatedAt ? incoming : existing)
              .copy();
      if (result.nickname.trim().isEmpty) {
        result.nickname = existing.nickname.trim().isNotEmpty
            ? existing.nickname
            : incoming.nickname;
      }
      if (result.faceURL?.trim().isNotEmpty != true) {
        result.faceURL = existing.faceURL?.trim().isNotEmpty == true
            ? existing.faceURL
            : incoming.faceURL;
      }
      if (result.participantUserIDs.isEmpty) {
        result.participantUserIDs = List.of(
            existing.participantUserIDs.isNotEmpty
                ? existing.participantUserIDs
                : incoming.participantUserIDs);
      }
      return result;
    }
    // Never downgrade a connection because of a duplicate unsuccessful event.
    final preferIncoming = incoming.success && !existing.success;
    final result = (preferIncoming ? incoming : existing).copy();
    if (result.nickname.trim().isEmpty && incoming.nickname.trim().isNotEmpty) {
      result.nickname = incoming.nickname;
    }
    if ((result.faceURL?.trim().isEmpty ?? true) &&
        incoming.faceURL?.trim().isNotEmpty == true) {
      result.faceURL = incoming.faceURL;
    }
    if (result.success &&
        incoming.success &&
        incoming.duration > result.duration) {
      result.duration = incoming.duration;
    }
    result.roomID ??= incoming.roomID;
    if (result.state?.trim().isNotEmpty != true) result.state = incoming.state;
    return result;
  }

  void _publish(List<CallRecords> records, String account) {
    if (!isAccountCurrent(account)) return;
    if (_activeAccount != account) {
      ++_viewGeneration;
      _activeAccount = account;
      callRecordsLoading.value = false;
    }
    callRecordsError.value = null;
    callRecordList.assignAll(records.map((record) => record.copy()));
  }

  Future<void> recordCall(CallRecords record,
          {required String accountID, bool Function()? isSessionCurrent}) =>
      _storeLocal(record,
          accountID: accountID, isSessionCurrent: isSessionCurrent);

  /// An outgoing report is durable before the HTTP request starts.
  Future<void> queueCallReport(CallRecords record,
          {required String accountID, bool Function()? isSessionCurrent}) =>
      _storeLocal(record,
          accountID: accountID,
          report: true,
          isSessionCurrent: isSessionCurrent);

  Future<void> _storeLocal(CallRecords record,
      {required String accountID,
      bool report = false,
      bool Function()? isSessionCurrent}) {
    final account = accountID.trim();
    final snapshot = record.copy();
    if (!_current(account, isSessionCurrent) ||
        (snapshot.userID.trim().isEmpty &&
            !(snapshot.roomType == 'group' && snapshot.groupID.isNotEmpty))) {
      return Future<void>.value();
    }
    return _write(() async {
      if (!_current(account, isSessionCurrent)) return;
      final box = await _box();
      if (!_current(account, isSessionCurrent)) return;
      final entry = _entry(box, account);
      final records = entry.records;
      final index =
          records.indexWhere((item) => item.recordKey == snapshot.recordKey);
      if (index < 0) {
        records.add(snapshot);
      } else {
        records[index] = _merge(records[index], snapshot);
      }
      if (report && snapshot.callID.isNotEmpty) {
        entry.pending[snapshot.recordKey] = snapshot;
      }
      await _commit(box, account, entry, isSessionCurrent: isSessionCurrent);
    });
  }

  /// The response and syncAt advance in the same account-scoped Hive write.
  /// Business notices call this without syncAt and cannot skip a pull page.
  Future<void> applyRemoteCallRecords(Iterable<CallRecords> incoming,
      {required String accountID,
      int? syncAt,
      bool Function()? isSessionCurrent}) {
    final snapshots = incoming.map((record) => record.copy()).toList();
    return _write(() async {
      if (!_current(accountID, isSessionCurrent)) return;
      final box = await _box();
      if (!_current(accountID, isSessionCurrent)) return;
      final entry = _entry(box, accountID);
      if (syncAt != null && syncAt < entry.syncAt) {
        throw StateError('Call-record watermark moved backwards');
      }
      for (final record in snapshots) {
        if (record.callID.isEmpty || entry.hidden.contains(record.recordKey)) {
          continue;
        }
        final index = entry.records
            .indexWhere((existing) => existing.recordKey == record.recordKey);
        if (index < 0) {
          entry.records.add(record);
        } else {
          entry.records[index] = _merge(entry.records[index], record);
        }
      }
      if (syncAt != null) entry.syncAt = syncAt;
      await _commit(box, accountID, entry, isSessionCurrent: isSessionCurrent);
    });
  }

  Future<void> acknowledgeCallReport(CallRecords submitted, CallRecords remote,
      {required String accountID, bool Function()? isSessionCurrent}) {
    final localSnapshot = submitted.copy();
    final serverSnapshot = remote.copy();
    return _write(() async {
      if (!_current(accountID, isSessionCurrent)) return;
      final box = await _box();
      if (!_current(accountID, isSessionCurrent)) return;
      final entry = _entry(box, accountID);
      final pending = entry.pending[localSnapshot.recordKey];
      if (pending != null &&
          jsonEncode(pending.toJson()) == jsonEncode(localSnapshot.toJson())) {
        entry.pending.remove(localSnapshot.recordKey);
      }
      if (!entry.hidden.contains(serverSnapshot.recordKey)) {
        final index = entry.records.indexWhere(
            (existing) => existing.recordKey == serverSnapshot.recordKey);
        if (index < 0) {
          entry.records.add(serverSnapshot);
        } else {
          entry.records[index] = _merge(entry.records[index], serverSnapshot);
        }
      }
      await _commit(box, accountID, entry, isSessionCurrent: isSessionCurrent);
    });
  }

  Future<void> addCallRecords(CallRecords record) =>
      recordCall(record, accountID: userID);

  Future<void> deleteCallRecords(CallRecords record) =>
      deleteCallRecordsBatch([record]);

  /// Deletes only captured records, leaving calls arriving during confirmation.
  Future<void> deleteCallRecordsBatch(Iterable<CallRecords> records) {
    final account = userID;
    final keys = records.map((record) => record.recordKey).toSet();
    if (!isAccountCurrent(account) || keys.isEmpty) return Future<void>.value();
    return _write(() async {
      if (!isAccountCurrent(account)) return;
      final box = await _box();
      if (!isAccountCurrent(account)) return;
      final entry = _entry(box, account);
      entry.hidden.addAll(keys);
      entry.records.removeWhere((record) => keys.contains(record.recordKey));
      await _commit(box, account, entry);
    });
  }

  @override
  void onInit() {
    super.onInit();
    unawaited(initCallRecords());
  }

  @override
  void onClose() {
    _closed = true;
    ++_viewGeneration;
    callRecordList.clear();
    // Close only this controller's box, never unrelated Hive application boxes.
    unawaited(() async {
      await _writes;
      final box = callRecordBox ?? await _opening;
      if (box?.isOpen == true) await box!.close();
    }()
        .catchError((Object _) {}));
    super.onClose();
  }
}

class CallRecordsSyncSnapshot {
  const CallRecordsSyncSnapshot(
      {this.syncAt = 0, this.pendingRecords = const []});
  final int syncAt;
  final List<CallRecords> pendingRecords;
}

class _CallCacheEntry {
  _CallCacheEntry({List<CallRecords>? records}) : records = records ?? [];
  final List<CallRecords> records;
  final hidden = <String>{};
  final pending = <String, CallRecords>{};
  int syncAt = 0;

  List<CallRecords> get visible => records
      .where((record) => !hidden.contains(record.recordKey))
      .map((record) => record.copy())
      .toList();

  void sort() => records.sort(
      (a, b) => b.timestampMilliseconds.compareTo(a.timestampMilliseconds));

  List<Object> encode() => [
        ...records,
        {
          '_callRecordsMeta': 1,
          'syncAt': syncAt,
          'hidden': hidden.toList(),
          'pending': pending.values.toList(),
        },
      ];
}
