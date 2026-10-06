import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../models/group_feature_context.dart';
import '../data/live_api.dart';
import '../data/live_permission_state.dart';
import '../models/live_errors.dart';
import '../models/live_models.dart';
import '../widgets/live_style.dart';
import '../widgets/live_watch_surface.dart';
import 'live_push_page.dart';
import 'live_tip_sheet.dart';

class LiveRoomPage extends StatefulWidget {
  const LiveRoomPage({super.key, required this.featureContext, this.session});
  final GroupFeatureContext featureContext;
  final LiveSession? session;
  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage>
    with WidgetsBindingObserver {
  LiveSession? _session;
  Object? _error;
  bool _loading = false, _busy = false;
  late final LivePermissionState _permissions;
  bool _foreground = true;
  int _loadGeneration = 0;
  GroupFeatureContext get featureContext => _permissions.context;
  bool get current => mounted && _permissions.sessionCurrent;
  bool get canOperate => current && _foreground && _permissions.current;
  @override
  void initState() {
    super.initState();
    _permissions = LivePermissionState(widget.featureContext);
    _permissions.addListener(_permissionsChanged);
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _permissions.setActive(_foreground);
    _session = widget.session;
    if (_session == null) {
      unawaited(_load());
    } else if (_foreground) {
      unawaited(_refreshPermissions());
    }
  }

  void _permissionsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshPermissions({bool force = false}) async {
    if (!current || !_foreground) return;
    try {
      await _permissions.refresh(force: force);
    } catch (error) {
      if (current && _foreground) setState(() => _error = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _permissions.setActive(_foreground);
    if (!_foreground) {
      ++_loadGeneration;
      if (mounted) setState(() => _loading = false);
    } else {
      unawaited(_refreshPermissions(force: true));
      if (_session == null) unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (_loading || !current || !_foreground) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await LiveApi(featureContext).current();
      if (current && _foreground && generation == _loadGeneration) {
        setState(() => _session = session);
        await _refreshPermissions();
      }
    } catch (error) {
      if (current && _foreground && generation == _loadGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _end() async {
    if (_busy || !canOperate) return;
    final confirm = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: const Text('结束直播'),
                content: const Text('确认结束直播吗？结束后请在 OBS 中停止推流。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('确认',
                          style: TextStyle(color: AppTokens.danger)))
                ]));
    if (confirm != true || !canOperate) return;
    setState(() => _busy = true);
    try {
      await _permissions.refresh();
      if (!canOperate) return;
      final session = await LiveApi(featureContext).end(revoke: false);
      if (current) setState(() => _session = session);
    } catch (error) {
      if (current && _foreground) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tip() async {
    if (!current || !_foreground || _session?.status != LiveStatus.live) return;
    try {
      await _permissions.refresh();
      if (!mounted) return;
      if (!canOperate || !featureContext.capabilities.live.canTip) return;
      if (_session?.status != LiveStatus.live) return;
      await GroupLiveTipSheet.show(context,
          featureContext: featureContext, session: _session!);
    } catch (error) {
      if (current && _foreground) setState(() => _error = error);
    }
  }

  Future<void> _openPush() async {
    if (!current || !_foreground || _session?.status.active != true) return;
    try {
      await _permissions.refresh();
      if (!mounted) return;
      if (!canOperate || !featureContext.capabilities.live.canPush) return;
      if (_session?.status.active != true) return;
      await Navigator.of(context)
          .push<LiveSession>(MaterialPageRoute<LiveSession>(
              builder: (_) => LivePushPage(
                  featureContext: featureContext,
                  session: _session!,
                  onStateChanged: (session) {
                    if (current) setState(() => _session = session);
                  })));
    } catch (error) {
      if (current && _foreground) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    ++_loadGeneration;
    WidgetsBinding.instance.removeObserver(this);
    _permissions.removeListener(_permissionsChanged);
    _permissions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: LiveStyle.screen,
      appBar: AppBar(
          leading: const LiveBackButton(),
          backgroundColor: LiveStyle.screen,
          foregroundColor: LiveStyle.screenInk,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          title: Text(_session?.roomName.isNotEmpty == true
              ? _session!.roomName
              : '群直播'),
          actions: [
            if (_session?.status == LiveStatus.live &&
                featureContext.capabilities.live.canTip)
              IconButton(
                  tooltip: '打赏主播',
                  icon: const Icon(Icons.card_giftcard_outlined),
                  onPressed: canOperate ? _tip : null),
            if (_session?.status.active == true &&
                featureContext.capabilities.live.canPush)
              IconButton(
                  tooltip: '推流信息',
                  icon: const Icon(Icons.settings_input_antenna),
                  onPressed: canOperate ? _openPush : null),
          ]),
      body: SafeArea(
          top: false,
          child: Column(children: [
            Expanded(
                child: Center(
                    child: !current
                        ? const Text('登录状态已变化，请重新进入',
                            style: TextStyle(color: LiveStyle.screenInk))
                        : _loading
                            ? const CircularProgressIndicator(
                                color: LiveStyle.screenInk)
                            : _session != null
                                ? GroupLiveWatchSurface(
                                    featureContext: featureContext,
                                    session: _session!,
                                    onClose: () => Navigator.of(context).pop(),
                                    onStateChanged: (session) {
                                      if (current) {
                                        setState(() => _session = session);
                                      }
                                    })
                                : _error != null
                                    ? _failure()
                                    : const Text('暂无直播',
                                        style: TextStyle(
                                            color: LiveStyle.screenInk)))),
            if (_error != null && _session != null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(liveErrorMessage(_error!),
                      style: const TextStyle(color: LiveStyle.red))),
            if (_session?.status == LiveStatus.live &&
                featureContext.capabilities.live.canManage)
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: LivePrimaryButton(
                      label: '结束直播',
                      busy: _busy,
                      onPressed: canOperate ? _end : null)),
          ])));
  Widget _failure() => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(liveErrorMessage(_error!),
            style: const TextStyle(color: LiveStyle.screenInk),
            textAlign: TextAlign.center),
        TextButton(onPressed: _load, child: const Text('重试'))
      ]));
}
