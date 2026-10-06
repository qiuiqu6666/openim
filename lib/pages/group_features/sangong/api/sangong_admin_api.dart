// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:dio/dio.dart';
import '../../data/group_feature_api.dart';
import 'package:openim/pages/group_features/sangong/api/sangong_game_http.dart';
import 'package:openim/pages/group_features/sangong/api/sangong_settings_api.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_bet_submit_cutoff.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_realtime_state.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_game_settings.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_my_config.dart';
import '../models/sangong_user_flow_result.dart';
import '../services/authorization/sangong_operation_scope.dart';
import 'sangong_scoped_requests.dart';
import 'package:openim/pages/group_features/sangong/utils/api_response_util.dart';

/// 三公运营接口（当前 Chat token + 服务端确认的 `X-Tenant-Id`）。
class SangongAdminApi {
  SangongAdminApi(this.http);
  final SangongGameHttp http;

  SangongScopedRequests get _dio => http.requests;

  Map<String, dynamic> _asMap(dynamic raw) {
    final payload = unwrapApiPayload(raw);
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    return const {};
  }

  SangongAdminSession _parseSession(dynamic raw) {
    final map = _asMap(raw);
    if (map.containsKey('round')) {
      return SangongAdminSession.fromJson(map);
    }
    throw const FormatException('Invalid Sangong session response');
  }

  List<SangongAdminUserReport> _parseUserReports(dynamic raw) {
    final payload = unwrapApiPayload(raw);
    final list = extractApiList(
      payload,
      listKeys: const ['users', 'items', 'reports'],
    );
    return list
        .whereType<Map>()
        .map((e) =>
            SangongAdminUserReport.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  SangongBalanceMutationResult _parseBalanceResult(dynamic raw) {
    final map = _asMap(raw);
    final user = map['user'] is Map ? map['user'] as Map : map;
    if (num.tryParse('${user['balance']}') == null) _unknownResult();
    return SangongBalanceMutationResult.fromResponse(map);
  }

  Never _unknownResult() => throw const GroupFeatureException('操作结果尚未确认，请刷新后查看',
      code: 'UNKNOWN_RESULT', unknownResult: true);

  SangongSessionMutationResult _parseSessionMutation(dynamic raw,
      {required bool running}) {
    final result = SangongSessionMutationResult.fromJson(_asMap(raw));
    final states = [result.status, result.session?.status ?? '']
        .map((state) => state.trim().toLowerCase());
    final confirmed = running
        ? states.contains('running')
        : states.any(const {'idle', 'stopped', 'ended'}.contains);
    if (!confirmed) _unknownResult();
    return result;
  }

  SangongGameSettings _parseSettings(dynamic raw) {
    final map = _asMap(raw);
    final nested = map['settings'];
    if (nested is Map) {
      return SangongGameSettings.fromJson(Map<String, dynamic>.from(nested));
    }
    if (map.containsKey('doorCount') || map.containsKey('minBet')) {
      return SangongGameSettings.fromJson(map);
    }
    throw const FormatException('Invalid Sangong settings response');
  }

  Future<SangongAdminSession> fetchSession() async {
    final res = await _dio.get('/api/v1/admin/session');
    return _parseSession(res.data);
  }

  Future<void> setupAdminAccount(
      {required String username, required String password}) async {
    await _dio.post('/api/v1/admin/auth/setup',
        data: {'username': username, 'password': password});
  }

  /// 开机：创建新会话，期数从第 1 期开始。
  Future<SangongSessionMutationResult> startSession() async {
    final res = await _dio.post(
      '/api/v1/admin/session/start',
      data: const <String, dynamic>{},
    );
    return _parseSessionMutation(res.data, running: true);
  }

  /// 关机：未结算当前局会作废并退款；有已结算局时发送最终管理账单。
  Future<SangongSessionMutationResult> stopSession() async {
    final res = await _dio.post(
      '/api/v1/admin/session/stop',
      data: const <String, dynamic>{},
    );
    return _parseSessionMutation(res.data, running: false);
  }

  /// 拉取管理端实时状态快照（首屏或断线重连）。
  Future<SangongAdminRealtimeState> fetchEventsSnapshot() async {
    final res = await _dio.get('/api/v1/admin/events/snapshot');
    final map = _asMap(res.data);
    final stateRaw = map['state'] ?? map;
    if (stateRaw is Map &&
        stateRaw.containsKey('version') &&
        stateRaw['settings'] is Map) {
      return SangongAdminRealtimeState.fromRequiredJson(
        Map<String, dynamic>.from(stateRaw),
      );
    }
    throw const FormatException('Invalid Sangong realtime response');
  }

  Future<SangongAdminUserReportPage> fetchUserReports({
    int? groupId,
    int page = 1,
    int pageSize = 50,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safePageSize = pageSize.clamp(1, 200);
    final query = <String, dynamic>{
      'page': safePage,
      'pageSize': safePageSize,
    };
    if (groupId != null) {
      query['groupId'] = groupId;
    }
    final res = await _dio.get(
      '/api/v1/admin/reports/users',
      queryParameters: query,
    );
    return _parseUserReportPage(
      res.data,
      requestedPage: safePage,
      requestedPageSize: safePageSize,
    );
  }

  SangongAdminUserReportPage _parseUserReportPage(
    dynamic raw, {
    required int requestedPage,
    required int requestedPageSize,
  }) {
    final payload = unwrapApiPayload(raw);
    final users = _parseUserReports(raw);
    if (payload is! Map) {
      return SangongAdminUserReportPage(
        users: users,
        page: requestedPage,
        pageSize: requestedPageSize,
        total: users.length,
        totalPages: users.isEmpty ? 0 : 1,
      );
    }
    final map = Map<String, dynamic>.from(payload);
    int asInt(dynamic value, int fallback) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    final page = asInt(map['page'], requestedPage);
    final size = asInt(map['pageSize'] ?? map['page_size'], requestedPageSize);
    final total = asInt(map['total'], users.length);
    var totalPages = asInt(
      map['totalPages'] ?? map['total_pages'],
      size <= 0 ? 1 : ((total + size - 1) / size).ceil(),
    );
    if (totalPages < 0) {
      totalPages = 0;
    }
    return SangongAdminUserReportPage(
      users: users,
      page: page,
      pageSize: size,
      total: total,
      totalPages: totalPages,
    );
  }

  Future<Map<String, dynamic>> fetchUserDetail(String imUserId) async {
    final response = await _dio.get(
      '/api/v1/admin/reports/user-detail',
      queryParameters: {'imUserId': imUserId.trim()},
    );
    return _asMap(response.data);
  }

  /// 查询指定用户本人及全部下级团队，可选查询日期。
  Future<List<Map<String, dynamic>>> fetchUserHierarchyReport({
    String? imUserId,
    int? userId,
    String? date,
    int? sessionId,
  }) async {
    final query = <String, dynamic>{
      if (imUserId != null && imUserId.trim().isNotEmpty)
        'imUserId': imUserId.trim(),
      if (userId != null) 'userId': userId,
      if (sessionId != null) 'sessionId': sessionId,
      if (sessionId == null && date != null && date.trim().isNotEmpty)
        'date': date.trim(),
    };
    // 不传用户参数时，查询当前租户全部顶级用户及其完整下级团队。
    final response = await _dio.get(
      '/api/v1/admin/reports/user-hierarchy',
      queryParameters: query,
    );
    final payload = unwrapApiPayload(response.data);
    final list = extractApiList(
      payload,
      listKeys: const ['members', 'users', 'team', 'items', 'reports'],
    );
    return list
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  /// 租户列表（不要求 `X-Tenant-Id`）。
  Future<List<Map<String, dynamic>>> fetchReportSessions() async {
    final response = await _dio
        .get('/api/v1/admin/sessions', queryParameters: {'limit': 30});
    final data = _asMap(response.data);
    return (data['sessions'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<SangongTenantInfo>> fetchTenants() async {
    final res = await _dio.get(
      '/api/v1/admin/tenants',
      options: Options(
        extra: const {SangongGameHttp.extraSkipTenant: true},
      ),
    );
    final payload = unwrapApiPayload(res.data);
    final list = extractApiList(
      payload,
      listKeys: const ['tenants', 'items', 'data'],
    );
    return list
        .whereType<Map>()
        .map((e) => SangongTenantInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 当前账号的三公配置（不要求 `X-Tenant-Id`）。
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
      '/api/v1/admin/my-config',
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
      '/api/v1/admin/my-config',
      data: body,
      options: Options(
        extra: const {SangongGameHttp.extraSkipTenant: true},
      ),
    );
    return _parseMyConfig(res.data);
  }

  /// 当前账号绑定下注群的成员列表（不拼群 ID，避免 `@TGS#` 被锚点截断）。
  ///
  /// `GET /api/v1/admin/my-config/members`，不要求 `X-Tenant-Id`。
  Future<List<SangongTenantAccessMember>> fetchMyConfigMembers() async {
    final res = await _dio.get(
      '/api/v1/admin/my-config/members',
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
  /// `POST /api/v1/admin/my-config/members`
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
      '/api/v1/admin/my-config/members',
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
  /// `DELETE /api/v1/admin/my-config/members/{imUserId}`
  Future<void> removeMyConfigMember({
    required String imUserId,
  }) async {
    final userId = Uri.encodeComponent(imUserId.trim());
    if (userId.isEmpty) {
      throw ArgumentError('imUserId required');
    }
    await _dio.delete(
      '/api/v1/admin/my-config/members/$userId',
      options: Options(
        extra: const {SangongGameHttp.extraSkipTenant: true},
      ),
    );
  }

  /// 无本地租户时：单租户自动选中；多租户需先进入游戏群。
  Future<bool> ensureTenantSelected() async => http.hasTenant;

  Future<SangongAdminUserReport?> findUserReport(String imUserId) async {
    final target = imUserId.trim();
    if (target.isEmpty) {
      return null;
    }
    var page = 1;
    while (page <= 100) {
      final result = await fetchUserReports(page: page, pageSize: 200);
      for (final report in result.users) {
        if (report.imUserId.trim() == target) {
          return report;
        }
      }
      if (!result.hasMore || result.users.isEmpty) {
        return null;
      }
      page += 1;
    }
    return null;
  }

  /// 用户详细流水：支持 `userId` / `imUserId` / `sessionId`（最多 500 条）。
  ///
  /// `GET /api/v1/admin/reports/user-flow`
  Future<SangongUserFlowReport> fetchUserFlow({
    String? imUserId,
    int? userId,
    int? sessionId,
  }) async =>
      (await fetchUserFlowResult(
              imUserId: imUserId, userId: userId, sessionId: sessionId))
          .report;

  /// Only identity/session filters are supported by the confirmed contract.
  /// Natural-day totals use fetchUserHierarchyReport(date: ...); flow detail
  /// remains newest-500 data and must expose that limit to the reader.
  Future<SangongUserFlowResult> fetchUserFlowResult({
    String? imUserId,
    int? userId,
    int? sessionId,
  }) async {
    final query = <String, dynamic>{};
    final im = imUserId?.trim() ?? '';
    if (im.isNotEmpty) {
      query['imUserId'] = im;
    } else if (userId != null && userId > 0) {
      query['userId'] = userId;
    }
    if (sessionId != null && sessionId > 0) {
      query['sessionId'] = sessionId;
    }
    final res = await _dio.get(
      '/api/v1/admin/reports/user-flow',
      queryParameters: query,
      options: Options(receiveTimeout: const Duration(milliseconds: 60000)),
    );
    return SangongUserFlowResult.fromJson(_asMap(res.data));
  }

  Future<SangongBalanceMutationResult> credit({
    required String imUserId,
    required int amount,
    String? operator,
    String? note,
  }) async {
    final op = operator?.trim() ?? '';
    final res = await _dio.post(
      '/api/v1/admin/users/credit',
      data: {
        'imUserId': imUserId.trim(),
        'amount': amount,
        if (op.isNotEmpty) 'operator': op,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return _parseBalanceResult(res.data);
  }

  Future<SangongBalanceMutationResult> debit({
    required String imUserId,
    required int amount,
    String? operator,
    String? note,
  }) async {
    final op = operator?.trim() ?? '';
    final res = await _dio.post(
      '/api/v1/admin/users/debit',
      data: {
        'imUserId': imUserId.trim(),
        'amount': amount,
        if (op.isNotEmpty) 'operator': op,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return _parseBalanceResult(res.data);
  }

  /// 群主/帮工设置可负额度。路径必须是三公内部数字 `userId`。
  ///
  /// `PUT /api/v1/admin/users/{userId}/max-negative`
  Future<Map<String, dynamic>> setUserMaxNegative({
    required int userId,
    required int maxNegative,
    String? imUserId,
  }) async {
    if (userId <= 0) {
      throw ArgumentError('userId required');
    }
    if (maxNegative < 0) {
      throw ArgumentError('maxNegative must be >= 0');
    }
    final scope = SangongOperationScope.capture(http.context, http.tenantId);
    bool current() =>
        http.hasAuth && scope.matches(http.context, http.tenantId);
    final res = await _dio.put(
      '/api/v1/admin/users/$userId/max-negative',
      data: {'maxNegative': maxNegative},
    );
    if (!current()) _unknownResult();
    final response = _asMap(res.data);
    Map<String, dynamic>? confirmedUser(Map<String, dynamic> payload) {
      final rawUser = payload['user'];
      final user =
          rawUser is Map ? Map<String, dynamic>.from(rawUser) : payload;
      final id =
          int.tryParse('${user['userId'] ?? user['user_id'] ?? user['id']}');
      final amount = int.tryParse(
          '${user['maxNegative'] ?? user['max_negative_balance']}');
      final returnedIm =
          '${user['imUserId'] ?? user['im_user_id'] ?? ''}'.trim();
      final expectedIm = imUserId?.trim() ?? '';
      if (id != userId ||
          amount != maxNegative ||
          (expectedIm.isNotEmpty &&
              returnedIm.isNotEmpty &&
              returnedIm != expectedIm)) {
        return null;
      }
      return user;
    }

    var user = confirmedUser(response);
    final target = imUserId?.trim() ?? '';
    if (user == null && target.isNotEmpty) {
      // A legacy void ack is accepted only after one authoritative read.
      // Never retry the write when its result cannot be confirmed.
      try {
        user = confirmedUser(await fetchUserDetail(target));
      } catch (_) {
        _unknownResult();
      }
    }
    if (user == null || !current()) _unknownResult();
    return {...response, 'user': user};
  }

  /// [group] 分组编号，如 `1`、`A`；`0` 或空字符串表示取消分组。
  Future<SangongBalanceMutationResult> setUserGroup({
    required String imUserId,
    required String group,
  }) async {
    final res = await _dio.put(
      '/api/v1/admin/users/group',
      data: {
        'imUserId': imUserId.trim(),
        'group': group.trim(),
      },
    );
    return _parseBalanceResult(res.data);
  }

  /// 设庄（全局门数 2～10），仅传 [door]，不传用户。
  Future<SangongGameSettings> setDoorCount(int door) async {
    final res = await _dio.post(
      '/api/v1/admin/banker/setup',
      data: {'door': door},
    );
    return _parseSettings(res.data);
  }

  /// 定庄：指定用户、庄门与展示限额（写入 round.bankerLimit，不自动合庄出资）。
  Future<SangongAdminSession> assignBanker({
    required String imUserId,
    required int door,
    int? limit,
    String? nickname,
  }) async {
    final res = await _dio.post(
      '/api/v1/admin/banker/setup',
      data: {
        'imUserId': imUserId.trim(),
        'door': door,
        if (limit != null) 'limit': limit,
        if (nickname != null && nickname.trim().isNotEmpty)
          'nickname': nickname.trim(),
      },
    );
    return _parseSession(res.data);
  }

  Future<void> sendBankerNotification() async {
    await _dio.post('/api/v1/admin/banker/send');
  }

  /// 快速定庄：解析消息文本、定庄并发送群通知（等同 setup-banker + banker/send）。
  Future<SangongQuickSetupBankerResult> quickSetupBanker({
    int? messageId,
    String? text,
    String? imUserId,
    String? nickname,
    int? door,
    int? limit,
  }) async {
    final body = <String, dynamic>{
      if (messageId != null && messageId > 0) 'messageId': messageId,
      if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
      if (imUserId != null && imUserId.trim().isNotEmpty)
        'imUserId': imUserId.trim(),
      if (nickname != null && nickname.trim().isNotEmpty)
        'nickname': nickname.trim(),
      if (door != null && door > 0) 'door': door,
      if (limit != null) 'limit': limit,
    };
    final res = await _dio.post(
      '/api/v1/admin/banker/quick-setup',
      data: body,
    );
    return SangongQuickSetupBankerResult.fromJson(_asMap(res.data));
  }

  Future<SangongAdminSession> addCoBank({
    int? roundId,
    required int userId,
    required int amount,
  }) async {
    final path = roundId != null && roundId > 0
        ? '/api/v1/admin/rounds/$roundId/co-bank'
        : '/api/v1/admin/rounds/current/co-bank';
    final res = await _dio.post(
      path,
      data: {
        'userId': userId,
        'amount': amount,
      },
    );
    return _parseSession(res.data);
  }

  Future<void> sendCoBankNotification() async {
    await _dio.post('/api/v1/admin/co-bank/send');
  }

  /// 取消指定用户在当前局的合庄。
  Future<SangongAdminSession> removeCoBank({required int userId}) async {
    final res = await _dio.post(
      '/api/v1/admin/rounds/current/co-bank/remove',
      data: {'userId': userId},
    );
    return _parseSession(res.data);
  }

  /// 关闭合庄窗口。
  Future<SangongAdminSession> closeCoBank({int? roundId}) async {
    final path = roundId != null && roundId > 0
        ? '/api/v1/admin/rounds/$roundId/co-bank/close'
        : '/api/v1/admin/rounds/current/co-bank/close';
    final res = await _dio.post(path, data: const <String, dynamic>{});
    return _parseSession(res.data);
  }

  /// 截止 / 重新截止下注。
  ///
  /// [cutoff] 为空时截止到本局最新 IM 消息；长按消息截止请传
  /// `untilMessageId` / `untilMsgSeq`（优先级同上）。
  /// 优先使用 [roundId] 路径 `/rounds/{id}/betting/submit`。
  Future<SangongBetSubmitResult> submitBets({
    SangongBetSubmitCutoff? cutoff,
    int? roundId,
  }) async {
    final body = cutoff?.toJson() ?? const <String, dynamic>{};
    final path = roundId != null && roundId > 0
        ? '/api/v1/admin/rounds/$roundId/betting/submit'
        : '/api/v1/admin/betting/submit';
    final res = await _dio.post(path, data: body);
    final map = _asMap(res.data);
    final submit = map['submit'];
    final result = SangongBetSubmitResult.fromJson(map);
    final placed = submit is Map
        ? int.tryParse('${submit['placedCount'] ?? submit['placed_count']}')
        : null;
    final failed = submit is Map
        ? int.tryParse('${submit['failedCount'] ?? submit['failed_count']}')
        : null;
    if (placed == null ||
        failed == null ||
        placed < 0 ||
        failed < 0 ||
        result.round == null ||
        result.round!.id <= 0 ||
        !result.round!.hasBetWindowClose) {
      _unknownResult();
    }
    return result;
  }

  /// 下注预览：截止提交前按消息顺序统计，不落注、不扣款、不关窗。
  ///
  /// 不支持 `send:true`；发送下注图请用 [sendBetReportImage]。
  Future<SangongBetPreviewResult> previewBets({
    SangongBetSubmitCutoff? cutoff,
    int? roundId,
  }) async {
    final body = cutoff?.toJson() ?? const <String, dynamic>{};
    final path = roundId != null && roundId > 0
        ? '/api/v1/admin/rounds/$roundId/betting/preview'
        : '/api/v1/admin/betting/preview';
    final res = await _dio.post(path, data: body);
    return SangongBetPreviewResult.fromJson(_asMap(res.data));
  }

  /// 群发统计清单图片（预览或正式，按截止点；与 betting/preview 同一套 cutoff）。
  ///
  /// `POST /api/v1/admin/reports/bet-image`
  Future<SangongReportImageResult> sendBetReportImage({
    SangongBetSubmitCutoff? cutoff,
    int? roundId,
  }) async {
    final body = <String, dynamic>{
      ...?cutoff?.toJson(),
      if (roundId != null && roundId > 0) 'roundId': roundId,
    };
    final res = await _dio.post(
      '/api/v1/admin/reports/bet-image',
      data: body,
      options: Options(receiveTimeout: const Duration(milliseconds: 60000)),
    );
    return SangongReportImageResult.fromJson(_asMap(res.data));
  }

  /// 群发结算明细图片到游戏群。
  ///
  /// `POST /api/v1/admin/reports/settle-image`
  /// [roundId] 须已结算；省略则取本会话最近已结算局。
  Future<SangongReportImageResult> sendSettleReportImage({int? roundId}) async {
    final body = <String, dynamic>{
      if (roundId != null && roundId > 0) 'roundId': roundId,
    };
    final res = await _dio.post(
      '/api/v1/admin/reports/settle-image',
      data: body,
      options: Options(receiveTimeout: const Duration(milliseconds: 60000)),
    );
    return SangongReportImageResult.fromJson(_asMap(res.data));
  }

  /// 群发流水/抽水账单到管理统计群（非游戏群结算明细）。
  ///
  /// `POST /api/v1/admin/reports/settle-bill`
  Future<SangongReportImageResult> sendSettleBillImage({int? roundId}) async {
    final body = <String, dynamic>{
      if (roundId != null && roundId > 0) 'roundId': roundId,
    };
    final res = await _dio.post(
      '/api/v1/admin/reports/settle-bill',
      data: body,
      options: Options(receiveTimeout: const Duration(milliseconds: 60000)),
    );
    return SangongReportImageResult.fromJson(_asMap(res.data));
  }

  /// 群发用户积分图（当前各用户积分一览 PNG）。
  ///
  /// `POST /api/v1/admin/reports/users/points-image`
  /// [imGroupId] 可选，默认当前游戏群；[groupId] 可选分组，`0` 表示未分组。
  Future<SangongReportImageResult> sendPointsReportImage({
    String? imGroupId,
    int? groupId,
  }) async {
    final body = <String, dynamic>{};
    final group = imGroupId?.trim() ?? '';
    if (group.isNotEmpty) {
      body['imGroupId'] = group;
    }
    if (groupId != null) {
      body['groupId'] = groupId;
    }
    final res = await _dio.post(
      '/api/v1/admin/reports/users/points-image',
      data: body,
      options: Options(receiveTimeout: const Duration(milliseconds: 60000)),
    );
    return SangongReportImageResult.fromJson(_asMap(res.data));
  }

  /// 群发走势图到游戏群（各庄门历史走势 JPEG）。
  Future<SangongReportImageResult> sendTrendReportImage() async {
    final res = await _dio.post(
      '/api/v1/admin/reports/trend-image',
      data: const <String, dynamic>{},
      options: Options(receiveTimeout: const Duration(milliseconds: 60000)),
    );
    return SangongReportImageResult.fromJson(_asMap(res.data));
  }

  /// 一键尝试发送下注图、结算图、积分图和走势图。
  Future<SangongReportImageResult> sendPreviewImages() async {
    final res = await _dio.post(
      '/api/v1/admin/reports/preview-images/send',
      data: const <String, dynamic>{},
      options: Options(receiveTimeout: const Duration(milliseconds: 60000)),
    );
    return SangongReportImageResult.fromJson(_asMap(res.data));
  }

  /// 查询当前局开彩录入状态。
  Future<SangongDrawFetchResult> fetchCurrentDraws() async {
    final res = await _dio.get('/api/v1/admin/rounds/current/draws');
    return SangongDrawFetchResult.fromJson(_asMap(res.data));
  }

  /// 批量录入开彩金额。
  Future<SangongDrawMutationResult> submitDraws(
    List<SangongDrawInput> draws,
  ) async {
    final res = await _dio.post(
      '/api/v1/admin/draws',
      data: {
        'draws': draws.map((e) => e.toJson()).toList(),
      },
    );
    return SangongDrawMutationResult.fromJson(_asMap(res.data));
  }

  /// 本局结算（须先录满开彩，`draw.complete === true`）。
  Future<SangongAdminRound> settleRound(int roundId) async {
    final res = await _dio.post('/api/v1/admin/rounds/$roundId/settle');
    final map = _asMap(res.data);
    final roundRaw = map['round'];
    if (roundRaw is Map) {
      return SangongAdminRound.fromJson(Map<String, dynamic>.from(roundRaw));
    }
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      type: DioExceptionType.unknown,
      error: 'INVALID_SETTLE_RESPONSE',
    );
  }

  /// 冲正结算：撤销分账并清空开彩，下注/合庄保留。
  Future<SangongVoidSettlementResult> voidSettlement(int roundId) async {
    final res = await _dio.post(
      '/api/v1/admin/rounds/$roundId/void-settlement',
    );
    return SangongVoidSettlementResult.fromJson(_asMap(res.data));
  }

  static const String lastSettledResettlePath =
      '/api/v1/admin/rounds/last-settled/resettle';

  /// 设置页冲正重结：定庄前后都打最近已结算局，不带 roundId。
  Future<SangongResettleResult> resettleLastSettled({
    required List<SangongDrawInput> draws,
  }) async {
    if (draws.isEmpty) {
      throw DioException(
        requestOptions: RequestOptions(path: lastSettledResettlePath),
        type: DioExceptionType.unknown,
        error: 'RESETTLE_DRAWS_REQUIRED',
      );
    }
    final res = await _dio.post(
      lastSettledResettlePath,
      data: {
        'draws': draws.map((e) => e.toJson()).toList(),
      },
    );
    return SangongResettleResult.fromJson(_asMap(res.data));
  }

  /// 指定历史局纠正。设置页「冲正重结」不要走这条。
  Future<SangongResettleResult> resettleRound({
    required int roundId,
    required List<SangongDrawInput> draws,
  }) async {
    if (draws.isEmpty) {
      throw DioException(
        requestOptions: RequestOptions(
          path: '/api/v1/admin/rounds/$roundId/resettle',
        ),
        type: DioExceptionType.unknown,
        error: 'RESETTLE_DRAWS_REQUIRED',
      );
    }
    final res = await _dio.post(
      '/api/v1/admin/rounds/$roundId/resettle',
      data: {
        'draws': draws.map((e) => e.toJson()).toList(),
      },
    );
    return SangongResettleResult.fromJson(_asMap(res.data));
  }

  Future<SangongGameSettings> updateMaxBet(int maxBet) async {
    if (!http.hasAuth) {
      throw DioException(
        requestOptions: RequestOptions(path: SangongSettingsApi.settingsPath),
        type: DioExceptionType.unknown,
        error: 'UNAUTHORIZED',
      );
    }
    if (!http.hasTenant) {
      throw DioException(
        requestOptions: RequestOptions(path: SangongSettingsApi.settingsPath),
        type: DioExceptionType.unknown,
        error: 'TENANT_REQUIRED',
      );
    }
    final res = await _dio.put(
      SangongSettingsApi.settingsPath,
      data: {'maxBet': maxBet},
    );
    return _parseSettings(res.data);
  }
}
