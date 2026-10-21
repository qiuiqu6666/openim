import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../../../widgets/auth/auth_reference.dart';
import '../../mine/settings/verification_code_result.dart';
import 'device_verification_copy.dart';
import 'widgets/device_verification_banner.dart';

/// 99chat's post-password device challenge. The login flow owns both requests;
/// this page never creates a login session or assumes verification succeeded.
class DeviceVerificationPage extends StatefulWidget {
  const DeviceVerificationPage({
    super.key,
    this.phoneMasked = '',
    this.initialPhoneNumber = '',
    this.initialAreaCode = '+86',
    this.requiresPhoneInput = false,
    this.onSendCode,
    this.onVerify,
    this.methods = const ['phone'],
    this.onMethodChanged,
  });

  final String phoneMasked;
  final String initialPhoneNumber;
  final String initialAreaCode;
  final bool requiresPhoneInput;
  final Future<VerificationCodeResult?> Function(
      String phoneNumber, String areaCode)? onSendCode;
  final Future<bool> Function(String code)? onVerify;
  final List<String> methods;
  final ValueChanged<String>? onMethodChanged;

  @override
  State<DeviceVerificationPage> createState() => _DeviceVerificationPageState();
}

class _DeviceVerificationPageState extends State<DeviceVerificationPage> {
  final _code = TextEditingController();
  late final TextEditingController _phone;
  final _codeFocus = FocusNode();
  final _phoneFocus = FocusNode();
  late String _areaCode;
  late String _observedPhone;
  bool _sending = false;
  bool _verifying = false;
  int _remaining = 0;
  int _requestVersion = 0;
  Timer? _timer;
  DateTime? _resendAt;
  late String _method;
  final _cooldowns = <String, DateTime>{};

  bool get _busy => _sending || _verifying;
  bool get _active => mounted && (ModalRoute.of(context)?.isCurrent ?? true);
  String get _phoneNumber => _phone.text.trim();
  bool get _phoneValid =>
      RegExp(r'^\d+$').hasMatch(_phoneNumber) &&
      IMUtils.isMobile(_areaCode, _phoneNumber);
  bool get _canSend =>
      !_busy &&
      _remaining == 0 &&
      (!widget.requiresPhoneInput || _phoneValid) &&
      widget.onSendCode != null;
  bool get _canVerify =>
      !_busy &&
      (!widget.requiresPhoneInput || _phoneValid) &&
      RegExp(r'^\d{6}$').hasMatch(_code.text.trim()) &&
      widget.onVerify != null;

  @override
  void initState() {
    super.initState();
    _method = widget.methods.first;
    _phone = TextEditingController(text: widget.initialPhoneNumber.trim());
    _observedPhone = _phone.text;
    _areaCode = widget.initialAreaCode;
    _phone.addListener(_phoneChanged);
    _code.addListener(_codeChanged);
  }

  @override
  void didUpdateWidget(covariant DeviceVerificationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPhoneNumber != widget.initialPhoneNumber ||
        oldWidget.initialAreaCode != widget.initialAreaCode ||
        oldWidget.requiresPhoneInput != widget.requiresPhoneInput) {
      _areaCode = widget.initialAreaCode;
      _phone.text = widget.initialPhoneNumber.trim();
      _invalidatePhone();
    }
  }

  void _codeChanged() {
    if (mounted) setState(() {});
  }

  void _phoneChanged() {
    if (!mounted) return;
    if (_observedPhone == _phoneNumber) return;
    _observedPhone = _phoneNumber;
    _invalidatePhone();
    setState(() {});
  }

  void _invalidatePhone() {
    _requestVersion++;
    _sending = false;
    _verifying = false;
    _timer?.cancel();
    _timer = null;
    _resendAt = null;
    _remaining = 0;
    _code.clear();
  }

  String get _maskedPhone {
    if (!widget.requiresPhoneInput && widget.phoneMasked.trim().isNotEmpty) {
      return widget.phoneMasked.trim();
    }
    final phone = _phoneNumber;
    if (!_phoneValid || phone.length < 8) return '';
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  Future<void> _chooseAreaCode() async {
    if (_busy || !widget.requiresPhoneInput) return;
    final version = _requestVersion;
    final area = await IMViews.showCountryCodePicker();
    if (!_active || version != _requestVersion || area == null) return;
    if (_areaCode != area) {
      setState(() {
        _areaCode = area;
        _invalidatePhone();
      });
    }
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    final duration = seconds.clamp(1, 86400);
    _resendAt = DateTime.now().add(Duration(seconds: duration));
    _cooldowns[_method] = _resendAt!;
    _remaining = duration;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final milliseconds = _resendAt!.difference(DateTime.now()).inMilliseconds;
      // The absolute deadline catches suspension; timer ticks also prevent a
      // backwards wall-clock adjustment from extending this resend interval.
      final secondsLeft =
          math.min((milliseconds / 1000).ceil(), duration - timer.tick);
      setState(() => _remaining = secondsLeft.clamp(0, 86400));
      if (_remaining == 0) timer.cancel();
    });
  }

  void _chooseMethod(String method) {
    if (_busy || method == _method) return;
    setState(() {
      _invalidatePhone();
      _method = method;
      final until = _cooldowns[method];
      if (until != null && until.isAfter(DateTime.now())) {
        _startCooldown(
            (until.difference(DateTime.now()).inMilliseconds / 1000).ceil());
      }
    });
    widget.onMethodChanged?.call(method);
  }

  Future<void> _sendCode() async {
    if (!_active || !_canSend) return;
    final version = _requestVersion;
    final phone = _phoneNumber;
    final area = _areaCode;
    setState(() => _sending = true);
    try {
      final result = await widget.onSendCode!(phone, area);
      if (!mounted ||
          !_active ||
          version != _requestVersion ||
          result == null) {
        return;
      }
      if (result.captchaVerified) {
        setState(() => _startCooldown(result.retryAfter));
      }
      final strings = DeviceVerificationCopy(context);
      if (result.sent) {
        IMViews.showToast(strings.sent);
      } else {
        IMViews.showToast(strings.sendFailed);
      }
    } catch (error) {
      if (_active && version == _requestVersion) {
        IMViews.showToast(
            HttpUtil.errorMessage(error, path: Urls.getVerificationCode));
      }
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _verify() async {
    if (!_active || !_canVerify) return;
    final version = _requestVersion;
    final code = _code.text.trim();
    FocusScope.of(context).unfocus();
    setState(() => _verifying = true);
    try {
      final verified = await widget.onVerify!(code);
      if (!mounted || !_active || version != _requestVersion || !verified) {
        return;
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (_active && version == _requestVersion) {
        IMViews.showToast(HttpUtil.errorMessage(error, path: Urls.login));
      }
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() => _verifying = false);
      }
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    _timer?.cancel();
    _phone.removeListener(_phoneChanged);
    _code.removeListener(_codeChanged);
    _phone.dispose();
    _code.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = DeviceVerificationCopy(context);
    final masked = _maskedPhone;
    return AuthFormScaffold(
      title: strings.title,
      showDivider: false,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AuthReferenceTokens.fieldGap),
      subtitle: strings.subtitle,
      backLabel: strings.back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.methods.length > 1) ...[
            Wrap(
              spacing: AuthReferenceTokens.fieldGap,
              children: [
                for (final method in widget.methods)
                  ChoiceChip(
                    label: Text(method == 'phone'
                        ? strings.phoneMethod
                        : strings.emailMethod),
                    selected: _method == method,
                    selectedColor: AuthReferenceTokens.color(
                            context, AuthReferenceTokens.brand500)
                        .withValues(alpha: 0.12),
                    checkmarkColor: AuthReferenceTokens.color(
                        context, AuthReferenceTokens.brand500),
                    onSelected: _busy ? null : (_) => _chooseMethod(method),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
              ],
            ),
            const SizedBox(height: AuthReferenceTokens.fieldGap),
          ],
          DeviceVerificationBanner(
            email: _method == 'email',
            subtitle: _method == 'email'
                ? strings.emailInstruction
                : strings.phoneInstruction,
            title: _method == 'email'
                ? strings.emailHint
                : masked.isEmpty
                    ? strings.smsHint
                    : strings.sentTo(masked),
          ),
          const SizedBox(height: AuthReferenceTokens.plainFormBannerGap),
          if (widget.requiresPhoneInput) ...[
            AuthFieldLabel(strings.phoneLabel,
                style: AuthReferenceTokens.plainFieldLabel
                    .copyWith(fontWeight: FontWeight.w400),
                padding: AuthReferenceTokens.plainFieldLabelPadding),
            AuthCompoundField(
              key: const ValueKey('device-verification-phone'),
              controller: _phone,
              focusNode: _phoneFocus,
              autofocus: false,
              enabled: !_busy,
              hint: strings.phoneHint,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 20,
              leadingWidth: AuthReferenceTokens.codeActionWidth,
              leading: AuthCountryCode(
                code: _areaCode,
                onTap: _busy ? null : _chooseAreaCode,
              ),
              showBorder: false,
              inputStyle: AuthReferenceTokens.plainFieldInput,
              hintStyle: AuthReferenceTokens.plainFieldHint,
              onFieldSubmitted: (_) => _codeFocus.requestFocus(),
            ),
            const SizedBox(height: AuthReferenceTokens.plainFormBannerGap),
          ],
          AuthFieldLabel(strings.codeLabel,
              style: AuthReferenceTokens.plainFieldLabel
                  .copyWith(fontWeight: FontWeight.w400),
              padding: AuthReferenceTokens.plainFieldLabelPadding),
          AuthCompoundField(
            key: const ValueKey('device-verification-code'),
            controller: _code,
            focusNode: _codeFocus,
            autofocus: false,
            enabled: !_busy,
            hint: strings.codeHint,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _verify(),
            showBorder: true,
            showClearButton: false,
            leadingWidth: AuthReferenceTokens.tapTarget,
            leading: Icon(Icons.mail_outline_rounded,
                size: AuthReferenceTokens.toolbarIcon,
                color: AuthReferenceTokens.color(
                    context, AuthReferenceTokens.ink400)),
            inputStyle: AuthReferenceTokens.plainFieldInput
                .copyWith(fontSize: AuthReferenceTokens.inputFontSize),
            hintStyle: AuthReferenceTokens.plainFieldHint
                .copyWith(fontSize: AuthReferenceTokens.inputFontSize),
            trailingWidth: AuthReferenceTokens.codeActionWidth -
                AuthReferenceTokens.fieldGap,
            trailing: TextButton(
              key: const ValueKey('device-verification-send'),
              onPressed: _canSend ? _sendCode : null,
              style: TextButton.styleFrom(
                foregroundColor: AuthReferenceTokens.color(
                    context, AuthReferenceTokens.brand500),
                disabledForegroundColor: AuthReferenceTokens.color(
                    context, AuthReferenceTokens.ink300),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, AuthReferenceTokens.tapTarget),
                textStyle: AuthReferenceTokens.codeAction.copyWith(
                    fontWeight: FontWeight.w500,
                    fontFamily:
                        Theme.of(context).textTheme.bodyMedium?.fontFamily),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_sending
                    ? strings.sending
                    : _remaining > 0
                        ? '${_remaining}s'
                        : strings.send),
              ),
            ),
          ),
          const SizedBox(height: AuthReferenceTokens.plainFormButtonGap),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AuthReferenceTokens.rLg),
              boxShadow: _canVerify ? AuthReferenceTokens.buttonShadow : null,
            ),
            child: AuthPrimaryButton(
              key: const ValueKey('device-verification-confirm'),
              text: strings.confirm,
              loading: _verifying,
              pill: true,
              disabledForegroundColor: AuthReferenceTokens.surface,
              disabledBackgroundColor: AuthReferenceTokens.color(
                      context, AuthReferenceTokens.brand500)
                  .withValues(alpha: .48),
              textStyle: AuthReferenceTokens.plainFormButton
                  .copyWith(fontWeight: FontWeight.w700),
              onPressed: _canVerify ? _verify : null,
            ),
          ),
          const SizedBox(height: AuthReferenceTokens.labelGap),
          Center(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                Text(strings.noCode,
                    style: AuthReferenceTokens.style(
                        context, AuthReferenceTokens.formSubtitle)),
                TextButton(
                  key: const ValueKey('device-verification-resend'),
                  onPressed: _canSend ? _sendCode : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(AuthReferenceTokens.tapTarget,
                        AuthReferenceTokens.tapTarget),
                    foregroundColor: AuthReferenceTokens.color(
                        context, AuthReferenceTokens.link),
                    disabledForegroundColor: AuthReferenceTokens.color(
                        context, AuthReferenceTokens.ink400),
                  ),
                  child: Text(strings.resend(_remaining)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
