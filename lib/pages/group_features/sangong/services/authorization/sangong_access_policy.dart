import '../../../models/group_feature_context.dart';

/// Personal agent access is granted by the authenticated, group-scoped server
/// capability. An absent or delayed public group summary neither grants nor
/// revokes this personal assignment; current private capabilities decide.
bool sangongAssignedAgentAccess(GroupFeatureContext context) =>
    context.sessionCurrent() &&
    context.capabilitiesCurrent() &&
    context.capabilities.sangong.canOpenAgent &&
    context.capabilities.sangong.tenantID.isNotEmpty;

bool sangongModuleAccess(GroupFeatureContext context) =>
    context.privilege
        .allows(userID: context.currentUserID, baseUrl: context.api.baseUrl) ||
    sangongAssignedAgentAccess(context);
