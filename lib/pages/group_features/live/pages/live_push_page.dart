import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/group_feature_context.dart';
import '../data/live_api.dart';
import '../data/live_permission_state.dart';
import '../models/live_errors.dart';
import '../models/live_models.dart';
import '../models/live_summary_events.dart';
import '../widgets/live_obs_guide.dart';
import '../widgets/live_style.dart';

class LivePushPage extends StatefulWidget {
  const LivePushPage(
      {super.key,
      required this.featureContext,
      required this.session,
      this.onStateChanged});
  final GroupFeatureContext featureContext;
  final LiveSession session;
  final ValueChanged<LiveSession>? onStateChanged;
  @override
  State<LivePushPage> createState() => _LivePushPageState();
}

class _LivePushPageState extends State<LivePushPage>
    with WidgetsBindingObserver {
  late LiveSession _session;
  LivePushInfo? _info;
  Object? _error;
  bool _loading = false, _busy = false;
  Timer? _expiry, _debounce;
  StreamSubscription<Map<String, dynamic>>? _events;
  late LiveSummaryEvents _summaries;
  GroupLiveFeature? _summary;
  int _epoch = 0;
  int _loadGeneration = 0;
  bool _foreground = true;
  bool _reloadQueued = false;
  LiveSession? _pendingEnded;
  bool _endedPublished = false;
  bool _endedReturning = false;
  late final LivePermissionState _permissions;
  String _permissionKey = '';
  GroupFeatureContext get featureContext => _permissions.context;
  bool get _retired =>
      _summary != null &&
      (_summary!.sessionID != _session.id || !_summary!.isActive);
  bool get current => mounted && _foreground && _permissions.current;
  bool get sessionCurrent => mounted && _permissions.sessionCurrent;
  bool get _canEnd =>
      current &&
      !_retired &&
      _session.status.active &&
      featureContext.capabilities.live.canManage;

  bool _matchesEndAction(bool revoke) {
    if (revoke != (_session.status != LiveStatus.live)) return false;
    final summary = _summary;
    if (summary == null) return true;
    // A fresh LIVE mirror invalidates an old revoke confirmation. A lagging
    // pre-live mirror cannot invalidate the business DTO's confirmed LIVE.
    return summary.sessionID == _session.id &&
        summary.isActive &&
        (!revoke || summary.status != 'live');
  }

  bool get expired => _info?.expiresAt?.isBefore(DateTime.now()) == true;
  LiveApi get api => LiveApi(featureContext);
  @override
  void initState() {
    super.initState();
    _permissions = LivePermissionState(widget.featureContext);
    _permissions.addListener(_permissionsChanged);
    _session = widget.session;
    _summaries = LiveSummaryEvents(widget.featureContext.features);
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _permissions.setActive(_foreground);
    _permissionKey = _readPermissionKey();
    _events = widget.featureContext.events.listen((event) {
      if (!sessionCurrent) return;
      final summary = _summaries.accept(event, widget.featureContext.groupID);
      if (summary != null && mounted) {
        ++_epoch;
        ++_loadGeneration;
        _expiry?.cancel();
        setState(() {
          _summary = summary;
          _loading = false;
          _info = null;
          _error = _retired
              ? StateError(liveSummaryStopReason(summary, _session.id))
              : null;
        });
      }
      if (_foreground &&
          (summary != null ||
              '${event['key']}'.toLowerCase().contains('live'))) {
        _queueLoad();
      }
    });
    unawaited(_load());
  }

  String _readPermissionKey() => '${_permissions.current}:'
      '${featureContext.capabilities.version}:${featureContext.capabilities.live.canPush}';

  void _permissionsChanged() {
    if (!mounted) return;
    final key = _readPermissionKey();
    if (key != _permissionKey) {
      _permissionKey = key;
      ++_epoch;
      _expiry?.cancel();
      _info = null;
      if (!_permissions.current || !featureContext.capabilities.live.canPush) {
        _error = StateError(featureContext.reloadCapabilities == null
            ? '操作权限已变化，请重新打开页面'
            : '推流权限已变化，正在校准最新权限');
      }
      if (_foreground && !_busy && _permissions.current) {
        if (_loading) {
          _reloadQueued = true;
        } else {
          _queueLoad();
        }
      }
    }
    setState(() {});
  }

  void _queueLoad() {
    if (_pendingEnded != null) return;
    if (_busy) {
      _reloadQueued = true;
      return;
    }
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 250), () => unawaited(_load()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _permissions.setActive(_foreground);
    if (!_foreground) {
      ++_epoch;
      ++_loadGeneration;
      _debounce?.cancel();
      _expiry?.cancel();
      _reloadQueued = false;
      setState(() {
        _info = null;
        _loading = false;
      });
    } else {
      if (_pendingEnded != null) {
        _publishEnded();
      } else {
        unawaited(_load(forcePermissions: true));
      }
    }
  }

  Future<void> _load({bool forcePermissions = false}) async {
    if (_loading ||
        !sessionCurrent ||
        !_foreground ||
        _busy ||
        _pendingEnded != null) {
      return;
    }
    final generation = ++_loadGeneration;
    var epoch = _epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_retired) {
        throw StateError(liveSummaryStopReason(_summary!, _session.id));
      }
      await _permissions.refresh(force: forcePermissions);
      if (!current || _retired) return;
      epoch = _epoch;
      _reloadQueued = false;
      final session = await api.detail(_session.id);
      if (!current || epoch != _epoch) return;
      setState(() {
        _session = session;
        if (!session.status.active) _info = null;
      });
      if (session.status != widget.session.status ||
          session.version != widget.session.version) {
        widget.onStateChanged?.call(session);
      }
      if (_retired) {
        setState(() =>
            _error = StateError(liveSummaryStopReason(_summary!, _session.id)));
        return;
      }
      if (session.status == LiveStatus.scheduled || !session.status.active) {
        return;
      }
      if (!featureContext.capabilities.live.canPush) {
        throw StateError('没有获取推流信息的权限');
      }
      if (_info != null && !expired && _info!.expiresAt != null) return;
      final info = await api.push(session.id);
      if (!current || epoch != _epoch) return;
      setState(() => _info = info);
      _expiry?.cancel();
      if (info.expiresAt != null) {
        final delay = info.expiresAt!.difference(DateTime.now());
        _expiry = Timer(delay.isNegative ? Duration.zero : delay, () {
          if (current) {
            setState(() {}); // Expiry disables copying; never renew in a loop.
          }
        });
      }
    } catch (error) {
      if (sessionCurrent && _foreground && epoch == _epoch) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
        if (_reloadQueued && _foreground && !_busy) {
          _reloadQueued = false;
          _queueLoad();
        }
      }
    }
  }

  Future<void> _copy() async {
    if (!current ||
        !featureContext.capabilities.live.canPush ||
        _retired ||
        _info == null ||
        expired) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: _info!.combinedURL));
    if (!mounted) return;
    if (current) {
      IMViews.showToast('推流地址已复制');
    }
  }

  Future<void> _end() async {
    if (_busy || _loading || !_canEnd) return;
    final revoke = _session.status != LiveStatus.live;
    final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text(revoke ? '撤销直播' : '结束直播'),
                content:
                    Text(revoke ? '确认撤销这场直播吗？' : '确认结束直播吗？结束后请在 OBS 中停止推流。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('确认',
                          style: TextStyle(color: AppTokens.danger)))
                ]));
    // A live update can change the action while its confirmation is open.
    // Require a fresh confirmation for the new action instead of reusing it.
    if (ok != true ||
        _busy ||
        _loading ||
        !_canEnd ||
        !_matchesEndAction(revoke)) {
      return;
    }
    ++_epoch;
    ++_loadGeneration;
    _debounce?.cancel();
    _expiry?.cancel();
    _reloadQueued = false;
    setState(() {
      _busy = true;
      _loading = false;
      _error = null;
    });
    try {
      await _permissions.refresh();
      if (!_canEnd || !_matchesEndAction(revoke)) return;
      final ended = await api.end(revoke: revoke);
      if (!mounted) return;
      // Own terminal summary may advance both permission and public epochs.
      if (sessionCurrent && ended.id == _session.id) {
        setState(() {
          _session = ended;
          _info = null;
          _error = null;
          _pendingEnded = ended;
        });
        _publishEnded();
      }
    } catch (error) {
      if (sessionCurrent && _foreground) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_reloadQueued && _foreground && _pendingEnded == null) {
          _reloadQueued = false;
          _queueLoad();
        }
      }
    }
  }

  void _publishEnded() {
    final ended = _pendingEnded;
    if (!sessionCurrent || !_foreground || ended == null || _endedReturning) {
      return;
    }
    if (!_endedPublished) {
      _endedPublished = true;
      widget.onStateChanged?.call(ended);
    }
    if (!mounted || !sessionCurrent || !_foreground) return;
    if (ModalRoute.of(context)?.isCurrent == true &&
        Navigator.of(context).canPop()) {
      _endedReturning = true;
      Navigator.of(context).pop<LiveSession>(ended);
    }
  }

  Future<void> _showGuide() async {
    if (!current || _info == null) return;
    await showLiveObsGuide(context, hint: _info!.hint);
    _publishEnded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
    _debounce?.cancel();
    unawaited(_events?.cancel() ?? Future<void>.value());
    _permissions.removeListener(_permissionsChanged);
    _permissions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LiveSetupShell(
          actions: [
            IconButton(
                tooltip: '刷新状态',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: !_busy && !_loading && sessionCurrent && _foreground
                    ? () => _load(forcePermissions: true)
                    : null)
          ],
          bottom: _session.status.active &&
                  !_retired &&
                  featureContext.capabilities.live.canManage
              ? LivePrimaryButton(
                  label: _session.status == LiveStatus.live ? '结束直播' : '撤销直播',
                  busy: _busy,
                  onPressed: !_busy && !_loading && _canEnd ? _end : null)
              : null,
          body:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Transform.scale(
                scale: 1.18,
                alignment: Alignment.topCenter,
                child: Image.asset(LiveStyle.onlineAsset,
                    width: double.infinity, fit: BoxFit.contain)),
            const SizedBox(height: 80),
            if (!sessionCurrent)
              Center(child: const Text('登录状态已变化，请重新进入'))
            else if (_loading && _info == null)
              const Center(child: CircularProgressIndicator())
            else if (_error != null && _info == null)
              LiveError(error: _error!, retry: _load)
            else if (_session.status == LiveStatus.scheduled)
              _pending()
            else if (!_session.status.active)
              Center(child: Text(_session.status.label))
            else if (_info != null)
              _card(),
            if (_error != null && _info != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(liveErrorMessage(_error!),
                      style: const TextStyle(color: AppTokens.danger))),
          ]));
  Widget _pending() => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: LiveStyle.card(context),
          borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        const Icon(Icons.schedule, size: 40, color: LiveStyle.blue),
        const SizedBox(height: 12),
        const Text('直播已预约',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(_session.scheduledAt == null
            ? '等待开播'
            : DateFormat('yyyy-MM-dd HH:mm')
                .format(_session.scheduledAt!.toLocal())),
        const SizedBox(height: 12),
        const Text('开播后可获取推流地址，请刷新状态。', textAlign: TextAlign.center)
      ]));
  Widget _card() => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: LiveStyle.card(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: LiveStyle.dark(context)
              ? []
              : const [
                  BoxShadow(
                      color: Color(0x14002D6B),
                      blurRadius: 18,
                      offset: Offset(0, 8))
                ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.settings_outlined, color: LiveStyle.blue),
          const SizedBox(width: 8),
          Expanded(
              child: Text('直播设置',
                  style: TextStyle(
                      color: LiveStyle.text(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700))),
          TextButton(
              onPressed: _showGuide,
              child: const Text('直播教程', style: TextStyle(fontSize: 12)))
        ]),
        const SizedBox(height: 16),
        _label(Icons.link_rounded, '推流地址'),
        const SizedBox(height: 8),
        SizedBox(
            height: 52,
            child: Stack(alignment: Alignment.centerRight, children: [
              Positioned.fill(
                  child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.fromLTRB(16, 0, 58, 0),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                          color: LiveStyle.dark(context)
                              ? LiveStyle.field(context)
                              : const Color(0xFFF4F7FB),
                          borderRadius: BorderRadius.circular(26)),
                      child: Text(expired ? '推流地址已过期，请刷新' : _info!.combinedURL,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13, color: LiveStyle.text(context))))),
              Material(
                  color: LiveStyle.card(context),
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                      onTap: expired ? null : _copy,
                      customBorder: const CircleBorder(),
                      child: const SizedBox.square(
                          dimension: 52,
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.copy_rounded,
                                    size: 16, color: LiveStyle.blue),
                                Text('复制',
                                    style: TextStyle(
                                        fontSize: 10,
                                        height: 1.1,
                                        color: LiveStyle.blue,
                                        fontWeight: FontWeight.w600))
                              ]))))
            ])),
        const SizedBox(height: 16),
        if (expired)
          const Text('地址已过期，请刷新后重新复制到推流软件。',
              style: TextStyle(color: AppTokens.danger))
        else
          LayoutBuilder(builder: (context, box) {
            final qr =
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label(Icons.widgets_outlined, '二维码'),
              const SizedBox(height: 10),
              Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF4F8FF),
                      borderRadius: BorderRadius.circular(22)),
                  child: QrImageView(
                      data: _info!.combinedURL,
                      size: 120,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white))
            ]);
            final tips = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _tipBox('使用芯象扫描二维码\n快速填写推流地址',
                      Icons.center_focus_strong_outlined),
                  const SizedBox(height: 12),
                  _tipBox(
                      '温馨提示\n\n1. 请在其他直播应用中填写以上推流地址开始直播\n\n'
                      '2. 支持 OBS 等主流直播软件\n\n3. 直播过程请保持网络稳定',
                      Icons.lightbulb_outline_rounded)
                ]);
            if (box.maxWidth < 310 ||
                MediaQuery.textScalerOf(context).scale(12) > 18) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [qr, const SizedBox(height: 16), tips]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: qr),
              const SizedBox(width: 12),
              Expanded(flex: 6, child: tips)
            ]);
          }),
      ]));
  Widget _label(IconData icon, String label) => Row(children: [
        Icon(icon, size: 20, color: LiveStyle.blue),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 14, color: LiveStyle.text(context))))
      ]);
  Widget _tipBox(String text, IconData icon) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: LiveStyle.dark(context)
              ? LiveStyle.field(context)
              : const Color(0xFFF3F8FF),
          borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: LiveStyle.blue, size: 22),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: LiveStyle.text(context))))
      ]));
}
