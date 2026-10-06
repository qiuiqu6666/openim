import '../../../models/group_feature_context.dart';

/// An operation belongs to one account, group and authorization snapshot.
class SangongOperationScope {
  SangongOperationScope.capture(this.context, this.tenantId)
      : userId = context.currentUserID,
        groupId = context.groupID,
        baseUrl = context.api.baseUrl,
        capabilityVersion = context.capabilities.version,
        privilege = context.privilege,
        privilegeRevision = context.privilege.revision,
        privileged = context.privilege.allows(
            userID: context.currentUserID, baseUrl: context.api.baseUrl),
        capabilityTenantId = context.capabilities.sangong.tenantID,
        permissions = (
          context.capabilities.sangong.canConfigure,
          context.capabilities.sangong.canManage,
          context.capabilities.sangong.canOpenAgent,
          context.capabilities.sangong.canViewRebateHistory,
          context.capabilities.sangong.raw['canManageMembers'] == true,
          context.features.sangong.enabled,
          context.features.sangong.manageEntry,
          context.features.sangong.agentEntry,
          context.features.sangong.rebateHistoryEntry,
        );

  final GroupFeatureContext context;
  final String? tenantId;
  final String userId, groupId, baseUrl;
  final int capabilityVersion;
  final Object privilege;
  final int privilegeRevision;
  final bool privileged;
  final String capabilityTenantId;
  final (bool, bool, bool, bool, bool, bool, bool, bool, bool) permissions;

  Object get token => (
        context.api,
        tenantId,
        userId,
        groupId,
        baseUrl,
        capabilityVersion,
        capabilityTenantId,
        permissions,
        privilege,
        privilegeRevision,
        privileged
      );

  bool matches(GroupFeatureContext current, String? currentTenant) =>
      privileged &&
      context.sessionCurrent() &&
      context.capabilitiesCurrent() &&
      current.sessionCurrent() &&
      current.capabilitiesCurrent() &&
      token == SangongOperationScope.capture(current, currentTenant).token;

  bool sameAccountAndGroup(GroupFeatureContext current) =>
      userId == current.currentUserID &&
      groupId == current.groupID &&
      baseUrl == current.api.baseUrl &&
      privileged &&
      identical(privilege, current.privilege) &&
      privilegeRevision == current.privilege.revision &&
      current.privilege.allows(
          userID: current.currentUserID, baseUrl: current.api.baseUrl) &&
      identical(context.api, current.api);

  bool sameContext(GroupFeatureContext current) =>
      sameAccountAndGroup(current) &&
      identical(context, current) &&
      capabilityVersion == current.capabilities.version;
}
