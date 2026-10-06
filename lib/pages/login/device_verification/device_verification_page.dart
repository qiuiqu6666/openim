import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../../../widgets/auth/auth_reference.dart';
import '../../mine/settings/verification_code_result.dart';
import 'device_verification_copy.dart';

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
  });

  final String phoneMasked;
  final String initialPhoneNumber;
  final String initialAreaCode;
  final bool requiresPhoneInput;
  final Future<VerificationCodeResult?> Function(
      String phoneNumber, String areaCode)? onSendCode;
  final Future<bool> Function(String code)? onVerify;

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
  bool _busy = false;
  int _remaining = 0;
  int _requestVersion = 0;
  Timer? _timer;
  DateTime? _resendAt;

  bool get _active => mounted && (ModalRoute.of(context)?.isCurrent ?? true);
  String get _phoneNumber => _phone.text.trim();
  bool get _phoneValid =>
      RegExp(r'^\d+$').hasMatch(_phoneNumber) &&
      IMUtils.isMobile(_areaCode, _phoneNumber);
  bool get _canSend =>
      !_busy && _remaining == 0 && _phoneValid && widget.onSendCode != null;
  bool get _canVerify =>
      !_busy &&
      _phoneValid &&
      RegExp(r'^\d{6}$').hasMatch(_code.text.trim()) &&
      widget.onVerify != null;

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: widget.initialPhoneNumber.trim());
    _observedPhone = _phone.text;
    _areaCode = widget.initialAreaCode;
    _phone.addListener(_phoneChanged);
    _code.addListener(_codeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_active) return;
      final node = widget.requiresPhoneInput ? _phoneFocus : _codeFocus;
      if (node.canRequestFocus) node.requestFocus();
    });
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
    _busy = false;
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

  Future<void> _sendCode() async {
    if (!_active || !_canSend) return;
    final version = _requestVersion;
    final phone = _phoneNumber;
    final area = _areaCode;
    setState(() => _busy = true);
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
      } else if (result.captchaVerified) {
        IMViews.showToast(strings.sendFailed);
      }
    } catch (error) {
      if (_active && version == _requestVersion) {
        IMViews.showToast(
            HttpUtil.errorMessage(error, path: Urls.getVerificationCode));
      }
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _verify() async {
    if (!_active || !_canVerify) return;
    final version = _requestVersion;
    final code = _code.text.trim();
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
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
        setState(() => _busy = false);
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
      subtitle: strings.subtitle,
      backLabel: strings.back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthInfoBanner(
            icon: Icons.shield_outlined,
            text: masked.isEmpty ? strings.smsHint : strings.sentTo(masked),
          ),
          const SizedBox(height: AuthReferenceTokens.plainFormBannerGap),
          if (widget.requiresPhoneInput) ...[
            AuthFieldLabel(strings.phoneLabel,
                style: AuthReferenceTokens.plainFieldLabel,
                padding: AuthReferenceTokens.plainFieldLabelPadding),
            AuthCompoundField(
              key: const ValueKey('device-verification-phone'),
              controller: _phone,
              focusNode: _phoneFocus,
              autofocus: true,
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
              style: AuthReferenceTokens.plainFieldLabel,
              padding: AuthReferenceTokens.plainFieldLabelPadding),
          AuthCompoundField(
            key: const ValueKey('device-verification-code'),
            controller: _code,
            focusNode: _codeFocus,
            autofocus: !widget.requiresPhoneInput,
            enabled: !_busy,
            hint: strings.codeHint,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _verify(),
            showBorder: false,
            inputStyle: AuthReferenceTokens.plainFieldInput,
            hintStyle: AuthReferenceTokens.plainFieldHint,
            trailingWidth: AuthReferenceTokens.codeActionWidth,
            trailing: TextButton(
              key: const ValueKey('device-verification-send'),
              onPressed: _canSend ? _sendCode : null,
              style: TextButton.styleFrom(
                foregroundColor: AuthReferenceTokens.brand500,
                disabledForegroundColor: AuthReferenceTokens.ink300,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, AuthReferenceTokens.tapTarget),
                textStyle: AuthReferenceTokens.codeAction.copyWith(
                    fontFamily:
                        Theme.of(context).textTheme.bodyMedium?.fontFamily),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_remaining > 0 ? '${_remaining}s' : strings.send),
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
              loading: _busy,
              pill: true,
              disabledForegroundColor: AuthReferenceTokens.surface,
              textStyle: AuthReferenceTokens.plainFormButton,
              onPressed: _canVerify ? _verify : null,
            ),
          ),
        ],
      ),
    );
  }
}
