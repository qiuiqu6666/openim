// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim/pages/group_features/sangong/api/sangong_settings_api.dart';
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
  late TextEditingController _imGroupGameIdController;
  late TextEditingController _imGroupAdminStatsIdController;
  late TextEditingController _imBotUserIdController;
  late List<TextEditingController> _pointOddsControllers;
  late List<TextEditingController> _pointBankerRakeControllers;
  late List<TextEditingController> _pointPlayerRakeControllers;
  late TextEditingController _pairOddsController;
  late TextEditingController _pairBankerRakeController;
  late TextEditingController _pairPlayerRakeController;
  late TextEditingController _maxHandOddsController;
  late TextEditingController _maxHandBankerRakeController;
  late TextEditingController _maxHandPlayerRakeController;

  @override
  void initState() {
    super.initState();
    _floatVisible = widget.floatVisible ?? true;
    _doorCountController = TextEditingController();
    _minBetController = TextEditingController();
    _maxBetController = TextEditingController();
    _imGroupGameIdController = TextEditingController();
    _imGroupAdminStatsIdController = TextEditingController();
    _imBotUserIdController = TextEditingController();
    _pointOddsControllers = List<TextEditingController>.generate(
        10, (_) => TextEditingController());
    _pointBankerRakeControllers = List<TextEditingController>.generate(
        10, (_) => TextEditingController());
    _pointPlayerRakeControllers = List<TextEditingController>.generate(
        10, (_) => TextEditingController());
    _pairOddsController = TextEditingController();
    _pairBankerRakeController = TextEditingController();
    _pairPlayerRakeController = TextEditingController();
    _maxHandOddsController = TextEditingController();
    _maxHandBankerRakeController = TextEditingController();
    _maxHandPlayerRakeController = TextEditingController();
    unawaited(_load());
  }

  @override
  void dispose() {
    _doorCountController.dispose();
    _minBetController.dispose();
    _maxBetController.dispose();
    _imGroupGameIdController.dispose();
    _imGroupAdminStatsIdController.dispose();
    _imBotUserIdController.dispose();
    for (final controller in _pointOddsControllers) {
      controller.dispose();
    }
    for (final controller in _pointBankerRakeControllers) {
      controller.dispose();
    }
    for (final controller in _pointPlayerRakeControllers) {
      controller.dispose();
    }
    _pairOddsController.dispose();
    _pairBankerRakeController.dispose();
    _pairPlayerRakeController.dispose();
    _maxHandOddsController.dispose();
    _maxHandBankerRakeController.dispose();
    _maxHandPlayerRakeController.dispose();
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
      final results = await Future.wait(
          [runtime.settings.loadForUi(), runtime.admin.fetchSession()]);
      final result = results[0] as SangongSettingsLoadResult;
      final session = results[1] as SangongAdminSession;
      if (!mounted || !runtime.isCurrent) return;
      _applySettings(result.settings);
      setState(() {
        _canEdit = result.canEdit;
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
    _imGroupGameIdController.text = settings.imGroupGameId;
    _imGroupAdminStatsIdController.text = settings.imGroupAdminStatsId;
    _imBotUserIdController.text = settings.imBotUserId;
    for (var i = 0; i < 10; i++) {
      final point = settings.points[i];
      _pointOddsControllers[i].text = _formatOdds(point.odds);
      _pointBankerRakeControllers[i].text = '${point.bankerRakePoints}';
      _pointPlayerRakeControllers[i].text = '${point.playerRakePoints}';
    }
    _pairOddsController.text = _formatOdds(settings.pair.odds);
    _pairBankerRakeController.text = '${settings.pair.bankerRakePoints}';
    _pairPlayerRakeController.text = '${settings.pair.playerRakePoints}';
    _maxHandOddsController.text = _formatOdds(settings.maxHand.odds);
    _maxHandBankerRakeController.text = '${settings.maxHand.bankerRakePoints}';
    _maxHandPlayerRakeController.text = '${settings.maxHand.playerRakePoints}';
  }

  String _formatOdds(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(1);
    }
    return value.toString();
  }

  SangongHandRule? _readHandRule({
    required String label,
    required TextEditingController oddsController,
    required TextEditingController bankerRakeController,
    required TextEditingController playerRakeController,
    required String invalidMessage,
  }) {
    final odds = double.tryParse(oddsController.text.trim());
    final bankerRake = int.tryParse(bankerRakeController.text.trim());
    final playerRake = int.tryParse(playerRakeController.text.trim());
    if (odds == null ||
        bankerRake == null ||
        playerRake == null ||
        odds <= 0 ||
        bankerRake < 0 ||
        playerRake < 0) {
      ToastUtils.toast(invalidMessage);
      return null;
    }
    return SangongHandRule(
      label: label,
      odds: odds,
      bankerRakePoints: bankerRake,
      playerRakePoints: playerRake,
    );
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

    final minBet = int.tryParse(_minBetController.text.trim()) ?? 0;
    final maxBet = int.tryParse(_maxBetController.text.trim()) ?? 0;
    if (minBet < 0 || maxBet < 0) {
      ToastUtils.toast(
        i18n.t(
          zhHans: '下注限额不能为负数',
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

    final points = <SangongPointRule>[];
    for (var i = 0; i < 10; i++) {
      final rule = _readHandRule(
        label: '$i点',
        oddsController: _pointOddsControllers[i],
        bankerRakeController: _pointBankerRakeControllers[i],
        playerRakeController: _pointPlayerRakeControllers[i],
        invalidMessage: i18n.t(
          zhHans: '$i点规则填写无效',
          zhHant: '$i點規則填寫無效',
          en: 'Invalid settings for point $i',
          ja: '$i点の設定が無効です',
          ko: '$i점 설정이 올바르지 않습니다',
        ),
      );
      if (rule == null) return null;
      points.add(
        SangongPointRule(
          point: i,
          label: rule.label,
          odds: rule.odds,
          bankerRakePoints: rule.bankerRakePoints,
          playerRakePoints: rule.playerRakePoints,
        ),
      );
    }

    final pair = _readHandRule(
      label: '对子',
      oddsController: _pairOddsController,
      bankerRakeController: _pairBankerRakeController,
      playerRakeController: _pairPlayerRakeController,
      invalidMessage: i18n.t(
        zhHans: '对子规则填写无效',
        zhHant: '對子規則填寫無效',
        en: 'Invalid pair settings',
        ja: 'ペアの設定が無効です',
        ko: '페어 설정이 올바르지 않습니다',
      ),
    );
    if (pair == null) return null;

    final maxHand = _readHandRule(
      label: '1.00',
      oddsController: _maxHandOddsController,
      bankerRakeController: _maxHandBankerRakeController,
      playerRakeController: _maxHandPlayerRakeController,
      invalidMessage: i18n.t(
        zhHans: '1.00 规则填写无效',
        zhHant: '1.00 規則填寫無效',
        en: 'Invalid max-hand settings',
        ja: '1.00の設定が無効です',
        ko: '1.00 설정이 올바르지 않습니다',
      ),
    );
    if (maxHand == null) return null;

    return SangongGameSettings(
      doorCount: doorCount,
      minBet: minBet,
      maxBet: maxBet,
      points: points,
      pair: pair,
      maxHand: maxHand,
      imGroupGameId: _imGroupGameIdController.text.trim(),
      imGroupAdminStatsId: _imGroupAdminStatsIdController.text.trim(),
      imBotUserId: _imBotUserIdController.text.trim(),
    );
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
          zhHans: '已保存，建议下一局生效',
          zhHant: '已保存，建議下一局生效',
          en: 'Saved. Changes apply from the next round.',
          ja: '保存しました。次の局から反映されます。',
          ko: '저장되었습니다. 다음 판부터 적용됩니다.',
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
      final result = await SangongScope.read(context).admin.stopSession();
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
          _buildSessionGroup(i18n, dark),
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
                zhHans: '建议下一局生效',
                zhHant: '建議下一局生效',
                en: 'Changes apply from the next round',
                ja: '次の局から反映されます',
                ko: '다음 판부터 적용됩니다',
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
          _sectionHeader(
            i18n.t(
              zhHans: '点数',
              zhHant: '點數',
              en: 'Point',
              ja: '点数',
              ko: '점수',
            ),
            i18n.t(
              zhHans: '赔率',
              zhHant: '賠率',
              en: 'Odds',
              ja: 'オッズ',
              ko: '배당',
            ),
            i18n.t(
              zhHans: '庄抽水',
              zhHant: '莊抽水',
              en: 'Banker',
              ja: '庄抽水',
              ko: '뱅커',
            ),
            i18n.t(
              zhHans: '闲抽水',
              zhHant: '閒抽水',
              en: 'Player',
              ja: '閑抽水',
              ko: '플레이어',
            ),
          ),
          SettingsGroup(
            children: [
              for (var i = 0; i < 10; i++)
                _oddsRakeRow(
                  label: '$i点',
                  oddsController: _pointOddsControllers[i],
                  bankerRakeController: _pointBankerRakeControllers[i],
                  playerRakeController: _pointPlayerRakeControllers[i],
                  readOnly: readOnly,
                  showDivider: i < 9,
                ),
            ],
          ),
          SettingsGroup(
            children: [
              _oddsRakeRow(
                label: i18n.t(
                  zhHans: '对子',
                  zhHant: '對子',
                  en: 'Pair',
                  ja: 'ペア',
                  ko: '페어',
                ),
                oddsController: _pairOddsController,
                bankerRakeController: _pairBankerRakeController,
                playerRakeController: _pairPlayerRakeController,
                readOnly: readOnly,
              ),
              _oddsRakeRow(
                label: '1.00',
                oddsController: _maxHandOddsController,
                bankerRakeController: _maxHandBankerRakeController,
                playerRakeController: _maxHandPlayerRakeController,
                readOnly: readOnly,
                showDivider: false,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(
    String col1,
    String col2,
    String col3,
    String col4,
  ) {
    final dark = settingsIsDark(context);
    TextStyle style = TextStyle(
      color: AppColors.subText(dark: dark),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(col1, style: style)),
          Expanded(
              flex: 2,
              child: Text(col2, textAlign: TextAlign.center, style: style)),
          Expanded(
              flex: 2,
              child: Text(col3, textAlign: TextAlign.center, style: style)),
          Expanded(
              flex: 2,
              child: Text(col4, textAlign: TextAlign.center, style: style)),
        ],
      ),
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

  Widget _oddsRakeRow({
    required String label,
    required TextEditingController oddsController,
    required TextEditingController bankerRakeController,
    required TextEditingController playerRakeController,
    required bool readOnly,
    bool showDivider = true,
  }) {
    final dark = settingsIsDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: AppColors.line(dark: dark),
                  width: 0.7,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.text(dark: dark),
                fontSize: 15,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: _compactField(
              controller: oddsController,
              readOnly: readOnly,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: _compactField(
              controller: bankerRakeController,
              readOnly: readOnly,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: _compactField(
              controller: playerRakeController,
              readOnly: readOnly,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactField({
    required TextEditingController controller,
    required bool readOnly,
    required TextInputType keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final dark = settingsIsDark(context);
    return TextField(
      controller: controller,
      readOnly: readOnly,
      enabled: !readOnly,
      textAlign: TextAlign.center,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      cursorColor: AppColors.primaryBlue,
      style: TextStyle(
        color: AppColors.text(dark: dark),
        fontSize: 15,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        filled: true,
        fillColor: AppColors.background(dark: dark),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.line(dark: dark)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.line(dark: dark)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
      ),
    );
  }
}
