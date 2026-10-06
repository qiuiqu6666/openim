import 'package:flutter/cupertino.dart';
import 'package:openim_common/openim_common.dart';

import '../../mine/settings/verification_code_result.dart';
import '../../mine/settings/widgets/aliyun_captcha_dialog.dart';
import '../../../routes/app_pages.dart';
import 'data/password_device_login_attempt.dart';
import 'device_verification_page.dart';

typedef DeviceCaptchaPresenter = Future<VerificationCodeResult?> Function(
  BuildContext context,
  Future<VerificationCodeResult> Function(String proof) request,
);

int? deviceLoginErrorCode(Object error) =>
    error is (int, String?) ? error.$1 : null;

/// Holds only this password attempt's routes, never the account's session.
class DeviceVerificationFlow {
  DeviceVerificationFlow({
    required this.attempt,
    required this.phoneNumber,
    required this.areaCode,
    required this.isCurrent,
    this.captchaPresenter,
  });

  final PasswordDeviceLoginAttempt attempt;
  final String phoneNumber;
  final String areaCode;
  final bool Function() isCurrent;
  final DeviceCaptchaPresenter? captchaPresenter;
  CupertinoPageRoute<bool>? _route;
  Route<VerificationCodeResult>? _captchaRoute;
  bool _cancelled = false;
  Object? _fatalError;
  LoginCertificate? _certificate;

  bool get _ownsAttempt => !_cancelled && isCurrent();
  bool get _ownsPage => _ownsAttempt && _route?.isCurrent == true;

  Future<LoginCertificate?> run(BuildContext context) async {
    if (!_ownsAttempt || !context.mounted) return null;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = CupertinoPageRoute<bool>(
      settings: const RouteSettings(name: AppRoutes.deviceVerification),
      builder: (pageContext) => DeviceVerificationPage(
        initialPhoneNumber: phoneNumber,
        initialAreaCode: areaCode,
        requiresPhoneInput: phoneNumber.isEmpty,
        onSendCode: (phone, area) => _send(pageContext, phone, area),
        onVerify: _verify,
      ),
    );
    _route = route;
    final verified = await navigator.push(route);
    _route = null;
    if (!_ownsAttempt) return null;
    if (_fatalError case final error?) throw error;
    return verified == true ? _certificate : null;
  }

  Future<VerificationCodeResult?> _send(
      BuildContext context, String phone, String area) async {
    if (!_ownsPage || !context.mounted) return null;
    Future<VerificationCodeResult> request(String proof) async {
      if (!_ownsAttempt) throw const DeviceVerificationCancelled();
      final result = await attempt.sendCode(
        areaCode: area,
        phoneNumber: phone,
        captchaVerifyParam: proof,
        isCurrent: () => _ownsAttempt,
      );
      if (!_ownsAttempt) throw const DeviceVerificationCancelled();
      return VerificationCodeResult(
        captchaVerified: result.captchaVerified,
        sent: result.sent,
        retryAfter: result.retryAfter,
      );
    }

    try {
      VerificationCodeResult? result;
      if (captchaPresenter != null) {
        if (!context.mounted || !_ownsPage) return null;
        result = await captchaPresenter!(context, request);
      } else {
        if (!context.mounted || !_ownsPage) return null;
        result = await showAliyunCaptcha(context, request,
            finishOnSendFailure: true,
            onRouteCreated: (route) => _captchaRoute = route);
      }
      return _ownsPage ? result : null;
    } finally {
      _captchaRoute = null;
    }
  }

  Future<bool> _verify(String code) async {
    if (!_ownsPage) return false;
    try {
      final certificate =
          await attempt.submit(verifyCode: code, isCurrent: () => _ownsAttempt);
      if (!_ownsPage) return false;
      _certificate = certificate;
      return true;
    } catch (error) {
      if (!_ownsPage) return false;
      if ({20001, 20082}.contains(deviceLoginErrorCode(error))) {
        _fatalError = error;
        _route!.navigator!.pop(false);
        return false;
      }
      rethrow;
    }
  }

  /// Remove owned routes even when the captcha temporarily covers the page.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _certificate = null;
    final captcha = _captchaRoute;
    if (captcha?.isActive == true) captcha!.navigator?.removeRoute(captcha);
    final page = _route;
    if (page?.isActive == true) page!.navigator?.removeRoute(page);
  }
}

class DeviceVerificationCancelled implements Exception {
  const DeviceVerificationCancelled();
}
