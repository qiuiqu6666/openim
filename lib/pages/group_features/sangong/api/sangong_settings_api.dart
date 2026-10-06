// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:dio/dio.dart';
import 'package:openim/pages/group_features/sangong/api/sangong_game_http.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_game_settings.dart';

import 'package:openim/pages/group_features/sangong/utils/api_response_util.dart';
import 'sangong_scoped_requests.dart';

class SangongSettingsLoadResult {
  const SangongSettingsLoadResult({
    required this.settings,
    required this.canEdit,
  });

  final SangongGameSettings settings;
  final bool canEdit;
}

/// 三公游戏规则：`GET/PUT /api/v1/settings`（经主服务 `/sangong`）。
/// 读取需服务端确认的 `X-Tenant-Id`；写入另需当前用户的配置权限。
class SangongSettingsApi {
  SangongSettingsApi(this.http, {required this.mayEdit});
  final SangongGameHttp http;
  final bool Function() mayEdit;

  static const String settingsPath = '/api/v1/settings';

  SangongScopedRequests get _dio => http.requests;

  bool get canEdit => http.canCallAdmin && mayEdit();

  SangongGameSettings _parseSettings(dynamic raw) {
    var payload = unwrapApiPayload(raw);
    if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);
      final nested = map['settings'];
      if (nested is Map) {
        return SangongGameSettings.fromJson(Map<String, dynamic>.from(nested));
      }
      if (map.containsKey('doorCount') ||
          map.containsKey('door_count') ||
          map.containsKey('points')) {
        return SangongGameSettings.fromJson(map);
      }
    }
    throw const FormatException('Invalid Sangong settings response');
  }

  Future<SangongGameSettings> fetch() async {
    final res = await _dio.get(settingsPath);
    return _parseSettings(res.data);
  }

  Future<SangongSettingsLoadResult> loadForUi() async {
    final settings = await fetch();
    return SangongSettingsLoadResult(
      settings: settings,
      canEdit: canEdit,
    );
  }

  Future<SangongGameSettings> save(SangongGameSettings settings) async {
    if (!http.hasAuth) {
      throw DioException(
        requestOptions: RequestOptions(path: settingsPath),
        type: DioExceptionType.unknown,
        error: 'UNAUTHORIZED',
      );
    }
    if (!http.hasTenant) {
      throw DioException(
        requestOptions: RequestOptions(path: settingsPath),
        type: DioExceptionType.unknown,
        error: 'TENANT_REQUIRED',
      );
    }
    final res = await http.requests.put(
      settingsPath,
      data: settings.toJson(),
    );
    return _parseSettings(res.data);
  }
}
