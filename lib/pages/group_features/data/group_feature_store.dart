import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../models/group_feature_context.dart';
import 'group_feature_api.dart';
import '../../../services/account_privilege/account_privilege_runtime.dart';

bool _samePermissionValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) =>
            b.containsKey(key) && _samePermissionValue(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (index) => index)
            .every((index) => _samePermissionValue(a[index], b[index]));
  }
  return a == b;
}

bool _sdkSummaryMissing(String? ex) {
  if (ex == null || ex.trim().isEmpty) return true;
  try {
    final metadata = jsonDecode(ex);
    return metadata is Map && !metadata.containsKey('groupFeatures');
  } catch (_) {
    return false;
  }
}

/// A single account-scoped cache. SDK metadata is seeded, not fetched by each row.
class GroupFeatureStore extends ChangeNotifier {
  GroupFeatureStore(
      {required this.api,
      required this.sessionCurrent,
      required this.fetchGroups,
      AccountPrivilegeAccess? accountPrivilege,
      DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        accountPrivilege = accountPrivilege ?? AccountPrivilegeRuntime.store {
    this.accountPrivilege.addListener(_privilegeChanged);
  }
  final AccountPrivilegeAccess accountPrivilege;
  void _privilegeChanged() {
    if (active) notifyListeners();
  }

  final GroupFeatureApi api;
  final bool Function() sessionCurrent;
  final Future<List<GroupInfo>> Function(List<String>) fetchGroups;
  final DateTime Function() _clock;
  final _groups = <String, GroupInfo>{};
  final _features = <String, GroupFeatures>{};
  final _liveStates =
      <String, ({GroupLiveFeature feature, int groupRevision})>{};
  final _pendingMirrors = <String, int>{};
  final _capabilities = <String, GroupFeatureCapabilities>{};
  final _expiry = <String, DateTime>{};
  final _pendingCapabilities = <String, Future<void>>{};
  final _capabilityEpoch = <String, int>{};
  final _capabilityMinimumVersion = <String, int>{};
  final _capabilityErrors = <String, GroupFeatureException>{};
  final _capabilityTokens = <String, CancelToken>{};
  final _requested = <String>{}, _queued = <String>{}, _left = <String>{};
  final _seenEvents = <String>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _groupEvents = <String, Stream<Map<String, dynamic>>>{};
  final _subscriptions = <StreamSubscription>[];
  bool _closed = false, _scheduled = false, _invalidated = false;
  bool get active => !_closed && !_invalidated && sessionCurrent();
  GroupFeatures features(String id) => _features[id] ?? const GroupFeatures();
  GroupLiveFeature liveFeature(String id) =>
      _liveStates[id]?.feature ?? features(id).live;

  /// A defensive metadata snapshot for a chat's first frame. Membership and
  /// operation permissions must still come from their current SDK/API checks.
  GroupInfo? cachedGroupInfo(String id) {
    if (!active || _left.contains(id)) return null;
    final cached = _groups[id];
    return cached == null ? null : GroupInfo.fromJson(cached.toJson());
  }

  GroupFeatureCapabilities capabilities(String id) =>
      _capabilities[id] ?? const GroupFeatureCapabilities();
  GroupFeatureException? capabilityError(String id) => _capabilityErrors[id];
  bool capabilitiesLoading(String id) => _pendingCapabilities.containsKey(id);
  Stream<Map<String, dynamic>> events(String id) => _groupEvents.putIfAbsent(id,
      () => _events.stream.where((event) => active && event['groupID'] == id));

  void bindSources(
      {required Stream<GroupInfo> groupChanged,
      required Stream<GroupInfo> joined,
      required Stream<GroupInfo> left,
      required Stream<GroupMembersInfo> memberDeleted,
      required Stream<GroupMembersInfo> memberChanged,
      required Stream<String> business,
      required Stream<void> synced,
      required Stream<void> kicked,
      required String Function() currentUserID}) {
    if (_subscriptions.isNotEmpty || !active) return;
    _subscriptions.addAll([
      groupChanged.listen(seed),
      joined.listen((info) {
        _left.remove(info.groupID);
        seed(info);
      }),
      left.listen((info) => remove(info.groupID)),
      memberDeleted.listen((info) {
        if (info.userID == currentUserID() && info.groupID != null) {
          remove(info.groupID!);
        }
      }),
      memberChanged.listen((info) {
        if (info.userID == currentUserID() && info.groupID != null) {
          invalidateCapabilities(info.groupID!);
          unawaited(loadCapabilities(info.groupID!));
        }
      }),
      business.listen(receiveBusiness),
      synced.listen((_) => refreshKnownGroups()),
      kicked.listen((_) => invalidateSession()),
    ]);
  }

  void seed(GroupInfo info) {
    if (!active || _left.contains(info.groupID)) return;
    final id = info.groupID;
    final gameTypeChanged =
        GroupGameType.fromEx(_groups[id]?.ex) != GroupGameType.fromEx(info.ex);
    _groups[id] = GroupInfo.fromJson(info.toJson());
    _requested.add(id);
    _queued.remove(id);
    final summary = GroupFeatures.fromEx(info.ex);
    final old = features(id);
    final pendingRevision = _pendingMirrors[id];
    // A committed business response stays authoritative while its SDK mirror
    // is pending, including the backend's non-JSON ex retry case.
    if (pendingRevision != null) {
      if (!summary.valid || summary.revision < pendingRevision) {
        if (gameTypeChanged) notifyListeners();
        return;
      }
      _pendingMirrors.remove(id);
    }
    if (summary.valid && old.valid && summary.revision <= old.revision) {
      if (gameTypeChanged) notifyListeners();
      return;
    }
    // Invalid/unknown schema must fail closed, even when a prior summary existed.
    _features[id] = summary;
    // Some deployed SDK mirrors never include groupFeatures. Missing metadata
    // cannot erase a verified current-session projection that has never had a
    // summary; explicit corruption and a previously valid summary still fail
    // closed, including after a pending mirror catches up.
    if (summary.valid || old.valid || !_sdkSummaryMissing(info.ex)) {
      _clearLiveStateForSummary(id, summary);
    }
    _updateAuthorizationScope(id, old, summary);
    _publishSummary(id, summary);
    notifyListeners();
  }

  void apply(String id, Map<String, dynamic> json, {bool publishEvent = true}) {
    if (!active || _left.contains(id)) return;
    final next = GroupFeatures.fromJson(json['groupFeatures'] ?? json);
    if (!next.valid || next.revision <= features(id).revision) return;
    final old = features(id);
    _features[id] = next;
    _clearLiveStateForSummary(id, next);
    _updateAuthorizationScope(id, old, next);
    if (publishEvent) _publishSummary(id, next);
    notifyListeners();
  }

  /// Only view state is projected from a validated live/current response.
  /// Group revisions and permission scopes remain owned by real summaries.
  void applyLiveState(String id, GroupLiveFeature next) {
    if (!active || id.isEmpty || _left.contains(id)) return;
    final previous = _liveStates[id]?.feature;
    _liveStates[id] = (feature: next, groupRevision: features(id).revision);
    if (previous != null &&
        previous.status == next.status &&
        previous.sessionID == next.sessionID &&
        previous.roomName == next.roomName &&
        previous.description == next.description &&
        previous.anchorUserID == next.anchorUserID &&
        previous.scheduledStartAt == next.scheduledStartAt) {
      return;
    }
    notifyListeners();
  }

  void _clearLiveStateForSummary(String id, GroupFeatures summary) {
    final projected = _liveStates[id];
    if (projected != null &&
        (!summary.valid || summary.revision > projected.groupRevision)) {
      _liveStates.remove(id);
    }
  }

  void _updateAuthorizationScope(
      String id, GroupFeatures old, GroupFeatures next) {
    bool changed(GroupGameFeature previous, GroupGameFeature current) =>
        previous.enabled != current.enabled ||
        previous.gameID != current.gameID ||
        previous.tenantID != current.tenantID ||
        previous.machineCode != current.machineCode ||
        previous.manageEntry != current.manageEntry ||
        previous.agentEntry != current.agentEntry ||
        previous.rebateHistoryEntry != current.rebateHistoryEntry;
    final liveQualificationChanged = old.live.isActive != next.live.isActive ||
        old.live.sessionID != next.live.sessionID ||
        old.live.anchorUserID != next.live.anchorUserID;
    if ((liveQualificationChanged ||
            changed(old.sangong, next.sangong) ||
            changed(old.markSix, next.markSix)) &&
        (_capabilities.containsKey(id) ||
            _pendingCapabilities.containsKey(id))) {
      invalidateCapabilities(id);
      unawaited(loadCapabilities(id));
    }
  }

  void _publishSummary(String id, GroupFeatures next) {
    _events.add({
      'key': 'groupFeaturesChanged',
      'groupID': id,
      'data': {'groupID': id, 'groupFeatures': next.raw},
    });
  }

  void hydrate(Iterable<String?> ids) {
    if (!active) return;
    for (final id in ids) {
      if (id == null ||
          id.isEmpty ||
          _left.contains(id) ||
          _requested.contains(id)) {
        continue;
      }
      _queued.add(id);
    }
    if (_queued.isEmpty || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(_flush);
  }

  Future<void> _flush() async {
    _scheduled = false;
    if (!active) return;
    final ids = _queued.toList();
    _queued.clear();
    _requested.addAll(ids);
    for (var start = 0; start < ids.length; start += 100) {
      if (!active) return;
      final batch = ids.sublist(start, (start + 100).clamp(0, ids.length));
      try {
        final groups = await fetchGroups(batch);
        if (!active) return;
        for (final group in groups) {
          // A push newer than this request always wins by server revision.
          seed(group);
        }
      } catch (_) {
        /* No per-row retries. Explicit resume/sync refresh retries once. */
      }
    }
  }

  void refreshKnownGroups() {
    if (!active) return;
    final ids = _requested.toList();
    _requested.clear();
    hydrate(ids);
  }

  void refreshGroup(String id) {
    if (!active || _left.contains(id)) return;
    _requested.remove(id);
    hydrate([id]);
  }

  Future<void> loadCapabilities(String id, {bool force = false}) {
    if (!active || _left.contains(id) || id.isEmpty) return Future.value();
    final pending = _pendingCapabilities[id];
    if (pending != null) return pending;
    if (!force && _expiry[id]?.isAfter(_clock()) == true) return Future.value();
    final epoch = _capabilityEpoch[id] ?? 0;
    final token = CancelToken();
    _capabilityTokens[id] = token;
    late Future<void> request;
    request = _loadCapabilities(id, epoch, token).whenComplete(() {
      if (identical(_pendingCapabilities[id], request)) {
        _pendingCapabilities.remove(id);
        _capabilityTokens.remove(id);
        if (active) notifyListeners();
      }
    });
    _pendingCapabilities[id] = request;
    notifyListeners();
    return request;
  }

  Future<void> _loadCapabilities(
      String id, int epoch, CancelToken token) async {
    try {
      final data = await api.get(
          '/chat/groups/${Uri.encodeComponent(id)}/feature-capabilities',
          cancelToken: token);
      if (!active ||
          _left.contains(id) ||
          (_capabilityEpoch[id] ?? 0) != epoch) {
        return;
      }
      if (data['groupID'] != id) {
        throw const GroupFeatureException('群权限数据不匹配', code: 'GROUP_MISMATCH');
      }
      final next = GroupFeatureCapabilities.fromJson(data);
      if (next.version < (_capabilityMinimumVersion[id] ?? 0)) {
        throw const GroupFeatureException('群功能权限正在更新，请重试',
            code: 'STALE_CAPABILITIES');
      }
      final previous = _capabilities[id];
      // A force refresh can discover a role change even without an SDK notice.
      if (previous != null &&
          (previous.version != next.version ||
              !_samePermissionValue(previous.live.raw, next.live.raw) ||
              !_samePermissionValue(previous.sangong.raw, next.sangong.raw) ||
              !_samePermissionValue(previous.markSix.raw, next.markSix.raw))) {
        _capabilityEpoch[id] = epoch + 1;
      }
      _capabilityMinimumVersion[id] = next.version;
      _capabilities[id] = next;
      _expiry[id] = _clock().add(Duration(seconds: next.cacheTTLSeconds));
      _capabilityErrors.remove(id);
      _events.add({
        'key': 'groupFeatureCapabilitiesResolved',
        'groupID': id,
        'data': {'groupID': id, 'capabilityVersion': next.version},
      });
    } catch (error) {
      if (!active ||
          _left.contains(id) ||
          (_capabilityEpoch[id] ?? 0) != epoch) {
        return;
      }
      final hadCapabilities = _capabilities.remove(id) != null;
      _capabilityErrors[id] = error is GroupFeatureException
          ? error
          : const GroupFeatureException('暂时无法获取群功能权限');
      // Negative caching stops a missing backend from being hit on every rebuild.
      _expiry[id] = _clock().add(const Duration(seconds: 30));
      if (hadCapabilities) {
        _capabilityEpoch[id] = epoch + 1;
        _events.add({
          'key': 'groupFeatureCapabilitiesInvalidated',
          'groupID': id,
          'data': {'groupID': id},
        });
      }
    }
  }

  void invalidateCapabilities(String id, {int? expectedVersion}) {
    if (!active) return;
    if (expectedVersion != null &&
        expectedVersion > (_capabilityMinimumVersion[id] ?? 0)) {
      _capabilityMinimumVersion[id] = expectedVersion;
    }
    _capabilityEpoch[id] = (_capabilityEpoch[id] ?? 0) + 1;
    _capabilityTokens.remove(id)?.cancel();
    _pendingCapabilities.remove(id);
    _capabilities.remove(id);
    _expiry.remove(id);
    _events.add({
      'key': 'groupFeatureCapabilitiesInvalidated',
      'groupID': id,
      'data': {'groupID': id},
    });
    notifyListeners();
  }

  void receiveBusiness(String raw) {
    if (!active) return;
    try {
      final message = featureMap(jsonDecode(raw));
      final key = featureString(message['key']);
      if (!const {
        'groupFeaturesChanged',
        'groupLiveChanged',
        'groupGameChanged',
        'groupFeatureCapabilitiesChanged'
      }.contains(key)) {
        return;
      }
      final rawData = message['data'];
      final data =
          featureMap(rawData is String ? jsonDecode(rawData) : rawData);
      final id = featureString(data['groupID'] ?? message['groupID']);
      if (id.isEmpty || _left.contains(id)) return;
      final eventID = featureString(message['eventId'] ?? data['eventId']);
      if (eventID.isNotEmpty && !_seenEvents.add(eventID)) return;
      if (_seenEvents.length > 256) _seenEvents.remove(_seenEvents.first);
      if (data['groupFeatures'] is Map) {
        apply(id, featureMap(data['groupFeatures']), publishEvent: false);
        // Routes must see the same accepted revision as the shared cache.
        data['groupFeatures'] = features(id).raw;
      }
      if (key == 'groupFeatureCapabilitiesChanged') {
        final version = data['capabilityVersion'];
        if (version is int && version < (_capabilityMinimumVersion[id] ?? 0)) {
          return;
        }
        invalidateCapabilities(id,
            expectedVersion: version is int ? version : null);
      }
      _events.add({
        ...message,
        'groupID': id,
        'data': data,
        'key': key,
        'eventId': eventID
      });
    } catch (_) {
      /* Ignore malformed/foreign business messages without breaking SDK listeners. */
    }
  }

  GroupFeatureContext context(
      {required String id,
      required String name,
      required String userID,
      required bool admin,
      required bool Function() current}) {
    final authorizationEpoch = _capabilityEpoch[id] ?? 0;
    GroupFeatureContext latest() => context(
        id: id, name: name, userID: userID, admin: admin, current: current);
    return GroupFeatureContext(
        groupID: id,
        groupName: name,
        currentUserID: userID,
        api: api,
        accountPrivilege: accountPrivilege,
        gameType: GroupGameType.fromEx(_groups[id]?.ex),
        features: features(id),
        liveState: liveFeature(id),
        capabilities: capabilities(id),
        isGroupAdmin: admin,
        sessionCurrent: () => active && !_left.contains(id) && current(),
        capabilitiesCurrent: () =>
            active &&
            !_left.contains(id) &&
            current() &&
            authorizationEpoch == (_capabilityEpoch[id] ?? 0),
        onFeaturesChanged: (json) => apply(id, json),
        onFeaturesCommitted: (json, pending) {
          if (!active || _left.contains(id)) return;
          final summary = GroupFeatures.fromJson(json);
          if (summary.valid && summary.revision >= features(id).revision) {
            final mirror = GroupFeatures.fromEx(_groups[id]?.ex);
            // Reads may omit imSyncStatus. An accepted business summary still
            // outranks an absent/older SDK mirror until that mirror catches up.
            if (pending ||
                !mirror.valid ||
                mirror.revision < summary.revision) {
              _pendingMirrors[id] = summary.revision;
            }
          }
          apply(id, json);
        },
        onLiveStateChanged: (live) {
          if (current()) applyLiveState(id, live);
        },
        readContext: latest,
        reloadCapabilities: (force) async {
          await loadCapabilities(id, force: force);
          final error = capabilityError(id);
          if (error != null) throw error;
          if (!_capabilities.containsKey(id)) {
            throw const GroupFeatureException('群功能权限正在更新，请重试',
                code: 'CAPABILITIES_CHANGED');
          }
          return latest();
        },
        onCapabilitiesInvalidated: () => invalidateCapabilities(id),
        events: events(id));
  }

  void remove(String id) {
    if (!active) return;
    invalidateCapabilities(id);
    _left.add(id);
    _groups.remove(id);
    _features.remove(id);
    _liveStates.remove(id);
    _pendingMirrors.remove(id);
    _queued.remove(id);
    _requested.remove(id);
    _events.add({
      'key': 'groupFeaturesChanged',
      'groupID': id,
      'action': 'left',
      'data': const {}
    });
    notifyListeners();
  }

  void invalidateSession() {
    if (_closed) return;
    _invalidated = true;
    clear();
  }

  void clear() {
    for (final token in _capabilityTokens.values) {
      token.cancel();
    }
    _groups.clear();
    _features.clear();
    _liveStates.clear();
    _pendingMirrors.clear();
    _capabilities.clear();
    _expiry.clear();
    _pendingCapabilities.clear();
    _capabilityTokens.clear();
    _capabilityErrors.clear();
    _capabilityEpoch.clear();
    _capabilityMinimumVersion.clear();
    _queued.clear();
    _requested.clear();
    _seenEvents.clear();
    _left.clear();
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    accountPrivilege.removeListener(_privilegeChanged);
    _closed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    clear();
    _events.close();
    super.dispose();
  }
}
