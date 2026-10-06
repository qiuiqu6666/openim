import 'dart:async';
import 'dart:convert';

import 'package:openim/pages/mine/secondary/calls/data/call_records_api.dart';
import 'package:openim_common/openim_common.dart';

import 'recent_call_test_support.dart';

class RecentCallsRequest {
  RecentCallsRequest(this.syncAt, this.limit, this.token);
  final int syncAt;
  final int limit;
  final String token;
  final result = Completer<CallRecordsPage>();

  void complete(List<CallRecords> records, {int? syncAt}) {
    final watermark = syncAt ??
        records.fold<int>(
            this.syncAt,
            (latest, record) =>
                record.updatedAt > latest ? record.updatedAt : latest);
    result.complete(CallRecordsPage(records: records, syncAt: watermark));
  }
}

class RecentCallsUiApi implements CallRecordsApi {
  final requests = <RecentCallsRequest>[];
  final reports = <CallRecords>[];

  @override
  String get baseUrl => 'https://chat-test.example';

  @override
  Future<CallRecordsPage> page(
      {required int syncAt, int limit = 200, required String token}) {
    final request = RecentCallsRequest(syncAt, limit, token);
    requests.add(request);
    return request.result.future;
  }

  @override
  Future<CallRecords> report(CallRecords record,
      {required String token}) async {
    reports.add(record.copy());
    return record.copy();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CallRecords remoteCall(
    {required String callID,
    String peer = 'peer-1',
    String name = '阿明',
    String status = 'completed',
    bool incoming = false,
    int duration = 73,
    int? updatedAt}) {
  final record = callFixture(
    room: callID,
    peer: peer,
    nickname: name,
    incoming: incoming,
    success: status == 'completed',
    state: status,
    duration: status == 'completed' ? duration : 0,
  );
  record.endedAt = record.startedAt + duration * 1000;
  record.updatedAt = updatedAt ?? record.endedAt + 1000;
  return record;
}

String callRecordNotice(CallRecords record, {String account = 'account-a'}) =>
    jsonEncode({
      'key': 'callRecordChanged',
      'sendUserID': account,
      'recvUserID': account,
      'data': jsonEncode({
        'callID': record.callID,
        'mediaType': record.type,
        'roomType': record.roomType,
        'direction': record.incomingCall ? 'in' : 'out',
        'status': record.status,
        'peerUserID': record.userID,
        'groupID': record.groupID,
        'duration': record.duration,
        'startedAt': record.startedAt,
        'endedAt': record.endedAt,
        'updatedAt': record.updatedAt,
      }),
    });
