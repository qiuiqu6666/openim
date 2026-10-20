import 'package:openim_common/localization.dart';
import 'dart:async';
import '../services/account_identity/sangong_team_user_search.dart';
import 'package:openim_common/openim_common.dart'
    show normalizePublicAccountSearch;
import '../services/account_identity/sangong_account_identity_resolver.dart';
import '../identity/widgets/sangong_identity_view.dart';
// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_transfers_page.dart';
import 'package:openim/pages/group_features/sangong/models/agent_rebate_models.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_member_detail_page.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/widgets/app_back_button.dart';
import '../widgets/authorization/sangong_agent_authorized_view.dart';

class SangongAgentTeamPage extends StatefulWidget {
  const SangongAgentTeamPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        SangongPageRoute(
          agent: true,
          context: context,
          settings: const RouteSettings(name: 'sangong_agent_team'),
          builder: (_) => const SangongAgentTeamPage(),
        ),
      );

  @override
  State<SangongAgentTeamPage> createState() => _SangongAgentTeamPageState();
}

class _SangongAgentTeamPageState extends State<SangongAgentTeamPage> {
  late final _accountSession = AgentSessionSnapshot(SangongScope.read(context));
  bool get _isCurrentSession => mounted && _accountSession.isCurrent;

  bool _direct = false;
  bool _loading = true;
  bool _transferring = false;
  String? _error;
  SangongTeamMembersDto? _data;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _searchedUserID;
  int _searchRequest = 0;
  int _loadRequest = 0;
  Timer? _searchTimer;
  final _userSearch = SangongTeamUserSearch();
  Set<String> _friendMatches = {};

  late final _accountSearch =
      SangongAccountIdentityResolver(isCurrent: () => _isCurrentSession);

  @override
  void dispose() {
    _searchTimer?.cancel();
    _userSearch.close();
    _searchController.dispose();
    _accountSearch.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted || !_isCurrentSession) return;
    final request = ++_loadRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data =
          await SangongScope.read(context).agent.fetchSangongTeamMembers(
                direct: _direct,
              );
      if (!mounted || !_isCurrentSession || request != _loadRequest) return;
      setState(() {
        _data = data;
        _loading = false;
      });
      unawaited(_loadIMNames(data, request));
      if (_searchQuery.isNotEmpty) _search(_searchQuery);
    } catch (error) {
      if (!mounted || !_isCurrentSession || request != _loadRequest) return;
      setState(() {
        _error = DioErrorMessage.forApp(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadIMNames(SangongTeamMembersDto data, int request) async {
    try {
      await _userSearch.load(data.members.map((m) => m.imUserId).toSet(),
          () => _isCurrentSession && request == _loadRequest);
      if (_isCurrentSession && request == _loadRequest) setState(() {});
    } catch (_) {
      // Business names and the independent friend/remark query remain usable.
    }
  }

  String _amount(num value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  Future<void> _transfer(SangongTeamMemberDto member) async {
    if (!mounted || !_isCurrentSession || _transferring) return;
    setState(() => _transferring = true);
    try {
      final agent = _data?.agent;
      final available = agent == null ? null : _amount(agent.transferAvailable);
      final amountText = await AppDialog.prompt(
        context: context,
        title: AppCopy.text('划转积分'),
        message: AppCopy.format('将自己的积分划转给 {#0}{#1}', [
          sangongDisplayName(member.nickname, member.imUserId),
          available == null ? '' : AppCopy.format('\n可划转约 {#0}', [available])
        ]),
        placeholder: AppCopy.text('请输入划转数量'),
        cancelText: '取消',
        confirmText: '下一步',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      );
      if (amountText == null || !mounted || !_isCurrentSession) return;
      final amount = num.tryParse(amountText.trim());
      if (amount == null || !amount.isFinite || amount <= 0) {
        ToastUtils.toast(AppCopy.text('请输入大于 0 的有效数量'), context: context);
        return;
      }
      final confirmed = await AppDialog.confirm(
        context: context,
        title: AppCopy.text('确认划转'),
        message: AppCopy.format('确认划转 {#0} 积分给该下级吗？', [_amount(amount)]),
        cancelText: '取消',
        confirmText: AppCopy.text('确认划转'),
      );
      if (!confirmed || !mounted || !_isCurrentSession) return;
      final result = await SangongScope.read(context).agent.transferToChild(
            toImUserId: member.imUserId,
            amount: amount,
          );
      if (!mounted || !_isCurrentSession) return;
      final fromBalance = result['fromBalance'];
      final maxNegative = result['maxNegative'];
      final current = _data;
      if (current?.agent != null &&
          (fromBalance != null || maxNegative != null)) {
        setState(() {
          _data = SangongTeamMembersDto(
            tenantId: current!.tenantId,
            userId: current.userId,
            direct: current.direct,
            aggregation: current.aggregation,
            sessionId: current.sessionId,
            batchNo: current.batchNo,
            businessDate: current.businessDate,
            sessionStatus: current.sessionStatus,
            agent: current.agent!.copyWith(
              balance: fromBalance == null
                  ? null
                  : (fromBalance is num
                      ? fromBalance.toDouble()
                      : num.tryParse(fromBalance.toString())?.toDouble()),
              maxNegative: maxNegative == null
                  ? null
                  : (maxNegative is num
                      ? maxNegative.toDouble()
                      : num.tryParse(maxNegative.toString())?.toDouble()),
            ),
            members: current.members,
          );
        });
      }
      ToastUtils.toast(
        AppCopy.format('划转成功{#0}', [
          result['referenceId'] == null
              ? ''
              : AppCopy.format('，流水号 {#0}', [result['referenceId']])
        ]),
        context: context,
      );
      await _load();
    } catch (error) {
      if (mounted && _isCurrentSession) {
        ToastUtils.toast(DioErrorMessage.forApp(error), context: context);
      }
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  void _search(String value) {
    final request = ++_searchRequest;
    _searchTimer?.cancel();
    _accountSearch.cancel();
    setState(() {
      _searchQuery = value;
      _searchedUserID = null;
      _friendMatches = {};
    });
    if (value.trim().isEmpty) return;
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (!_isCurrentSession || request != _searchRequest) return;
      unawaited(_searchIM(value, request));
      if (normalizePublicAccountSearch(value) != null) {
        unawaited(_searchAccount(value, request));
      }
    });
  }

  Future<void> _searchIM(String value, int request) async {
    try {
      final ids = await _userSearch.searchFriends(
          value, (_data?.members ?? []).map((m) => m.imUserId).toSet());
      if (mounted && _isCurrentSession && request == _searchRequest) {
        setState(() => _friendMatches = ids);
      }
    } catch (error) {
      if (mounted && _isCurrentSession && request == _searchRequest) {
        ToastUtils.toast(AppCopy.text('OpenIM 昵称/备注查询失败，请重试'),
            context: context);
      }
    }
  }

  Future<void> _searchAccount(String value, int request) async {
    try {
      final id =
          await _accountSearch.resolve(value, allowInternalUserId: false);
      if (mounted && _isCurrentSession && request == _searchRequest) {
        setState(() => _searchedUserID = id);
      }
    } catch (error) {
      if (mounted && _isCurrentSession && request == _searchRequest) {
        ToastUtils.toast(DioErrorMessage.forApp(error), context: context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final query = _searchQuery.trim().toLowerCase();
    final members = (data?.members ?? const <SangongTeamMemberDto>[])
        .where(
          (member) =>
              query.isEmpty ||
              member.imUserId == _searchedUserID ||
              _friendMatches.contains(member.imUserId) ||
              _userSearch.matches(member.imUserId, query) ||
              member.nickname.toLowerCase().contains(query) ||
              (SangongIdentityScope.read(context)
                          .peek(member.imUserId)
                          ?.account ??
                      '')
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return SangongAgentAuthorizedView(
      runtime: _accountSession.runtime,
      session: _accountSession,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          leading: const AppBackButton(),
          title: Text(AppCopy.text('查询下级')),
          actions: [
            if (SangongScope.read(context).canViewRebateHistory)
              TextButton(
                onPressed: () {
                  if (_isCurrentSession) {
                    SangongAgentTransfersPage.open(context);
                  }
                },
                child: Text(AppCopy.text('划转记录')),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: false, label: Text(AppCopy.text('全部下级'))),
                  ButtonSegment(value: true, label: Text(AppCopy.text('直属下级'))),
                ],
                selected: {_direct},
                onSelectionChanged: (value) {
                  final direct = value.first;
                  if (direct == _direct) return;
                  setState(() => _direct = direct);
                  _load();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: AppCopy.text('搜索昵称、备注、公开账号或用户ID'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: AppCopy.text('清空搜索'),
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _search('');
                          },
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (data != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.batchNo.isNotEmpty
                            ? '${data.businessDate} · 批次 ${data.batchNo}'
                            : data.businessDate.isEmpty
                                ? '批次 ID ${data.sessionId}'
                                : '${data.businessDate} · 批次 ID ${data.sessionId}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      query.isEmpty
                          ? '共 ${data.members.length} 人'
                          : '找到 ${members.length} 人 / 共 ${data.members.length} 人',
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildBody(members)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<SangongTeamMemberDto> members) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(AppCopy.text('重试'))),
          ],
        ),
      );
    }
    if (members.isEmpty) {
      return Center(
        child: Text(_searchQuery.trim().isEmpty
            ? AppCopy.text('暂无下级')
            : AppCopy.text('未找到匹配的下级')),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: members.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
        itemBuilder: (context, index) => _memberTile(members[index]),
      ),
    );
  }

  Widget _memberTile(SangongTeamMemberDto member) {
    final name = member.nickname.trim().isEmpty
        ? AppCopy.text('用户')
        : member.nickname.trim();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: SangongIMAvatar(
          userID: member.imUserId, nickname: member.nickname, size: 52),
      title: SangongUserName(
        userID: member.imUserId,
        nickname: name,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SangongPublicAccount(
              userID: member.imUserId,
              style: Theme.of(context).textTheme.bodySmall),
          Text(AppCopy.format('第 {#0} 级  ·  余额 {#1}  ·  未返水 {#2}', [
            member.levelNo,
            _amount(member.balance),
            _amount(member.pendingRebate)
          ])),
          Text(AppCopy.format('闲流水 {#0}  ·  庄流水 {#1}', [
            _amount(member.playerTurnover),
            _amount(member.bankerTurnover)
          ])),
        ],
      ),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: AppCopy.text('划转积分'),
          icon: const Icon(Icons.swap_horiz_rounded),
          onPressed: _transferring || member.imUserId.trim().isEmpty
              ? null
              : () => _transfer(member),
        ),
        const Icon(Icons.chevron_right_rounded),
      ]),
      onTap: () {
        if (!_isCurrentSession) return;
        SangongAgentMemberDetailPage.open(context, member);
      },
    );
    /*
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _metricSection('当前批次统计', [
                ('总流水', member.batchTotalTurnover),
                ('玩家流水', member.playerTurnover),
                ('庄家流水', member.bankerTurnover),
                ('上分', member.batchUp),
                ('下分', member.batchDown),
                ('盈亏', member.batchProfitLoss),
                ('当前已返水', member.batchRebate),
              ]),
              const SizedBox(height: 14),
              Divider(height: 1, color: colorScheme.outlineVariant),
              const SizedBox(height: 14),
              _metricSection('今日', [
                ('上分', member.todayUp),
                ('下分', member.todayDown),
                ('盈亏', member.todayProfitLoss),
              ]),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: member.imUserId.trim().isEmpty
                      ? null
                      : () => _transfer(member),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('划转积分'),
                ),
              ),
            ],
          ),
        ),
      ],
    );*/
  }
}
