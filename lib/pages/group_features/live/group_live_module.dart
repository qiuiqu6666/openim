import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../models/group_feature_context.dart';
import 'data/live_api.dart';
import 'models/live_models.dart';
import 'pages/live_entry_page.dart';
import 'pages/live_room_page.dart';
import 'widgets/live_banner.dart';
import 'widgets/live_watch_surface.dart';
export 'models/live_models.dart';
export 'widgets/live_banner.dart' show GroupLiveBadge;

abstract final class GroupLiveModule {
  static Future<LiveSession?> openManage(BuildContext context,
          {required GroupFeatureContext featureContext,
          ValueChanged<LiveSession>? onStateChanged}) =>
      Navigator.of(context, rootNavigator: true).push<LiveSession>(
          MaterialPageRoute(
              builder: (_) => LiveEntryPage(
                  featureContext: featureContext,
                  onStateChanged: onStateChanged)));
  static Future<void> openWatch(BuildContext context,
      {required GroupFeatureContext featureContext,
      LiveSession? session}) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
            builder: (_) => LiveRoomPage(
                featureContext: featureContext, session: session)));
  }
}

/// Regular column content above chat messages. It never overlays the composer.
/// Opening the player replaces the banner, rather than creating a second player.
class GroupLiveFeatureHost extends StatefulWidget {
  const GroupLiveFeatureHost(
      {super.key, required this.featureContext, this.onStateChanged});
  final GroupFeatureContext featureContext;
  final ValueChanged<LiveSession?>? onStateChanged;
  @override
  State<GroupLiveFeatureHost> createState() => _GroupLiveFeatureHostState();
}

class _GroupLiveFeatureHostState extends State<GroupLiveFeatureHost>
    with WidgetsBindingObserver {
  LiveSession? _session;
  String _face = '';
  String _avatarScope = '';
  bool _watching = false, _loading = false;
  bool _refreshQueued = false;
  int _request = 0, _scope = 0;
  CancelToken? _cancel;
  Timer? _debounce;
  StreamSubscription<Map<String, dynamic>>? _events;
  bool get current => mounted && widget.featureContext.sessionCurrent();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _acceptFeature(widget.featureContext.liveFeature);
    _subscribe();
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    final scope = _scope;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (current && scope == _scope) unawaited(_refresh());
    });
  }

  void _subscribe() {
    _events = widget.featureContext.events.listen((event) {
      if ('${event['key']}'.toLowerCase().contains('live') && !_watching) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), () {
          if (!current || _watching) return;
          if (_loading) {
            _refreshQueued = true;
          } else {
            unawaited(_refresh());
          }
        });
      }
    });
  }

  void _acceptFeature(GroupLiveFeature feature) {
    if (!feature.isActive || feature.sessionID.isEmpty) {
      _session = null;
      _watching = false;
      return;
    }
    if (_matchesVisibleFeature(feature)) return;
    final previous = _session?.id == feature.sessionID ? _session : null;
    _session = LiveSession(
        id: feature.sessionID,
        groupID: widget.featureContext.groupID,
        status: _featureStatus(feature),
        roomName: feature.roomName,
        description: feature.description,
        anchorID: feature.anchorUserID,
        scheduledAt: feature.scheduledStartAt,
        version: previous?.version ?? 0,
        expireAt: previous?.expireAt,
        endReason: previous?.endReason ?? '',
        imSyncStatus: previous?.imSyncStatus ?? '');
    unawaited(_resolveAvatar(_session!));
  }

  bool _matchesVisibleFeature(GroupLiveFeature feature) {
    if (!feature.isActive) return _session == null;
    final session = _session;
    return session?.id == feature.sessionID &&
        session?.groupID == widget.featureContext.groupID &&
        session?.status == _featureStatus(feature) &&
        session?.roomName == feature.roomName &&
        session?.description == feature.description &&
        session?.anchorID == feature.anchorUserID &&
        session?.scheduledAt == feature.scheduledStartAt;
  }

  LiveStatus _featureStatus(GroupLiveFeature feature) =>
      feature.status == 'ready'
          ? LiveStatus.authorized
          : LiveStatus.parse(feature.status);

  bool _sameFeature(GroupLiveFeature previous, GroupLiveFeature next) =>
      previous.status == next.status &&
      previous.sessionID == next.sessionID &&
      previous.roomName == next.roomName &&
      previous.description == next.description &&
      previous.anchorUserID == next.anchorUserID &&
      previous.scheduledStartAt == next.scheduledStartAt;

  Future<void> _resolveAvatar(LiveSession session) async {
    if (session.anchorID.isEmpty || !current) return;
    final scopeVersion = _scope;
    final scope =
        '${widget.featureContext.currentUserID}|${widget.featureContext.groupID}|${session.anchorID}';
    if (_avatarScope == scope) return;
    _avatarScope = scope;
    _face = '';
    try {
      final list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
          groupID: widget.featureContext.groupID,
          userIDList: [session.anchorID]);
      if (current &&
          scopeVersion == _scope &&
          _session?.id == session.id &&
          _session?.anchorID == session.anchorID &&
          list.isNotEmpty) {
        if (_avatarScope == scope) {
          setState(() => _face = list.first.faceURL ?? '');
        }
      }
    } catch (_) {/* Existing AvatarView renders its SDK-style fallback. */}
  }

  Future<void> _refresh() async {
    if (_loading || !current) return;
    final request = ++_request;
    final feature = widget.featureContext;
    final minimumSession = _session;
    final cancel = _cancel = CancelToken();
    _loading = true;
    try {
      final session = await LiveApi(feature)
          .current(cancelToken: cancel, minimumSession: minimumSession);
      if (!current || !feature.sessionCurrent() || request != _request) return;
      final latest = feature.readCurrentContext();
      if (latest.features.valid &&
          (!feature.features.valid ||
              latest.features.revision > feature.features.revision) &&
          !_matchesSummary(session, latest.features.live)) {
        return;
      }
      if (feature.features.valid && !latest.features.valid) return;
      if (session != null &&
          session.id == _session?.id &&
          session.version < _session!.version) {
        return;
      }
      setState(() {
        _session = session;
        if (session?.status.active != true) _watching = false;
      });
      widget.onStateChanged?.call(session);
      if (session != null) unawaited(_resolveAvatar(session));
    } catch (_) {
      // Background calibration keeps the accepted entry without an error row.
      // Watching and management pages retain their own actionable error states.
    } finally {
      if (mounted && request == _request) {
        _cancel = null;
        _loading = false;
        if (_refreshQueued) {
          _refreshQueued = false;
          if (!_watching) unawaited(_refresh());
        }
      }
    }
  }

  bool _matchesSummary(LiveSession? session, GroupLiveFeature feature) {
    if (!feature.isActive) return session == null;
    final status = _featureStatus(feature);
    return session?.id == feature.sessionID && session?.status == status;
  }

  void _cancelRead() {
    ++_request;
    _cancel?.cancel('Live context changed');
    _cancel = null;
    _loading = false;
    _refreshQueued = false;
  }

  @override
  void didUpdateWidget(covariant GroupLiveFeatureHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.featureContext.currentUserID !=
            widget.featureContext.currentUserID ||
        oldWidget.featureContext.groupID != widget.featureContext.groupID ||
        !identical(oldWidget.featureContext.api, widget.featureContext.api)) {
      ++_scope;
      _cancelRead();
      _debounce?.cancel();
      _face = '';
      _avatarScope = '';
      _watching = false;
      _session = null;
      unawaited(_events?.cancel() ?? Future<void>.value());
      _subscribe();
      _acceptFeature(widget.featureContext.liveFeature);
      _scheduleRefresh();
    } else {
      final previous = oldWidget.featureContext;
      final next = widget.featureContext;
      final summaryChanged = (next.features.valid &&
              next.features.revision > previous.features.revision) ||
          (previous.features.valid && !next.features.valid);
      final projectionChanged =
          !_sameFeature(previous.liveFeature, next.liveFeature);
      if (summaryChanged || projectionChanged) {
        // A newer summary or a different accepted display projection wins over
        // an older read. Our own unchanged projection keeps the real DTO and
        // its version, rather than resetting it during a capability rebuild.
        if (summaryChanged || !_matchesVisibleFeature(next.liveFeature)) {
          _cancelRead();
        }
        _acceptFeature(next.liveFeature);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_watching) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    ++_scope;
    _cancelRead();
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!current || _session?.status.active != true) {
      return const SizedBox.shrink();
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_watching)
        GroupLiveWatchSurface(
            anchorFaceURL: _face,
            featureContext: widget.featureContext,
            session: _session!,
            onClose: () => setState(() => _watching = false),
            onStateChanged: (session) {
              if (!current) return;
              setState(() {
                _session = session;
                if (!session.status.active) _watching = false;
              });
              widget.onStateChanged?.call(session);
            })
      else
        GroupLiveBanner(
            session: _session!,
            anchorFaceURL: _face,
            onWatch: () => setState(() => _watching = true)),
    ]);
  }
}
