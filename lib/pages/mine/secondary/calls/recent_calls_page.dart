import 'package:openim_common/localization.dart';
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
import 'widgets/recent_call_icons.dart';

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
      title: _label(AppCopy.text('开始通话'), 'Start a Call'),
      actions: [
        SettingsAction(_label(AppCopy.text('语音通话'), 'Audio Call'), 'audio'),
        SettingsAction(_label(AppCopy.text('视频通话'), 'Video Call'), 'video'),
      ],
    );
    if (!mounted || !_sessionCurrent(account) || type == null) return;
    final starter = widget.onStartCall;
    if (starter == null) {
      await showUnavailableSettingsAction(
          context,
          type == 'video'
              ? _label(AppCopy.text('视频通话'), 'Video Call')
              : _label(AppCopy.text('语音通话'), 'Audio Call'));
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

  Future<void> _openProfile(CallRecords record) async {
    if (_acting || record.roomType == 'group' || record.userID.trim().isEmpty) {
      return;
    }
    if (!_sessionCurrent(_cache.userID)) return;
    setState(() => _acting = true);
    try {
      await AppNavigator.startUserProfilePane(
          userID: record.userID,
          nickname: record.nickname,
          faceURL: record.faceURL);
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
        title: _label(AppCopy.text('隐藏通话记录'), 'Hide Call Records'),
        message: bulk
            ? _label(
                AppCopy.format(
                    '从本设备隐藏当前列表的 {#0} 条通话记录？其他设备仍可查看。', [snapshot.length]),
                'Hide ${snapshot.length} call records on this device? They remain available on other devices.')
            : _label(AppCopy.text('从本设备隐藏这条通话记录？其他设备仍可查看。'),
                'Hide this call record on this device? It remains available on other devices.'),
        confirmText: _label(AppCopy.text('隐藏'), 'Hide'),
        destructive: true,
      );
      if (!confirmed || !_sessionCurrent(account)) return;
      await _cache.deleteCallRecordsBatch(snapshot);
    } catch (error) {
      if (mounted && _sessionCurrent(account)) {
        showSettingsError(context, error,
            _label(AppCopy.text('隐藏失败，请重试'), 'Could not hide. Try again.'));
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
          color: dark
              ? RecentCallTokens.segmentDark
              : RecentCallTokens.segmentLight,
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
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : RecentCallTokens.transition,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppTokens.surface(dark: dark)
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(RecentCallTokens.segmentItemRadius),
                  boxShadow:
                      selected ? const [RecentCallTokens.segmentShadow] : null,
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
                  const RecentNewCallIcon(),
                  const SizedBox(width: RecentCallTokens.newCallGap),
                  Expanded(
                      child: Text(
                          _label(AppCopy.text('开始新通话'), 'Start a New Call'),
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
        title: _label(AppCopy.text('通话记录读取失败'), 'Could not load call records'),
        actionLabel: _label(AppCopy.text('重试'), 'Retry'),
        onAction: () => unawaited(_refresh()),
      );
    }
    if (records.isEmpty) {
      return SettingsEmptyState(
        icon: _tab == _RecentCallTab.missed
            ? Icons.phone_missed_outlined
            : Icons.call_outlined,
        title: _tab == _RecentCallTab.missed
            ? _label(AppCopy.text('暂无未接记录'), 'No missed calls')
            : _label(AppCopy.text('暂无通话记录'), 'No call records'),
      );
    }
    return ListView.separated(
      key: const ValueKey('recent-calls-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: records.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: _editing
            ? RecentCallTokens.editingDividerIndent
            : RecentCallTokens.dividerIndent,
        endIndent: AppTokens.s5,
        color: AppTokens.border(dark: dark),
      ),
      itemBuilder: (context, index) {
        final record = records[index];
        return RecentCallTile(
            record: record,
            editing: _editing,
            enabled: !_acting,
            onRedial: () => unawaited(_redial(record)),
            onProfile: () => unawaited(_openProfile(record)),
            onDelete: () => unawaited(_delete([record])));
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
            opaque: true,
            toolbarHeight: kToolbarHeight,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            backgroundColor: surface,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: overlay,
            leadingWidth: _editing ? RecentCallTokens.editLeadingWidth : null,
            leading: _editing
                ? TextButton(
                    key: const ValueKey('recent-calls-delete-visible'),
                    onPressed: _acting || records.isEmpty
                        ? null
                        : () => unawaited(_delete(records, bulk: true)),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.only(
                            left: RecentCallTokens.newCallGap,
                            right: RecentCallTokens.actionGap),
                        alignment: Alignment.centerLeft,
                        foregroundColor: RecentCallTokens.danger,
                        disabledForegroundColor:
                            AppTokens.textSecondary(dark: dark)),
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _tab == _RecentCallTab.all
                              ? _label(AppCopy.text('删除全部'), 'Delete All')
                              : _label(AppCopy.text('删除未接'), 'Delete Missed'),
                          style: const TextStyle(
                              fontSize: AppTokens.secondaryFontSize,
                              fontWeight: FontWeight.w500),
                        )),
                  )
                : IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: RecentCallTokens.backIconSize,
                        color: AppTokens.accent),
                  ),
            title: _segments(dark),
            actions: [
              SizedBox(
                width: RecentCallTokens.headerActionWidth,
                child: TextButton(
                  key: const ValueKey('recent-calls-edit'),
                  onPressed: _acting || (!_editing && records.isEmpty)
                      ? null
                      : () => setState(() => _editing = !_editing),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTokens.accent,
                    disabledForegroundColor:
                        AppTokens.textSecondary(dark: dark),
                  ),
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                          _editing
                              ? _label('完成', 'Done')
                              : _label(AppCopy.text('编辑'), 'Edit'),
                          style: const TextStyle(
                              fontSize: RecentCallTokens.nameSize,
                              fontWeight: FontWeight.w500))),
                ),
              ),
              const SizedBox(width: RecentCallTokens.actionGap),
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
                        _label(AppCopy.text('同步失败，已保留本地记录'),
                            'Sync failed. Saved records are still available.'),
                        style: TextStyle(
                            color: AppTokens.textSecondary(dark: dark)),
                      )),
                      TextButton(
                          onPressed: () => unawaited(_refresh()),
                          child: Text(_label(AppCopy.text('重试'), 'Retry'))),
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
