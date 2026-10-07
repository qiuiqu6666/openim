import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';

import '../../models/binding/sangong_group_tenant_state.dart';
import '../../models/sangong_my_config.dart';
import '../../utils/api_response_util.dart';
import '../diagnostics/sangong_api_debug_log.dart';

/// Reads and saves the current game group through Chat. Agent groups use their
/// own context endpoint; account-default configuration is never consulted.
class SangongGroupTenantApi {
  const SangongGroupTenantApi();

  Future<SangongGroupTenantState> fetch(GroupFeatureContext context,
          {String? tenantId}) =>
      _inContext(context, (api) async {
        final requestedId = _requestedId(context.groupID);
        if (tenantId != null) {
          throw const GroupFeatureException('请通过代理群入口查询绑定关系',
              code: 'INVALID_REQUEST');
        }
        try {
          final raw = await api.requestData(
            '/sangong/api/v2/groups/${Uri.encodeComponent(requestedId)}/config',
            useBearerAuth: true,
            diagnostics: SangongApiDebugLog.create(),
            preserveEnvelope: true,
          );
          return _parse(raw,
              requestedId: requestedId,
              currentGroupId: context.groupID,
              requireCurrentGroup: true);
        } on GroupFeatureException catch (error) {
          if (error.statusCode == 404 &&
              error.serverCode == 'TENANT_NOT_FOUND') {
            return SangongGroupTenantState(
              status: SangongGroupTenantStatus.notFound,
              tenantId: requestedId,
              message: '当前群尚未配置三公',
            );
          }
          if (error.statusCode == 403 &&
              error.serverCode == 'TENANT_ACCESS_DENIED') {
            return SangongGroupTenantState(
              status: SangongGroupTenantStatus.accessDenied,
              tenantId: requestedId,
              message: '当前群已配置三公，请联系配置者授权',
            );
          }
          rethrow;
        }
      });

  Future<SangongGroupTenantState> create(GroupFeatureContext context,
          {required Map<String, dynamic> body}) =>
      _inContext(context, (api) async {
        if (!context.isGroupAdmin ||
            !context.readCurrentContext().isGroupAdmin) {
          throw const GroupFeatureException('只有群主或群管理员可以创建三公配置',
              code: 'GROUP_ADMIN_REQUIRED');
        }
        final requestedId = _requestedId(context.groupID);
        _checkBodyGroup(body, requestedId, requireGroup: true);
        final bot = body['imBotUserId'];
        if (bot is! String || bot.trim().isEmpty) {
          throw const GroupFeatureException('请填写机器人用户ID',
              code: 'INVALID_REQUEST');
        }
        final raw = await api.requestData(
          '/sangong/api/v2/groups/${Uri.encodeComponent(requestedId)}/config',
          method: 'PUT',
          body: body,
          useBearerAuth: true,
          diagnostics: SangongApiDebugLog.create(),
          preserveEnvelope: true,
        );
        if (!context.readCurrentContext().isGroupAdmin) {
          throw const GroupFeatureException('群管理权限已变化，请重新进入',
              code: 'GROUP_ADMIN_CHANGED');
        }
        final payload = unwrapApiPayload(raw);
        final hasOk = (raw is Map && raw['ok'] == true) ||
            (payload is Map && payload['ok'] == true);
        final rejected =
            (raw is Map && raw.containsKey('ok') && raw['ok'] != true) ||
                (payload is Map &&
                    payload.containsKey('ok') &&
                    payload['ok'] != true);
        if (!hasOk || rejected) _unknownWriteResult();
        return _parseWrite(raw, requestedId: requestedId, requireActive: true);
      });

  Future<SangongGroupTenantState> update(GroupFeatureContext context,
          {required String tenantId, required Map<String, dynamic> body}) =>
      _inContext(context, (api) async {
        final requestedId = _requestedId(context.groupID);
        final verified = context.capabilities.sangong.tenantID;
        if (tenantId != (verified.isNotEmpty ? verified : context.groupID)) {
          throw const GroupFeatureException('当前群不是要修改的三公下注群',
              code: 'INVALID_REQUEST');
        }
        _checkBodyGroup(body, requestedId, requireGroup: false);
        final raw = await api.requestData(
          '/sangong/api/v2/groups/${Uri.encodeComponent(requestedId)}/config',
          method: 'PUT',
          body: body,
          useBearerAuth: true,
          diagnostics: SangongApiDebugLog.create(),
          preserveEnvelope: true,
        );
        return _parseWrite(raw, requestedId: requestedId, requireActive: false);
      });

  Future<T> _inContext<T>(GroupFeatureContext context,
      Future<T> Function(GroupFeatureApi api) action) async {
    final api = context.api;
    final userId = context.currentUserID;
    final groupId = context.groupID;
    final baseUrl = api.baseUrl;
    final privilege = context.privilege;
    final privilegeRevision = privilege.revision;

    void checkCurrent() {
      final current = context.readCurrentContext();
      if (!context.sessionCurrent() ||
          !current.sessionCurrent() ||
          current.currentUserID != userId ||
          current.groupID != groupId ||
          !identical(current.api, api) ||
          api.baseUrl != baseUrl) {
        throw const GroupFeatureException('登录状态已变化，请重新进入',
            code: 'SESSION_CHANGED', authRequired: true);
      }
      if (!identical(current.privilege, privilege) ||
          privilege.revision != privilegeRevision) {
        throw const GroupFeatureException('账号特权已变化，请重新进入',
            code: 'PRIVILEGE_CHANGED');
      }
      if (!privilege.allows(userID: userId, baseUrl: baseUrl)) {
        throw const GroupFeatureException('当前账号没有三公特权',
            code: 'PRIVILEGE_REQUIRED');
      }
    }

    checkCurrent();
    try {
      final result = await action(api);
      checkCurrent();
      return result;
    } catch (_) {
      checkCurrent();
      rethrow;
    }
  }

  String _requestedId(String value) {
    final id = value.trim();
    if (id.isEmpty) {
      throw const GroupFeatureException('三公租户标识不能为空', code: 'INVALID_REQUEST');
    }
    return id;
  }

  void _checkBodyGroup(Map<String, dynamic> body, String requestedId,
      {required bool requireGroup}) {
    if ((requireGroup && !body.containsKey('imGroupGameId')) ||
        (body.containsKey('imGroupGameId') &&
            body['imGroupGameId'] != requestedId) ||
        (body.containsKey('im_group_game_id') &&
            body['im_group_game_id'] != requestedId)) {
      throw const GroupFeatureException('下注群ID必须是当前群，不能更换绑定群',
          code: 'INVALID_REQUEST');
    }
  }

  SangongGroupTenantState _parseWrite(dynamic raw,
      {required String requestedId, required bool requireActive}) {
    try {
      final payload = unwrapApiPayload(raw);
      if ((raw is Map && raw.containsKey('ok') && raw['ok'] != true) ||
          (payload is Map &&
              payload.containsKey('ok') &&
              payload['ok'] != true)) {
        _unknownWriteResult();
      }
      final data = _configurationData(raw);
      final game = data['imGroupGameId'] ?? data['im_group_game_id'];
      final bot = data['imBotUserId'] ?? data['im_bot_user_id'];
      if (game is! String ||
          game.trim().isEmpty ||
          bot is! String ||
          bot.trim().isEmpty ||
          (requireActive && data['active'] != true)) {
        _unknownWriteResult();
      }
      return _parse(raw,
          requestedId: requestedId,
          currentGroupId: requestedId,
          requireCurrentGroup: true);
    } on GroupFeatureException catch (error) {
      if (error.code == 'INVALID_RESPONSE') _unknownWriteResult();
      rethrow;
    }
  }

  Map<String, dynamic> _configurationData(dynamic raw) {
    final payload = unwrapApiPayload(raw);
    if (raw is! Map || payload is! Map) _invalidResponse();
    final outer = Map<String, dynamic>.from(payload);
    final nested = outer['tenant'];
    if (outer.containsKey('tenant') && nested is! Map) _invalidResponse();
    return <String, dynamic>{
      ...outer,
      if (nested is Map) ...Map<String, dynamic>.from(nested),
    };
  }

  SangongGroupTenantState _parse(dynamic raw,
      {required String requestedId,
      required String currentGroupId,
      required bool requireCurrentGroup}) {
    final data = _configurationData(raw);
    final envelope = Map<String, dynamic>.from(raw as Map);
    if (data['configured'] == false) {
      if (data['groupID'] != currentGroupId || data['canInitialize'] != true) {
        _invalidResponse();
      }
      return SangongGroupTenantState(
          status: SangongGroupTenantStatus.notFound,
          tenantId: '',
          message: '当前群尚未配置三公',
          raw: envelope);
    }
    final active = data['active'];
    if (active is! bool) _invalidResponse();
    final resolvedTenant =
        data['tenantId'] ?? data['tenantID'] ?? data['tenant_id'];
    if (resolvedTenant is! String || resolvedTenant.trim().isEmpty) {
      _invalidResponse();
    }
    for (final key in const ['tenantId', 'tenantID', 'id', 'tenant_id']) {
      if (data.containsKey(key) &&
          (data[key] is! String || data[key].trim() != resolvedTenant)) {
        _invalidResponse();
      }
    }
    for (final key in const ['imGroupGameId', 'im_group_game_id']) {
      if (data.containsKey(key) &&
          (data[key] is! String ||
              data[key].trim().isEmpty ||
              (requireCurrentGroup && data[key].trim() != currentGroupId))) {
        _invalidResponse();
      }
    }
    if (!data.containsKey('imGroupGameId') &&
        !data.containsKey('im_group_game_id')) {
      _invalidResponse();
    }
    final config = SangongMyConfig.fromJson({
      ...data,
      'configured': true,
      'tenantId': resolvedTenant,
      if (data['canEditConfig'] == null && data['can_edit_config'] == null)
        'canEditConfig': false,
      if (data['canManageMembers'] == null &&
          data['can_manage_members'] == null)
        'canManageMembers': false,
    });
    final message = featureString(data['message'] ?? data['msg']);
    return SangongGroupTenantState(
      status: active == true
          ? SangongGroupTenantStatus.configured
          : SangongGroupTenantStatus.disabled,
      config: config,
      tenantId: resolvedTenant,
      message: message.isNotEmpty
          ? message
          : active == false
              ? '当前群的三公已停用'
              : '',
      raw: envelope,
    );
  }

  Never _invalidResponse() => throw const GroupFeatureException('服务返回的数据格式不正确',
      code: 'INVALID_RESPONSE');

  Never _unknownWriteResult() =>
      throw const GroupFeatureException('操作结果尚未确认，请刷新后查看',
          code: 'UNKNOWN_RESULT', unknownResult: true);
}
