enum DesktopAuthorizationState { scanned, approved, active, expired, cancelled }

class DesktopAuthorization {
  const DesktopAuthorization(
      {required this.deviceName,
      required this.platform,
      required this.expiresAt,
      required this.state,
      this.region = '',
      this.code = ''});
  final String deviceName, platform, region, code;
  final DateTime expiresAt;
  final DesktopAuthorizationState state;
}

/// Public identifier only. Never accept an API URL or credentials from a QR.
String? parseDesktopLoginQr(String source) {
  return RegExp(r'^99chat-login:v1:([A-Za-z0-9_-]{43})$')
      .firstMatch(source)
      ?.group(1);
}

abstract interface class DesktopAuthorizationService {
  Future<DesktopAuthorization> scan(String requestId);
  Future<DesktopAuthorization> confirm(String requestId,
      {String verificationCode = ''});
  Future<DesktopAuthorization> status(String requestId);
  Future<void> cancel(String requestId);
}

class DesktopAuthorizationUnavailable implements Exception {
  const DesktopAuthorizationUnavailable();
}

/// No speculative endpoints: replace this adapter after the backend contract
/// is verified. Production must never simulate approval or activation.
class UnavailableDesktopAuthorizationService
    implements DesktopAuthorizationService {
  const UnavailableDesktopAuthorizationService();
  @override
  Future<DesktopAuthorization> scan(String id) async =>
      throw const DesktopAuthorizationUnavailable();
  @override
  Future<DesktopAuthorization> confirm(String id,
          {String verificationCode = ''}) async =>
      throw const DesktopAuthorizationUnavailable();
  @override
  Future<DesktopAuthorization> status(String id) async =>
      throw const DesktopAuthorizationUnavailable();
  @override
  Future<void> cancel(String id) async =>
      throw const DesktopAuthorizationUnavailable();
}
