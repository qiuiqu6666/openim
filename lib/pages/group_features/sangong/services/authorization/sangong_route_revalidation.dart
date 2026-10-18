import '../../../data/group_feature_api.dart';
import '../../../models/group_feature_context.dart';
import 'sangong_operation_scope.dart';

/// Reauthorizes an open operator or assigned-agent page without relaxing requests.
/// Command confirmations keep their own captured scope and are never replayed.
class SangongRouteRevalidation {
  SangongRouteRevalidation({
    required this.readContext,
    required this.readTenant,
    required this.canUseRoute,
    required this.updateContext,
    required this.confirmBinding,
    required this.sessionCurrent,
    this.agent = false,
    this.configuration = false,
  }) : _confirmed = SangongOperationScope.capture(readContext(), readTenant());

  final GroupFeatureContext Function() readContext;
  final String? Function() readTenant;
  final bool Function() canUseRoute, sessionCurrent;
  final bool agent;
  final bool configuration;
  final void Function(GroupFeatureContext) updateContext;
  final Future<void> Function() confirmBinding;
  SangongOperationScope _confirmed;

  // Assigned agents may have no account privilege. During invalidation the
  // old capability is no longer current, so compare identity without treating
  // that temporary absence as revocation. No business access is granted until
  // refresh verifies the same tenant and a fresh canOpenAgent grant.
  bool _sameIdentity(GroupFeatureContext next) => agent
      ? _confirmed.userId == next.currentUserID &&
          _confirmed.groupId == next.groupID &&
          _confirmed.baseUrl == next.api.baseUrl &&
          identical(_confirmed.context.api, next.api) &&
          identical(_confirmed.privilege, next.privilege) &&
          _confirmed.privilegeRevision == next.privilege.revision
      : _confirmed.sameAccountAndGroup(next);

  bool _permitted(GroupFeatureContext context) => agent
      ? context.capabilities.sangong.canOpenAgent
      : configuration
          ? context.capabilities.sangong.canConfigure ||
              (context.gameType == GroupGameType.sangong &&
                  context.isGroupAdmin)
          : context.capabilities.sangong.canManage;

  bool get canRevalidate {
    final next = readContext().readCurrentContext();
    final capability = next.capabilities.sangong;
    final tenant = capability.tenantID;
    // Invalidating the store produces an empty placeholder. An explicit,
    // current server denial is final and must not be refreshed into a grant.
    final denied = next.capabilitiesCurrent() &&
        (next.capabilities.version > 0 || capability.raw.isNotEmpty) &&
        !_permitted(next);
    return sessionCurrent() &&
        !denied &&
        _confirmed.context.sessionCurrent() &&
        _sameIdentity(next) &&
        _confirmed.context.gameType == next.gameType &&
        (tenant.isEmpty || tenant == _confirmed.capabilityTenantId);
  }

  bool get current =>
      canRevalidate &&
      canUseRoute() &&
      _confirmed.matches(readContext(), readTenant());

  Future<bool> refresh(bool Function() active) async {
    // Superseded reads are bounded; network failures remain on this route with
    // an explicit retry instead of causing a request loop or returning to chat.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!active() || !canRevalidate) return false;
      GroupFeatureContext? verified;
      try {
        verified = await readContext()
            .readCurrentContext()
            .refreshCapabilities(force: true);
        if (!active() || !canRevalidate) return false;
        if (!_sameIdentity(verified) ||
            verified.gameType != _confirmed.context.gameType ||
            !_permitted(verified) ||
            verified.capabilities.sangong.tenantID !=
                _confirmed.capabilityTenantId) {
          return false;
        }
        updateContext(verified);
        await confirmBinding();
        if (!active() || !canRevalidate) return false;
        if (!verified.capabilitiesCurrent()) continue;
        if (!canUseRoute() || readTenant() != _confirmed.tenantId) return false;
        _confirmed = SangongOperationScope.capture(readContext(), readTenant());
        return true;
      } catch (error) {
        if (!active() || !canRevalidate) return false;
        if ((verified != null && !verified.capabilitiesCurrent()) ||
            (error is GroupFeatureException &&
                error.code == 'CAPABILITIES_CHANGED')) {
          continue;
        }
        rethrow;
      }
    }
    throw StateError('群权限仍在更新，请重试');
  }
}
