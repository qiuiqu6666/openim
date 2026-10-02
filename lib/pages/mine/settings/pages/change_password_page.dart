import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    super.key,
    required this.service,
    this.phoneNumber = '',
  });

  final SettingsService service;
  final String phoneNumber;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  static final RegExp _passwordPattern =
      RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,}$');

  final _oldPassword = TextEditingController();
  final _smsCode = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _busy = false;

  bool get _isPhoneBound => widget.phoneNumber.trim().isNotEmpty;

  String get _boundPhoneMasked {
    final phone = widget.phoneNumber.trim();
    if (phone.length <= 7) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  bool get _confirmPasswordMismatch =>
      _confirmPassword.text.isNotEmpty &&
      _newPassword.text != _confirmPassword.text;

  bool get _canSubmit {
    if (_busy || !_passwordPattern.hasMatch(_newPassword.text) || _confirmPasswordMismatch) {
      return false;
    }
    if (_confirmPassword.text != _newPassword.text) return false;
    if (_isPhoneBound) return _smsCode.text.length == 6;
    return _oldPassword.text.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _oldPassword,
      _smsCode,
      _newPassword,
      _confirmPassword,
    ]) {
      controller.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _oldPassword.dispose();
    _smsCode.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!widget.service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '获取验证码', en: 'Get code'),
      );
      return;
    }
    await widget.service.requestPhoneCode(widget.phoneNumber.trim());
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_canSubmit) return;
    if (!widget.service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '修改密码', en: 'Change Password'),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      if (_isPhoneBound) {
        await widget.service.changePasswordWithPhoneCode(
          phone: widget.phoneNumber.trim(),
          code: _smsCode.text,
          newPassword: _newPassword.text,
        );
      } else {
        await widget.service.changePassword(
          oldPassword: _oldPassword.text,
          newPassword: _newPassword.text,
        );
      }
      if (mounted) Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final helperColor = settingsSecondaryTextColor(context);

    return SettingsScaffold(
      title: settingsText(context, zh: '修改密码', en: 'Change Password'),
      dismissKeyboardOnOutsideTap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(
            _isPhoneBound
                ? settingsText(
                    context,
                    zh: '通过短信验证码验证身份后，设置新的登录密码。',
                    en: 'Verify your identity with an SMS code, then set a new login password.',
                  )
                : settingsText(
                    context,
                    zh: '请输入旧密码和新密码，完成登录密码修改。',
                    en: 'Enter your current password and a new password to update your login password.',
                  ),
            style: TextStyle(
              color: helperColor,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
        SettingsGroup(
          margin: EdgeInsets.zero,
          children: [
            if (_isPhoneBound) ...[
              SettingsCell(
                title: settingsText(context, zh: '绑定手机号', en: 'Bound Phone Number'),
                value: _boundPhoneMasked,
                showArrow: false,
              ),
              _CodeInputRow(
                label: settingsText(context, zh: '验证码', en: 'Verification Code'),
                hint: settingsText(context, zh: '请输入验证码', en: 'Enter code'),
                controller: _smsCode,
                buttonText: settingsText(context, zh: '获取验证码', en: 'Get code'),
                onPressed: _busy ? null : _sendCode,
              ),
            ] else
              _PasswordInputRow(
                label: settingsText(context, zh: '旧密码', en: 'Current Password'),
                hint: settingsText(context, zh: '请输入旧密码', en: 'Enter current password'),
                controller: _oldPassword,
                obscureText: _obscureOld,
                onToggleObscure: () => setState(() => _obscureOld = !_obscureOld),
              ),
            _PasswordInputRow(
              label: settingsText(context, zh: '新密码', en: 'New Password'),
              hint: settingsText(
                context,
                zh: '密码需为 8 位以上英文和数字组合',
                en: 'Password must contain letters and numbers with at least 8 characters',
              ),
              controller: _newPassword,
              obscureText: _obscureNew,
              onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
            ),
            _PasswordInputRow(
              label: settingsText(context, zh: '确认密码', en: 'Confirm Password'),
              hint: settingsText(context, zh: '再次输入新密码', en: 'Confirm new password'),
              controller: _confirmPassword,
              obscureText: _obscureConfirm,
              showDivider: false,
              onToggleObscure: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _confirmPasswordMismatch
              ? Text(
                  settingsText(context, zh: '两次输入的密码不一致', en: 'Passwords do not match'),
                  style: const TextStyle(
                    color: AppTokens.danger,
                    fontSize: 12,
                    height: 1.2,
                  ),
                )
              : Text(
                  settingsText(
                    context,
                    zh: '新密码建议包含字母和数字组合。',
                    en: 'We recommend using a password that contains both letters and numbers.',
                  ),
                  style: TextStyle(color: helperColor, fontSize: 12),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: _canSubmit
                    ? AppTokens.accent
                    : settingsBorderColor(context),
                foregroundColor:
                    _canSubmit ? AppTokens.onAccent : settingsSecondaryTextColor(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _canSubmit ? _submit : null,
              child: Text(
                _busy
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

class _CodeInputRow extends StatelessWidget {
  const _CodeInputRow({
    required this.label,
    required this.hint,
    required this.buttonText,
    required this.controller,
    required this.onPressed,
  });

  final String label;
  final String hint;
  final String buttonText;
  final TextEditingController controller;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: settingsBorderColor(context), width: 0.7),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(color: settingsTextColor(context), fontSize: 16),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              cursorColor: AppTokens.accent,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: settingsSecondaryTextColor(context),
                  fontSize: 16,
                ),
                border: InputBorder.none,
                filled: false,
                isCollapsed: true,
              ),
              style: TextStyle(color: settingsTextColor(context), fontSize: 16),
            ),
          ),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: AppTokens.accent,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: Text(
              buttonText,
              style: TextStyle(
                fontSize: 15,
                color: onPressed == null
                    ? settingsSecondaryTextColor(context)
                    : AppTokens.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordInputRow extends StatelessWidget {
  const _PasswordInputRow({
    required this.label,
    required this.hint,
    required this.controller,
    required this.obscureText,
    required this.onToggleObscure,
    this.showDivider = true,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscureText;
  final bool showDivider;
  final VoidCallback onToggleObscure;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: settingsBorderColor(context),
                  width: 0.7,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(color: settingsTextColor(context), fontSize: 16),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              cursorColor: AppTokens.accent,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: settingsSecondaryTextColor(context),
                  fontSize: 16,
                ),
                border: InputBorder.none,
                filled: false,
                isCollapsed: true,
              ),
              style: TextStyle(color: settingsTextColor(context), fontSize: 16),
            ),
          ),
          IconButton(
            onPressed: onToggleObscure,
            splashRadius: 18,
            icon: Icon(
              obscureText
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
              color: settingsSecondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }
}
