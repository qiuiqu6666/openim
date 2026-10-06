import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../../settings/widgets/settings_widgets.dart';
import 'data/call_records_repository.dart';
import 'data/call_records_runtime.dart';
import 'recent_call_tile.dart';
import 'recent_call_tokens.dart';

enum _RecentCallTab { all, missed }

class RecentCallsPage extends StatefulWidget {
  const RecentCallsPage({
    super.key,
    this.onStartCall,
    this.cacheController,
    this.repository,
  });

  final void Function(String userId, bool video)? onStartCall;
  final CacheController? cacheController;
  final CallRecordsRepository? repository;

  @override
  State<RecentCallsPage> createState() => _RecentCallsPageState();
}

class _RecentCallsPageState extends State<RecentCallsPage>
    with WidgetsBindingObserver {
  late final CacheController _cache;
  CallRecordsRepository? _repository;
  _RecentCallTab _tab = _RecentCallTab.all;
  bool _editing = false;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _cache = widget.cacheController ??
        widget.repository?.cache ??
        Get.find<CacheController>();
    _repository = widget.repository ??
        (widget.cacheController == null ? CallRecordsRuntime.repository : null);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  Future<void> _refresh() => _repository?.refresh() ?? _cache.initCallRecords();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _label(String zh, String en) => settingsText(context, zh: zh, en: en);

  List<CallRecords> get _visible => _cache.callRecordList
      .where((record) => _tab == _RecentCallTab.all || record.isMissed)
      .toList();

  bool _sessionCurrent(String account) =>
      mounted && _cache.isAccountCurrent(account);

  Future<void> _chooseCall(String userId, String account) async {
    if (!_sessionCurrent(account) || userId.trim().isEmpty) return;
    final type = await showSettingsActionSheet<String>(
      context,
      title: _label('开始通话', 'Start a Call'),
      actions: [
        SettingsAction(_label('语音通话', 'Audio Call'), 'audio'),
        SettingsAction(_label('视频通话', 'Video Call'), 'video'),
      ],
    );
    if (!mounted || !_sessionCurrent(account) || type == null) return;
    final starter = widget.onStartCall;
    if (starter == null) {
      await showUnavailableSettingsAction(
          context,
          type == 'video'
              ? _label('视频通话', 'Video Call')
              : _label('语音通话', 'Audio Call'));
      return;
    }
    starter(userId.trim(), type == 'video');
  }

  Future<void> _startNewCall() async {
    if (_acting) return;
    final account = _cache.userID;
    if (!_cache.isAccountCurrent(account)) return;
    setState(() => _acting = true);
    try {
      final result =
          await AppNavigator.startSelectContacts(action: SelAction.crateGroup);
      if (!_sessionCurrent(account) || result == null) return;
      final picked = IMUtils.convertSelectContactsResultToUserInfo(result);
      if (picked == null || picked.isEmpty) return;
      await _chooseCall(picked.first.userID ?? '', account);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _redial(CallRecords record) async {
    if (_acting || record.roomType == 'group') return;
    final account = _cache.userID;
    setState(() => _acting = true);
    try {
      await _chooseCall(record.userID, account);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _delete(List<CallRecords> records, {bool bulk = false}) async {
    if (_acting || records.isEmpty) return;
    final account = _cache.userID;
    final snapshot = records.map((record) => record.copy()).toList();
    setState(() => _acting = true);
    try {
      final confirmed = await showSettingsConfirm(
        context,
        title: _label('隐藏通话记录', 'Hide Call Records'),
        message: bulk
            ? _label('从本设备隐藏当前列表的 ${snapshot.length} 条通话记录？其他设备仍可查看。',
                'Hide ${snapshot.length} call records on this device? They remain available on other devices.')
            : _label('从本设备隐藏这条通话记录？其他设备仍可查看。',
                'Hide this call record on this device? It remains available on other devices.'),
        confirmText: _label('隐藏', 'Hide'),
        destructive: true,
      );
      if (!confirmed || !_sessionCurrent(account)) return;
      await _cache.deleteCallRecordsBatch(snapshot);
    } catch (error) {
      if (mounted && _sessionCurrent(account)) {
        showSettingsError(
            context, error, _label('隐藏失败，请重试', 'Could not hide. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Widget _segments(bool dark) => Container(
        width: RecentCallTokens.segmentWidth,
        height: RecentCallTokens.segmentHeight,
        padding: const EdgeInsets.all(RecentCallTokens.segmentInset),
        decoration: BoxDecoration(
          color: AppTokens.surfaceAlt(dark: dark),
          borderRadius: BorderRadius.circular(RecentCallTokens.segmentRadius),
        ),
        child: Row(
            children: _RecentCallTab.values.map((tab) {
          final selected = tab == _tab;
          return Expanded(
              child: Semantics(
            selected: selected,
            button: true,
            child: GestureDetector(
              key: ValueKey('recent-calls-tab-${tab.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: _acting ? null : () => setState(() => _tab = tab),
              child: AnimatedContainer(
                duration: RecentCallTokens.transition,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppTokens.surface(dark: dark)
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(RecentCallTokens.segmentItemRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        tab == _RecentCallTab.all
                            ? _label('全部', 'All')
                            : _label('未接', 'Missed'),
                        style: TextStyle(
                            color: AppTokens.textPrimary(dark: dark),
                            fontSize: AppTokens.secondaryFontSize,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500),
                      )),
                ),
              ),
            ),
          ));
        }).toList()),
      );

  Widget _newCall(bool dark) => Container(
        margin: const EdgeInsets.fromLTRB(AppTokens.s5, AppTokens.s4,
            AppTokens.s5, RecentCallTokens.mediaGap),
        decoration: BoxDecoration(
            color: AppTokens.surface(dark: dark),
            borderRadius:
                BorderRadius.circular(RecentCallTokens.sectionRadius)),
        child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('recent-calls-new'),
              borderRadius:
                  BorderRadius.circular(RecentCallTokens.sectionRadius),
              onTap: _acting || _editing ? null : _startNewCall,
              child: Container(
                constraints:
                    const BoxConstraints(minHeight: AppTokens.listItemHeight),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s5, vertical: AppTokens.s4),
                child: Row(children: [
                  const Icon(Icons.add_call,
                      size: AppTokens.chevronSize, color: AppTokens.accent),
                  const SizedBox(width: AppTokens.s4),
                  Expanded(
                      child: Text(_label('开始新通话', 'Start a New Call'),
                          style: const TextStyle(
                              color: AppTokens.accent,
                              fontSize: RecentCallTokens.nameSize,
                              fontWeight: FontWeight.w500))),
                ]),
              ),
            )),
      );

  Widget _records(
      bool dark, List<CallRecords> records, bool loading, String? error) {
    if (records.isEmpty && loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTokens.accent));
    }
    if (records.isEmpty && error != null) {
      return SettingsEmptyState(
        icon: Icons.error_outline,
        title: _label('通话记录读取失败', 'Could not load call records'),
        actionLabel: _label('重试', 'Retry'),
        onAction: () => unawaited(_refresh()),
      );
    }
    if (records.isEmpty) {
      return SettingsEmptyState(
        icon: _tab == _RecentCallTab.missed
            ? Icons.phone_missed_outlined
            : Icons.call_outlined,
        title: _tab == _RecentCallTab.missed
            ? _label('暂无未接记录', 'No missed calls')
            : _label('暂无通话记录', 'No call records'),
      );
    }
    return ListView.builder(
      key: const ValueKey('recent-calls-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppTokens.s5, 0, AppTokens.s5, AppTokens.s7),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        final radius = Radius.circular(RecentCallTokens.sectionRadius);
        return ClipRRect(
          borderRadius: BorderRadius.vertical(
              top: index == 0 ? radius : Radius.zero,
              bottom: index == records.length - 1 ? radius : Radius.zero),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            RecentCallTile(
                record: record,
                editing: _editing,
                enabled: !_acting,
                onRedial: () => unawaited(_redial(record)),
                onDelete: () => unawaited(_delete([record]))),
            if (index != records.length - 1)
              Divider(
                  height: 1,
                  thickness: .5,
                  color: AppTokens.border(dark: dark)),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final background = AppTokens.background(dark: dark);
    final surface = AppTokens.surface(dark: dark);
    final overlay =
        AppSystemBars.styleFor(surface, navigationBackground: background);
    return Obx(() {
      final records = _visible;
      final loading = _cache.callRecordsLoading.value;
      final error = _cache.callRecordsError.value;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: Scaffold(
          backgroundColor: background,
          appBar: GlassAppBar(
            toolbarHeight: kToolbarHeight,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            backgroundColor: surface,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: overlay,
            leading: _editing
                ? IconButton(
                    key: const ValueKey('recent-calls-delete-visible'),
                    tooltip: _tab == _RecentCallTab.all
                        ? _label('隐藏全部记录', 'Hide all records')
                        : _label('隐藏未接记录', 'Hide missed records'),
                    onPressed: _acting || records.isEmpty
                        ? null
                        : () => unawaited(_delete(records, bulk: true)),
                    icon:
                        Icon(Icons.delete_outline, color: settingsDanger(dark)),
                  )
                : IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: RecentCallTokens.mediaIconSize,
                        color: AppTokens.accent),
                  ),
            title: _segments(dark),
            actions: [
              IconButton(
                key: const ValueKey('recent-calls-edit'),
                tooltip: _editing ? _label('完成', 'Done') : _label('编辑', 'Edit'),
                onPressed: _acting || (!_editing && records.isEmpty)
                    ? null
                    : () => setState(() => _editing = !_editing),
                icon: Icon(_editing ? Icons.check : Icons.edit_outlined,
                    color: AppTokens.accent),
              )
            ],
          ),
          body: SafeArea(
              top: false,
              child: Column(children: [
                _newCall(dark),
                if (records.isNotEmpty && loading)
                  const LinearProgressIndicator(color: AppTokens.accent),
                if (records.isNotEmpty && error != null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppTokens.s5),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                        _label('同步失败，已保留本地记录',
                            'Sync failed. Saved records are still available.'),
                        style: TextStyle(
                            color: AppTokens.textSecondary(dark: dark)),
                      )),
                      TextButton(
                          onPressed: () => unawaited(_refresh()),
                          child: Text(_label('重试', 'Retry'))),
                    ]),
                  ),
                Expanded(
                    child: RefreshIndicator(
                  onRefresh: _refresh,
                  color: AppTokens.accent,
                  child: records.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) =>
                              SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: SizedBox(
                                    height: constraints.maxHeight,
                                    child: _records(
                                        dark, records, loading, error)),
                              ))
                      : _records(dark, records, loading, error),
                )),
              ])),
        ),
      );
    });
  }
}
