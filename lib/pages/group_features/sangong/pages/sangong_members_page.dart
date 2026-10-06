// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_my_config.dart';
import 'package:openim/pages/group_features/sangong/support/settings_exports.dart';
import '../../../contacts/search/contact_search_source.dart';
import '../services/account_identity/sangong_account_identity_resolver.dart';
import '../services/authorization/sangong_operation_scope.dart';

/// 三公成员管理：群主添加帮工（走 `/admin/my-config/members`，不拼群 ID）。
class SangongMembersPage extends StatefulWidget {
  const SangongMembersPage({super.key, this.accountSearchSource});

  final ContactSearchSource? accountSearchSource;

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      SangongPageRoute(
        context: context,
        settings: const RouteSettings(name: 'sangong_members'),
        builder: (_) => const SangongMembersPage(),
      ),
    );
  }

  /// 配置保存成功后替换当前页，直接进入加帮工。
  static Future<void> openReplace(BuildContext context) {
    return Navigator.of(context).pushReplacement(
      SangongPageRoute(
        context: context,
        settings: const RouteSettings(name: 'sangong_members'),
        builder: (_) => const SangongMembersPage(),
      ),
    );
  }

  @override
  State<SangongMembersPage> createState() => _SangongMembersPageState();
}

class _SangongMembersPageState extends State<SangongMembersPage> {
  bool _loading = true;
  bool _busy = false;
  String? _errorMessage;
  List<SangongTenantAccessMember> _members = const [];
  late final SangongRuntime _runtime;
  late final SangongAccountIdentityResolver _identity;
  late final SangongOperationScope _pageScope;
  bool _scopeInvalid = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _runtime = SangongScope.read(context);
    _pageScope = _captureScope();
    _identity = SangongAccountIdentityResolver(
      isCurrent: () => _matches(_pageScope) && _runtime.canManageMembers,
      scopeToken: () => _captureScope().token,
      source: widget.accountSearchSource,
    );
    _runtime.addListener(_onRuntimeChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _loadGeneration++;
    _runtime.removeListener(_onRuntimeChanged);
    _identity.close();
    super.dispose();
  }

  SangongOperationScope _captureScope() => SangongOperationScope.capture(
      _runtime.featureContext, _runtime.http.tenantId);

  bool _matches(SangongOperationScope scope) =>
      mounted &&
      !_scopeInvalid &&
      _runtime.isCurrent &&
      scope.matches(_runtime.featureContext, _runtime.http.tenantId);

  void _onRuntimeChanged() {
    if (!mounted ||
        (_matches(_pageScope) && (_loading || _runtime.canManageMembers))) {
      return;
    }
    _scopeInvalid = true;
    _loadGeneration++;
    _identity.cancel();
    setState(() {
      _members = const [];
      _busy = false;
      _loading = false;
      _errorMessage = null;
    });
  }

  Future<void> _load() async {
    final scope = _captureScope();
    final generation = ++_loadGeneration;
    if (!_matches(scope)) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await _runtime.config.refreshFromNetwork();
      if (!mounted || !_matches(scope) || generation != _loadGeneration) return;
      if (!_runtime.canManageMembers) {
        setState(() => _loading = false);
        _onRuntimeChanged();
        return;
      }
      final members =
          await SangongScope.read(context).admin.fetchMyConfigMembers();
      if (!_matches(scope) || generation != _loadGeneration) return;
      int rank(SangongTenantAccessMember m) {
        if (m.isOwner) return 0;
        if (m.isAdmin) return 1;
        return 2;
      }

      members.sort((a, b) {
        final byRole = rank(a).compareTo(rank(b));
        if (byRole != 0) return byRole;
        return a.imUserId.compareTo(b.imUserId);
      });
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (error) {
      if (!_matches(scope) || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _errorMessage = DioErrorMessage.forApp(error);
      });
    }
  }

  String _roleLabel(AppI18n i18n, SangongTenantAccessMember member) {
    if (member.isOwner) {
      return i18n.t(zhHans: '群主', zhHant: '群主', en: 'Owner');
    }
    if (member.isAdmin) {
      return i18n.t(zhHans: '帮工', zhHant: '幫工', en: 'Helper');
    }
    return member.role;
  }

  Future<void> _showAddHelperDialog() async {
    final scope = _captureScope();
    if (_busy || !_matches(scope) || !_runtime.canManageMembers) return;
    final i18n = AppI18n.of(context);
    final imUserId = await AppDialog.prompt(
      context: context,
      title: i18n.t(zhHans: '添加帮工', zhHant: '添加幫工', en: 'Add helper'),
      message: i18n.t(
        zhHans: '对方须为特权用户。添加后可在本下注群操作台上下分、跑局，不能改配置。',
        zhHant: '對方須為特權用戶。添加後可在本下注群操作台上下分、跑局，不能改配置。',
        en: 'Helper must be privileged. They can operate but not edit config.',
      ),
      placeholder: i18n.t(
        zhHans: '公开账号名（可带 @）或用户 ID',
        zhHant: '公開帳號名（可帶 @）或用戶 ID',
        en: 'Public account (optional @) or user ID',
      ),
      cancelText: i18n.t(zhHans: '取消', zhHant: '取消', en: 'Cancel'),
      confirmText: i18n.t(zhHans: '添加', zhHant: '添加', en: 'Add'),
      inputFormatters: [
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
      ],
    );
    if (imUserId == null || !_matches(scope) || !_runtime.canManageMembers) {
      return;
    }
    setState(() => _busy = true);
    try {
      final resolved = await _identity.resolve(imUserId);
      if (resolved == null || !_matches(scope) || !_runtime.canManageMembers) {
        return;
      }
      await _runtime.admin.upsertMyConfigMember(
        imUserId: resolved,
        role: 'admin',
      );
      if (!_matches(scope) || !_runtime.canManageMembers) return;
      ToastUtils.toast(
        i18n.t(zhHans: '已添加帮工', zhHant: '已添加幫工', en: 'Helper added'),
      );
      await _load();
    } catch (error) {
      if (!_matches(scope)) return;
      ToastUtils.toast(DioErrorMessage.forApp(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _removeMember(SangongTenantAccessMember member) async {
    final scope = _captureScope();
    if (_busy ||
        member.imUserId.isEmpty ||
        !_matches(scope) ||
        !_runtime.canManageMembers) {
      return;
    }
    final i18n = AppI18n.of(context);
    if (member.isOwner) {
      ToastUtils.toast(
        i18n.t(
          zhHans: '不能直接移除群主',
          zhHant: '不能直接移除群主',
          en: 'Cannot remove owner',
        ),
      );
      return;
    }
    final ok = await AppDialog.confirm(
      context: context,
      title: i18n.t(zhHans: '移除帮工', zhHant: '移除幫工', en: 'Remove helper'),
      message: i18n.t(
        zhHans: '确定移除 ${member.imUserId}？移除后对方将看不到本群三公入口。',
        zhHant: '確定移除 ${member.imUserId}？移除後對方將看不到本群三公入口。',
        en: 'Remove ${member.imUserId}? They will lose access.',
      ),
      confirmText: i18n.t(zhHans: '移除', zhHant: '移除', en: 'Remove'),
      destructive: true,
    );
    if (!mounted || !ok || !_matches(scope) || !_runtime.canManageMembers) {
      return;
    }
    setState(() => _busy = true);
    try {
      await SangongScope.read(context).admin.removeMyConfigMember(
            imUserId: member.imUserId,
          );
      if (!_matches(scope) || !_runtime.canManageMembers) return;
      ToastUtils.toast(
        i18n.t(zhHans: '已移除', zhHant: '已移除', en: 'Removed'),
      );
      await _load();
    } catch (error) {
      if (!_matches(scope)) return;
      ToastUtils.toast(DioErrorMessage.forApp(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_matches(_pageScope) || (!_loading && !_runtime.canManageMembers)) {
      return const Scaffold(
        body: Center(child: Text('当前游戏权限已变化，请重新进入')),
      );
    }
    final i18n = AppI18n.of(context);
    final dark = settingsIsDark(context);
    final title = i18n.t(
      zhHans: '成员管理',
      zhHant: '成員管理',
      en: 'Members',
    );

    if (_loading) {
      return SettingsScaffold(
        title: title,
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      );
    }

    if (_errorMessage != null && _members.isEmpty) {
      return SettingsScaffold(
        title: title,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: AppColors.subText(dark: dark)),
            ),
          ),
          SettingsPrimaryButton(
            text: i18n.t(zhHans: '重试', zhHant: '重試', en: 'Retry'),
            onPressed: _load,
          ),
        ],
      );
    }

    return SettingsScaffold(
      title: title,
      bottom: SettingsPrimaryButton(
        text: _busy
            ? i18n.t(zhHans: '处理中...', zhHant: '處理中...', en: 'Working...')
            : i18n.t(zhHans: '添加帮工', zhHant: '添加幫工', en: 'Add helper'),
        onPressed: _busy ? () {} : _showAddHelperDialog,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            i18n.t(
              zhHans: '帮工必须同样是特权用户。添加后进入本下注群即可使用操作台。',
              zhHant: '幫工必須同樣是特權用戶。添加後進入本下注群即可使用操作台。',
              en: 'Helpers must also be privileged users.',
            ),
            style: TextStyle(
              color: AppColors.subText(dark: dark),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
        if (_members.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Text(
              i18n.t(
                zhHans: '暂无成员',
                zhHant: '暫無成員',
                en: 'No members yet',
              ),
              style: TextStyle(color: AppColors.subText(dark: dark)),
            ),
          )
        else
          SettingsGroup(
            children: [
              for (var i = 0; i < _members.length; i++)
                SettingsCell(
                  title: _members[i].imUserId,
                  value: _roleLabel(i18n, _members[i]),
                  showArrow: !_members[i].isOwner,
                  showDivider: i < _members.length - 1,
                  onTap: _members[i].isOwner
                      ? null
                      : () => unawaited(_removeMember(_members[i])),
                ),
            ],
          ),
      ],
    );
  }
}
