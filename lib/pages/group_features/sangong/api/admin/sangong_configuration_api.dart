import 'package:dio/dio.dart';
import '../../models/sangong_my_config.dart';
import '../../utils/api_response_util.dart';
import '../sangong_game_http.dart';
import '../sangong_scoped_requests.dart';

/// Configuration belongs to the current game group, including its operators.
class SangongConfigurationApi {
  SangongConfigurationApi(this.http);
  final SangongGameHttp http;
  SangongScopedRequests get _dio => http.requests;
  Map<String, dynamic> _asMap(dynamic raw) {
    final value = unwrapApiPayload(raw);
    if (value is! Map) {
      throw const FormatException('Invalid group configuration');
    }
    return Map<String, dynamic>.from(value);
  }

  /// 当前游戏群的三公配置。方法名保留给现有页面，路由只绑定当前群。
  SangongMyConfig _parseMyConfig(dynamic raw) {
    final map = _asMap(raw);
    if (!map.containsKey('configured') ||
        !_hasReadableConfigurationStatus(map['configured'])) {
      throw const FormatException('Invalid Sangong configuration response');
    }
    return SangongMyConfig.fromJson(map);
  }

  // An unknown status must not become a first-time configuration via the
  // model's false default. Keep accepted values aligned with its bool reader.
  bool _hasReadableConfigurationStatus(dynamic value) {
    if (value is bool || value is num) return true;
    if (value is String) {
      return const {'true', 'false', '1', '0', 'yes', 'no'}
          .contains(value.trim().toLowerCase());
    }
    return false;
  }

  Future<SangongMyConfig> fetchMyConfig() async {
    final res = await _dio.get(
      '/api/v2/groups/${Uri.encodeComponent(http.context.groupID)}/config',
      options: Options(
        extra: const {SangongGameHttp.extraSkipTenant: true},
      ),
    );
    return _parseMyConfig(res.data);
  }

  /// 群主保存 / 认领下注群配置（不要求 `X-Tenant-Id`）。
  Future<SangongMyConfig> saveMyConfig({
    required String name,
    required String imGroupGameId,
    required String imGroupAdminStatsId,
    String imGroupLedgerId = '',
    required String imBotUserId,
    String imGroupWaterId = '',
  }) async {
    if (imGroupGameId.trim() != http.context.groupID) {
      throw ArgumentError('下注群必须是当前群');
    }
    final body = <String, dynamic>{
      'name': name.trim(),
      'imGroupGameId': imGroupGameId.trim(),
      'imGroupAdminStatsId': imGroupAdminStatsId.trim(),
      'imGroupLedgerId': imGroupLedgerId.trim(),
      'imBotUserId': imBotUserId.trim(),
    };
    final water = imGroupWaterId.trim();
    if (water.isNotEmpty) {
      body['imGroupWaterId'] = water;
    }
    final res = await _dio.put(
      '/api/v2/groups/${Uri.encodeComponent(http.context.groupID)}/config',
      data: body,
      options: Options(
        extra: const {SangongGameHttp.extraSkipTenant: true},
      ),
    );
    return _parseMyConfig(res.data);
  }

  /// 当前下注群的运营成员列表，群 ID 和用户 ID 均按路径段编码。
  ///
  /// `GET /api/v2/groups/{groupId}/access`。
  Future<List<SangongTenantAccessMember>> fetchMyConfigMembers() async {
    final res = await _dio.get(
      '/api/v2/groups/${Uri.encodeComponent(http.context.groupID)}/access',
      options: Options(
        extra: const {SangongGameHttp.extraSkipTenant: true},
      ),
    );
    final payload = unwrapApiPayload(res.data);
    final list = extractApiList(
      payload,
      listKeys: const ['members', 'items', 'access', 'data'],
    );
    return list
        .whereType<Map>()
        .map(
          (e) => SangongTenantAccessMember.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  /// 群主添加 / 修改帮工。`role` 一般为 `admin`。
  ///
  /// `POST /api/v2/groups/{groupId}/access`。
  Future<void> upsertMyConfigMember({
    required String imUserId,
    String role = 'admin',
  }) async {
    final userId = imUserId.trim();
    final normalizedRole = role.trim().toLowerCase();
    if (userId.isEmpty) {
      throw ArgumentError('imUserId required');
    }
    await _dio.post(
      '/api/v2/groups/${Uri.encodeComponent(http.context.groupID)}/access',
      data: <String, dynamic>{
        'imUserId': userId,
        'role': normalizedRole.isEmpty ? 'admin' : normalizedRole,
      },
      options: Options(
        extra: const {SangongGameHttp.extraSkipTenant: true},
      ),
    );
  }

  /// 群主移除成员。
  ///
  /// `DELETE /api/v2/groups/{groupId}/access/{imUserId}`。
  Future<void> removeMyConfigMember({
    required String imUserId,
  }) async {
    final userId = Uri.encodeComponent(imUserId.trim());
    if (userId.isEmpty) {
      throw ArgumentError('imUserId required');
    }
    await _dio.delete(
      '/api/v2/groups/${Uri.encodeComponent(http.context.groupID)}/access/$userId',
      options: Options(
        extra: const {SangongGameHttp.extraSkipTenant: true},
      ),
    );
  }

  /// 无本地租户时：单租户自动选中；多租户需先进入游戏群。
  Future<bool> ensureTenantSelected() async => http.hasTenant;
}
