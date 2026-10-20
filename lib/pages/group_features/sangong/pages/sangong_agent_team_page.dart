import 'package:flutter/services.dart';
import '../../mark_six/widgets/mark_six_style.dart';
import '../../widgets/group_feature_tokens.dart';
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

  String _sortBy = 'balance';
  bool _sortDescending = true;
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
                direct: false,
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
    final tokens = GroupFeatureTokens.of(context);
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
    members.sort((a, b) {
      final left = _sortBy == 'balance'
          ? a.balance
          : _sortBy == 'level'
              ? a.levelNo
              : a.playerTurnover + a.bankerTurnover;
      final right = _sortBy == 'balance'
          ? b.balance
          : _sortBy == 'level'
              ? b.levelNo
              : b.playerTurnover + b.bankerTurnover;
      final order =
          _sortDescending ? right.compareTo(left) : left.compareTo(right);
      return order == 0 ? a.imUserId.compareTo(b.imUserId) : order;
    });
    return SangongAgentAuthorizedView(
      runtime: _accountSession.runtime,
      session: _accountSession,
      child: Scaffold(
        backgroundColor: tokens.background,
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
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                    child: ColoredBox(
                        color: tokens.surface,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                              child: TextField(
                                controller: _searchController,
                                textInputAction: TextInputAction.search,
                                onChanged: _search,
                                decoration: InputDecoration(
                                  hintText: AppCopy.text('搜索昵称、备注或账号'),
                                  filled: true,
                                  fillColor: tokens.background,
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
                                    borderRadius: BorderRadius.circular(
                                        MarkSixStyle.radius),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(tokens.inset),
                              child: _teamFilterBar(
                                  data, members.length, query.isNotEmpty),
                            ),
                          ],
                        ))),
                _buildBody(members),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _teamFilterBar(
      SangongTeamMembersDto? data, int visible, bool searching) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = GroupFeatureTokens.of(context);
    final total = data?.members.length ?? 0;
    Widget sortButton(String key, String title) {
      final selected = _sortBy == key;
      return ChoiceChip(
        selected: selected,
        showCheckmark: false,
        label: Text(
            '${AppCopy.text(title)}${selected ? (_sortDescending ? ' ↓' : ' ↑') : ''}'),
        tooltip: selected
            ? (_sortDescending ? '从高到低，点击改为从低到高' : '从低到高，点击改为从高到低')
            : key == 'level'
                ? '点击从低到高排序'
                : '点击从高到低排序',
        onSelected: (_) => setState(() {
          if (selected) {
            _sortDescending = !_sortDescending;
          } else {
            _sortBy = key;
            _sortDescending = key != 'level';
          }
        }),
      );
    }

    final count = Text.rich(
        TextSpan(children: [
          TextSpan(text: searching ? '找到 ' : '共 '),
          TextSpan(
              text: '${searching ? visible : total}',
              style: TextStyle(
                  color: colors.primary, fontWeight: FontWeight.w700)),
          TextSpan(text: searching ? ' 人 / 共 $total 人' : ' 人'),
        ]),
        style: theme.textTheme.bodyMedium?.copyWith(color: tokens.text));
    return Wrap(
      spacing: tokens.inset / 2,
      runSpacing: tokens.inset / 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        sortButton('balance', '积分排序'),
        sortButton('turnover', '总流水排序'),
        sortButton('level', '层级排序'),
        count,
      ],
    );
  }

  Widget _buildBody(List<SangongTeamMemberDto> members) {
    if (_loading) {
      return const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: Text(AppCopy.text('重试'))),
              ],
            ),
          ));
    }
    if (members.isEmpty) {
      return SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(_searchQuery.trim().isEmpty
                ? AppCopy.text('暂无下级')
                : AppCopy.text('未找到匹配的下级')),
          ));
    }
    final tokens = GroupFeatureTokens.of(context);
    return SliverPadding(
      padding: EdgeInsets.all(tokens.inset),
      sliver: SliverList.separated(
        itemCount: members.length,
        separatorBuilder: (_, __) => SizedBox(height: tokens.inset / 2),
        itemBuilder: (context, index) => _memberTile(members[index]),
      ),
    );
  }

  Widget _memberTile(SangongTeamMemberDto member) {
    final style = MarkSixStyle.of(context);
    final theme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(_TeamReferenceTokens.radius);
    void detail() {
      if (_isCurrentSession) SangongAgentMemberDetailPage.open(context, member);
    }

    Widget metric(String label, num value, {bool primary = false}) => Expanded(
          child: Semantics(
              container: true,
              excludeSemantics: true,
              label: '${AppCopy.text(label)} ${_amount(value)}',
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_amount(value),
                        style: theme.titleLarge?.copyWith(
                            fontSize: _TeamReferenceTokens.valueSize,
                            fontWeight: FontWeight.w600,
                            color: primary ? style.primary : style.text))),
                const SizedBox(height: _TeamReferenceTokens.smallGap),
                Text(AppCopy.text(label),
                    style: theme.bodySmall?.copyWith(
                        fontSize: _TeamReferenceTokens.labelSize,
                        color: style.secondary)),
              ])),
        );
    Widget divider() => Container(
        width: 1,
        height: _TeamReferenceTokens.dividerHeight,
        color: style.divider);
    final referenceHeight = _TeamReferenceTokens.height *
        (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 3.0);
    // Fixed reference composition scales as a whole; it never changes into a grid.
    return LayoutBuilder(
        builder: (context, constraints) => SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxWidth *
                  _TeamReferenceTokens.height /
                  _TeamReferenceTokens.width,
              child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _TeamReferenceTokens.width,
                    height: referenceHeight,
                    child: Material(
                        color: style.surface,
                        borderRadius: radius,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: detail,
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: _TeamReferenceTokens.inset),
                              child: Row(children: [
                                SangongIMAvatar(
                                    userID: member.imUserId,
                                    nickname: member.nickname,
                                    size: _TeamReferenceTokens.avatar),
                                const SizedBox(width: _TeamReferenceTokens.gap),
                                Expanded(
                                    child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Row(children: [
                                        Expanded(
                                            child: SangongIdentityView(
                                                userID: member.imUserId,
                                                builder: (identity) => Text(
                                                    identity
                                                                ?.nickname
                                                                .trim()
                                                                .isNotEmpty ==
                                                            true
                                                        ? identity!.nickname
                                                        : member.nickname,
                                                    maxLines: 1,
                                                    overflow: TextOverflow
                                                        .ellipsis,
                                                    style: theme.titleLarge?.copyWith(
                                                        fontSize:
                                                            _TeamReferenceTokens
                                                                .nameSize,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: style.text)))),
                                        Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 20, vertical: 10),
                                            decoration: BoxDecoration(
                                                color: style.background,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        _TeamReferenceTokens
                                                            .radius)),
                                            child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .workspace_premium_rounded,
                                                      color: style.primary,
                                                      size: 28),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                      AppCopy.format('第 {#0} 级',
                                                          [member.levelNo]),
                                                      style: theme.bodyMedium
                                                          ?.copyWith(
                                                              fontSize:
                                                                  _TeamReferenceTokens
                                                                      .labelSize,
                                                              color: style
                                                                  .secondary)),
                                                ])),
                                        Icon(Icons.chevron_right_rounded,
                                            color: style.secondary, size: 36),
                                      ]),
                                      SangongIdentityView(
                                          userID: member.imUserId,
                                          builder: (identity) {
                                            final account =
                                                identity?.account ?? '';
                                            return Row(children: [
                                              Flexible(
                                                  child: Text(
                                                      '账号：${account.isEmpty ? AppCopy.text('未获取') : account}',
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                      style: theme.bodyMedium
                                                          ?.copyWith(
                                                              fontSize:
                                                                  _TeamReferenceTokens
                                                                      .labelSize,
                                                              color: style
                                                                  .secondary))),
                                              IconButton(
                                                  tooltip: AppCopy.text('复制账号'),
                                                  icon: const Icon(
                                                      Icons.copy_rounded,
                                                      size: 26),
                                                  color: style.secondary,
                                                  onPressed: account.isEmpty
                                                      ? null
                                                      : () async {
                                                          await Clipboard.setData(
                                                              ClipboardData(
                                                                  text:
                                                                      account));
                                                          if (context.mounted &&
                                                              _isCurrentSession) {
                                                            ToastUtils.toast(
                                                                AppCopy.text(
                                                                    '账号已复制'),
                                                                context:
                                                                    context);
                                                          }
                                                        }),
                                            ]);
                                          }),
                                      const SizedBox(
                                          height: _TeamReferenceTokens.gap),
                                      Row(children: [
                                        metric('总积分', member.balance,
                                            primary: true),
                                        divider(),
                                        metric('未返水', member.pendingRebate),
                                        divider(),
                                        metric('闲流水', member.playerTurnover),
                                        divider(),
                                        metric('庄流水', member.bankerTurnover),
                                        divider(),
                                        const SizedBox(width: 20),
                                        IconButton(
                                            tooltip: AppCopy.text('划转积分'),
                                            style: IconButton.styleFrom(
                                                foregroundColor: style.primary,
                                                backgroundColor: style.primary
                                                    .withValues(alpha: .06),
                                                minimumSize:
                                                    const Size(164, 64),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 24)),
                                            icon: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                      Icons.swap_horiz_rounded,
                                                      size: 36),
                                                  const SizedBox(width: 12),
                                                  Text(AppCopy.text('划转'),
                                                      style: const TextStyle(
                                                          fontSize: 28)),
                                                ]),
                                            onPressed: _transferring ||
                                                    member.imUserId
                                                        .trim()
                                                        .isEmpty
                                                ? null
                                                : () => _transfer(member)),
                                      ]),
                                    ])),
                              ])),
                        )),
                  )),
            ));
  }
}

abstract final class _TeamReferenceTokens {
  static const width = 960.0;
  static const height = 312.0;
  static const radius = 28.0;
  static const inset = 32.0;
  static const avatar = 128.0;
  static const gap = 32.0;
  static const smallGap = 8.0;
  static const nameSize = 36.0;
  static const valueSize = 32.0;
  static const labelSize = 22.0;
  static const dividerHeight = 40.0;
}
