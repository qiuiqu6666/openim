import '../identity/widgets/sangong_identity_view.dart';
// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'dart:async';

import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_user_detail_page.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/support/settings_exports.dart';
import 'package:openim_common/openim_common.dart';
import '../../../contacts/search/contact_search_source.dart';
import '../services/account_identity/sangong_account_identity_resolver.dart';
import '../services/authorization/sangong_operation_scope.dart';
import '../support/sangong_ui.dart' show DioErrorMessage;

class SangongAllUsersPage extends StatefulWidget {
  const SangongAllUsersPage({super.key, this.accountSearchSource});
  final ContactSearchSource? accountSearchSource;
  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        SangongPageRoute(
            context: context, builder: (_) => const SangongAllUsersPage()),
      );
  @override
  State<SangongAllUsersPage> createState() => _SangongAllUsersPageState();
}

class _SangongAllUsersPageState extends State<SangongAllUsersPage> {
  static const int _pageSize = 50;

  final _searchController = TextEditingController();
  final List<SangongAdminUserReport> _users = [];
  String _query = '';
  String _lastAutoFillQuery = '';
  bool _pointsDescending = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;
  int _page = 0;
  int _totalPages = 0;
  int _searchGeneration = 0;
  int _listGeneration = 0;
  bool _scopeInvalid = false;
  Timer? _searchTimer;
  bool _accountLoading = false;
  String? _accountError;
  SangongAdminUserReport? _accountUser;
  late final SangongRuntime _runtime;
  late final SangongAccountIdentityResolver _identity;
  late final SangongOperationScope _pageScope;

  bool get _hasMore => _page < _totalPages;
  bool get _isAccountQuery =>
      _query.startsWith('@') || normalizePublicAccountSearch(_query) != null;

  @override
  void initState() {
    super.initState();
    _runtime = SangongScope.read(context);
    _pageScope = _captureScope();
    _identity = SangongAccountIdentityResolver(
      isCurrent: () => mounted && _runtime.canManage,
      scopeToken: () => _captureScope().token,
      source: widget.accountSearchSource,
    );
    _runtime.addListener(_onRuntimeChanged);
    _loadFirst();
  }

  @override
  void dispose() {
    _searchGeneration++;
    _searchTimer?.cancel();
    _runtime.removeListener(_onRuntimeChanged);
    _identity.close();
    _searchController.dispose();
    super.dispose();
  }

  void _onRuntimeChanged() {
    if (!mounted || (_runtime.canManage && _matches(_pageScope))) return;
    _scopeInvalid = true;
    _searchGeneration++;
    _listGeneration++;
    _searchTimer?.cancel();
    _identity.cancel();
    setState(() {
      _users.clear();
      _accountUser = null;
      _accountError = null;
      _accountLoading = false;
      _loading = false;
      _loadingMore = false;
      _failed = true;
    });
  }

  SangongOperationScope _captureScope() => SangongOperationScope.capture(
      _runtime.featureContext, _runtime.http.tenantId);

  bool _matches(SangongOperationScope scope) =>
      mounted &&
      !_scopeInvalid &&
      _runtime.canManage &&
      scope.matches(_runtime.featureContext, _runtime.http.tenantId);

  Future<void> _loadFirst() async {
    final scope = _captureScope();
    final generation = ++_listGeneration;
    if (!_matches(scope)) return;
    setState(() {
      _loading = true;
      _failed = false;
      _loadingMore = false;
      _users.clear();
      _page = 0;
      _totalPages = 0;
    });
    try {
      final result = await SangongScope.read(context).admin.fetchUserReports(
            page: 1,
            pageSize: _pageSize,
          );
      if (!_matches(scope) || generation != _listGeneration) {
        return;
      }
      setState(() {
        _users.addAll(result.users);
        _page = result.page;
        _totalPages = result.totalPages;
        _loading = false;
      });
      _fillIfSearching();
    } catch (_) {
      if (!_matches(scope) || generation != _listGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    final scope = _captureScope();
    final generation = _listGeneration;
    if (!_matches(scope) || _loading || _loadingMore || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final result = await SangongScope.read(context).admin.fetchUserReports(
            page: _page + 1,
            pageSize: _pageSize,
          );
      if (!_matches(scope) || generation != _listGeneration) {
        return;
      }
      setState(() {
        _users.addAll(result.users);
        _page = result.page;
        _totalPages = result.totalPages;
        _loadingMore = false;
      });
      _fillIfSearching();
    } catch (_) {
      if (!_matches(scope) || generation != _listGeneration) {
        return;
      }
      setState(() => _loadingMore = false);
    }
  }

  void _fillIfSearching() {
    if (_isAccountQuery ||
        _query.isEmpty ||
        _query == _lastAutoFillQuery ||
        !_hasMore ||
        _loadingMore) {
      return;
    }
    _lastAutoFillQuery = _query;
    final visible = _visibleUsers();
    if (visible.length < 12) {
      _loadMore();
    }
  }

  List<SangongAdminUserReport> _visibleUsers() {
    if (_isAccountQuery) {
      return _accountUser == null ? [] : [_accountUser!];
    }
    final users = _users
        .where((user) =>
            _query.isEmpty ||
            user.nickname.toLowerCase().contains(_query.toLowerCase()) ||
            (SangongIdentityScope.read(context).peek(user.imUserId)?.account ??
                    '')
                .toLowerCase()
                .contains(_query.toLowerCase()))
        .toList();
    users.sort((a, b) => _pointsDescending
        ? b.balance.compareTo(a.balance)
        : a.balance.compareTo(b.balance));
    return users;
  }

  void _onQueryChanged(String value) {
    if (!_matches(_pageScope)) return;
    _searchTimer?.cancel();
    _identity.cancel();
    final generation = ++_searchGeneration;
    setState(() {
      _query = value.trim();
      _accountUser = null;
      _accountError = null;
      _accountLoading = false;
    });
    if (_isAccountQuery) {
      if (normalizePublicAccountSearch(_query) == null) {
        setState(() => _accountError = '请输入完整的 10 位公开账号名');
        return;
      }
      setState(() => _accountLoading = true);
      _searchTimer = Timer(const Duration(milliseconds: 300),
          () => unawaited(_searchAccount(_query, generation)));
    } else {
      _fillIfSearching();
    }
  }

  bool _acceptsSearch(int generation) =>
      _matches(_pageScope) && generation == _searchGeneration;

  Future<void> _searchAccount(String query, int generation) async {
    if (!_acceptsSearch(generation)) return;
    try {
      final userId = await _identity.resolve(query, allowInternalUserId: false);
      if (userId == null || !_acceptsSearch(generation)) return;
      final detail = await _runtime.admin.fetchUserDetail(userId);
      if (!_acceptsSearch(generation)) return;
      final raw = detail['user'];
      if (raw is! Map) throw const FormatException('Missing tenant user');
      final user = Map<String, dynamic>.from(raw);
      if ('${user['imUserId'] ?? user['im_user_id'] ?? ''}'.trim() != userId ||
          int.tryParse('${user['userId'] ?? user['user_id'] ?? user['id']}') ==
              null ||
          int.tryParse('${user['balance']}') == null) {
        throw const FormatException('Invalid tenant user');
      }
      final report = SangongAdminUserReport.fromJson({
        ...user,
        'userId': user['userId'] ?? user['user_id'] ?? user['id'],
      });
      if (report.userId == null || report.userId! <= 0) {
        throw const FormatException('Invalid tenant user ID');
      }
      setState(() {
        _accountUser = report;
        _accountLoading = false;
      });
    } catch (error) {
      if (!_acceptsSearch(generation)) return;
      setState(() {
        _accountLoading = false;
        _accountError = DioErrorMessage.forApp(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_matches(_pageScope)) {
      return Scaffold(
        appBar: AppBar(title: const Text('全部用户'), centerTitle: true),
        body: const Center(child: Text('当前游戏权限已变化，请重新进入')),
      );
    }
    final users = _visibleUsers();
    final colors = Theme.of(context).colorScheme;
    final header = Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 23),
                hintText: '搜索公开账号或已加载的昵称',
                isDense: true,
                filled: true,
                fillColor: colors.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 15,
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(28)),
                  borderSide: BorderSide(color: colors.primary, width: 1.2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              tooltip: _pointsDescending ? '积分从高到低' : '积分从低到高',
              onPressed: () =>
                  setState(() => _pointsDescending = !_pointsDescending),
              icon: Icon(
                _pointsDescending
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('全部用户'), centerTitle: true),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: 1 +
            (_isAccountQuery
                ? (_accountLoading || _accountError != null ? 1 : users.length)
                : (_loading || _failed
                    ? 1
                    : users.length + (_hasMore ? 1 : 0))),
        itemBuilder: (context, index) {
          if (index == 0) return header;
          if (_isAccountQuery) {
            if (_accountLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_accountError != null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(_accountError!),
                  if (normalizePublicAccountSearch(_query) != null)
                    TextButton(
                      onPressed: () => _onQueryChanged(_query),
                      child: const Text('重试'),
                    ),
                ]),
              );
            }
            return _userCell(context, users[index - 1]);
          }
          if (_loading) return const Center(child: CircularProgressIndicator());
          if (_failed) {
            return TextButton(
                onPressed: _loadFirst, child: const Text('加载失败，点击重试'));
          }
          if (index == users.length + 1) {
            return TextButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(_loadingMore ? '加载中…' : '加载更多用户'));
          }
          return _userCell(context, users[index - 1]);
        },
      ),
    );
  }

  Widget _userCell(BuildContext context, SangongAdminUserReport user) {
    final colors = Theme.of(context).colorScheme;
    final nickname = user.nickname.trim();
    final id = user.imUserId.trim();
    return SettingsCell(
      onTap: id.isEmpty
          ? null
          : () => _matches(_pageScope)
              ? Navigator.of(context).push(
                  SangongPageRoute(
                    context: context,
                    builder: (_) => SangongUserDetailPage(user: user),
                  ),
                )
              : null,
      leading: SangongIMAvatar(userID: id, nickname: nickname),
      title: '',
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            nickname.isNotEmpty ? nickname : '未设置昵称',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SangongPublicAccount(
              userID: id, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(
            '下级 ${user.childrenCount}  ·  返水 ${user.rebatePer10000}',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
      trailing: Text(
        '积分 ${user.balance}',
        style: TextStyle(
          color: colors.error,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      showArrow: false,
      showDivider: true,
    );
  }
}
