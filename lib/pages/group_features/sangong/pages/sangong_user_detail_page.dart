import '../identity/widgets/sangong_identity_view.dart';
// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_account_flow_entry.dart';
import '../models/sangong_user_flow_result.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_account_flow_list.dart';
import 'package:openim/pages/group_features/sangong/widgets/app_back_button.dart';
import '../widgets/sangong_user_flow_tabs.dart';
import '../profile/sangong_authorized_view.dart';
import '../services/authorization/sangong_operation_scope.dart';
import '../agents/widgets/sangong_agent_user_actions.dart';

String sangongReportDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

bool sangongEntryOnDate(SangongAccountFlowEntry entry, String day) {
  final parsed = DateTime.tryParse(entry.createdAt);
  if (parsed == null) return false;
  // Explicit offsets are converted to the database's Asia/Shanghai date.
  final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(entry.createdAt);
  final time = zoned ? parsed.toUtc().add(const Duration(hours: 8)) : parsed;
  return sangongReportDate(time) == day;
}

Map<String, dynamic> sangongOwnSummary(
    List<Map<String, dynamic>> members, String id) {
  for (final member in members) {
    if ('${member['imUserId']}' == id) return member;
  }
  return const {};
}

class SangongUserDetailPage extends StatefulWidget {
  const SangongUserDetailPage(
      {super.key, required this.user, this.initialSessionId});
  final int? initialSessionId;
  final SangongAdminUserReport user;
  @override
  State<SangongUserDetailPage> createState() => _SangongUserDetailPageState();
}

class _SangongUserDetailPageState extends State<SangongUserDetailPage> {
  late final _runtime = SangongScope.read(context);
  late final _api = _runtime.admin;
  late final SangongOperationScope _pageScope;
  DateTime _date = DateTime.now().toUtc().add(const Duration(hours: 8));
  bool _batch = false, _busy = true;
  int? _sessionId;
  int _generation = 0;
  int _profileGeneration = 0;
  String? _error, _profileError, _sessionsError;
  Map<String, dynamic> _detail = {}, _summary = {};
  List<Map<String, dynamic>> _sessions = [];
  SangongUserFlowReport _flow = const SangongUserFlowReport();
  SangongUserFlowResult _flowResult = const SangongUserFlowResult();
  bool _savingMaxNegative = false;
  bool get _current =>
      mounted &&
      _runtime.canManage &&
      _pageScope.matches(_runtime.featureContext, _runtime.http.tenantId);

  @override
  void initState() {
    super.initState();
    _pageScope = SangongOperationScope.capture(
        _runtime.featureContext, _runtime.http.tenantId);
    _sessionId = widget.initialSessionId;
    _batch = _sessionId != null;
    _loadSessions();
    _load();
  }

  Future<void> _loadProfile() async {
    if (!_current) return;
    final generation = ++_profileGeneration;
    try {
      final detail = await _api.fetchUserDetail(widget.user.imUserId);
      if (_current && generation == _profileGeneration) {
        setState(() {
          _detail = detail;
          _profileError = null;
        });
      }
    } catch (_) {
      if (_current && generation == _profileGeneration) {
        setState(() => _profileError = '资料加载失败，点击重试');
      }
    }
  }

  Future<void> _loadSessions() async {
    if (!_current) return;
    try {
      final sessions = await _api.fetchReportSessions();
      if (_current) {
        setState(() {
          _sessions = sessions;
          _sessionsError = null;
        });
      }
    } catch (_) {
      if (_current) setState(() => _sessionsError = '批次加载失败，点击重试');
    }
  }

  Future<void> _load() async {
    if (!_current) return;
    final generation = ++_generation;
    final profileGeneration = _profileGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final batch = _batch;
      final day = sangongReportDate(_date);
      var sessionId = batch ? _sessionId : null;
      if (batch && sessionId == null) {
        final current = await _api.fetchSession();
        if (!_current || generation != _generation) return;
        sessionId = current.session?.id;
        if (sessionId == null) {
          final sessions = await _api.fetchReportSessions();
          if (!_current || generation != _generation) return;
          if (sessions.isNotEmpty) {
            sessionId = int.tryParse('${sessions.first['id']}');
          }
        }
        if (!_current || generation != _generation) return;
        if (sessionId == null) {
          setState(() {
            _summary = {};
            _flow = const SangongUserFlowReport();
            _flowResult = const SangongUserFlowResult();
            _busy = false;
          });
          return;
        }
      }
      final flowResult = await _api.fetchUserFlowResult(
        imUserId: widget.user.imUserId,
        sessionId: sessionId,
        date: batch ? null : day,
      );
      if (!_current || generation != _generation) return;
      final flow = flowResult.report;
      setState(() {
        _summary = flowResult.summary;
        // A report started before a confirmed limit/rate edit may still supply
        // valid ledger totals, but must not restore its older user profile.
        if (profileGeneration == _profileGeneration) {
          _detail = flowResult.detail;
          _profileError = null;
        }
        _flow = flow;
        _flowResult = flowResult;
        _busy = false;
      });
    } catch (error) {
      if (_current && generation == _generation) {
        setState(() {
          _error = DioErrorMessage.forApp(error);
          _busy = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    if (!_current) return;
    final today = DateTime.now().toUtc().add(const Duration(hours: 8));
    final date = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(2000),
        lastDate: today);
    if (!_current || date == null) return;
    setState(() => _date = date);
    _load();
  }

  Map<String, dynamic> get _profileMap {
    final raw = _detail['user'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return const {};
  }

  int _signedInt(dynamic value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int _readNonNegative(dynamic value, int fallback) {
    final parsed = _signedInt(value, fallback);
    return parsed < 0 ? fallback : parsed;
  }

  int _savedMaxNegative() {
    final profile = _profileMap;
    if (profile.containsKey('maxNegative') ||
        profile.containsKey('max_negative_balance')) {
      return _readNonNegative(
        profile['maxNegative'] ?? profile['max_negative_balance'],
        widget.user.maxNegative,
      );
    }
    return widget.user.maxNegative;
  }

  int? _numericUserId() {
    final raw =
        _profileMap['userId'] ?? _profileMap['user_id'] ?? widget.user.userId;
    if (raw is int && raw > 0) {
      return raw;
    }
    final parsed = int.tryParse(raw?.toString() ?? '');
    if (parsed != null && parsed > 0) {
      return parsed;
    }
    return null;
  }

  void _toast(String message) {
    if (!_current) {
      return;
    }
    ToastUtils.toast(message, context: context);
  }

  Widget _wrapCurrentDialog(BuildContext dialogContext, Widget child) =>
      ListenableBuilder(
          listenable: _runtime,
          builder: (_, __) => _current
              ? child
              : CupertinoAlertDialog(
                  title: const Text('游戏信息已变化'),
                  content: const Text('当前游戏权限已变化，请重新进入'),
                  actions: [
                      CupertinoDialogAction(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('关闭')),
                    ]));

  Future<void> _openMaxNegativeDialog(int balance) async {
    if (_savingMaxNegative || !_current) return;
    final userId = _numericUserId();
    if (userId == null) {
      _toast('缺少用户编号，无法设置');
      return;
    }
    final current = _savedMaxNegative();
    final amountText = await AppDialog.prompt(
      context: context,
      title: '设置可负额度',
      message: '当前可划转约 ${balance + current}（余额 + 可负额度）\n0 表示关闭负分',
      placeholder: '请输入可负额度',
      initialValue: '$current',
      cancelText: '取消',
      confirmText: '下一步',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      allowEmpty: true,
      dialogWrapper: _wrapCurrentDialog,
    );
    if (!mounted || amountText == null || !_current) {
      return;
    }
    final value = int.tryParse(amountText.trim());
    if (value == null || value < 0) {
      _toast('须为大于等于 0 的整数');
      return;
    }
    final confirmed = await AppDialog.confirm(
      context: context,
      title: '确认设置',
      message: '确认将可负额度设为 $value 吗？\n设置后可划转约 ${balance + value}',
      cancelText: '取消',
      confirmText: '确认保存',
      dialogWrapper: _wrapCurrentDialog,
    );
    if (!confirmed || !_current) {
      return;
    }
    setState(() => _savingMaxNegative = true);
    _profileGeneration++;
    try {
      final body = await _api.setUserMaxNegative(
        userId: userId,
        maxNegative: value,
        imUserId: widget.user.imUserId,
      );
      if (!_current) {
        return;
      }
      final user = body['user'];
      // Reads issued before this confirmed save cannot restore an old limit.
      _profileGeneration++;
      setState(() {
        if (user is Map) {
          final currentUser = _detail['user'];
          _detail = {
            ..._detail,
            'user': {
              if (currentUser is Map) ...Map<String, dynamic>.from(currentUser),
              ...Map<String, dynamic>.from(user),
            },
          };
        }
      });
      _toast('已保存');
      _loadProfile();
    } catch (error) {
      if (_current) {
        _toast(DioErrorMessage.forApp(error));
      }
    } finally {
      if (mounted) setState(() => _savingMaxNegative = false);
    }
  }

  Widget _maxNegativeEntry(Color muted, int balance) {
    final maxNegative = _savedMaxNegative();
    final transfer = balance + maxNegative;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('可负额度 $maxNegative',
                    style: TextStyle(fontSize: 13, color: muted)),
                const SizedBox(height: 2),
                Text('可划转 约 $transfer',
                    style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: _savingMaxNegative
                ? null
                : () => _openMaxNegativeDialog(balance),
            child: Text(_savingMaxNegative ? '核实保存结果…' : '设置额度'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raw = _detail['user'];
    final profile = raw is Map ? raw : const {};
    final nickname = profile['nickname']?.toString() ?? widget.user.nickname;
    final parent = _detail['parent'];
    final metrics = <String, String>{
      '闲流水': 'playerTurnover',
      '庄流水': 'bankerTurnover',
      '总流水': 'todayTotalTurnover',
      '上分': 'todayUp',
      '下分': 'todayDown',
      '盈亏': 'todayProfitLoss',
    };
    final today =
        sangongReportDate(DateTime.now().toUtc().add(const Duration(hours: 8)));
    final colors = Theme.of(context).colorScheme;
    final muted = colors.onSurfaceVariant;
    return SangongAuthorizedView(
        runtime: _runtime,
        isCurrent: () => _current,
        child: DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                  leading: const AppBackButton(),
                  title: const Text('用户详情'),
                  actions: [
                    IconButton(
                        onPressed: _busy
                            ? null
                            : () {
                                _load();
                              },
                        icon: const Icon(Icons.refresh)),
                  ]),
              body: SafeArea(
                  child: NestedScrollView(
                      headerSliverBuilder: (context, innerBoxIsScrolled) => [
                            SliverToBoxAdapter(
                                child: Column(children: [
                              Container(
                                margin:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                    color: colors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(16)),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        SangongIMAvatar(
                                            userID: widget.user.imUserId,
                                            nickname: nickname,
                                            size: 46),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              SangongUserName(
                                                  userID: widget.user.imUserId,
                                                  nickname: nickname,
                                                  style: const TextStyle(
                                                      fontSize: 17,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                              SangongPublicAccount(
                                                  userID: widget.user.imUserId,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: muted)),
                                            ])),
                                        if (_profileError != null)
                                          IconButton(
                                              onPressed: _loadProfile,
                                              tooltip: '资料加载失败，点击重试',
                                              icon: Icon(Icons.refresh,
                                                  color: colors.error,
                                                  size: 20)),
                                      ]),
                                      const SizedBox(height: 12),
                                      Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text('当前积分',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: muted)),
                                                  Text(
                                                      '${profile['balance'] ?? widget.user.balance}',
                                                      style: TextStyle(
                                                          fontSize: 26,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              colors.primary)),
                                                ])),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    children: [
                                                  Text(
                                                      '每万返水 ${profile['rebatePer10000'] ?? widget.user.rebatePer10000}',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: muted)),
                                                  const SizedBox(height: 4),
                                                  if (_profileError != null ||
                                                      parent is! Map)
                                                    Text(
                                                        _profileError != null
                                                            ? '上级：暂未获取'
                                                            : '上级：未设置',
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            color: muted))
                                                  else
                                                    SangongPublicAccount(
                                                        userID:
                                                            '${parent['imUserId'] ?? ''}',
                                                        prefix: '上级账号：',
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            color: muted)),
                                                ])),
                                          ]),
                                      _maxNegativeEntry(
                                        muted,
                                        _signedInt(
                                          profile['balance'] ??
                                              widget.user.balance,
                                          widget.user.balance,
                                        ),
                                      ),
                                      if (_profileError == null &&
                                          profile['userId'] is int)
                                        SangongAgentUserActions(
                                            userId: profile['userId'] as int,
                                            imUserId: widget.user.imUserId,
                                            nickname: nickname,
                                            rebatePct: num.tryParse(
                                                    '${profile['rebatePct']}') ??
                                                0,
                                            parentUserId: parent is Map
                                                ? int.tryParse(
                                                        '${parent['userId']}') ??
                                                    0
                                                : 0,
                                            onChanged: _loadProfile),
                                    ]),
                              ),
                              Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: SizedBox(
                                      width: double.infinity,
                                      child: SegmentedButton<bool>(
                                        showSelectedIcon: false,
                                        style: SegmentedButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            selectedBackgroundColor:
                                                colors.primaryContainer,
                                            selectedForegroundColor:
                                                colors.onPrimaryContainer),
                                        segments: const [
                                          ButtonSegment(
                                              value: false,
                                              label: Text('经营日汇总'),
                                              icon: Icon(
                                                  Icons.calendar_today_outlined,
                                                  size: 16)),
                                          ButtonSegment(
                                              value: true,
                                              label: Text('开机批次'),
                                              icon: Icon(Icons.layers_outlined,
                                                  size: 16))
                                        ],
                                        selected: {_batch},
                                        onSelectionChanged: (value) {
                                          setState(() => _batch = value.first);
                                          _load();
                                        },
                                      ))),
                              if (!_batch)
                                Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      IconButton(
                                          onPressed: () {
                                            setState(() => _date =
                                                _date.subtract(
                                                    const Duration(days: 1)));
                                            _load();
                                          },
                                          icon: const Icon(Icons.chevron_left)),
                                      TextButton(
                                          onPressed: _pickDate,
                                          child: Text(
                                              '${sangongReportDate(_date)} · 上海时间开机日')),
                                      IconButton(
                                          onPressed: sangongReportDate(_date) ==
                                                  today
                                              ? null
                                              : () {
                                                  setState(() => _date =
                                                      _date.add(const Duration(
                                                          days: 1)));
                                                  _load();
                                                },
                                          icon:
                                              const Icon(Icons.chevron_right)),
                                    ])
                              else
                                Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                    child: DecoratedBox(
                                        decoration: BoxDecoration(
                                            border: Border.all(
                                                color: colors.outlineVariant),
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12),
                                            child: DropdownButtonHideUnderline(
                                                child: DropdownButton<int>(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              dropdownColor: colors.surface,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  color: colors.onSurface),
                                              isExpanded: true,
                                              value: _sessionId ?? -1,
                                              items: [
                                                const DropdownMenuItem(
                                                    value: -1,
                                                    child: Text('当前／最近一次开机')),
                                                for (final session in _sessions)
                                                  if (int.tryParse(
                                                          '${session['id']}') !=
                                                      null)
                                                    DropdownMenuItem(
                                                        value: int.parse(
                                                            '${session['id']}'),
                                                        child: Text(
                                                            '${session['batchNo'] ?? session['businessDate'] ?? '批次'} · #${session['id']}'))
                                              ],
                                              onChanged: (value) {
                                                setState(() => _sessionId =
                                                    value == -1 ? null : value);
                                                _load();
                                              },
                                            ))))),
                              if (_batch && _sessionsError != null)
                                TextButton(
                                    onPressed: _loadSessions,
                                    child: Text(_sessionsError!)),
                              if (!_busy && _error == null) ...[
                                Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    decoration: BoxDecoration(
                                        color: colors.surfaceContainerLow,
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    child: LayoutBuilder(
                                        builder:
                                            (context, constraints) => Wrap(
                                                    children: [
                                                      for (final metric
                                                          in metrics.entries)
                                                        SizedBox(
                                                            width: constraints
                                                                    .maxWidth /
                                                                3,
                                                            child: Padding(
                                                                padding: const EdgeInsets
                                                                    .symmetric(
                                                                    vertical:
                                                                        6),
                                                                child: Column(
                                                                    children: [
                                                                      Text(
                                                                          metric
                                                                              .key,
                                                                          style: Theme.of(context)
                                                                              .textTheme
                                                                              .bodySmall),
                                                                      Text(
                                                                          '${_summary[metric.value] ?? 0}',
                                                                          style: TextStyle(
                                                                              fontWeight: FontWeight.w600,
                                                                              color: metric.key == '盈亏' ? ((num.tryParse('${_summary[metric.value]}') ?? 0) < 0 ? colors.error : colors.primary) : colors.onSurface,
                                                                              fontSize: 18)),
                                                                    ]))),
                                                    ]))),
                                if (_summary.isEmpty)
                                  const Text('该统计范围内无用户汇总记录，按 0 显示',
                                      style: TextStyle(fontSize: 12)),
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 6),
                                    child: Row(children: [
                                      Expanded(
                                          child: Text('本人汇总 · 最近明细',
                                              style: TextStyle(
                                                  fontSize: 11, color: muted))),
                                      Tooltip(
                                          triggerMode: TooltipTriggerMode.tap,
                                          message:
                                              '盈亏包含下注扣款、退款、派彩和庄方结算，不含上下分及返水。',
                                          child: Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: Icon(Icons.info_outline,
                                                  size: 16, color: muted))),
                                    ])),
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 6),
                                  child: Text(
                                    _flowResult.coverageMessage(batch: _batch),
                                    key:
                                        const ValueKey('sangong-flow-coverage'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: _flowResult.reachedLedgerLimit
                                              ? colors.error
                                              : muted,
                                        ),
                                  ),
                                ),
                              ],
                            ])),
                            if (!_busy && _error == null)
                              const SliverPersistentHeader(
                                  pinned: true,
                                  delegate: SangongUserFlowTabs()),
                          ],
                      body: _busy
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                      Text(_error!),
                                      TextButton(
                                          onPressed: _load,
                                          child: const Text('重试')),
                                    ]))
                              : TabBarView(children: [
                                  SangongAccountFlowList(
                                      entries: _flow.betEntries, bets: true),
                                  SangongAccountFlowList(
                                      entries: _flow.bankerEntries,
                                      bets: true,
                                      contributions:
                                          _batch ? _flow.coBankFlow : const []),
                                  SangongAccountFlowList(
                                      entries: _flow.scoreEntries, bets: false),
                                ]))),
            )));
  }
}
