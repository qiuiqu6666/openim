import '../report_center/pages/report_center_page.dart';
// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'sangong_my_config_page.dart';
import 'sangong_members_page.dart';
import 'sangong_all_users_page.dart';
import 'package:flutter/services.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_game_settings.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/support/settings_exports.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_round_settle_flow.dart';

class SangongGameRulesSettingsPage extends StatefulWidget {
  const SangongGameRulesSettingsPage({
    super.key,
    this.floatVisible,
    this.onFloatVisibleChanged,
  });

  final bool? floatVisible;
  final ValueChanged<bool>? onFloatVisibleChanged;

  static Future<void> open(
    BuildContext context, {
    bool? floatVisible,
    ValueChanged<bool>? onFloatVisibleChanged,
  }) {
    return Navigator.of(context).push<void>(
      SangongPageRoute(
        context: context,
        settings: const RouteSettings(name: 'sangong_game_rules_settings'),
        builder: (_) => SangongGameRulesSettingsPage(
          floatVisible: floatVisible,
          onFloatVisibleChanged: onFloatVisibleChanged,
        ),
      ),
    );
  }

  @override
  State<SangongGameRulesSettingsPage> createState() =>
      _SangongGameRulesSettingsPageState();
}

class _SangongGameRulesSettingsPageState
    extends State<SangongGameRulesSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  bool _sessionBusy = false;
  bool _canEdit = false;
  String? _errorMessage;
  SangongAdminSession _session = const SangongAdminSession();
  late bool _floatVisible;

  late TextEditingController _doorCountController;
  late TextEditingController _minBetController;
  late TextEditingController _maxBetController;
  late TextEditingController _rakePercentController;

  @override
  void initState() {
    super.initState();
    _floatVisible = widget.floatVisible ?? true;
    _doorCountController = TextEditingController();
    _minBetController = TextEditingController();
    _maxBetController = TextEditingController();
    _rakePercentController = TextEditingController();
    unawaited(_load());
  }

  @override
  void dispose() {
    _doorCountController.dispose();
    _minBetController.dispose();
    _maxBetController.dispose();
    _rakePercentController.dispose();
    super.dispose();
  }

  void _onFloatVisibleChanged(bool value) {
    setState(() => _floatVisible = value);
    widget.onFloatVisibleChanged?.call(value);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final runtime = SangongScope.read(context);
      final state = await runtime.admin.fetchEventsSnapshot();
      final session = SangongAdminSession(
          status: state.status, session: state.session, round: state.round);
      if (!mounted || !runtime.isCurrent) return;
      _applySettings(state.settings);
      setState(() {
        _canEdit = runtime.settings.canEdit;
        _session = session;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = DioErrorMessage.forApp(error);
      });
    }
  }

  void _applySettings(SangongGameSettings settings) {
    _doorCountController.text = '${settings.doorCount}';
    _minBetController.text = '${settings.minBet}';
    _maxBetController.text = '${settings.maxBet}';
    _rakePercentController.text = '${settings.rakePercent}';
  }

  SangongGameSettings? _readForm() {
    final i18n = AppI18n.of(context);
    final doorCount = int.tryParse(_doorCountController.text.trim());
    if (doorCount == null || doorCount < 2 || doorCount > 10) {
      ToastUtils.toast(
        i18n.t(
          zhHans: '门数需在 2～10 之间',
          zhHant: '門數需在 2～10 之間',
          en: 'Door count must be between 2 and 10',
          ja: '門数は2〜10の範囲で入力してください',
          ko: '문 수는 2~10 사이여야 합니다',
        ),
      );
      return null;
    }

    final minBet = int.tryParse(_minBetController.text.trim());
    final maxBet = int.tryParse(_maxBetController.text.trim());
    if (minBet == null || maxBet == null || minBet < 0 || maxBet < 0) {
      ToastUtils.toast(
        i18n.t(
          zhHans: '请输入非负整数下注限额',
          zhHant: '下注限額不能為負數',
          en: 'Bet limits cannot be negative',
          ja: 'ベット上限は負の値にできません',
          ko: '베팅 한도는 음수일 수 없습니다',
        ),
      );
      return null;
    }
    if (maxBet > 0 && minBet > maxBet) {
      ToastUtils.toast(
        i18n.t(
          zhHans: '最小下注不能大于最大下注',
          zhHant: '最小下注不能大於最大下注',
          en: 'Min bet cannot exceed max bet',
          ja: '最小ベットは最大ベットを超えられません',
          ko: '최소 베팅은 최대 베팅보다 클 수 없습니다',
        ),
      );
      return null;
    }
    if (maxBet > SangongGameSettings.maxMaxBet) {
      ToastUtils.toast(
        i18n.t(
          zhHans: '最大下注不能超过 ${SangongGameSettings.maxMaxBet}',
          zhHant: '最大下注不能超過 ${SangongGameSettings.maxMaxBet}',
          en: 'Max bet cannot exceed ${SangongGameSettings.maxMaxBet}',
        ),
      );
      return null;
    }

    final rake = int.tryParse(_rakePercentController.text.trim());
    if (rake == null || rake < 0 || rake > 100) {
      ToastUtils.toast(i18n.t(
          zhHans: '庄家抽水比例须为 0～100 的整数',
          zhHant: '莊家抽水比例須為 0～100 的整數',
          en: 'Banker rake must be an integer from 0 to 100'));
      return null;
    }
    return SangongGameSettings(
        doorCount: doorCount,
        minBet: minBet,
        maxBet: maxBet,
        rakePercent: rake);
  }

  Future<void> _save() async {
    if (!_canEdit || _saving) return;
    final payload = _readForm();
    if (payload == null) return;

    setState(() => _saving = true);
    final i18n = AppI18n.of(context);
    try {
      final saved = await SangongScope.read(context).settings.save(payload);
      if (!mounted) return;
      _applySettings(saved);
      ToastUtils.toast(
        i18n.t(
          zhHans: '规则已保存',
          zhHant: '規則已儲存',
          en: 'Rules saved.',
          ja: '保存しました。',
          ko: '저장되었습니다.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ToastUtils.toast(DioErrorMessage.forApp(error));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _sessionStatusLabel(AppI18n i18n) {
    if (_session.isRunning) {
      final period = _session.periodNo;
      if (period > 0) {
        return i18n.t(
          zhHans: '运行中 · 第$period期',
          zhHant: '運行中 · 第$period期',
          en: 'Running · Round $period',
        );
      }
      return i18n.t(
        zhHans: '运行中',
        zhHant: '運行中',
        en: 'Running',
      );
    }
    return i18n.t(
      zhHans: '待机',
      zhHant: '待機',
      en: 'Idle',
    );
  }

  Future<void> _refreshSession() async {
    try {
      final session = await SangongScope.read(context).admin.fetchSession();
      if (!mounted) return;
      setState(() => _session = session);
    } catch (_) {}
  }

  Future<void> _startSession() async {
    if (!_canEdit || _sessionBusy || _session.isRunning) {
      return;
    }
    setState(() => _sessionBusy = true);
    final i18n = AppI18n.of(context);
    try {
      final result = await SangongScope.read(context).admin.startSession();
      if (!mounted) return;
      await _refreshSession();
      ToastUtils.toast(
        result.message.isNotEmpty
            ? result.message
            : i18n.t(
                zhHans: '开机成功',
                zhHant: '開機成功',
                en: 'Session started',
              ),
      );
    } catch (error) {
      if (!mounted) return;
      ToastUtils.toast(DioErrorMessage.forApp(error));
    } finally {
      if (mounted) {
        setState(() => _sessionBusy = false);
      }
    }
  }

  Future<void> _confirmStopSession() async {
    if (!_canEdit || _sessionBusy || !_session.isRunning) {
      return;
    }
    final i18n = AppI18n.of(context);
    final sessionId = _session.session?.id ?? 0;
    if (sessionId <= 0) return;
    final ok = await AppDialog.confirm(
      context: context,
      title: i18n.t(
        zhHans: '确认关机',
        zhHant: '確認關機',
        en: 'Stop session',
      ),
      message: i18n.t(
        zhHans: '关机后会话结束。若当前局未结算，将自动作废并退款；已有结算局会发送最终管理账单。用户余额保留。',
        zhHant: '關機後會話結束。若當前局未結算，將自動作廢並退款；已有結算局會發送最終管理帳單。用戶餘額保留。',
        en: 'Stopping ends the session. An unsettled round will be voided and refunded; a final admin bill is sent if any round settled. Balances are kept.',
      ),
      confirmText: i18n.t(
        zhHans: '关机',
        zhHant: '關機',
        en: 'Stop',
      ),
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    setState(() => _sessionBusy = true);
    try {
      final result = await SangongScope.read(context)
          .admin
          .stopSession(sessionId: sessionId);
      if (!mounted) return;
      await _refreshSession();
      ToastUtils.toast(
        result.message.isNotEmpty
            ? result.message
            : i18n.t(
                zhHans: '关机成功',
                zhHant: '關機成功',
                en: 'Session stopped',
              ),
      );
    } catch (error) {
      if (!mounted) return;
      ToastUtils.toast(DioErrorMessage.forApp(error));
    } finally {
      if (mounted) {
        setState(() => _sessionBusy = false);
      }
    }
  }

  Future<void> _resetRound() async {
    final runtime = SangongScope.read(context);
    final round = _session.round;
    if (_sessionBusy || _saving || !runtime.canManage || round == null) return;
    final ok = await AppDialog.confirm(
      context: context,
      title: '退回全部注单并取消定庄',
      message:
          '退回第${round.periodNo}期全部有效下注，清除庄家和合庄，保留本期期号并恢复未定庄。已撤注退款的注单不会重复退款。',
    );
    if (!mounted || !ok || !runtime.isCurrent) return;
    setState(() => _sessionBusy = true);
    try {
      final session = await runtime.admin.resetUnopenedRound(round.id);
      if (!mounted || !runtime.isCurrent) return;
      setState(() {
        _session = session;
        _canEdit = runtime.settings.canEdit;
      });
      ToastUtils.toast('全部有效注单已退回，已恢复未定庄');
    } catch (error) {
      if (mounted && runtime.isCurrent) {
        ToastUtils.toast(DioErrorMessage.forApp(error));
      }
    } finally {
      if (mounted) setState(() => _sessionBusy = false);
    }
  }

  Widget _buildSessionGroup(AppI18n i18n, bool dark) {
    final running = _session.isRunning;
    final actionLabel = running
        ? i18n.t(zhHans: '关机', zhHant: '關機', en: 'Stop')
        : i18n.t(zhHans: '开机', zhHant: '開機', en: 'Start');
    final actionColor =
        running ? Colors.red : Theme.of(context).colorScheme.primary;

    return SettingsGroup(
      children: [
        SettingsCell(
          title: i18n.t(
            zhHans: '会话状态',
            zhHant: '會話狀態',
            en: 'Session',
          ),
          showArrow: false,
          showDivider: _canEdit,
          trailing: _sessionBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _sessionStatusLabel(i18n),
                  style: TextStyle(
                    color: running
                        ? const Color(0xFF1B9E3E)
                        : AppColors.subText(dark: dark),
                    fontSize: 15,
                  ),
                ),
        ),
        if (_canEdit)
          SettingsCell(
            title: actionLabel,
            showArrow: false,
            showDivider: false,
            titleStyle: TextStyle(
              color: _sessionBusy ? AppColors.subText(dark: dark) : actionColor,
              fontSize: 16,
            ),
            onTap: _sessionBusy
                ? null
                : () => unawaited(
                      running ? _confirmStopSession() : _startSession(),
                    ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final dark = settingsIsDark(context);
    final readOnly = !_canEdit;

    return SettingsScaffold(
      title: i18n.t(
        zhHans: '游戏规则',
        zhHant: '遊戲規則',
        en: 'Game Rules',
        ja: 'ゲームルール',
        ko: '게임 규칙',
      ),
      dismissKeyboardOnOutsideTap: true,
      disableLeading: _saving || _sessionBusy,
      bottom: _canEdit
          ? SettingsPrimaryButton(
              text: _saving
                  ? i18n.t(
                      zhHans: '保存中...',
                      zhHant: '保存中...',
                      en: 'Saving...',
                      ja: '保存中...',
                      ko: '저장 중...',
                    )
                  : i18n.t(
                      zhHans: '保存',
                      zhHant: '保存',
                      en: 'Save',
                      ja: '保存',
                      ko: '저장',
                    ),
              onPressed: _saving ? () {} : _save,
            )
          : null,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.subText(dark: dark)),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _load,
                  child: Text(
                    i18n.t(
                      zhHans: '重试',
                      zhHant: '重試',
                      en: 'Retry',
                      ja: '再試行',
                      ko: '다시 시도',
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          SettingsGroup(
            children: [
              SettingsCell(
                title: i18n.t(
                  zhHans: '当前群配置',
                  zhHant: '目前群配置',
                  en: 'Current Group Config',
                ),
                showDivider: false,
                onTap: _saving || _sessionBusy
                    ? null
                    : () => unawaited(SangongMyConfigPage.open(
                          context,
                          groupScoped: true,
                          initialGameGroupId:
                              SangongScope.read(context).featureContext.groupID,
                        )),
              ),
            ],
          ),
          if (SangongScope.read(context).canManageMembers)
            SettingsGroup(children: [
              SettingsCell(
                title: i18n.t(zhHans: '帮工管理', zhHant: '幫工管理', en: 'Helpers'),
                value: i18n.t(
                    zhHans: '添加 / 移除帮工',
                    zhHant: '新增 / 移除幫工',
                    en: 'Add / remove helpers'),
                showDivider: false,
                onTap: _saving || _sessionBusy
                    ? null
                    : () => unawaited(SangongMembersPage.open(context)),
              ),
            ]),
          if (SangongScope.read(context).canManage)
            SettingsGroup(children: [
              SettingsCell(
                title: i18n.t(zhHans: '全部用户', zhHant: '全部用戶', en: 'All users'),
                value: i18n.t(
                    zhHans: '积分 / 流水',
                    zhHant: '積分 / 流水',
                    en: 'Points / ledger'),
                showDivider: false,
                onTap: _saving || _sessionBusy
                    ? null
                    : () => unawaited(SangongAllUsersPage.open(context)),
              )
            ]),
          if (SangongScope.read(context).canManage)
            SettingsGroup(children: [
              SettingsCell(
                  title: '报表中心',
                  value: '汇总 / 用户 / 团队 / 账变 / 牌局',
                  showDivider: false,
                  onTap: _saving || _sessionBusy
                      ? null
                      : () => unawaited(SangongReportCenterPage.open(context)))
            ]),
          _buildSessionGroup(i18n, dark),
          if (SangongScope.read(context).canManage &&
              _session.isRunning &&
              _session.round != null &&
              (_session.round!.bankerDoor ?? 0) > 0 &&
              _session.round!.drawLockedAt.isEmpty &&
              const {'betting', 'co_bank_closed', 'await_banker_door'}
                  .contains(_session.round!.status))
            SettingsGroup(children: [
              SettingsCell(
                title: i18n.t(
                    zhHans: '退回全部注单并取消定庄',
                    zhHant: '退回全部注單並取消定莊',
                    en: 'Refund all bets and clear banker'),
                showDivider: false,
                onTap: _saving || _sessionBusy
                    ? null
                    : () => unawaited(_resetRound()),
              ),
            ]),
          if (widget.onFloatVisibleChanged != null)
            SettingsGroup(
              children: [
                SettingsCell(
                  title: i18n.t(
                    zhHans: '冲正重结',
                    zhHant: '沖正重結',
                    en: 'Resettle',
                  ),
                  value:
                      SangongRoundSettleFlow.lastSettledCaption(context, i18n),
                  onTap: () => unawaited(
                    SangongRoundSettleFlow.runLastSettledResettle(context),
                  ),
                ),
                SettingsCell(
                  title: i18n.t(
                    zhHans: '显示游戏浮窗',
                    zhHant: '顯示遊戲浮窗',
                    en: 'Show Game Float',
                    ja: 'ゲーム浮窗を表示',
                    ko: '게임 플로팅 표시',
                  ),
                  showArrow: false,
                  showDivider: false,
                  trailing: SettingsPlatformSwitch(
                    value: _floatVisible,
                    onChanged: _onFloatVisibleChanged,
                  ),
                ),
              ],
            ),
          if (!_canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                i18n.t(
                  zhHans: '当前为只读查看；此账号没有修改权限',
                  zhHant: '目前為唯讀查看；此帳號沒有修改權限',
                  en: 'Read-only view. This account cannot edit the rules.',
                  ja: '現在は閲覧のみです。このアカウントには変更権限がありません。',
                  ko: '현재 읽기 전용입니다. 이 계정에는 수정 권한이 없습니다.',
                ),
                style: TextStyle(
                  color: AppColors.subText(dark: dark),
                  fontSize: 13,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              i18n.t(
                zhHans: '请在定庄前修改规则。输赢按 1:1；只按闲家总下注流水向庄家抽水，小数向下取整。',
                zhHant: '請在定莊前修改規則。輸贏按 1:1；只按閒家總下注流水向莊家抽水，小數向下取整。',
                en: 'Edit before selecting the banker. Payout is 1:1; banker rake applies to total player stakes, rounded down.',
                ja: '庄の設定前に変更してください。配当は1:1、庄の手数料は総ベット額を基準に切り捨てます。',
                ko: '뱅커 지정 전에 변경하세요. 배당은 1:1이며 뱅커 수수료는 전체 베팅액 기준으로 내림합니다.',
              ),
              style: TextStyle(
                color: AppColors.subText(dark: dark),
                fontSize: 13,
              ),
            ),
          ),
          SettingsGroup(
            children: [
              _numberField(
                label: i18n.t(
                  zhHans: '门数',
                  zhHant: '門數',
                  en: 'Doors',
                  ja: '門数',
                  ko: '문 수',
                ),
                controller: _doorCountController,
                readOnly: readOnly,
              ),
              _numberField(
                label: i18n.t(
                  zhHans: '最小下注',
                  zhHant: '最小下注',
                  en: 'Min Bet',
                  ja: '最小ベット',
                  ko: '최소 베팅',
                ),
                controller: _minBetController,
                readOnly: readOnly,
              ),
              _numberField(
                label: i18n.t(
                  zhHans: '最大下注（0 不限）',
                  zhHant: '最大下注（0 不限）',
                  en: 'Max Bet (0 = unlimited)',
                  ja: '最大ベット（0=無制限）',
                  ko: '최대 베팅 (0=무제한)',
                ),
                controller: _maxBetController,
                readOnly: readOnly,
                showDivider: false,
              ),
            ],
          ),
          SettingsGroup(children: [
            _numberField(
              label: i18n.t(
                  zhHans: '庄家抽水（%）', zhHant: '莊家抽水（%）', en: 'Banker rake (%)'),
              controller: _rakePercentController,
              readOnly: readOnly,
              showDivider: false,
            ),
          ]),
        ],
      ],
    );
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    required bool readOnly,
    bool showDivider = true,
  }) {
    return SettingsInputCell(
      label: label,
      hint: '',
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      readOnly: readOnly,
    );
  }
}
