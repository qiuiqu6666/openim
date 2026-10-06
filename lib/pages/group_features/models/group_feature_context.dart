import '../data/group_feature_api.dart';
import 'group_features.dart';
import 'group_feature_capabilities.dart';
import 'group_game_type.dart';
import '../../../services/account_privilege/account_privilege_runtime.dart';
export 'group_features.dart';
export 'group_feature_capabilities.dart';
export 'group_game_type.dart';

bool _alwaysCurrent() => true;

/// Snapshot plus account-scoped dependencies, passed explicitly to every business page.
class GroupFeatureContext {
  const GroupFeatureContext(
      {required this.groupID,
      required this.groupName,
      required this.currentUserID,
      required this.api,
      this.accountPrivilege,
      this.gameType = GroupGameType.ordinary,
      this.features = const GroupFeatures(),
      this.liveState,
      this.capabilities = const GroupFeatureCapabilities(),
      this.isGroupAdmin = false,
      required this.sessionCurrent,
      required this.onFeaturesChanged,
      this.capabilitiesCurrent = _alwaysCurrent,
      this.reloadCapabilities,
      this.readContext,
      this.onCapabilitiesInvalidated,
      this.onFeaturesCommitted,
      this.onLiveStateChanged,
      this.events = const Stream<Map<String, dynamic>>.empty()});
  final String groupID, groupName, currentUserID;
  final GroupFeatureApi api;
  final AccountPrivilegeAccess? accountPrivilege;

  /// Public display metadata, independent of summary and private permissions.
  final GroupGameType gameType;
  AccountPrivilegeAccess get privilege =>
      accountPrivilege ?? AccountPrivilegeRuntime.store;
  final GroupFeatures features;

  /// Public display projection from a verified current-session read. It may be
  /// inactive while the SDK summary still describes the previous live slot.
  /// Permission decisions continue to use [features] and [capabilities].
  final GroupLiveFeature? liveState;
  GroupLiveFeature get liveFeature => liveState ?? features.live;
  final GroupFeatureCapabilities capabilities;
  final bool isGroupAdmin;
  final bool Function() sessionCurrent;

  /// Private operations must reject the old authorization snapshot after invalidation.
  final bool Function() capabilitiesCurrent;
  final void Function(Map<String, dynamic>) onFeaturesChanged;
  final Stream<Map<String, dynamic>> events;

  /// The account-owned store supplies refreshed snapshots to already-open routes.
  final Future<GroupFeatureContext> Function(bool force)? reloadCapabilities;
  final GroupFeatureContext Function()? readContext;
  final void Function()? onCapabilitiesInvalidated;
  final void Function(Map<String, dynamic> summary, bool mirrorPending)?
      onFeaturesCommitted;

  /// A public current-session read can update badges without a group summary.
  /// This projection carries no group revision, authorization or credentials.
  final void Function(GroupLiveFeature)? onLiveStateChanged;

  void acceptFeatures(Map<String, dynamic> summary,
      {bool mirrorPending = false}) {
    if (onFeaturesCommitted != null) {
      onFeaturesCommitted!(summary, mirrorPending);
    } else {
      onFeaturesChanged(summary);
    }
  }

  GroupFeatureContext readCurrentContext() => readContext?.call() ?? this;

  Future<GroupFeatureContext> refreshCapabilities({bool force = false}) async {
    if (!sessionCurrent()) {
      throw const GroupFeatureException('登录状态已变化，请重新进入',
          code: 'SESSION_CHANGED', authRequired: true);
    }
    final next =
        reloadCapabilities == null ? this : await reloadCapabilities!(force);
    if (!sessionCurrent() ||
        !next.sessionCurrent() ||
        next.groupID != groupID ||
        next.currentUserID != currentUserID ||
        !identical(next.api, api)) {
      throw const GroupFeatureException('登录状态已变化，请重新进入',
          code: 'SESSION_CHANGED', authRequired: true);
    }
    if (!next.capabilitiesCurrent()) {
      throw const GroupFeatureException('群功能权限正在更新，请重试',
          code: 'CAPABILITIES_CHANGED');
    }
    return next;
  }

  void invalidateCapabilities() => onCapabilitiesInvalidated?.call();
}
