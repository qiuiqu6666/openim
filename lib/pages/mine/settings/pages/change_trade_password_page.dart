import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_service.dart';
import '../account_security/sms_policy_state.dart';
import '../widgets/verification_code_flow.dart';
import '../widgets/settings_widgets.dart';

class ChangeTradePasswordPage extends StatefulWidget {
  const ChangeTradePasswordPage({
    super.key,
    required this.service,
    this.phoneNumber = '',
  });

  final SettingsService service;
  final String phoneNumber;

  @override
  State<ChangeTradePasswordPage> createState() =>
      _ChangeTradePasswordPageState();
}

class _ChangeTradePasswordPageState extends State<ChangeTradePasswordPage>
    with SmsPolicyState<ChangeTradePasswordPage> {
  @override
  SettingsService get securityService => widget.service;
  final _codeFlow = VerificationCodeFlow();
  final _old = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNext = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  bool get _smsMode => widget.phoneNumber.trim().isNotEmpty;
  String get _maskedPhone {
    final phone = widget.phoneNumber.trim();
    if (phone.length <= 7) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  @override
  void initState() {
    super.initState();
    _codeFlow.addListener(_refresh);
    _old.addListener(_refresh);
    _next.addListener(_refresh);
    _confirm.addListener(_refresh);
  }

  @override
  void dispose() {
    _codeFlow.dispose();
    _old.removeListener(_refresh);
    _next.removeListener(_refresh);
    _confirm.removeListener(_refresh);
    _old.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool _sixDigits(String text) => RegExp(r'^\d{6}$').hasMatch(text.trim());

  bool get _canSubmit =>
      smsPolicyReady &&
      !_submitting &&
      (smsExempt || _sixDigits(_old.text)) &&
      _sixDigits(_next.text) &&
      _next.text.trim() == _confirm.text.trim();

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!await refreshSmsPolicy() || !mounted || !_canSubmit) return;
    if (!widget.service.isSecurityBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '修改支付密码', en: 'Change payment password'),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      if (_smsMode || smsExempt) {
        await widget.service.resetTradePassword(
            code: smsExempt ? '' : _old.text.trim(),
            password: _next.text.trim());
      } else {
        await widget.service.changeTradePassword(
            oldPassword: _old.text.trim(), newPassword: _next.text.trim());
      }
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(context,
            zh: _smsMode ? '支付密码重置成功' : '支付密码修改成功',
            en: _smsMode
                ? 'Payment password reset successfully'
                : 'Payment password changed successfully'),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showSettingsError(
        context,
        error,
        settingsText(
          context,
          zh: '修改失败，请稍后重试',
          en: 'Failed to update. Please try again later.',
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openReset() async {
    if (_submitting || !_smsMode || !_codeFlow.canSend) return;
    setState(() => _submitting = true);
    try {
      final sent = await _codeFlow.send(
          context,
          (param) => widget.service
              .requestTradePasswordCode(captchaVerifyParam: param));
      if (mounted && sent) {
        showSettingsMessage(
            context, settingsText(context, zh: '验证码已发送', en: 'Code sent'));
      }
    } catch (error) {
      if (mounted) {
        showSettingsError(context, error,
            settingsText(context, zh: '发送失败，请稍后重试', en: 'Could not send code'));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _eye(bool obscure, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final helper = AppTokens.textSecondary(dark: dark);
    final digits = <TextInputFormatter>[
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(6),
    ];

    return SettingsScaffold(
      title: settingsText(context, zh: '修改支付密码', en: 'Change Payment Password'),
      dismissKeyboardOnOutsideTap: true,
      children: [
        smsPolicyNotice(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTokens.s5, AppTokens.s4, AppTokens.s5, AppTokens.s4),
          child: Text(
            settingsText(
              context,
              zh: smsExempt
                  ? '请输入并确认新的 6 位支付密码。'
                  : _smsMode
                      ? '通过绑定手机的验证码设置新的 6 位支付密码。'
                      : '请输入当前支付密码，并设置新的 6 位数字支付密码。',
              en: smsExempt
                  ? 'Enter and confirm a new 6-digit payment password.'
                  : _smsMode
                      ? 'Use a code sent to your bound phone to set a new payment password.'
                      : 'Enter your current payment password, then set a new 6-digit one.',
            ),
            style: TextStyle(
                color: helper,
                fontSize: AppTokens.captionFontSize,
                height: 1.5),
          ),
        ),
        SettingsGroup(
          margin: EdgeInsets.zero,
          children: [
            if (!smsExempt && _smsMode)
              SettingsCell(
                title: settingsText(context,
                    zh: '绑定手机号', en: 'Bound Phone Number'),
                value: _maskedPhone,
                showArrow: false,
              ),
            if (!smsExempt)
              SettingsInputCell(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppTokens.s5),
                label: settingsText(context,
                    zh: _smsMode ? '验证码' : '原密码',
                    en: _smsMode ? 'SMS Code' : 'Current Password'),
                hint: settingsText(context,
                    zh: _smsMode ? '请输入验证码' : '请输入 6 位支付密码',
                    en: _smsMode ? 'Enter the 6-digit code' : 'Enter 6 digits'),
                controller: _old,
                obscureText: !_smsMode && _obscureOld,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                trailing: _smsMode
                    ? TextButton(
                        style: TextButton.styleFrom(
                            foregroundColor: AppTokens.accent),
                        onPressed: _submitting || !_codeFlow.canSend
                            ? null
                            : _openReset,
                        child: Text(_codeFlow.label(context)))
                    : _eye(_obscureOld,
                        () => setState(() => _obscureOld = !_obscureOld)),
              ),
            SettingsInputCell(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppTokens.s5),
              label: settingsText(context, zh: '新密码', en: 'New Password'),
              hint: settingsText(context,
                  zh: '请输入 6 位数字', en: 'Enter new 6 digits'),
              controller: _next,
              obscureText: _obscureNext,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              trailing: _eye(
                _obscureNext,
                () => setState(() => _obscureNext = !_obscureNext),
              ),
            ),
            SettingsInputCell(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppTokens.s5),
              label: settingsText(context, zh: '确认密码', en: 'Confirm Password'),
              hint: settingsText(context, zh: '再次输入新密码', en: 'Enter it again'),
              controller: _confirm,
              obscureText: _obscureConfirm,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              showDivider: false,
              trailing: _eye(
                _obscureConfirm,
                () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ],
        ),
        if (_confirm.text.isNotEmpty &&
            _next.text.trim() != _confirm.text.trim())
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
                settingsText(context,
                    zh: '两次输入的支付密码不一致', en: 'Payment passwords do not match'),
                style: const TextStyle(color: AppTokens.danger)),
          ),
        if (!_smsMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.s5, AppTokens.s4, AppTokens.s5, 0),
            child: Text(
                settingsText(context,
                    zh: '绑定手机号后，可通过短信验证码重置支付密码。',
                    en:
                        'Link a phone number to reset your payment password by SMS.'),
                style: TextStyle(
                    color: helper,
                    fontSize: AppTokens.captionFontSize,
                    height: 1.5)),
          ),
        const SizedBox(height: AppTokens.s5),
        SettingsPrimaryButton(
          text: settingsText(context, zh: '完成', en: 'Done'),
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}
