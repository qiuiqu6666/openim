import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';

class BatchReadTarget {
  const BatchReadTarget(this.conversationID, this.hasReadSeq);
  final String conversationID;
  final int hasReadSeq;

  Map<String, dynamic> toJson() =>
      {'conversationID': conversationID, 'hasReadSeq': hasReadSeq};

  factory BatchReadTarget.fromJson(Map json) {
    final id = json['conversationID'];
    final seq = json['hasReadSeq'];
    if (id is! String || id.isEmpty || seq is! int || seq <= 0) {
      throw const FormatException('Invalid batch read target');
    }
    return BatchReadTarget(id, seq);
  }
}

/// Captures credentials once so a batch cannot cross an account/server switch.
class ConversationBatchReadApi {
  ConversationBatchReadApi()
      : _base = Config.imApiUrl,
        _token = DataSp.imToken,
        _user = DataSp.userID;

  final String _base;
  final String? _token, _user;
  final _cancel = CancelToken();

  bool get isCurrent =>
      _token != null &&
      _token.isNotEmpty &&
      _user == DataSp.userID &&
      _token == DataSp.imToken &&
      _base == Config.imApiUrl;

  void close() => _cancel.cancel();

  Future<Map> _post(String route, Map<String, dynamic> body) async {
    if (!isCurrent) throw StateError('Session is no longer active');
    final data = await HttpUtil.post('$_base/msg/$route',
        data: body,
        showErrorToast: false,
        cancelToken: _cancel,
        options: Options(
            headers: {'token': _token},
            receiveTimeout: const Duration(seconds: 30)));
    if (!isCurrent) throw StateError('Session is no longer active');
    if (data is! Map) {
      throw const FormatException('Invalid batch read response');
    }
    return data;
  }

  Future<List<BatchReadTarget>> prepare(String scope,
      {List<String>? conversationIDs}) async {
    final data = await _post('prepare_batch_read', {
      'scope': scope,
      if (conversationIDs != null) 'conversationIDs': conversationIDs,
    });
    final rows = data['targets'];
    if (rows is! List) throw const FormatException('Missing read targets');
    return rows.map((row) => BatchReadTarget.fromJson(row as Map)).toList();
  }

  Future<Set<String>> apply(List<BatchReadTarget> targets) async {
    final data = await _post('batch_mark_conversations_as_read',
        {'targets': targets.map((target) => target.toJson()).toList()});
    final results = data['results'];
    if (results is! List) throw const FormatException('Missing read results');
    final expected = {for (final t in targets) t.conversationID: t.hasReadSeq};
    return {
      for (final row in results)
        if (row is Map &&
            row['success'] == true &&
            expected.containsKey(row['conversationID']) &&
            expected[row['conversationID']] == row['hasReadSeq'])
          row['conversationID'] as String,
    };
  }
}
