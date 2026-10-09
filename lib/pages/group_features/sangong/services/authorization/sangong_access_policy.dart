import '../../../models/group_feature_context.dart';

/// Personal agent access is granted by the authenticated, group-scoped server
/// capability. Public group metadata alone never grants account access.
bool sangongAssignedAgentAccess(GroupFeatureContext context) =>
    context.sessionCurrent() &&
    context.capabilitiesCurrent() &&
    context.features.sangong.enabled &&
    context.features.sangong.agentEntry &&
    context.capabilities.sangong.canOpenAgent &&
    context.capabilities.sangong.tenantID.isNotEmpty;

bool sangongModuleAccess(GroupFeatureContext context) =>
    context.privilege
        .allows(userID: context.currentUserID, baseUrl: context.api.baseUrl) ||
    sangongAssignedAgentAccess(context);
