import 'package:flutter/cupertino.dart';
import 'package:openim_common/openim_common.dart';

import '../../mine/settings/verification_code_result.dart';
import '../../../routes/app_pages.dart';
import '../../../routes/swipe_back/app_page_route.dart';
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
  AppMaterialPageRoute<bool>? _route;
  bool _cancelled = false;
  String _method = "phone";
  Object? _fatalError;
  LoginCertificate? _certificate;

  bool get _ownsAttempt => !_cancelled && isCurrent();
  bool get _ownsPage => _ownsAttempt && _route?.isCurrent == true;

  Future<LoginCertificate?> run(BuildContext context) async {
    if (!_ownsAttempt || !context.mounted) return null;
    final methods = await attempt.methods(isCurrent: () => _ownsAttempt);
    if (!_ownsAttempt || !context.mounted) return null;
    if (methods.isEmpty) {
      return attempt.submit(isCurrent: () => _ownsAttempt);
    }
    _method = methods.first;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = AppMaterialPageRoute<bool>(
      settings: const RouteSettings(name: AppRoutes.deviceVerification),
      builder: (pageContext) => DeviceVerificationPage(
        methods: methods,
        onMethodChanged: (method) => _method = method,
        initialPhoneNumber: phoneNumber,
        initialAreaCode: areaCode,
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
    final result = await attempt.sendCode(
      method: _method,
      areaCode: area,
      phoneNumber: phone,
      isCurrent: () => _ownsAttempt,
    );
    if (!_ownsPage) return null;
    return VerificationCodeResult(
      captchaVerified: result.captchaVerified,
      sent: result.sent,
      retryAfter: result.retryAfter,
    );
  }

  Future<bool> _verify(String code) async {
    if (!_ownsPage) return false;
    try {
      final certificate = await attempt.submit(
          verifyCode: code, method: _method, isCurrent: () => _ownsAttempt);
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

  /// Remove the route owned by this login attempt.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _certificate = null;
    final page = _route;
    if (page?.isActive == true) page!.navigator?.removeRoute(page);
  }
}

class DeviceVerificationCancelled implements Exception {
  const DeviceVerificationCancelled();
}
