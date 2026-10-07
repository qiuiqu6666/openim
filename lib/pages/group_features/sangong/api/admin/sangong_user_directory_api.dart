import '../../models/sangong_admin_models.dart';
import '../sangong_game_http.dart';
import '../sangong_v2_api.dart';

/// Cursor pagination is kept inside the directory's current group runtime.
class SangongUserDirectoryApi {
  SangongUserDirectoryApi(this.http);
  final SangongGameHttp http;
  final _cursors = <String, Map<int, int>>{};
  SangongV2Api get _api => SangongV2Api(http);

  Future<SangongAdminUserReportPage> page(
      {int? groupId, int page = 1, int pageSize = 50}) async {
    if (page < 1) throw ArgumentError('page must be positive');
    final size = pageSize.clamp(1, 100);
    final key =
        '${http.context.currentUserID}/${http.context.groupID}/${http.tenantId}/$groupId/$size';
    if (page == 1) _cursors[key] = {1: 0};
    final cursor = _cursors[key]?[page];
    if (cursor == null) throw StateError('请从首页刷新用户列表');
    final result = await _api.read('users', query: {
      'limit': size,
      if (cursor > 0) 'beforeId': cursor,
      if (groupId != null) 'groupId': groupId
    });
    if (result['users'] is! List ||
        result['total'] is! int ||
        result['nextBeforeId'] is! int) {
      throw const FormatException('群用户列表格式无效');
    }
    final next = result['nextBeforeId'] as int;
    if (next > 0) _cursors[key]![page + 1] = next;
    final total = result['total'] as int;
    return SangongAdminUserReportPage(
        users: (result['users'] as List).map((row) {
          if (row is! Map ||
              row['userId'] is! int ||
              row['imUserId'] is! String ||
              row['balance'] is! int) {
            throw const FormatException('群用户资料无效');
          }
          return SangongAdminUserReport.fromJson(
              Map<String, dynamic>.from(row));
        }).toList(),
        page: page,
        pageSize: size,
        total: total,
        totalPages: total == 0 ? 0 : (total + size - 1) ~/ size);
  }

  Future<Map<String, dynamic>> detail(String imUserId) async {
    final target = imUserId.trim();
    if (target.isEmpty) throw ArgumentError('imUserId required');
    final data = await _api.read('user', query: {'imUserId': target});
    final user = data['user'];
    if (data['exists'] == false && user == null) return data;
    if (data['exists'] != true ||
        user is! Map ||
        user['imUserId'] != target ||
        user['balance'] is! int) {
      throw const FormatException('用户资料与当前账号不匹配');
    }
    return data;
  }

  Future<SangongAdminUserReport?> find(String imUserId) async {
    final data = await detail(imUserId);
    return data['exists'] == false
        ? null
        : SangongAdminUserReport.fromJson(
            Map<String, dynamic>.from(data['user']));
  }
}
