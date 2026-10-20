import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';
import '../../../../../widgets/auth/auth_copy.dart';
import '../../../../../widgets/auth/auth_form_rules.dart';
import '../../../../../widgets/auth/auth_reference.dart';
import '../../widgets/aliyun_captcha_dialog.dart';
import '../../widgets/settings_widgets.dart';
import 'email_account_service.dart';
import 'email_input_cell.dart';

class EmailAccountPage extends StatefulWidget {
  const EmailAccountPage({super.key, this.service});
  final EmailAccountService? service;
  @override
  State<EmailAccountPage> createState() => _EmailAccountPageState();
}

class _EmailAccountPageState extends State<EmailAccountPage> {
  late final EmailAccountService _service;
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _oldCode = TextEditingController();
  final _password = TextEditingController();
  String? _current;
  String? _error;
  bool _busy = false;
  bool _loading = true;
  bool _submitted = false;
  bool _obscure = true;
  bool get _changing => _current?.isNotEmpty == true;
  bool get _active => mounted && _service.isCurrent;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? OpenIMEmailAccountService();
    for (final controller in [_email, _code, _oldCode, _password]) {
      controller.addListener(_edited);
    }
    _load();
  }

  void _edited() {
    if (mounted && !_busy) setState(() => _error = null);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = await _service.load();
      if (_active) setState(() => _current = email);
    } catch (error) {
      if (mounted) setState(() => _error = HttpUtil.errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _send(bool old) async {
    if (!_active || _busy || _current == null) return false;
    if (!old && AuthFormRules.email(_email.text) != null) {
      setState(() => _submitted = true);
      return false;
    }
    final email = old ? _current! : _email.text.trim().toLowerCase();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await showAliyunCaptcha(context, (captcha) async {
        if (!_active) throw StateError('Account session changed');
        return _service.send(email,
            old ? 'change_old' : (_changing ? 'change_new' : 'bind'), captcha);
      });
      if (!mounted || !_service.isCurrent) return false;
      if (result?.sent == true) {
        showSettingsMessage(
            context, authText('验证码已发送，请查收邮件', 'Code sent. Check your email.'));
      }
      return result?.sent == true;
    } catch (error) {
      if (mounted) setState(() => _error = HttpUtil.errorMessage(error));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_active || _busy || _current == null) return;
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (AuthFormRules.email(_email.text) != null ||
        AuthFormRules.verificationCode(_code.text, sixDigits: true) != null ||
        (_changing
            ? AuthFormRules.verificationCode(_oldCode.text, sixDigits: true) !=
                null
            : AuthFormRules.loginPassword(_password.text) != null)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await _service.save(
          changing: _changing,
          email: _email.text,
          code: _code.text,
          oldCode: _oldCode.text,
          password: _password.text);
      if (!mounted || !_service.isCurrent) return;
      showSettingsMessage(context, authText('邮箱保存成功', 'Email saved'));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = HttpUtil.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _oldCode.dispose();
    _password.dispose();
    super.dispose();
  }

  Widget _codeField(bool old) => EmailInputCell(
        label: old
            ? authText('旧邮箱验证码', 'Current email code')
            : authText('邮箱验证码', 'Email code'),
        controller: old ? _oldCode : _code,
        enabled: !_busy,
        hint: authText('6 位邮箱验证码', '6-digit email code'),
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6)
        ],
        autofillHints: const [AutofillHints.oneTimeCode],
        errorText: _submitted
            ? AuthFormRules.verificationCode((old ? _oldCode : _code).text,
                sixDigits: true)
            : null,
        showDivider: old,
        trailing: AuthCodeAction(enabled: !_busy, onSend: () => _send(old)),
      );

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: authText(_changing ? '修改邮箱' : '绑定邮箱',
            _changing ? 'Change Email' : 'Link Email'),
        dismissKeyboardOnOutsideTap: true,
        children: [
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _current == null)
            TextButton(
                onPressed: _load, child: Text(authText('重新加载', 'Retry'))),
          if (!_loading && _current != null)
            AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppTokens.s4, 14, AppTokens.s4, 10),
                    child: Text(
                      authText('绑定邮箱后，可用于登录、找回密码及按隐私设置搜索添加好友。',
                          'Link an email to log in, recover your password, and be found according to your privacy settings.'),
                      style: TextStyle(
                          color: AppTokens.textSecondary(
                              dark: settingsIsDark(context)),
                          fontSize: 13,
                          height: 1.45),
                    ),
                  ),
                  SettingsGroup(
                    margin: EdgeInsets.zero,
                    children: [
                      if (_changing) ...[
                        SettingsCell(
                            title: authText('当前邮箱', 'Current email'),
                            value: _current!,
                            showArrow: false),
                        _codeField(true),
                      ] else
                        EmailInputCell(
                          label: authText('登录密码', 'Login password'),
                          hint: authText('请输入登录密码', 'Enter login password'),
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          errorText: _submitted
                              ? AuthFormRules.loginPassword(_password.text)
                              : null,
                          trailing: IconButton(
                            tooltip: authText(_obscure ? '显示密码' : '隐藏密码',
                                _obscure ? 'Show password' : 'Hide password'),
                            onPressed: _busy
                                ? null
                                : () => setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                      EmailInputCell(
                        label: authText('新邮箱', 'New email'),
                        hint: authText('请输入邮箱地址', 'Enter email address'),
                        controller: _email,
                        onChanged: (_) => _code.clear(),
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        errorText: _submitted
                            ? AuthFormRules.email(_email.text)
                            : null,
                      ),
                      _codeField(false),
                    ],
                  ),
                  if (_changing)
                    Padding(
                      padding: const EdgeInsets.all(AppTokens.s4),
                      child: Text(
                          authText('旧邮箱无法接收验证码时，请联系客服核实身份。',
                              'If you cannot access your current email, contact support to verify your identity.'),
                          style: TextStyle(
                              color: AppTokens.textSecondary(
                                  dark: settingsIsDark(context)),
                              fontSize: 13,
                              height: 1.45)),
                    ),
                  SettingsPrimaryButton(
                    text: authText(_changing ? '完成修改' : '完成绑定',
                        _changing ? 'Change Email' : 'Link Email'),
                    loading: _busy,
                    padding: const EdgeInsets.fromLTRB(
                        AppTokens.s4, AppTokens.s6, AppTokens.s4, 0),
                    borderRadius: 10,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppTokens.s5),
              child: Semantics(
                  liveRegion: true, child: AuthFormMessage(text: _error)),
            ),
        ],
      );
}
