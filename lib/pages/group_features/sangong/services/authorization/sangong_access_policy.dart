import '../../../models/group_feature_context.dart';

/// Personal agent access is granted by the authenticated, group-scoped server
/// capability. An absent or delayed public group summary neither grants nor
/// revokes this personal assignment; current private capabilities decide.
bool sangongAssignedAgentAccess(GroupFeatureContext context) =>
    context.sessionCurrent() &&
    context.capabilitiesCurrent() &&
    context.capabilities.sangong.canOpenAgent &&
    context.capabilities.sangong.tenantID.isNotEmpty;

/// OpenIM's group type chooses the entry; it never grants personal access.
/// An active betting group can also host a personally assigned agent route.
bool sangongAgentEntryVisible(GroupFeatureContext context) =>
    (context.gameType == GroupGameType.sangongAgent ||
        context.gameType == GroupGameType.sangong) &&
    sangongAssignedAgentAccess(context);

bool sangongModuleAccess(GroupFeatureContext context) =>
    context.privilege
        .allows(userID: context.currentUserID, baseUrl: context.api.baseUrl) ||
    sangongAssignedAgentAccess(context);
