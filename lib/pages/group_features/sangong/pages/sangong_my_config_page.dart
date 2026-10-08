import '../identity/widgets/sangong_identity_view.dart';
// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_my_config.dart';
import 'package:openim/pages/group_features/sangong/support/settings_exports.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_members_page.dart';
import '../../../contacts/search/contact_search_source.dart';
import '../services/account_identity/sangong_account_identity_resolver.dart';
import '../services/authorization/sangong_operation_scope.dart';
import '../models/binding/sangong_group_tenant_state.dart';
import '../api/binding/sangong_group_tenant_api.dart';
import '../api/diagnostics/sangong_api_debug_log.dart';
import '../agents/pages/sangong_agent_groups_page.dart';

/// 三公「我的配置」：绑定下注群 / 结账群 / 机器人（仅群主可改）。
class SangongMyConfigPage extends StatefulWidget {
  const SangongMyConfigPage({
    super.key,
    this.initialGameGroupId = '',
    this.onSaved,
    this.accountSearchSource,
    this.groupScoped = false,
  });

  /// 从当前聊天进入时预填下注群。
  final String initialGameGroupId;
  final ValueChanged<SangongMyConfig>? onSaved;
  final ContactSearchSource? accountSearchSource;
  final bool groupScoped;

  static Future<SangongMyConfig?> open(
    BuildContext context, {
    String initialGameGroupId = '',
    ValueChanged<SangongMyConfig>? onSaved,
    bool groupScoped = false,
  }) {
    return Navigator.of(context).push<SangongMyConfig>(
      SangongPageRoute(
        context: context,
        settings: const RouteSettings(name: 'sangong_my_config'),
        builder: (_) => SangongMyConfigPage(
          initialGameGroupId: initialGameGroupId,
          onSaved: onSaved,
          groupScoped: groupScoped,
        ),
      ),
    );
  }

  @override
  State<SangongMyConfigPage> createState() => _SangongMyConfigPageState();
}

class _SangongMyConfigPageState extends State<SangongMyConfigPage> {
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;
  SangongMyConfig _config = const SangongMyConfig();
  late final SangongRuntime _runtime;
  late final SangongAccountIdentityResolver _identity;
  late SangongOperationScope _pageScope;
  bool _scopeInvalid = false;
  bool _pageActive = true;
  bool _committingSavedConfig = false;
  int _loadGeneration = 0;

  late final TextEditingController _nameController;
  late final TextEditingController _gameGroupController;
  late final TextEditingController _statsGroupController;
  late final TextEditingController _ledgerGroupController;
  late final TextEditingController _botController;

  @override
  void initState() {
    super.initState();
    _runtime = SangongScope.read(context);
    _pageScope = _captureScope();
    _identity = SangongAccountIdentityResolver(
      isCurrent: () => mounted && _runtime.isCurrent && _runtime.canConfigure,
      scopeToken: () => _captureScope().token,
      source: widget.accountSearchSource,
    );
    _nameController = TextEditingController();
    _gameGroupController = TextEditingController(
      text: ChatIdFormat.normalizeGroupId(widget.initialGameGroupId),
    );
    _statsGroupController = TextEditingController();
    _ledgerGroupController = TextEditingController();
    _botController = TextEditingController();
    _runtime.addListener(_onRuntimeChanged);
    unawaited(_load());
  }

  @override
  void deactivate() {
    _pageActive = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _pageActive = true;
    _onRuntimeChanged();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _runtime.removeListener(_onRuntimeChanged);
    _identity.close();
    _nameController.dispose();
    _gameGroupController.dispose();
    _statsGroupController.dispose();
    _ledgerGroupController.dispose();
    _botController.dispose();
    super.dispose();
  }

  SangongOperationScope _captureScope() => SangongOperationScope.capture(
      _runtime.featureContext, _runtime.http.tenantId);

  bool _matches(SangongOperationScope scope) =>
      mounted &&
      _pageActive &&
      !_scopeInvalid &&
      _runtime.isCurrent &&
      scope.matches(_runtime.featureContext, _runtime.http.tenantId);

  bool _initialBindingConfirmed(SangongOperationScope scope) {
    final config = _runtime.config.config;
    return mounted &&
        _pageActive &&
        _runtime.isCurrent &&
        scope.tenantId == null &&
        scope.sameContext(_runtime.featureContext) &&
        config.configured &&
        config.imGroupGameId == scope.groupId &&
        config.tenantId == _runtime.http.tenantId;
  }

  void _onRuntimeChanged() {
    if (!mounted || !_pageActive || _scopeInvalid) return;
    final mayView = _runtime.canConfigure ||
        (widget.groupScoped && _runtime.isCurrent && _runtime.isPrivileged);
    if (mayView && _matches(_pageScope)) return;
    if (_runtime.canConfigure &&
        (_committingSavedConfig ||
            (_loading && _initialBindingConfirmed(_pageScope)))) {
      _pageScope = _captureScope();
      return;
    }
    _scopeInvalid = true;
    _loadGeneration++;
    _identity.cancel();
    _nameController.clear();
    _gameGroupController.clear();
    _statsGroupController.clear();
    _ledgerGroupController.clear();
    _botController.clear();
    setState(() {
      _config = const SangongMyConfig();
      _errorMessage = null;
      _loading = false;
      _saving = false;
    });
  }

  Future<void> _load() async {
    final scope = _captureScope();
    final generation = ++_loadGeneration;
    if (!_matches(scope)) return;
    if (widget.groupScoped) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
      try {
        final registration = await _runtime.groupTenant.refresh();
        if (!_matches(scope) || generation != _loadGeneration) return;
        final config = registration.config;
        if (registration.status != SangongGroupTenantStatus.notFound &&
            config == null) {
          throw StateError(registration.message);
        }
        _applyConfig(config ?? const SangongMyConfig());
        setState(() {
          _config = config ?? const SangongMyConfig();
          _loading = false;
        });
      } catch (error) {
        if (!_matches(scope) || generation != _loadGeneration) return;
        setState(() {
          _loading = false;
          _errorMessage = DioErrorMessage.forApp(error);
        });
      }
      return;
    }
    final cached = SangongScope.read(context).config.hasCachedConfig
        ? SangongScope.read(context).config.config
        : null;
    if (cached != null) {
      _applyConfig(cached);
      setState(() {
        _config = cached;
        _loading = false;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final config =
          await SangongScope.read(context).config.refreshFromNetwork();
      if ((!_matches(scope) && !_initialBindingConfirmed(scope)) ||
          generation != _loadGeneration) {
        return;
      }
      _applyConfig(config);
      setState(() {
        _config = config;
        _loading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!_matches(scope) || generation != _loadGeneration) return;
      if (cached != null) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = DioErrorMessage.forApp(error);
      });
    }
  }

  void _applyConfig(SangongMyConfig config) {
    if (config.configured) {
      _nameController.text = config.name;
      _gameGroupController.text = config.imGroupGameId;
      _statsGroupController.text = config.imGroupAdminStatsId;
      _ledgerGroupController.text = config.imGroupLedgerId;
      _botController.clear();
      unawaited(_loadBotAccount(config));
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      _nameController.text = '一号厅';
    }
    final preset = ChatIdFormat.normalizeGroupId(widget.initialGameGroupId);
    if (_gameGroupController.text.trim().isEmpty && preset.isNotEmpty) {
      _gameGroupController.text = preset;
    }
  }

  Future<void> _loadBotAccount(SangongMyConfig config) async {
    final scope = _captureScope();
    final identity =
        await SangongIdentityScope.read(context).resolve(config.imBotUserId);
    if (!mounted ||
        !_matches(scope) ||
        _config.imBotUserId != config.imBotUserId ||
        _botController.text.isNotEmpty) {
      return;
    }
    if (identity?.account.isNotEmpty == true) {
      _botController.text = identity!.account;
    }
  }

  bool get _canEdit {
    if (!_matches(_pageScope)) return false;
    if (widget.groupScoped && !_config.configured) {
      return _runtime.canInitialize;
    }
    if (widget.groupScoped) {
      return _runtime.featureContext.capabilities.sangong.canConfigure;
    }
    if (!_config.configured) {
      return SangongScope.read(context).canConfigure;
    }
    return SangongScope.read(context).canConfigure &&
        (_config.canEditConfig || _config.isOwner);
  }

  Future<void> _save() async {
    final scope = _captureScope();
    final wasFirstSetup = !_config.configured;
    if (_saving || !_canEdit) {
      return;
    }
    final i18n = AppI18n.of(context);
    final name = _nameController.text.trim();
    final gameGroup =
        ChatIdFormat.normalizeGroupId(_gameGroupController.text.trim());
    final statsGroup =
        ChatIdFormat.normalizeGroupId(_statsGroupController.text.trim());
    final ledgerGroup =
        ChatIdFormat.normalizeGroupId(_ledgerGroupController.text.trim());
    final bot = _botController.text.trim();

    if (!widget.groupScoped && name.isEmpty) {
      ToastUtils.toast(
        i18n.t(zhHans: '请填写厅名', zhHant: '請填寫廳名', en: 'Enter a name'),
      );
      return;
    }
    if (gameGroup.isEmpty) {
      ToastUtils.toast(
        i18n.t(
          zhHans: '请填写下注群 ID',
          zhHant: '請填寫下注群 ID',
          en: 'Enter game group ID',
        ),
      );
      return;
    }
    if (!widget.groupScoped && statsGroup.isEmpty) {
      ToastUtils.toast(
        i18n.t(
          zhHans: '请填写结账群 ID',
          zhHant: '請填寫結賬群 ID',
          en: 'Enter settle group ID',
        ),
      );
      return;
    }
    if (bot.isEmpty && _config.imBotUserId.isEmpty) {
      ToastUtils.toast(
        i18n.t(
          zhHans: '请填写机器人公开账号名',
          zhHant: '請填寫機器人公開帳號名',
          en: 'Enter bot public account',
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final botUserId = bot.isEmpty
          ? _config.imBotUserId
          : await _identity.resolve(bot, knownUserId: _config.imBotUserId);
      if (botUserId == null || !_matches(scope) || !_runtime.canConfigure) {
        return;
      }
      if (widget.groupScoped) {
        await _saveCurrentGroup(scope,
            name: name,
            gameGroup: gameGroup,
            statsGroup: statsGroup,
            ledgerGroup: ledgerGroup,
            botUserId: botUserId);
        return;
      }
      final saved = await _runtime.admin.saveMyConfig(
        name: name,
        imGroupGameId: gameGroup,
        imGroupAdminStatsId: statsGroup,
        imGroupLedgerId: ledgerGroup,
        imGroupWaterId: _config.imGroupWaterId,
        imBotUserId: botUserId,
      );
      if (!mounted || !_runtime.isCurrent) return;
      if (!saved.configured || saved.tenantId.isEmpty) {
        throw const FormatException('Save did not confirm a configured tenant');
      }
      final acceptedInitialSave = wasFirstSetup &&
          scope.sameAccountAndGroup(_runtime.featureContext) &&
          saved.imGroupGameId == gameGroup &&
          (_runtime.http.tenantId == scope.tenantId ||
              _runtime.http.tenantId == saved.tenantId);
      if (!_matches(scope) && !acceptedInitialSave) return;
      final normalized = saved;
      _committingSavedConfig = true;
      _scopeInvalid = false;
      _pageScope = _captureScope();
      try {
        await _runtime.config.applySaved(normalized);
      } finally {
        _committingSavedConfig = false;
      }
      if (!mounted || !SangongScope.read(context).isCurrent) return;
      _pageScope = _captureScope();
      _applyConfig(normalized);
      final canManageMembers =
          normalized.canManageMembers || normalized.isOwner;
      setState(() {
        _config = normalized;
        _saving = false;
      });
      widget.onSaved?.call(_config);
      ToastUtils.toast(
        i18n.t(zhHans: '已保存', zhHant: '已保存', en: 'Saved'),
      );
      if (!mounted) return;
      // 首次绑定成功后进成员页加帮工（走 /my-config/members，不拼群 ID）。
      if (wasFirstSetup && canManageMembers) {
        await SangongMembersPage.openReplace(context);
      } else {
        Navigator.of(context).pop(_config);
      }
    } catch (error) {
      if (!_matches(scope)) return;
      ToastUtils.toast(DioErrorMessage.forApp(error));
    } finally {
      if (mounted && _pageActive) setState(() => _saving = false);
    }
  }

  Future<void> _saveCurrentGroup(SangongOperationScope scope,
      {required String name,
      required String gameGroup,
      required String statsGroup,
      required String ledgerGroup,
      required String botUserId}) async {
    if (!_matches(scope) || gameGroup != _runtime.featureContext.groupID) {
      return;
    }
    final registration = _runtime.groupTenant.state;
    final initialize =
        registration?.status == SangongGroupTenantStatus.notFound;
    if (initialize && !_runtime.canInitialize) {
      throw StateError('只有当前群的群主或管理员可以初始化三公');
    }
    if (!initialize &&
        (registration?.config == null ||
            !_runtime.featureContext.capabilities.sangong.canConfigure)) {
      throw StateError('当前账号不能修改该群的三公配置');
    }
    final body = <String, dynamic>{
      if (!initialize || name.isNotEmpty) 'name': name,
      if (initialize) 'imGroupGameId': gameGroup,
      'imBotUserId': botUserId,
      'imGroupAdminStatsId': statsGroup,
      'imGroupLedgerId': ledgerGroup,
      'imGroupWaterId': _config.imGroupWaterId,
    };
    const api = SangongGroupTenantApi();
    final saved = initialize
        ? await api.create(_runtime.featureContext, body: body)
        : await api.update(_runtime.featureContext,
            tenantId: registration!.tenantId, body: body);
    if (!_matches(scope)) return;
    final config = saved.config;
    if (config == null) {
      throw const FormatException('Save did not confirm group config');
    }
    _committingSavedConfig = true;
    try {
      _runtime.groupTenant.applySaved(saved);
      _applyConfig(config);
      setState(() {
        _config = config;
      });
      widget.onSaved?.call(config);
      final entry = _runtime.featureContext;
      final next = await SangongApiDebugLog.trace(
          () => entry.refreshCapabilities(force: true));
      if (!_runtime.isSessionCurrent ||
          !_runtime.isPrivileged ||
          !scope.sameAccountAndGroup(next)) {
        return;
      }
      _runtime.updateContext(next);
      await _runtime.ensureManageBinding();
      if (!mounted || !_pageActive || !_runtime.isCurrent) return;
      _pageScope = _captureScope();
      _scopeInvalid = false;
      ToastUtils.toast('已保存', context: context);
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(config);
      }
    } finally {
      _committingSavedConfig = false;
    }
  }

  void _fillCurrentChatAsGameGroup() {
    final preset = ChatIdFormat.normalizeGroupId(widget.initialGameGroupId);
    if (preset.isEmpty) {
      return;
    }
    setState(() => _gameGroupController.text = preset);
  }

  @override
  Widget build(BuildContext context) {
    if (!_matches(_pageScope)) {
      return const Scaffold(
        body: Center(child: Text('当前游戏权限已变化，请重新进入')),
      );
    }
    final i18n = AppI18n.of(context);
    final dark = settingsIsDark(context);
    final title = i18n.t(
      zhHans: widget.groupScoped ? '当前群配置' : '我的配置',
      zhHant: widget.groupScoped ? '目前群配置' : '我的配置',
      en: widget.groupScoped ? 'Group Config' : 'My Config',
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

    if (_errorMessage != null && !_config.configured) {
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

    final readOnly = !_canEdit;
    return SettingsScaffold(
      title: title,
      dismissKeyboardOnOutsideTap: true,
      bottom: _canEdit
          ? SettingsPrimaryButton(
              text: _saving
                  ? i18n.t(zhHans: '保存中...', zhHant: '保存中...', en: 'Saving...')
                  : i18n.t(zhHans: '保存', zhHant: '保存', en: 'Save'),
              onPressed: _saving ? () {} : _save,
            )
          : null,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            _config.configured
                ? i18n.t(
                    zhHans: _canEdit
                        ? '报表群接收管理账单，上下分通知群接收上下分消息。修改机器人或接收群前请先关机，填写后点击保存生效。'
                        : '你是帮工，只能在操作台上下分跑局，不能改配置。',
                    zhHant: _canEdit
                        ? '報表群接收管理帳單，上下分通知群接收上下分訊息。修改機器人或接收群前請先關機，填寫後點擊保存生效。'
                        : '你是幫工，只能在操作台上下分跑局，不能改配置。',
                    en: _canEdit
                        ? 'The report group receives management bills; the notice group receives credit/debit messages. Stop the session before changing the bot or recipient groups, then save.'
                        : 'Helpers can operate rounds but cannot edit config.',
                  )
                : i18n.t(
                    zhHans: '首次配置：绑定本厅的下注群、结账群和机器人。保存后将由服务端确认你的运营角色。',
                    zhHant: '首次配置：綁定本廳的下注群、結賬群和機器人。保存後將由服務端確認你的營運角色。',
                    en: 'Bind game group, settle group and bot. The service confirms your operator role after saving.',
                  ),
            style: TextStyle(
              color: AppColors.subText(dark: dark),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
        if (_config.configured)
          SettingsGroup(
            children: [
              SettingsCell(
                title: i18n.t(zhHans: '我的角色', zhHant: '我的角色', en: 'Role'),
                value: _config.isOwner
                    ? i18n.t(zhHans: '群主', zhHant: '群主', en: 'Owner')
                    : _config.isAdmin
                        ? i18n.t(zhHans: '帮工', zhHant: '幫工', en: 'Helper')
                        : _config.myRole,
                showArrow: false,
                showDivider: false,
              ),
            ],
          ),
        SettingsGroup(
          children: [
            SettingsInputCell(
              label: i18n.t(zhHans: '厅名', zhHant: '廳名', en: 'Name'),
              hint: i18n.t(zhHans: '一号厅', zhHant: '一號廳', en: 'Hall 1'),
              controller: _nameController,
              readOnly: readOnly,
            ),
            SettingsInputCell(
              label: i18n.t(zhHans: '下注群', zhHant: '下注群', en: 'Game group'),
              hint: i18n.t(zhHans: '群 ID', zhHant: '群 ID', en: 'Group ID'),
              controller: _gameGroupController,
              readOnly: readOnly || _config.configured || widget.groupScoped,
            ),
            SettingsInputCell(
              label: i18n.t(zhHans: '报表群', zhHant: '報表群', en: 'Report group'),
              hint: i18n.t(zhHans: '群 ID', zhHant: '群 ID', en: 'Group ID'),
              controller: _statsGroupController,
              readOnly: readOnly,
            ),
            SettingsInputCell(
              label: i18n.t(
                zhHans: '上下分通知群',
                zhHant: '上下分通知群',
                en: 'Credit/Debit Notice Group',
              ),
              hint: i18n.t(zhHans: '群 ID', zhHant: '群 ID', en: 'Group ID'),
              controller: _ledgerGroupController,
              readOnly: readOnly,
            ),
            SettingsInputCell(
              label: i18n.t(zhHans: '机器人', zhHant: '機器人', en: 'Bot'),
              hint: i18n.t(
                zhHans: '公开账号名（可带 @）',
                zhHant: '公開帳號名（可帶 @）',
                en: 'Public account (optional @)',
              ),
              controller: _botController,
              readOnly: readOnly,
            ),
          ],
        ),
        if (_canEdit && _config.configured)
          SettingsGroup(children: [
            SettingsCell(
                title: '代理群绑定',
                value: '独立代理群',
                showDivider: false,
                onTap: () => SangongAgentGroupsPage.open(context))
          ]),
        if (_canEdit &&
            !widget.groupScoped &&
            !_config.configured &&
            widget.initialGameGroupId.trim().isNotEmpty)
          SettingsGroup(
            children: [
              SettingsCell(
                title: i18n.t(
                  zhHans: '使用当前聊天群作为下注群',
                  zhHant: '使用當前聊天群作為下注群',
                  en: 'Use current chat as game group',
                ),
                showDivider: false,
                onTap: _fillCurrentChatAsGameGroup,
              ),
            ],
          ),
      ],
    );
  }
}
