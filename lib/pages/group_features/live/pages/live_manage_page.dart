import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:intl/intl.dart';
import 'package:openim_common/openim_common.dart';
import '../../models/group_feature_context.dart';
import '../../data/group_feature_api.dart';
import '../data/live_api.dart';
import '../data/live_permission_state.dart';
import '../models/live_errors.dart';
import '../models/live_models.dart';
import '../models/live_summary_events.dart';
import '../widgets/live_style.dart';
import '../widgets/live_obs_guide.dart';
import 'live_member_picker.dart';
import 'live_push_page.dart';

class LiveManagePage extends StatefulWidget {
  const LiveManagePage(
      {super.key,
      required this.featureContext,
      this.onStateChanged,
      this.currentLoaded = false});
  final GroupFeatureContext featureContext;
  final ValueChanged<LiveSession>? onStateChanged;

  /// The entry already confirmed that this group has no active live session.
  final bool currentLoaded;
  @override
  State<LiveManagePage> createState() => _LiveManagePageState();
}

class _LiveManagePageState extends State<LiveManagePage>
    with WidgetsBindingObserver {
  final _name = TextEditingController(), _description = TextEditingController();
  GroupMembersInfo? _anchor;
  LiveSession? _session;
  DateTime? _scheduled;
  bool _loading = true, _busy = false, _immediate = true, _loaded = false;
  bool _creationUncertain = false;
  bool _reloadQueued = false;
  GroupLiveFeature? _summary;
  Object? _error;
  late final LivePermissionState _permissions;
  late final LiveSummaryEvents _summaries;
  StreamSubscription<Map<String, dynamic>>? _events;
  Timer? _debounce;
  bool _foreground = true;
  int _loadGeneration = 0;
  String? _savedNotice;
  LiveSession? _savedState;
  GroupFeatureContext get featureContext => _permissions.context;
  LiveApi get api => LiveApi(featureContext);
  bool get sessionCurrent => mounted && _permissions.sessionCurrent;
  bool get current => sessionCurrent && _foreground && _permissions.current;
  @override
  void initState() {
    super.initState();
    _permissions = LivePermissionState(widget.featureContext);
    _permissions.addListener(_permissionsChanged);
    _summaries = LiveSummaryEvents(widget.featureContext.features);
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _permissions.setActive(_foreground);
    _events = widget.featureContext.events.listen((event) {
      final summary = _summaries.accept(event, widget.featureContext.groupID);
      if (summary == null || !sessionCurrent) return;
      _summary = summary;
      if (!_foreground) return;
      if (_busy) {
        _reloadQueued = true;
        return;
      }
      _debounce?.cancel();
      _debounce =
          Timer(const Duration(milliseconds: 250), () => unawaited(_load()));
    });
    unawaited(_load());
  }

  void _permissionsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _permissions.setActive(_foreground);
    if (!_foreground) {
      ++_loadGeneration;
      _debounce?.cancel();
      return;
    }
    _publishSaved();
    if (!_busy) unawaited(_load(forcePermissions: true));
  }

  Future<void> _load({bool forcePermissions = false}) async {
    if (!sessionCurrent || !_foreground || _busy) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fetched =
          !_loaded && widget.currentLoaded ? null : await api.current();
      if (!sessionCurrent || !_foreground || generation != _loadGeneration) {
        return;
      }
      // A delayed replica read must not replace a confirmed newer write.
      final known = _session;
      final session = fetched != null &&
              known != null &&
              fetched.id == known.id &&
              fetched.version < known.version
          ? known
          : fetched;
      setState(() {
        _session = session;
        _name.text = session?.roomName ?? '';
        _description.text = session?.description ?? '';
        _scheduled = session?.scheduledAt?.toLocal();
        _immediate = _scheduled == null;
        _loaded = true;
        if (session != null) _creationUncertain = false;
      });
      await _permissions.refresh(force: forcePermissions);
      if (!current || generation != _loadGeneration) return;
      if (session?.anchorID.isNotEmpty == true) {
        try {
          final members = await OpenIM.iMManager.groupManager
              .getGroupMembersInfo(
                  groupID: featureContext.groupID,
                  userIDList: [session!.anchorID]);
          if (current && generation == _loadGeneration && members.isNotEmpty) {
            setState(() => _anchor = members.first);
          }
        } catch (_) {
          /* The verified session remains usable if avatar lookup fails. */
        }
      }
    } catch (error) {
      if (sessionCurrent && _foreground && generation == _loadGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickAnchor() async {
    final member = await Navigator.of(context).push<GroupMembersInfo>(
        MaterialPageRoute(
            builder: (_) => LiveMemberPicker(featureContext: featureContext)));
    if (current && member != null) setState(() => _anchor = member);
  }

  Future<void> _pickTime() async {
    final minimum = DateTime.now().add(const Duration(minutes: 2));
    var selected = _scheduled?.isAfter(minimum) == true ? _scheduled! : minimum;
    final at = await showModalBottomSheet<DateTime>(
        context: context,
        useSafeArea: true,
        backgroundColor: LiveStyle.card(context),
        builder: (sheetContext) => SizedBox(
            height: 310,
            child: Column(children: [
              Row(children: [
                TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('取消')),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(selected),
                    child: const Text('完成'))
              ]),
              Expanded(
                  child: CupertinoDatePicker(
                      initialDateTime: selected,
                      minimumDate: minimum,
                      use24hFormat: true,
                      onDateTimeChanged: (value) => selected = value))
            ])));
    if (current && at != null) {
      setState(() {
        _scheduled = at;
        _immediate = false;
      });
    }
  }

  void _beginMutation() {
    _debounce?.cancel();
    _reloadQueued = false;
    ++_loadGeneration;
    setState(() {
      _busy = true;
      _loading = false;
      _error = null;
    });
  }

  void _finishMutation() {
    if (!mounted) return;
    setState(() => _busy = false);
    if (_reloadQueued && sessionCurrent && _foreground) {
      _reloadQueued = false;
      _debounce?.cancel();
      _debounce =
          Timer(const Duration(milliseconds: 250), () => unawaited(_load()));
    }
  }

  Future<void> _save() async {
    if (_busy || !current || _creationUncertain) return;
    final creating = _session == null || !_session!.status.active;
    _beginMutation();
    try {
      await _permissions.refresh();
      if (!current) return;
      if (!_immediate && _scheduled == null) {
        throw const FormatException('请选择预约开播时间');
      }
      final session = creating
          ? await api.configure(
              name: _name.text,
              description: _description.text,
              anchorID: _anchor?.userID ?? '',
              scheduledAt: _immediate ? null : _scheduled)
          : await api.schedule(
              name: _name.text,
              at: _scheduled ?? (throw const FormatException('请选择预约开播时间')));
      // A committed summary can invalidate this operation's permission epoch.
      // Its confirmed result still belongs to this account and group.
      if (!sessionCurrent) return;
      setState(() {
        _session = session;
        _scheduled = session.scheduledAt?.toLocal();
        _immediate = _scheduled == null;
      });
      _savedNotice = '直播设置已保存';
      _savedState = session;
      _publishSaved();
      if (!_foreground) return;
      final refreshed = await _permissions.refresh();
      if (!mounted) return;
      if (!current) return;
      final livePermissions = refreshed.capabilities.live;
      final showConfiguration = widget.currentLoaded
          ? session.status.active &&
              (livePermissions.canManage || livePermissions.canPush)
          : session.status == LiveStatus.authorized && livePermissions.canPush;
      if (showConfiguration) {
        final ended = await Navigator.of(context).push<LiveSession>(
            MaterialPageRoute<LiveSession>(
                builder: (_) => LivePushPage(
                    featureContext: refreshed,
                    session: session,
                    onStateChanged: widget.onStateChanged)));
        if (!mounted) return;
        if (sessionCurrent && ended != null) {
          setState(() {
            _session = ended;
            _scheduled = ended.scheduledAt?.toLocal();
            _immediate = _scheduled == null;
          });
        }
        if (sessionCurrent &&
            _foreground &&
            widget.currentLoaded &&
            ModalRoute.of(context)?.isCurrent == true &&
            Navigator.of(context).canPop()) {
          Navigator.of(context).pop(ended);
        }
      }
    } catch (error) {
      if (!sessionCurrent || !_foreground) return;
      if (creating &&
          error is GroupFeatureException &&
          (error.code == '20069' || error.unknownResult)) {
        setState(() => _creationUncertain = true);
        // A conflict or timeout must never cause an automatic second authorize.
        try {
          final actual = await api.current();
          if (!sessionCurrent || !_foreground) return;
          if (actual != null) {
            setState(() {
              _session = actual;
              _name.text = actual.roomName;
              _description.text = actual.description;
              _scheduled = actual.scheduledAt?.toLocal();
              _immediate = _scheduled == null;
              _creationUncertain = false;
              _error = StateError(error.code == '20069'
                  ? '该群已有未结束的直播，已显示当前场次'
                  : '创建结果尚未确认，已显示当前场次，请核对后继续');
            });
            widget.onStateChanged?.call(actual);
            await _permissions.refresh();
            return;
          }
        } catch (calibrationError) {
          if (sessionCurrent && _foreground) {
            setState(() => _error = StateError(
                '创建结果尚未确认，请刷新当前场次：${liveErrorMessage(calibrationError)}'));
          }
          return;
        }
      }
      if (sessionCurrent && _foreground) setState(() => _error = error);
    } finally {
      _finishMutation();
    }
  }

  void _publishSaved() {
    if (!sessionCurrent || !_foreground || _savedNotice == null) return;
    final notice = _savedNotice!;
    _savedNotice = null;
    final saved = _savedState;
    _savedState = null;
    if (saved != null) widget.onStateChanged?.call(saved);
    IMViews.showToast(notice);
  }

  Future<void> _openPush() async {
    if (_busy || !sessionCurrent || !_foreground || _session == null) return;
    try {
      final refreshed = await _permissions.refresh();
      if (!mounted) return;
      if (!current) return;
      if (!refreshed.capabilities.live.canPush) throw StateError('没有获取推流信息的权限');
      final session = _session!;
      if (!session.status.active) return;
      final ended = await Navigator.of(context).push<LiveSession>(
          MaterialPageRoute<LiveSession>(
              builder: (_) => LivePushPage(
                  featureContext: refreshed,
                  session: session,
                  onStateChanged: widget.onStateChanged)));
      if (sessionCurrent && ended != null) {
        setState(() {
          _session = ended;
          _scheduled = ended.scheduledAt?.toLocal();
          _immediate = _scheduled == null;
        });
      }
    } catch (error) {
      if (sessionCurrent && _foreground) setState(() => _error = error);
    }
  }

  Future<void> _end() async {
    if (_busy || _session == null || !current) return;
    final sessionID = _session!.id;
    final revoke = _session!.status != LiveStatus.live;
    bool actionCurrent() =>
        current &&
        _session?.id == sessionID &&
        _session?.status.active == true &&
        featureContext.capabilities.live.canManage &&
        revoke == (_session!.status != LiveStatus.live) &&
        (_summary == null ||
            (_summary!.sessionID == sessionID &&
                _summary!.isActive &&
                (!revoke || _summary!.status != 'live')));
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(revoke ? '撤销直播' : '结束直播'),
                content:
                    Text(revoke ? '确认撤销这场直播吗？' : '确认结束直播吗？结束后请在 OBS 中停止推流。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('确认',
                          style: TextStyle(color: AppTokens.danger)))
                ]));
    if (confirmed != true || _busy || _loading || !actionCurrent()) return;
    _beginMutation();
    try {
      await _permissions.refresh();
      if (!actionCurrent()) return;
      final ended = await api.end(revoke: revoke);
      if (!mounted) return;
      if (!sessionCurrent || ended.id != sessionID) return;
      setState(() {
        _session = ended;
        _scheduled = ended.scheduledAt?.toLocal();
        _immediate = _scheduled == null;
      });
      if (_foreground) {
        widget.onStateChanged?.call(ended);
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent == true &&
            Navigator.of(context).canPop()) {
          Navigator.of(context).pop(ended);
        }
      }
    } catch (error) {
      if (sessionCurrent && _foreground) setState(() => _error = error);
    } finally {
      _finishMutation();
    }
  }

  @override
  void dispose() {
    ++_loadGeneration;
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    unawaited(_events?.cancel() ?? Future<void>.value());
    _permissions.removeListener(_permissionsChanged);
    _permissions.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _session?.status.active == true;
    final editable = !active || _session!.status == LiveStatus.scheduled;
    final allowed = active
        ? featureContext.capabilities.live.canManage
        : featureContext.capabilities.live.canConfigure;
    return PopScope<LiveSession>(
        canPop: true,
        child: LiveSetupShell(
            title: '',
            bodyPadding: active
                ? const EdgeInsets.fromLTRB(16, 0, 16, 24)
                : EdgeInsets.zero,
            actions: [
              TextButton.icon(
                  onPressed: () => showLiveObsGuide(context),
                  icon: const Icon(Icons.help_outline,
                      size: 16, color: Color(0xFF8A8F99)),
                  label: const Text('直播教程',
                      style: TextStyle(fontSize: 13, color: Color(0xFF8A8F99))))
            ],
            bottom: _loading
                ? null
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    if (active && featureContext.capabilities.live.canManage)
                      TextButton(
                          onPressed: _busy ? null : _end,
                          child: Text(
                              _session!.status == LiveStatus.live
                                  ? '结束直播'
                                  : '撤销直播',
                              style: const TextStyle(color: AppTokens.danger))),
                    if (editable)
                      LivePrimaryButton(
                          label: _creationUncertain
                              ? '刷新当前场次'
                              : active
                                  ? '保存修改'
                                  : '开启直播',
                          busy: _busy,
                          onPressed: _creationUncertain
                              ? sessionCurrent && _foreground
                                  ? () => _load(forcePermissions: true)
                                  : null
                              : allowed && current
                                  ? _save
                                  : null),
                  ]),
            body: _loading
                ? const Center(
                    child: Padding(
                        padding: EdgeInsets.only(top: 120),
                        child: CircularProgressIndicator()))
                : _error != null && !_loaded
                    ? LiveError(error: _error!, retry: _load)
                    : Transform.translate(
                        offset: active ? Offset.zero : const Offset(0, -24),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                  padding: active
                                      ? EdgeInsets.zero
                                      : const EdgeInsets.fromLTRB(24, 0, 24, 4),
                                  child: Image.asset(
                                      active
                                          ? LiveStyle.heroAsset
                                          : LiveStyle.createAsset,
                                      height: active ? 168 : null,
                                      fit: BoxFit.contain)),
                              if (active)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Text('直播间配置',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: LiveStyle.text(context),
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700))),
                              Padding(
                                  padding: active
                                      ? EdgeInsets.zero
                                      : const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                  child: Container(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 16, 16, 18),
                                      decoration: BoxDecoration(
                                          color: LiveStyle.card(context),
                                          borderRadius: BorderRadius.circular(
                                              LiveStyle.cardRadius),
                                          boxShadow: LiveStyle.dark(context)
                                              ? []
                                              : const [
                                                  BoxShadow(
                                                      color: Color(0x14002D6B),
                                                      blurRadius: 18,
                                                      offset: Offset(0, 8))
                                                ]),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Wrap(
                                                spacing: 8,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Text('直播设置',
                                                      style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: LiveStyle.text(
                                                              context))),
                                                  Text('简单几步，快速开启直播',
                                                      style: TextStyle(
                                                          fontSize: 13,
                                                          color: LiveStyle
                                                              .secondary(
                                                                  context)))
                                                ]),
                                            const SizedBox(height: 22),
                                            _field(
                                                Icons.title,
                                                '直播间名称',
                                                _counterField(
                                                    key: const ValueKey(
                                                        'live-room-name'),
                                                    controller: _name,
                                                    enabled: editable && !_busy,
                                                    maxLength: 10,
                                                    hint: '请输入直播间名称')),
                                            _field(
                                                Icons.article,
                                                '直播描述（可选）',
                                                _counterField(
                                                    controller: _description,
                                                    enabled: !active && !_busy,
                                                    maxLength: 30,
                                                    hint: '介绍一下你的直播内容，吸引更多观众')),
                                            _field(
                                                Icons.person,
                                                '主播',
                                                Material(
                                                    color: LiveStyle.field(
                                                        context),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    child: ListTile(
                                                        leading: AvatarView(
                                                            width: 40,
                                                            height: 40,
                                                            url: _anchor
                                                                ?.faceURL,
                                                            text: _anchor
                                                                    ?.nickname ??
                                                                _session
                                                                    ?.anchorID ??
                                                                '主播'),
                                                        title: Text(_anchor
                                                                ?.nickname ??
                                                            _session
                                                                ?.anchorID ??
                                                            '请选择主播'),
                                                        trailing: const Icon(
                                                            Icons
                                                                .chevron_right),
                                                        onTap: !active && !_busy
                                                            ? _pickAnchor
                                                            : null))),
                                            _field(
                                                Icons.calendar_today_outlined,
                                                '预计开播时间',
                                                Row(children: [
                                                  Expanded(
                                                      child: _mode(
                                                          true,
                                                          Icons.bolt_rounded,
                                                          '立即开播',
                                                          '准备好就开始直播',
                                                          !active && !_busy
                                                              ? () => setState(
                                                                  () =>
                                                                      _immediate =
                                                                          true)
                                                              : null)),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                      child: _mode(
                                                          false,
                                                          Icons
                                                              .calendar_month_outlined,
                                                          '预约开播',
                                                          _scheduled == null
                                                              ? '设置未来的开播时间'
                                                              : DateFormat(
                                                                      'yyyy-MM-dd HH:mm')
                                                                  .format(
                                                                      _scheduled!),
                                                          editable && !_busy
                                                              ? _pickTime
                                                              : null))
                                                ])),
                                            if (active &&
                                                featureContext
                                                    .capabilities.live.canPush)
                                              TextButton(
                                                  onPressed: current
                                                      ? _openPush
                                                      : null,
                                                  child: const Text('查看推流地址')),
                                            if (!allowed)
                                              Text('当前账号没有配置直播的权限',
                                                  style: TextStyle(
                                                      color:
                                                          LiveStyle.secondary(
                                                              context))),
                                            if (_error != null)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 12),
                                                  child: Text(
                                                      liveErrorMessage(_error!),
                                                      style: const TextStyle(
                                                          color: AppTokens
                                                              .danger))),
                                          ]))),
                            ]))));
  }

  Widget _counterField(
          {Key? key,
          required TextEditingController controller,
          required bool enabled,
          required int maxLength,
          required String hint}) =>
      AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                  color: LiveStyle.dark(context)
                      ? LiveStyle.field(context)
                      : const Color(0xFFF4F6F8),
                  borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Expanded(
                    child: TextField(
                        key: key,
                        controller: controller,
                        enabled: enabled,
                        maxLength: maxLength,
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.3,
                            color: LiveStyle.dark(context)
                                ? LiveStyle.text(context)
                                : const Color(0xFF1A1D24)),
                        decoration: InputDecoration(
                            hintText: hint,
                            hintStyle: const TextStyle(
                                fontSize: 14, color: Color(0xFFB4B8C2)),
                            isDense: true,
                            filled: false,
                            counterText: '',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 16)))),
                Text('${controller.text.length}/$maxLength',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFC0C4CC))),
              ])));
  Widget _field(IconData icon, String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: LiveStyle.blue.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: LiveStyle.blue, size: 22)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: LiveStyle.text(context))))
        ]),
        const SizedBox(height: 8),
        child
      ]));
  Widget _mode(bool immediate, IconData icon, String title, String subtitle,
      VoidCallback? onTap) {
    final selected = _immediate == immediate;
    return Material(
        color: selected
            ? LiveStyle.blue.withValues(alpha: .08)
            : LiveStyle.field(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selected
                            ? LiveStyle.blue
                            : AppTokens.border(dark: LiveStyle.dark(context)))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(icon,
                                size: 20,
                                color: selected
                                    ? LiveStyle.blue
                                    : LiveStyle.secondary(context)),
                            Text(title,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? LiveStyle.blue
                                        : LiveStyle.text(context)))
                          ]),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 11,
                              color: LiveStyle.secondary(context)))
                    ]))));
  }
}
