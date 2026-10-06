import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../models/group_feature_context.dart';
import '../data/live_api.dart';
import '../models/live_models.dart';
import '../widgets/live_style.dart';
import 'live_manage_page.dart';
import 'live_push_page.dart';
import 'live_room_page.dart';

/// Chooses the owner surface once, inside the caller's original route.
/// The route's result remains pending until the chosen page actually closes.
class LiveEntryPage extends StatefulWidget {
  const LiveEntryPage(
      {super.key, required this.featureContext, this.onStateChanged});
  final GroupFeatureContext featureContext;
  final ValueChanged<LiveSession>? onStateChanged;

  @override
  State<LiveEntryPage> createState() => _LiveEntryPageState();
}

class _LiveEntryPageState extends State<LiveEntryPage> {
  Widget? _page;
  Object? _error;
  bool _loading = false;
  int _generation = 0;
  CancelToken? _request;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading || _page != null || !widget.featureContext.sessionCurrent()) {
      return;
    }
    final generation = ++_generation;
    final original = widget.featureContext;
    final request = _request = CancelToken();
    bool current() =>
        mounted && generation == _generation && original.sessionCurrent();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var session = await LiveApi(original).current(cancelToken: request);
      if (!current()) return;
      var feature = await original.refreshCapabilities();
      if (!current()) return;
      feature = _latestContext(original, feature);
      // Permission calibration may wait across an SDK-confirmed new scene.
      // Reconcile a conflicting snapshot once; never loop or show creation
      // from an earlier null while the group already confirms an active scene.
      if (_sceneChanged(original.features, feature.features) &&
          _sceneConflicts(session, feature.features)) {
        session = await LiveApi(feature).current(cancelToken: request);
        if (!current()) return;
        feature = _latestContext(original, feature);
        if (_sceneConflicts(session, feature.features)) {
          throw StateError('直播场次信息正在更新，请重试');
        }
      }
      final permissions = feature.capabilities.live;
      final Widget page;
      if (session != null) {
        page = permissions.canManage || permissions.canPush
            ? LivePushPage(
                featureContext: feature,
                session: session,
                onStateChanged: widget.onStateChanged)
            : LiveRoomPage(featureContext: feature, session: session);
      } else {
        if (!permissions.canConfigure) throw StateError('没有配置直播的权限');
        page = LiveManagePage(
            featureContext: feature,
            currentLoaded: true,
            onStateChanged: widget.onStateChanged);
      }
      setState(() => _page = page);
    } catch (error) {
      if (current()) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
      if (identical(_request, request)) _request = null;
    }
  }

  GroupFeatureContext _latestContext(
      GroupFeatureContext original, GroupFeatureContext refreshed) {
    final latest = refreshed.readCurrentContext();
    if (!latest.sessionCurrent() ||
        latest.groupID != original.groupID ||
        latest.currentUserID != original.currentUserID ||
        !identical(latest.api, original.api)) {
      throw StateError('登录状态已变化，请重新进入');
    }
    if (!latest.capabilitiesCurrent()) {
      throw StateError('群功能权限正在更新，请重试');
    }
    return latest;
  }

  bool _sceneChanged(GroupFeatures previous, GroupFeatures next) =>
      next.valid &&
      next.revision > previous.revision &&
      (next.live.sessionID != previous.live.sessionID ||
          next.live.isActive != previous.live.isActive ||
          next.live.status != previous.live.status);

  bool _sceneConflicts(LiveSession? session, GroupFeatures features) {
    if (!features.valid) return false;
    final live = features.live;
    if (!live.isActive) return session?.status.active == true;
    if (session == null || session.id != live.sessionID) return true;
    // A same-scene pre-live SDK mirror may lag an authoritative LIVE DTO.
    return (live.status == 'live' && session.status != LiveStatus.live) ||
        (live.status == 'ready' && session.status == LiveStatus.scheduled);
  }

  @override
  void dispose() {
    ++_generation;
    _request?.cancel('live entry closed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_page != null) return _page!;
    return LiveSetupShell(
        body: _loading && widget.featureContext.sessionCurrent()
            ? Padding(
                padding: const EdgeInsets.only(top: 120),
                child: Center(child: LoadingView.indicator()))
            : LiveError(
                error: _error ?? StateError('登录状态已变化，请重新进入'), retry: _load));
  }
}
