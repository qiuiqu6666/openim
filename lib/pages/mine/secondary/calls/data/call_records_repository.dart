import 'dart:async';
import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'call_records_api.dart';

typedef CallRecordProfileResolver = Future<List<CallRecords>> Function(
    List<CallRecords> records);

/// Reuses CacheController's account Hive entry and observable call list.
class CallRecordsRepository {
  CallRecordsRepository({
    required this.cache,
    CallRecordsApi? api,
    String? Function()? accountIDProvider,
    String? Function()? tokenProvider,
    CallRecordProfileResolver? profileResolver,
    this.limit = 200,
  })  : api = api ?? CallRecordsApi(),
        _accountIDProvider = accountIDProvider ?? (() => DataSp.userID),
        _tokenProvider = tokenProvider ?? (() => DataSp.chatToken),
        _profileResolver = profileResolver ?? _sdkProfiles {
    if (limit < 1 || limit > 500) {
      throw ArgumentError('Invalid call-record limit');
    }
    accountID = _accountIDProvider() ?? '';
    _token = _tokenProvider() ?? '';
    _endpoint = this.api.baseUrl;
  }

  final CacheController cache;
  final CallRecordsApi api;
  final int limit;
  final String? Function() _accountIDProvider;
  final String? Function() _tokenProvider;
  final CallRecordProfileResolver _profileResolver;
  late final String accountID;
  late final String _token;
  late final String _endpoint;
  bool _closed = false;
  bool _again = false;
  Future<void>? _sync;
  int _syncAt = 0;
  int _pendingCount = 0;

  bool get isDisposed => _closed;
  int get syncAt => _syncAt;
  int get pendingCount => _pendingCount;
  bool get isCurrent =>
      !_closed &&
      accountID.isNotEmpty &&
      _accountIDProvider() == accountID &&
      _tokenProvider() == _token &&
      api.baseUrl == _endpoint &&
      cache.isAccountCurrent(accountID);

  static Future<List<CallRecords>> _sdkProfiles(
      List<CallRecords> records) async {
    final copies = records.map((record) => record.copy()).toList();
    final users = copies
        .where((record) => record.roomType == 'single')
        .map((record) => record.userID)
        .where((id) => id.isNotEmpty)
        .toSet();
    final groups = copies
        .where((record) => record.roomType == 'group')
        .map((record) => record.groupID)
        .where((id) => id.isNotEmpty)
        .toSet();
    await Future.wait([
      if (users.isNotEmpty)
        (() async {
          try {
            final profiles = await OpenIM.iMManager.userManager
                .getUsersInfo(userIDList: users.toList())
                .timeout(const Duration(seconds: 2));
            final byID = {
              for (final profile in profiles) profile.userID: profile
            };
            for (final record
                in copies.where((row) => row.roomType == 'single')) {
              final profile = byID[record.userID];
              record.nickname = profile?.nickname ?? record.nickname;
              record.faceURL = profile?.faceURL ?? record.faceURL;
            }
          } catch (_) {
            // An unavailable SDK profile falls back to the IM identifier.
          }
        })(),
      if (groups.isNotEmpty)
        (() async {
          try {
            final profiles = await OpenIM.iMManager.groupManager
                .getGroupsInfo(groupIDList: groups.toList())
                .timeout(const Duration(seconds: 2));
            final byID = {
              for (final profile in profiles) profile.groupID: profile
            };
            for (final record
                in copies.where((row) => row.roomType == 'group')) {
              final profile = byID[record.groupID];
              record.nickname = profile?.groupName ?? record.nickname;
              record.faceURL = profile?.faceURL ?? record.faceURL;
            }
          } catch (_) {
            // Stored group calls remain readable without extending the engine.
          }
        })(),
    ]);
    return copies;
  }

  Future<List<CallRecords>> _enrich(List<CallRecords> records) async {
    try {
      return await _profileResolver(records.map((row) => row.copy()).toList());
    } catch (_) {
      return records;
    }
  }

  /// Terminal callbacks wait for durable local storage, never for the network.
  Future<void> recordCall(CallRecords record,
      {required String accountID}) async {
    if (!isCurrent || accountID != this.accountID) return;
    if (!record.incomingCall && record.callID.isNotEmpty) {
      await cache.queueCallReport(record,
          accountID: accountID, isSessionCurrent: () => isCurrent);
    } else {
      await cache.recordCall(record,
          accountID: accountID, isSessionCurrent: () => isCurrent);
    }
    if (isCurrent) unawaited(refresh());
  }

  Future<void> refresh() {
    if (!isCurrent) return Future<void>.value();
    final running = _sync;
    if (running != null) {
      _again = true;
      return running;
    }
    final work = _refresh();
    _sync = work;
    unawaited(work.whenComplete(() {
      if (identical(_sync, work)) _sync = null;
    }));
    return work;
  }

  Future<void> _refresh() async {
    do {
      _again = false;
      if (!isCurrent) return;
      await cache.initCallRecords();
      if (!isCurrent) return;
      cache.callRecordsLoading.value = true;
      cache.callRecordsError.value = null;
      String? reportError;
      try {
        var snapshot =
            await cache.callRecordsSyncSnapshot(accountID: accountID);
        if (!isCurrent) return;
        _syncAt = snapshot.syncAt;
        _pendingCount = snapshot.pendingRecords.length;
        if (_token.isEmpty) return;
        for (final record in snapshot.pendingRecords) {
          if (!isCurrent) return;
          try {
            final response = await api.report(record, token: _token);
            if (!isCurrent) return;
            final enriched = await _enrich([response]);
            if (!isCurrent) return;
            await cache.acknowledgeCallReport(record, enriched.single,
                accountID: accountID, isSessionCurrent: () => isCurrent);
          } catch (_) {
            if (!isCurrent) return;
            reportError = '通话记录尚未同步，将在下次连接时重试。';
            break;
          }
        }
        snapshot = await cache.callRecordsSyncSnapshot(accountID: accountID);
        if (!isCurrent) return;
        _pendingCount = snapshot.pendingRecords.length;
        var cursor = snapshot.syncAt;
        while (isCurrent) {
          final page =
              await api.page(syncAt: cursor, limit: limit, token: _token);
          if (!isCurrent) return;
          final more = page.records.length >= limit;
          if (page.syncAt < cursor || (more && page.syncAt <= cursor)) {
            throw const FormatException('Call-record cursor did not advance');
          }
          if (page.records.any((record) =>
              record.updatedAt <= cursor || record.updatedAt > page.syncAt)) {
            throw const FormatException('Call-record page escaped its cursor');
          }
          final enriched = await _enrich(page.records);
          if (!isCurrent) return;
          await cache.applyRemoteCallRecords(enriched,
              accountID: accountID,
              syncAt: page.syncAt,
              isSessionCurrent: () => isCurrent);
          if (!isCurrent) return;
          cursor = page.syncAt;
          _syncAt = cursor;
          if (!more) break;
        }
        if (isCurrent) cache.callRecordsError.value = reportError;
      } catch (_) {
        if (isCurrent) {
          cache.callRecordsError.value = '通话记录暂时无法同步，请稍后重试。';
        }
      } finally {
        if (isCurrent) cache.callRecordsLoading.value = false;
      }
    } while (_again && isCurrent);
  }

  /// Full push rows improve the list immediately; they never advance syncAt.
  Future<bool> handleNotification(String raw) async {
    if (!isCurrent) return false;
    try {
      final envelope = jsonDecode(raw);
      if (envelope is! Map ||
          envelope['key'] != 'callRecordChanged' ||
          envelope['sendUserID'] != accountID ||
          envelope['recvUserID'] != accountID) {
        return false;
      }
      final data = envelope['data'];
      final record =
          CallRecordsApi.decodeRecord(data is String ? jsonDecode(data) : data);
      final enriched = await _enrich([record]);
      if (!isCurrent) return false;
      await cache.applyRemoteCallRecords(enriched,
          accountID: accountID, isSessionCurrent: () => isCurrent);
      return isCurrent;
    } catch (_) {
      // An untrusted/malformed notice never changes the private call cache.
      return false;
    }
  }

  void dispose() {
    _closed = true;
    _again = false;
  }
}
