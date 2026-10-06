import 'package:dio/dio.dart';
import '../../models/group_feature_context.dart';
import '../../data/group_feature_api.dart';
import '../models/live_errors.dart';
import '../models/live_models.dart';
import '../models/live_tip_currency.dart';

/// Chat-token adapter for the deployed group-live contract.
class LiveApi {
  const LiveApi(this.context);
  final GroupFeatureContext context;
  static const prefix = '/group-live/api/v1';
  static const maxTipAmount = 9007199254740991;
  String get groupPath =>
      '$prefix/groups/${Uri.encodeComponent(context.groupID)}/live';
  String sessionPath(String id) => '$prefix/live/${Uri.encodeComponent(id)}';
  void checkSession() {
    if (!context.sessionCurrent()) throw StateError('登录状态已变化，请重新进入');
  }

  void checkPermissionSession({bool resultPending = false}) {
    checkSession();
    if (!context.capabilitiesCurrent()) {
      throw GroupFeatureException('操作权限已变化，请重新打开页面',
          code: 'CAPABILITIES_CHANGED', unknownResult: resultPending);
    }
  }

  void _acceptSummary(Map<String, dynamic> json) {
    final value = json['groupFeatures'];
    if (value is Map) {
      final summary = Map<String, dynamic>.from(value);
      if (GroupFeatures.fromJson(summary).valid) {
        context.acceptFeatures(summary,
            mirrorPending: json['imSyncStatus'] == 'pending');
      }
    }
  }

  Future<Map<String, dynamic>> _request(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      CancelToken? cancelToken}) async {
    try {
      return await context.api
          .request(path, method: method, body: body, cancelToken: cancelToken);
    } on GroupFeatureException catch (error) {
      checkSession();
      if (livePermissionDenied(error)) context.invalidateCapabilities();
      throw mapLiveError(error);
    }
  }

  String _name(String value) {
    final name = value.trim();
    if (name.isEmpty || name.runes.length > 10) {
      throw const FormatException('直播间名称不能为空，且最多 10 个字');
    }
    return name;
  }

  void _id(String value) {
    if (value.trim().isEmpty) throw const FormatException('直播场次 ID 不能为空');
  }

  LiveSession _committedSession(Map<String, dynamic> json,
      {bool ended = false}) {
    checkSession();
    LiveSession? committed;
    try {
      final result = parseSession(json);
      committed = result;
      if (ended && result.status.active) {
        throw const FormatException('服务端尚未确认结束直播');
      }
      final summary = GroupFeatures.fromJson(json['groupFeatures']);
      final status = switch (result.status) {
        LiveStatus.scheduled => 'scheduled',
        LiveStatus.authorized => 'ready',
        LiveStatus.live => 'live',
        _ => 'ended'
      };
      if (!summary.valid ||
          summary.live.sessionID != result.id ||
          summary.live.status != status) {
        throw const FormatException('直播写入响应未返回匹配的完整群摘要');
      }
      _acceptSummary(json);
      // Permission notifications may legitimately follow this committed write.
      // A valid success DTO remains success; session changes still fence it.
      return result;
    } on FormatException {
      throw LiveApiException('操作结果尚未确认，请刷新场次后查看，请勿重复提交',
          code: 'INVALID_RESPONSE',
          unknownResult: true,
          committedSession: committed);
    }
  }

  LiveSession parseSession(Map<String, dynamic> json) {
    final result = LiveSession.fromJson(json);
    if (result.id.isEmpty || result.status == LiveStatus.unknown) {
      throw const FormatException('直播接口返回的场次信息不完整');
    }
    if (result.groupID != context.groupID) {
      throw const FormatException('直播场次不属于当前群');
    }
    return result;
  }

  Future<LiveSession?> current(
      {CancelToken? cancelToken, LiveSession? minimumSession}) async {
    checkSession();
    final requestedFeatures = context.readCurrentContext().features;
    final json = await _request('$groupPath/current', cancelToken: cancelToken);
    checkSession();
    final cancellation = cancelToken?.cancelError;
    if (cancellation != null) throw cancellation;
    if (json['active'] == false) {
      _checkCurrentSummary(json, requestedFeatures);
      _acceptSummary(json);
      _publishCurrentState(const GroupLiveFeature(), cancelToken);
      return null;
    }
    if (json['active'] != true || json['session'] is! Map) {
      throw const FormatException('直播接口未返回 active/session');
    }
    final result =
        parseSession(Map<String, dynamic>.from(json['session'] as Map));
    if (!result.status.active) throw const FormatException('当前场次状态不正确');
    // The current endpoint may lag behind a session already displayed by this
    // reader. Reject its older version before notifying any shared observers.
    if (minimumSession != null &&
        result.id == minimumSession.id &&
        result.version < minimumSession.version) {
      throw const LiveApiException('直播状态已更新，请刷新后查看', code: 'STALE_RESPONSE');
    }
    _checkCurrentSummary(json, requestedFeatures);
    _acceptSummary(json);
    _publishCurrentState(
        GroupLiveFeature(
            status: switch (result.status) {
              LiveStatus.scheduled => 'scheduled',
              LiveStatus.authorized => 'ready',
              LiveStatus.live => 'live',
              _ => 'none'
            },
            sessionID: result.id,
            roomName: result.roomName,
            description: result.description,
            anchorUserID: result.anchorID,
            scheduledStartAt: result.scheduledAt),
        cancelToken);
    return result;
  }

  void _publishCurrentState(GroupLiveFeature live, CancelToken? cancelToken) {
    checkSession();
    final cancellation = cancelToken?.cancelError;
    if (cancellation != null) throw cancellation;
    context.onLiveStateChanged?.call(live);
  }

  void _checkCurrentSummary(
      Map<String, dynamic> json, GroupFeatures requestedFeatures) {
    final summary = GroupFeatures.fromJson(json['groupFeatures']);
    final latest = context.readCurrentContext().features;
    // Session versions and group-summary revisions are separate sequences.
    // A newer push (or fail-closed SDK invalidation) wins over an in-flight GET,
    // even when this deployed endpoint omits groupFeatures altogether.
    if (latest.valid != requestedFeatures.valid ||
        latest.revision != requestedFeatures.revision ||
        (summary.valid && latest.valid && summary.revision < latest.revision)) {
      throw const LiveApiException('直播状态已更新，请刷新后查看', code: 'STALE_RESPONSE');
    }
  }

  Future<LiveSession> detail(String id, {CancelToken? cancelToken}) async {
    checkSession();
    _id(id);
    final json = await _request(sessionPath(id), cancelToken: cancelToken);
    checkSession();
    final result = parseSession(json);
    if (result.id != id) throw const FormatException('直播场次不匹配');
    _acceptSummary(json);
    return result;
  }

  Future<LivePlayInfo> play(String id, {CancelToken? cancelToken}) async {
    checkSession();
    _id(id);
    final json = await _request('${sessionPath(id)}/play-info',
        cancelToken: cancelToken);
    checkSession();
    final result = LivePlayInfo.fromJson(json);
    if (result.id != id || result.supportedSources.isEmpty) {
      throw const FormatException('未配置可播放的 HTTP FLV/HLS 直播地址');
    }
    return result;
  }

  Future<LivePushInfo> push(String id) async {
    checkPermissionSession();
    if (!context.capabilities.live.canPush) throw StateError('没有获取推流信息的权限');
    _id(id);
    final json = await _request('${sessionPath(id)}/push-info');
    checkPermissionSession();
    final result = LivePushInfo.fromJson(json);
    if (result.server.isEmpty || result.key.isEmpty) {
      throw const FormatException('推流信息尚未配置，请刷新状态');
    }
    return result;
  }

  Future<LiveSession> configure(
      {required String name,
      required String description,
      required String anchorID,
      DateTime? scheduledAt}) async {
    checkPermissionSession();
    if (!context.capabilities.live.canConfigure) throw StateError('没有配置直播的权限');
    final roomName = _name(name);
    final details = description.trim();
    if (details.runes.length > 30) throw const FormatException('直播描述最多 30 个字');
    if (anchorID.trim().isEmpty) throw const FormatException('请选择主播');
    if (scheduledAt != null &&
        scheduledAt.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      throw const FormatException('预约时间至少在一分钟后');
    }
    final json = await _request('$groupPath/authorize', method: 'POST', body: {
      'roomName': roomName,
      'anchorUserId': anchorID.trim(),
      'description': details,
      'scheduledStartAt': scheduledAt?.toUtc().toIso8601String(),
    });
    return _committedSession(json);
  }

  Future<LiveSession> schedule(
      {required String name, required DateTime at}) async {
    checkPermissionSession();
    if (!context.capabilities.live.canManage) throw StateError('没有管理直播的权限');
    final roomName = _name(name);
    if (at.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      throw const FormatException('预约时间至少在一分钟后');
    }
    final json = await _request('$groupPath/schedule', method: 'PATCH', body: {
      'roomName': roomName,
      'scheduledStartAt': at.toUtc().toIso8601String()
    });
    return _committedSession(json);
  }

  Future<LiveSession> end({required bool revoke}) async {
    checkPermissionSession();
    if (!context.capabilities.live.canManage) throw StateError('没有管理直播的权限');
    final json = await _request('$groupPath/${revoke ? 'revoke' : 'stop'}',
        method: 'POST');
    return _committedSession(json, ended: true);
  }

  Future<Map<String, dynamic>> tip(
      {required String id,
      required String currency,
      required int amount,
      required String password,
      required String orderID,
      required String memo}) async {
    checkPermissionSession();
    if (!context.capabilities.live.canTip) throw StateError('没有打赏权限');
    _id(id);
    final acceptedCurrencies =
        LiveTipCurrency.fromCapabilities(context.capabilities.live.raw);
    final decimals = const {'USDT': 6, 'TRX': 6, 'BI99': 2}[currency];
    if (decimals == null ||
        !acceptedCurrencies.any(
            (value) => value.code == currency && value.decimals == decimals)) {
      throw const FormatException('该直播暂不支持此打赏币种，请刷新可用币种');
    }
    final remark = memo.trim();
    if (amount <= 0 ||
        amount > maxTipAmount ||
        !RegExp(r'^\d{6}$').hasMatch(password) ||
        orderID.trim().isEmpty ||
        remark.runes.length > 50) {
      throw const FormatException('打赏金额、备注或支付密码不正确');
    }
    final json =
        await _request('${sessionPath(id)}/tip', method: 'POST', body: {
      'currency': currency,
      'amount': amount,
      'payPin': password,
      'clientOrderId': orderID,
      'memo': remark
    });
    checkSession();
    if ((int.tryParse('${json['tipId']}') ?? 0) <= 0 ||
        json['liveSessionId'] is! String ||
        liveString(json, 'liveSessionId') != id) {
      throw const LiveApiException('服务端未返回有效的打赏结果，请核对账单后重试',
          code: 'INVALID_RESPONSE', unknownResult: true);
    }
    return json;
  }
}
