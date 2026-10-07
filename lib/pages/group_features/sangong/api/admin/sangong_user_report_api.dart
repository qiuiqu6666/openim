import '../../models/sangong_user_flow_result.dart';
import '../sangong_game_http.dart';
import '../sangong_v2_api.dart';

class SangongUserReportApi {
  SangongUserReportApi(this.http);
  final SangongGameHttp http;

  Future<SangongUserFlowResult> fetch(
      {required String imUserId, int? sessionId, String? date}) async {
    final id = imUserId.trim();
    if (id.isEmpty || (sessionId != null && date != null)) {
      throw ArgumentError('请指定用户及一种统计范围');
    }
    final context = http.context, tenant = http.tenantId;
    final api = SangongV2Api(http);
    final query = <String, dynamic>{
      'imUserId': id,
      if (sessionId != null) 'sessionId': sessionId,
      if (date != null) 'date': date,
      'limit': 100,
    };
    final first = await api.read('user-report', query: query);
    final user = first['user'];
    if (user is! Map ||
        user['imUserId'] != id ||
        first['summary'] is! Map ||
        first['entries'] is! List ||
        first['totalEntries'] is! int) {
      throw const FormatException('用户报表格式或身份无效');
    }
    final entries = List<dynamic>.from(first['entries']);
    var cursor = _cursor(first);
    while (cursor > 0 && entries.length < SangongUserFlowResult.ledgerLimit) {
      if (!identical(http.context, context) || http.tenantId != tenant) {
        throw StateError('群或账号已变化');
      }
      final page =
          await api.read('user-report', query: {...query, 'beforeId': cursor});
      if (page['version'] != first['version'] ||
          page['entries'] is! List ||
          page['user'] is! Map ||
          page['user']['imUserId'] != id) {
        throw StateError('用户报表已更新，请刷新后查看');
      }
      entries.addAll(page['entries'] as List);
      final next = _cursor(page);
      if (next >= cursor) throw const FormatException('流水分页游标无效');
      cursor = next;
    }
    if (!identical(http.context, context) || http.tenantId != tenant) {
      throw StateError('群或账号已变化');
    }
    return SangongUserFlowResult.fromJson(
        {...first, 'entries': entries, 'nextBeforeId': cursor});
  }

  int _cursor(Map<String, dynamic> data) {
    final cursor = data['nextBeforeId'];
    if (cursor is! int || cursor < 0) {
      throw const FormatException('流水分页游标无效');
    }
    return cursor;
  }
}
