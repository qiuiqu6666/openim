// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import '../../data/group_feature_api.dart';
import 'package:openim/pages/group_features/sangong/api/sangong_game_http.dart';
import 'package:openim/pages/group_features/sangong/api/sangong_settings_api.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_bet_submit_cutoff.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_realtime_state.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_game_settings.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_my_config.dart';
import '../models/sangong_user_flow_result.dart';
import 'sangong_scoped_requests.dart';
import 'sangong_v2_api.dart';
import 'admin/sangong_configuration_api.dart';
import 'admin/sangong_wallet_api.dart';
import 'admin/sangong_round_api.dart';
import 'admin/sangong_betting_api.dart';
import 'admin/sangong_user_directory_api.dart';
import 'admin/sangong_report_images_api.dart';
import 'admin/sangong_user_report_api.dart';
import 'package:openim/pages/group_features/sangong/utils/api_response_util.dart';

/// 三公运营接口，使用当前 Chat 登录与明确的群作用域。
class SangongAdminApi {
  SangongAdminApi(this.http);
  final SangongGameHttp http;
  SangongV2Api get _v2 => SangongV2Api(http);

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

  Future<SangongAdminSession> fetchSession() async {
    return _parseSession(await _v2.read('snapshot'));
  }

  /// 开机：创建新会话，期数从第 1 期开始。
  Future<SangongSessionMutationResult> startSession() async {
    return _parseSessionMutation(await _v2.command('session.start', {}),
        running: true);
  }

  /// Close only the batch the operator confirmed, never a newer one.
  Future<SangongSessionMutationResult> stopSession(
      {required int sessionId}) async {
    if (sessionId <= 0) throw ArgumentError('sessionId required');
    return _parseSessionMutation(
        await _v2.command('session.stop', {'sessionId': sessionId}),
        running: false);
  }

  /// 拉取管理端实时状态快照（首屏或断线重连）。
  Future<SangongAdminRealtimeState> fetchEventsSnapshot() async {
    final group = Uri.encodeComponent(http.context.groupID);
    final res = await _dio.get('/api/v2/groups/$group/snapshot');
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

  late final _directory = SangongUserDirectoryApi(http);
  Future<SangongAdminUserReportPage> fetchUserReports(
          {int? groupId, int page = 1, int pageSize = 50}) =>
      _directory.page(groupId: groupId, page: page, pageSize: pageSize);
  Future<Map<String, dynamic>> fetchUserDetail(String imUserId) =>
      _directory.detail(imUserId);

  /// 当前游戏群的经营批次。
  Future<List<Map<String, dynamic>>> fetchReportSessions() async {
    final data = await _v2.read('sessions', query: {'limit': 30});
    return (data['sessions'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  SangongConfigurationApi get _configuration => SangongConfigurationApi(http);
  Future<SangongMyConfig> fetchMyConfig() => _configuration.fetchMyConfig();
  Future<SangongMyConfig> saveMyConfig(
          {required String name,
          required String imGroupGameId,
          required String imGroupAdminStatsId,
          String imGroupLedgerId = '',
          required String imBotUserId,
          String imGroupWaterId = ''}) =>
      _configuration.saveMyConfig(
          name: name,
          imGroupGameId: imGroupGameId,
          imGroupAdminStatsId: imGroupAdminStatsId,
          imGroupLedgerId: imGroupLedgerId,
          imBotUserId: imBotUserId,
          imGroupWaterId: imGroupWaterId);
  Future<List<SangongTenantAccessMember>> fetchMyConfigMembers() =>
      _configuration.fetchMyConfigMembers();
  Future<void> upsertMyConfigMember(
          {required String imUserId, String role = 'admin'}) =>
      _configuration.upsertMyConfigMember(imUserId: imUserId, role: role);
  Future<void> removeMyConfigMember({required String imUserId}) =>
      _configuration.removeMyConfigMember(imUserId: imUserId);
  Future<bool> ensureTenantSelected() async => http.hasTenant;

  Future<SangongAdminUserReport?> findUserReport(String imUserId) =>
      _directory.find(imUserId);

  Future<SangongUserFlowResult> fetchUserFlowResult({
    required String imUserId,
    int? sessionId,
    String? date,
  }) =>
      SangongUserReportApi(http)
          .fetch(imUserId: imUserId, sessionId: sessionId, date: date);

  SangongWalletApi get _wallet => SangongWalletApi(http);
  Future<SangongBalanceMutationResult> credit(
          {required String imUserId,
          required int amount,
          String? operator,
          String? note}) =>
      _wallet.adjust(
          imUserId: imUserId, amount: amount, credit: true, note: note);
  Future<SangongBalanceMutationResult> debit(
          {required String imUserId,
          required int amount,
          String? operator,
          String? note}) =>
      _wallet.adjust(
          imUserId: imUserId, amount: amount, credit: false, note: note);
  Future<Map<String, dynamic>> setUserMaxNegative(
          {required int userId, required int maxNegative, String? imUserId}) =>
      _wallet.setLimit(userId: userId, maxNegative: maxNegative);

  /// [group] 分组编号，如 `1`、`A`；`0` 或空字符串表示取消分组。
  Future<SangongBalanceMutationResult> setUserGroup({
    required String imUserId,
    required String group,
  }) async {
    return _parseBalanceResult(await _v2.command(
        'user.group', {'imUserId': imUserId.trim(), 'group': group.trim()}));
  }

  /// 设庄（全局门数 2～10），仅传 [door]，不传用户。
  Future<SangongGameSettings> setDoorCount(int door) async {
    final api = SangongSettingsApi(http,
        mayEdit: () => http.context.capabilities.sangong.canManage);
    final rules = await api.fetch();
    return api.save(rules.copyWith(doorCount: door));
  }

  SangongRoundApi get _rounds => SangongRoundApi(http);
  Future<SangongAdminSession> assignBanker(
          {required int roundId,
          required String imUserId,
          required int door,
          int? limit,
          String? nickname}) =>
      _rounds.assignBanker(
          roundId: roundId,
          imUserId: imUserId,
          door: door,
          limit: limit,
          nickname: nickname);
  Future<void> sendBankerNotification({required int roundId}) async {
    await _rounds.command('round.open', roundId);
  }

  Future<SangongQuickSetupBankerResult> quickSetupBanker(
          {required int roundId,
          String? text,
          String? imUserId,
          String? nickname,
          int? door,
          int? limit}) =>
      _rounds.quickBanker(
          roundId: roundId,
          text: text,
          imUserId: imUserId,
          nickname: nickname,
          door: door,
          limit: limit);
  Future<SangongAdminSession> addCoBank(
          {required int roundId, required int userId, required int amount}) =>
      _rounds.coBank(
          'round.co_bank', roundId, {'userId': userId, 'amount': amount});
  Future<void> sendCoBankNotification({required int roundId}) async {
    await _rounds.command('round.co_bank_notice', roundId);
  }

  Future<SangongAdminSession> removeCoBank(
          {required int roundId, required int userId}) =>
      _rounds.coBank('round.co_bank_remove', roundId, {'userId': userId});
  Future<SangongAdminSession> closeCoBank({required int roundId}) =>
      _rounds.coBank('round.co_bank_close', roundId);

  Future<SangongBetSubmitResult> submitBets(
          {SangongBetSubmitCutoff? cutoff, required int roundId}) =>
      SangongBettingApi(http).close(roundId, cutoff);
  Future<SangongBetPreviewResult> previewBets(
          {SangongBetSubmitCutoff? cutoff, required int roundId}) =>
      SangongBettingApi(http).preview(roundId, cutoff);

  SangongReportImagesApi get _images => SangongReportImagesApi(http);
  Future<SangongReportImageResult> sendBetReportImage({
    SangongBetSubmitCutoff? cutoff,
    required int roundId,
  }) =>
      _images.send('bets', roundId: roundId, cutoff: cutoff);
  Future<SangongReportImageResult> sendSettleReportImage(
          {required int roundId}) =>
      _images.send('settlement', roundId: roundId);
  Future<SangongReportImageResult> sendSettleBillImage(
          {required int roundId}) =>
      _images.send('bill', roundId: roundId);
  Future<SangongReportImageResult> sendPointsReportImage(
          {String? imGroupId, int? groupId}) =>
      _images.send('points', targetGroupId: imGroupId, groupId: groupId);
  Future<SangongReportImageResult> sendTrendReportImage() =>
      _images.send('trend');

  Future<SangongDrawFetchResult> fetchCurrentDraws() => _rounds.fetchDraws();
  Future<SangongDrawMutationResult> submitDraws(List<SangongDrawInput> draws,
          {required int roundId}) =>
      _rounds.submitDraws(roundId, draws);
  Future<SangongAdminRound> settleRound(int roundId) => _rounds.settle(roundId);
  Future<SangongVoidSettlementResult> voidSettlement(int roundId) =>
      _rounds.reverse(roundId);
  Future<SangongResettleResult> resettleLastSettled(
          {required int roundId, required List<SangongDrawInput> draws}) =>
      _rounds.resettle(roundId, draws);
  Future<SangongResettleResult> resettleRound(
          {required int roundId, required List<SangongDrawInput> draws}) =>
      _rounds.resettle(roundId, draws);

  Future<SangongGameSettings> updateMaxBet(int maxBet) async {
    final api = SangongSettingsApi(http,
        mayEdit: () => http.context.capabilities.sangong.canManage);
    final rules = await api.fetch();
    return api.save(rules.copyWith(maxBet: maxBet));
  }
}
