import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_service.dart';
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

class _ChangeTradePasswordPageState extends State<ChangeTradePasswordPage> {
  final _old = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNext = true;
  bool _obscureConfirm = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _old.addListener(_refresh);
    _next.addListener(_refresh);
    _confirm.addListener(_refresh);
  }

  @override
  void dispose() {
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
      !_submitting &&
      _sixDigits(_old.text) &&
      _sixDigits(_next.text) &&
      _next.text.trim() == _confirm.text.trim();

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!widget.service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '修改支付密码', en: 'Change payment password'),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.service.changeTradePassword(
        oldPassword: _old.text.trim(),
        newPassword: _next.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      showSettingsMessage(
        context,
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

  void _openReset() {
    if (widget.phoneNumber.trim().isEmpty) return;
    showUnavailableSettingsAction(
      context,
      settingsText(context, zh: '短信重置支付密码', en: 'Reset payment password by SMS'),
    );
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(
            settingsText(
              context,
              zh: '请输入当前支付密码，并设置新的 6 位数字支付密码。',
              en: 'Enter your current payment password, then set a new 6-digit one.',
            ),
            style: TextStyle(color: helper, fontSize: 13, height: 1.45),
          ),
        ),
        SettingsGroup(
          margin: EdgeInsets.zero,
          children: [
            SettingsInputCell(
              label: settingsText(context, zh: '原密码', en: 'Current Password'),
              hint: settingsText(context, zh: '请输入 6 位支付密码', en: 'Enter 6 digits'),
              controller: _old,
              obscureText: _obscureOld,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              trailing: _eye(
                _obscureOld,
                () => setState(() => _obscureOld = !_obscureOld),
              ),
            ),
            SettingsInputCell(
              label: settingsText(context, zh: '新密码', en: 'New Password'),
              hint: settingsText(context, zh: '请输入新的 6 位支付密码', en: 'Enter new 6 digits'),
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
              label: settingsText(context, zh: '确认密码', en: 'Confirm Password'),
              hint: settingsText(context, zh: '请再次输入支付密码', en: 'Enter it again'),
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
        if (widget.phoneNumber.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: GestureDetector(
              onTap: _openReset,
              child: Text(
                settingsText(
                  context,
                  zh: '忘记支付密码？通过短信验证码重置',
                  en: 'Forgot your payment password? Reset it with an SMS code.',
                ),
                style: const TextStyle(
                  color: AppTokens.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              settingsText(
                context,
                zh: '未绑定手机时无法通过短信重置支付密码。',
                en: 'SMS reset is unavailable without a linked phone number.',
              ),
              style: TextStyle(color: helper, fontSize: 12, height: 1.45),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppTokens.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTokens.border(dark: dark),
                disabledForegroundColor: helper,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                _submitting
                    ? settingsText(context, zh: '提交中...', en: 'Submitting...')
                    : settingsText(context, zh: '完成', en: 'Done'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
