import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../models/group_feature_context.dart';
import '../utils/api_response_util.dart';
import 'sangong_api_config.dart';
import 'sangong_scoped_requests.dart';
import 'diagnostics/sangong_api_debug_log.dart';

/// Per-account/per-group adapter to the reference proxy. It never owns or
/// copies credentials, and never infers an authorized tenant from a group ID.
class SangongGameHttp {
  SangongGameHttp(this.context,
      {String? baseUrl,
      String? configuredTenantId,
      String pathPrefix = SangongApiConfig.pathPrefix})
      : baseUrlOverride = SangongApiConfig.normalizeBaseUrl(
            baseUrl ?? SangongApiConfig.baseUrl),
        configuredTenantId =
            (configuredTenantId ?? SangongApiConfig.tenantId).trim(),
        pathPrefix = SangongApiConfig.normalizePathPrefix(pathPrefix) {
    client = Dio(BaseOptions(baseUrl: 'https://sangong.invalid'));
    requests = SangongScopedRequests(client, scopedOptions);
    client.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) async {
      try {
        final requestContext =
            options.extra[_extraContext] as GroupFeatureContext? ?? context;
        final requestTenant = options.extra.containsKey(_extraTenant)
            ? options.extra[_extraTenant]
            : tenantId;
        final requestPrivilege =
            options.extra[_extraPrivilege] ?? context.privilege;
        final requestPrivilegeRevision =
            options.extra[_extraPrivilegeRevision] ??
                context.privilege.revision;
        bool scopeCurrent() =>
            !_closed &&
            identical(requestContext, context) &&
            requestContext.sessionCurrent() &&
            requestContext.capabilitiesCurrent() &&
            identical(requestPrivilege, context.privilege) &&
            requestPrivilegeRevision == context.privilege.revision &&
            requestTenant == tenantId;
        if (!scopeCurrent()) throw StateError('账号或群上下文已变化，请重新进入');
        _checkPermission(options);
        final skipTenant = options.extra[extraSkipTenant] == true;
        if (!skipTenant && !hasTenant) throw StateError('未确认当前群的三公业务绑定');
        final data = await requestContext.api.requestData(
            requestPath(options.path),
            method: options.method,
            query: options.queryParameters,
            body: options.data is Map
                ? Map<String, dynamic>.from(options.data)
                : null,
            headers: requestHeaders(skipTenant: skipTenant),
            cancelToken: _cancelToken,
            baseUrlOverride: baseUrlOverride,
            useBearerAuth: true,
            diagnostics: SangongApiDebugLog.create(),
            preserveEnvelope: true);
        if (!scopeCurrent()) {
          throw StateError('账号或群上下文已变化，请重新进入');
        }
        _checkPermission(options);
        final envelope = readApiWriteEnvelope(data);
        final payload = envelope.payload;
        if (envelope.isBusinessError ||
            (data is Map && data['ok'] == false) ||
            (payload is Map && payload['ok'] == false)) {
          throw DioException(
              requestOptions: options,
              response: Response(requestOptions: options, data: payload),
              type: DioExceptionType.badResponse,
              error: payload is Map ? payload['message'] ?? '操作未成功' : '操作未成功');
        }
        if (payload is Map && payload['groupFeatures'] is Map) {
          final summary = Map<String, dynamic>.from(payload['groupFeatures']);
          if (summary['revision'] is int && summary['schemaVersion'] == 1) {
            requestContext.onFeaturesChanged(summary);
          }
        }
        handler.resolve(
            Response(requestOptions: options, data: data, statusCode: 200));
      } catch (error) {
        handler.reject(error is DioException
            ? error
            : DioException(
                requestOptions: options,
                error: error,
                type: hasAuth
                    ? DioExceptionType.unknown
                    : DioExceptionType.cancel));
      }
    }));
  }
  static const tenantHeader = 'X-Tenant-Id';
  static const extraSkipTenant = 'sangongSkipTenant';
  static const _extraContext = 'sangongRequestContext';
  static const _extraTenant = 'sangongRequestTenant';
  static const _extraPrivilege = 'sangongRequestPrivilege';
  static const _extraPrivilegeRevision = 'sangongRequestPrivilegeRevision';
  GroupFeatureContext context;
  final String? baseUrlOverride;

  /// Transport tenant supplied by deployment config; it does not grant a
  /// role or replace the verified binding used by request scope checks.
  final String configuredTenantId;
  String? get requestTenantId =>
      tenantId ?? (configuredTenantId.isNotEmpty ? configuredTenantId : null);
  String get baseUrl => baseUrlOverride ?? context.api.baseUrl;
  final String pathPrefix;
  String requestPath(String path) => SangongApiConfig.requestPath(
      baseUrl: baseUrl, pathPrefix: pathPrefix, path: path);
  Map<String, dynamic> requestHeaders({bool skipTenant = false}) => {
        if (configuredTenantId.isNotEmpty || !skipTenant)
          tenantHeader: skipTenant && configuredTenantId.isNotEmpty
              ? configuredTenantId
              : requestTenantId,
      };
  final CancelToken _cancelToken = CancelToken();
  late final Dio client;
  late final SangongScopedRequests requests;
  Options scopedOptions([Options? options]) => (options ?? Options()).copyWith(
        extra: {
          ...?options?.extra,
          _extraContext: context,
          _extraTenant: tenantId,
          _extraPrivilege: context.privilege,
          _extraPrivilegeRevision: context.privilege.revision,
        },
      );
  final tenantIdListenable = ValueNotifier<String?>(null);
  String? get tenantId => tenantIdListenable.value;
  bool get hasTenant => tenantId?.trim().isNotEmpty == true;
  bool get hasAuth =>
      !_closed &&
      context.sessionCurrent() &&
      context.capabilitiesCurrent() &&
      context.privilege
          .allows(userID: context.currentUserID, baseUrl: context.api.baseUrl);
  bool get canCallAdmin => hasAuth && hasTenant;
  bool _closed = false;
  void _checkPermission(RequestOptions options) {
    if (!context.privilege
        .allows(userID: context.currentUserID, baseUrl: context.api.baseUrl)) {
      throw StateError('当前账号没有三公特权');
    }
    final feature = context.features.sangong;
    final capability = context.capabilities.sangong;
    final configuration = options.path.startsWith('/api/v1/admin/my-config') ||
        options.path == '/api/v1/admin/tenants';
    if (configuration) {
      if (!capability.canConfigure && !capability.canManage) {
        throw StateError('没有三公配置权限');
      }
      if (options.method != 'GET' && !capability.canConfigure) {
        throw StateError('没有三公配置权限');
      }
    } else if (options.path.startsWith('/api/v1/admin/') ||
        options.path == '/api/v1/settings') {
      if (!feature.enabled || !feature.manageEntry || !capability.canManage) {
        throw StateError('没有当前群的三公运营权限');
      }
    } else if (options.path.startsWith('/api/v1/me/') ||
        options.path.startsWith('/api/v1/agent/')) {
      if (!feature.enabled || !feature.agentEntry || !capability.canOpenAgent) {
        throw StateError('没有当前群的三公代理权限');
      }
      if ((options.path == '/api/v1/me/member-daily' ||
              options.path == '/api/v1/me/transfers') &&
          (!feature.rebateHistoryEntry || !capability.canViewRebateHistory)) {
        throw StateError('没有当前群的收益历史查看权限');
      }
    }
  }

  Future<void> hydrateTenant() async {}
  void setTenantId(String? value) {
    if (_closed) return;
    final next = value?.trim();
    // Revocation must always be able to clear the old binding, even when the
    // old authorization epoch was invalidated before updateContext arrived.
    if (next?.isNotEmpty == true && !hasAuth) return;
    tenantIdListenable.value = next?.isNotEmpty == true ? next : null;
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _cancelToken.cancel('Sangong scope disposed');
    client.close(force: true);
    tenantIdListenable.dispose();
  }
}
