import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

class ChangePhonePage extends StatefulWidget {
  const ChangePhonePage({
    super.key,
    required this.service,
    this.isBound = false,
    this.currentPhone = '',
    this.embedded = false,
  });

  final SettingsService service;
  final bool isBound;
  final String currentPhone;
  final bool embedded;

  @override
  State<ChangePhonePage> createState() => _ChangePhonePageState();
}

class _ChangePhonePageState extends State<ChangePhonePage> {
  final oldCodeController = TextEditingController();
  final newPhoneController = TextEditingController();
  final newCodeController = TextEditingController();

  int step = 1;
  bool busy = false;

  bool get _isBindMode => !widget.isBound;
  int get _uiStep => step <= 1 ? 1 : 2;
  bool get _validNewPhone => newPhoneController.text.trim().length >= 6;
  bool get _canVerifyOld => oldCodeController.text.length == 6 && !busy;
  bool get _canBindConfirm =>
      _validNewPhone && newCodeController.text.length == 6 && !busy;
  bool get _canConfirm => _canBindConfirm;

  String get _currentPhoneDisplay {
    final phone = widget.currentPhone.trim();
    if (phone.isEmpty) return '';
    if (phone.length <= 7) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  @override
  void initState() {
    super.initState();
    oldCodeController.addListener(_refresh);
    newPhoneController.addListener(_refresh);
    newCodeController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    oldCodeController.dispose();
    newPhoneController.dispose();
    newCodeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode(String phone) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!widget.service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '获取验证码', en: 'Get Code'),
      );
      return;
    }
    await widget.service.requestPhoneCode(phone);
  }

  Future<void> _verifyOld() async {
    if (!_canVerifyOld) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!widget.service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '验证当前手机号', en: 'Verify current phone'),
      );
      return;
    }
    setState(() => busy = true);
    try {
      await widget.service.verifyCurrentPhoneCode(
        phone: widget.currentPhone.trim(),
        code: oldCodeController.text.trim(),
      );
      if (mounted) setState(() => step = 2);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!widget.service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '修改手机号', en: 'Change Phone Number'),
      );
      return;
    }
    setState(() => busy = true);
    try {
      await widget.service.bindPhone(
        phone: newPhoneController.text.trim(),
        code: newCodeController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _bindConfirm() async => _confirm();

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final helperColor = AppTokens.textSecondary(dark: dark);

    return SettingsScaffold(
      title: _isBindMode
          ? settingsText(context, zh: '绑定手机号', en: 'Link Phone Number')
          : settingsText(context, zh: '修改手机号', en: 'Change Phone Number'),
      embedded: widget.embedded,
      dismissKeyboardOnOutsideTap: true,
      children: [
        if (_isBindMode) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              settingsText(
                context,
                zh: '绑定手机号后，可使用修改密码、支付密码等功能。',
                en: 'After linking a phone number, you can change your password and set a payment password.',
              ),
              style: TextStyle(color: helperColor, fontSize: 13, height: 1.45),
            ),
          ),
          SettingsGroup(
            margin: EdgeInsets.zero,
            children: [
              SettingsInputCell(
                label: settingsText(context, zh: '手机号', en: 'Phone Number'),
                hint: settingsText(context, zh: '请输入手机号', en: 'Enter phone number'),
                keyboardType: TextInputType.phone,
                controller: newPhoneController,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(20),
                ],
              ),
              _CodeCell(
                label: settingsText(context, zh: '验证码', en: 'Verification Code'),
                hint: settingsText(context, zh: '请输入验证码', en: 'Enter verification code'),
                buttonText: settingsText(context, zh: '获取验证码', en: 'Get Code'),
                controller: newCodeController,
                onPressed: _validNewPhone
                    ? () => _sendCode(newPhoneController.text.trim())
                    : null,
                dark: dark,
                showDivider: false,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: _buttonStyle(context, _canBindConfirm),
                onPressed: _canBindConfirm ? _bindConfirm : null,
                child: Text(
                  busy
                      ? settingsText(context, zh: '处理中...', en: 'Processing...')
                      : settingsText(context, zh: '完成绑定', en: 'Link Phone'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              _uiStep == 1
                  ? settingsText(
                      context,
                      zh: '先验证当前绑定手机号，再进入下一步绑定新手机号。',
                      en: 'Verify your current phone number first, then proceed to bind a new one.',
                    )
                  : settingsText(
                      context,
                      zh: '当前手机号已验证，请绑定新的手机号并完成验证。',
                      en: 'Your current phone number has been verified. Please bind and verify a new number.',
                    ),
              style: TextStyle(color: helperColor, fontSize: 13, height: 1.45),
            ),
          ),
          _StepIndicator(currentStep: _uiStep),
          if (_uiStep == 1) ...[
            _StepLabel(
              text: settingsText(
                context,
                zh: '第 1 步  验证当前手机号',
                en: 'Step 1  Verify Current Phone Number',
              ),
            ),
            SettingsGroup(
              margin: EdgeInsets.zero,
              children: [
                SettingsCell(
                  title: settingsText(context, zh: '当前手机号', en: 'Current Phone Number'),
                  value: _currentPhoneDisplay,
                  showArrow: false,
                ),
                _CodeCell(
                  label: settingsText(context, zh: '旧号验证码', en: 'Current Code'),
                  hint: settingsText(context, zh: '请输入验证码', en: 'Enter verification code'),
                  buttonText: settingsText(context, zh: '获取验证码', en: 'Get Code'),
                  controller: oldCodeController,
                  onPressed: busy
                      ? null
                      : () => _sendCode(widget.currentPhone.trim()),
                  dark: dark,
                  showDivider: false,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: _buttonStyle(context, _canVerifyOld),
                  onPressed: _canVerifyOld ? _verifyOld : null,
                  child: Text(
                    settingsText(context, zh: '下一步', en: 'Next'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ] else ...[
            _StepLabel(
              text: settingsText(
                context,
                zh: '第 2 步  绑定新手机号',
                en: 'Step 2  Bind New Phone Number',
              ),
            ),
            SettingsGroup(
              margin: EdgeInsets.zero,
              children: [
                SettingsCell(
                  title: settingsText(context, zh: '当前手机号', en: 'Current Phone Number'),
                  value: _currentPhoneDisplay,
                  showArrow: false,
                ),
                SettingsInputCell(
                  label: settingsText(context, zh: '新手机号', en: 'New Phone Number'),
                  hint: settingsText(context, zh: '请输入新手机号', en: 'Enter new phone number'),
                  keyboardType: TextInputType.phone,
                  controller: newPhoneController,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(20),
                  ],
                ),
                _CodeCell(
                  label: settingsText(context, zh: '新号验证码', en: 'New Number Code'),
                  hint: settingsText(context, zh: '请输入验证码', en: 'Enter verification code'),
                  buttonText: settingsText(context, zh: '获取验证码', en: 'Get Code'),
                  controller: newCodeController,
                  onPressed: _validNewPhone
                      ? () => _sendCode(newPhoneController.text.trim())
                      : null,
                  dark: dark,
                  showDivider: false,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: busy ? null : () => setState(() => step = 1),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTokens.accent,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    settingsText(context, zh: '返回上一步', en: 'Back'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: _buttonStyle(context, _canConfirm),
                  onPressed: _canConfirm ? _confirm : null,
                  child: Text(
                    busy
                        ? settingsText(context, zh: '处理中...', en: 'Processing...')
                        : settingsText(context, zh: '完成', en: 'Done'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  ButtonStyle _buttonStyle(BuildContext context, bool enabled) {
    final dark = settingsIsDark(context);
    return ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor:
          enabled ? AppTokens.accent : AppTokens.border(dark: dark),
      foregroundColor:
          enabled ? Colors.white : AppTokens.textSecondary(dark: dark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}

class _CodeCell extends StatelessWidget {
  const _CodeCell({
    required this.label,
    required this.hint,
    required this.buttonText,
    required this.controller,
    required this.onPressed,
    required this.dark,
    this.showDivider = true,
  });

  final String label;
  final String hint;
  final String buttonText;
  final TextEditingController controller;
  final VoidCallback? onPressed;
  final bool dark;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  bottom: BorderSide(
                    color: AppTokens.border(dark: dark),
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
                style: TextStyle(
                  color: AppTokens.textPrimary(dark: dark),
                  fontSize: 16,
                ),
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
                  border: InputBorder.none,
                  filled: false,
                  isCollapsed: true,
                  hintStyle: TextStyle(
                    color: AppTokens.textSecondary(dark: dark),
                    fontSize: 16,
                  ),
                ),
                style: TextStyle(
                  color: AppTokens.textPrimary(dark: dark),
                  fontSize: 16,
                ),
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
                      ? AppTokens.textSecondary(dark: dark)
                      : AppTokens.accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Text(
        text,
        style: TextStyle(
          color: AppTokens.textSecondary(dark: dark),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep});
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTokens.surface(dark: dark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.border(dark: dark), width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StepIndicatorItem(
              index: 1,
              title: settingsText(context, zh: '验证当前手机号', en: 'Verify Current Phone'),
              active: currentStep == 1,
              done: currentStep > 1,
            ),
          ),
          Container(
            width: 26,
            height: 1,
            color: currentStep > 1
                ? AppTokens.accent.withValues(alpha: 0.35)
                : AppTokens.border(dark: dark),
          ),
          Expanded(
            child: _StepIndicatorItem(
              index: 2,
              title: settingsText(context, zh: '绑定新手机号', en: 'Bind New Phone'),
              active: currentStep == 2,
              done: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIndicatorItem extends StatelessWidget {
  const _StepIndicatorItem({
    required this.index,
    required this.title,
    required this.active,
    required this.done,
  });

  final int index;
  final String title;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final highlighted = active || done;
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: highlighted ? AppTokens.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted ? AppTokens.accent : AppTokens.border(dark: dark),
            ),
          ),
          child: Text(
            '$index',
            style: TextStyle(
              color: highlighted
                  ? Colors.white
                  : AppTokens.textSecondary(dark: dark),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: highlighted
                  ? AppTokens.textPrimary(dark: dark)
                  : AppTokens.textSecondary(dark: dark),
              fontSize: 14,
              fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
