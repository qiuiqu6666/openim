import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_service.dart';
import '../account_security/sms_policy_state.dart';
import 'country_code_page.dart';
import '../widgets/verification_code_flow.dart';
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

class _ChangePhonePageState extends State<ChangePhonePage>
    with SmsPolicyState<ChangePhonePage> {
  @override
  SettingsService get securityService => widget.service;
  late final TextEditingController areaCodeController;
  final oldCodeController = TextEditingController();
  final newPhoneController = TextEditingController();
  final newCodeController = TextEditingController();

  final _oldCodeFlow = VerificationCodeFlow();
  final _newCodeFlow = VerificationCodeFlow();
  VerificationCodeFlow get _codeFlow =>
      !_isBindMode && step == 1 ? _oldCodeFlow : _newCodeFlow;
  int step = 1;
  bool busy = false;

  bool get _isBindMode => !widget.isBound;
  int get _uiStep => smsExempt ? 2 : (step <= 1 ? 1 : 2);
  bool get _validNewPhone => newPhoneController.text.trim().length >= 6;
  bool get _canVerifyOld =>
      smsPolicyReady && oldCodeController.text.length == 6 && !busy;
  bool get _canBindConfirm =>
      smsPolicyReady &&
      _validNewPhone &&
      (smsExempt || newCodeController.text.length == 6) &&
      !busy;
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
    _oldCodeFlow.addListener(_refresh);
    _newCodeFlow.addListener(_refresh);
    areaCodeController =
        TextEditingController(text: widget.service.securityAreaCode);
    oldCodeController.addListener(_refresh);
    newPhoneController.addListener(_refresh);
    newCodeController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _oldCodeFlow.dispose();
    _newCodeFlow.dispose();
    areaCodeController.dispose();
    oldCodeController.dispose();
    newPhoneController.dispose();
    newCodeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode(String phone) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!widget.service.isSecurityBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '获取验证码', en: 'Get Code'),
      );
      return;
    }
    if (busy || !_codeFlow.canSend) return;
    setState(() => busy = true);
    try {
      final sent = await _codeFlow.send(context, (param) async {
        if (!_isBindMode && step == 1) {
          return widget.service
              .requestPhoneCode(phone, captchaVerifyParam: param);
        } else {
          return widget.service.requestNewPhoneCode(phone,
              captchaVerifyParam: param,
              areaCode: areaCodeController.text.trim());
        }
      });
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
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _verifyOld() async {
    if (!_canVerifyOld) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!widget.service.isSecurityBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '填写旧号验证码', en: 'Verify current phone'),
      );
      return;
    }
    setState(() => busy = true);
    try {
      if (mounted) setState(() => step = 2);
    } catch (error) {
      if (mounted) {
        showSettingsError(
            context,
            error,
            settingsText(context,
                zh: '操作失败，请检查验证码后重试', en: 'Check the codes and try again'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    if (!await refreshSmsPolicy() || !mounted || !_canConfirm) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!widget.service.isSecurityBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '修改手机号', en: 'Change Phone Number'),
      );
      return;
    }
    setState(() => busy = true);
    try {
      if (_isBindMode) {
        await widget.service.bindPhone(
            phone: newPhoneController.text.trim(),
            code: smsExempt ? '' : newCodeController.text,
            areaCode: areaCodeController.text.trim());
      } else {
        await widget.service.changePhone(
            phone: newPhoneController.text.trim(),
            oldCode: smsExempt ? '' : oldCodeController.text,
            newCode: smsExempt ? '' : newCodeController.text,
            areaCode: areaCodeController.text.trim());
      }
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(context,
            zh: _isBindMode ? '手机号绑定成功' : '手机号修改成功',
            en: _isBindMode
                ? 'Phone number linked successfully'
                : 'Phone number changed successfully'),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        showSettingsError(
            context,
            error,
            settingsText(context,
                zh: '操作失败，请检查验证码后重试', en: 'Check the codes and try again'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _selectCountry() async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) =>
            CountryCodePage(selectedCode: areaCodeController.text)));
    if (mounted && code != null) setState(() => areaCodeController.text = code);
  }

  Widget _areaCodeInput(BuildContext context) => InkWell(
        onTap: busy ? null : _selectCountry,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: AppTokens.s8 + AppTokens.s4),
          child: Row(children: [
            Flexible(
                child: Text(areaCodeController.text,
                    style: TextStyle(
                        color: AppTokens.textPrimary(
                            dark: settingsIsDark(context)),
                        fontSize: AppTokens.secondaryFontSize))),
            const Icon(Icons.expand_more_rounded, size: AppTokens.s5),
          ]),
        ),
      );

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
        smsPolicyNotice(context),
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
                hint: settingsText(context,
                    zh: '请输入手机号', en: 'Enter phone number'),
                keyboardType: TextInputType.phone,
                controller: newPhoneController,
                leadingWidth: AppTokens.listItemHeight,
                leading: _areaCodeInput(context),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(20),
                ],
              ),
              if (!smsExempt)
                _CodeCell(
                  label:
                      settingsText(context, zh: '验证码', en: 'Verification Code'),
                  hint: settingsText(context,
                      zh: '请输入验证码', en: 'Enter verification code'),
                  buttonText: _codeFlow.label(context),
                  controller: newCodeController,
                  onPressed: _validNewPhone && !busy && _codeFlow.canSend
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
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              smsExempt
                  ? settingsText(context,
                      zh: '请输入新的手机号码。', en: 'Enter your new phone number.')
                  : _uiStep == 1
                      ? settingsText(
                          context,
                          zh: '先填写当前手机的验证码，再输入新号码；提交时验证两个号码。',
                          en: 'Enter the code sent to your current phone, then enter the new number. Both are verified on submit.',
                        )
                      : settingsText(
                          context,
                          zh: '请输入新手机号和验证码，提交时验证新旧号码。',
                          en: 'Enter the new phone and code. Both codes are verified when you submit.',
                        ),
              style: TextStyle(color: helperColor, fontSize: 13, height: 1.45),
            ),
          ),
          if (!smsExempt) _StepIndicator(currentStep: _uiStep),
          if (_uiStep == 1) ...[
            _StepLabel(
              text: settingsText(
                context,
                zh: '第 1 步  填写旧号验证码',
                en: 'Step 1  Verify Current Phone Number',
              ),
            ),
            SettingsGroup(
              margin: EdgeInsets.zero,
              children: [
                SettingsCell(
                  title: settingsText(context,
                      zh: '当前手机号', en: 'Current Phone Number'),
                  value: _currentPhoneDisplay,
                  showArrow: false,
                ),
                _CodeCell(
                  label: settingsText(context, zh: '旧号验证码', en: 'Current Code'),
                  hint: settingsText(context,
                      zh: '请输入验证码', en: 'Enter verification code'),
                  buttonText: _codeFlow.label(context),
                  controller: oldCodeController,
                  onPressed: busy || !_codeFlow.canSend
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
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ] else ...[
            if (!smsExempt)
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
                  title: settingsText(context,
                      zh: '当前手机号', en: 'Current Phone Number'),
                  value: _currentPhoneDisplay,
                  showArrow: false,
                ),
                SettingsInputCell(
                  label:
                      settingsText(context, zh: '新手机号', en: 'New Phone Number'),
                  hint: settingsText(context,
                      zh: '请输入新手机号', en: 'Enter new phone number'),
                  keyboardType: TextInputType.phone,
                  controller: newPhoneController,
                  leadingWidth: AppTokens.listItemHeight,
                  leading: _areaCodeInput(context),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(20),
                  ],
                ),
                if (!smsExempt)
                  _CodeCell(
                    label: settingsText(context,
                        zh: '新号验证码', en: 'New Number Code'),
                    hint: settingsText(context,
                        zh: '请输入验证码', en: 'Enter verification code'),
                    buttonText: _codeFlow.label(context),
                    controller: newCodeController,
                    onPressed: _validNewPhone && !busy && _codeFlow.canSend
                        ? () => _sendCode(newPhoneController.text.trim())
                        : null,
                    dark: dark,
                    showDivider: false,
                  ),
              ],
            ),
            if (!smsExempt)
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
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
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
                        ? settingsText(context,
                            zh: '处理中...', en: 'Processing...')
                        : settingsText(context, zh: '完成', en: 'Done'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
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
              title: settingsText(context,
                  zh: '填写旧号验证码', en: 'Verify Current Phone'),
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
              color:
                  highlighted ? AppTokens.accent : AppTokens.border(dark: dark),
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
