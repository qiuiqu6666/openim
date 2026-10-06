/// The device-login SMS response treats missing proof flags as unsuccessful.
/// This contract is intentionally separate from existing account-code pages.
class DeviceVerificationCodeResult {
  const DeviceVerificationCodeResult({
    required this.captchaVerified,
    required this.sent,
    this.retryAfter = 60,
  });

  final bool captchaVerified;
  final bool sent;
  final int retryAfter;

  factory DeviceVerificationCodeResult.fromJson(dynamic data) {
    if (data is! Map) {
      throw const FormatException('Invalid device verification response');
    }
    final captcha = data['captchaVerifyResult'] == true;
    final sent = captcha && data['bizResult'] == true;
    final retry = data['retryAfter'];
    if (retry != null && (retry is! int || retry < 0 || retry > 86400)) {
      throw const FormatException('Invalid device verification interval');
    }
    return DeviceVerificationCodeResult(
      captchaVerified: captcha,
      sent: sent,
      retryAfter: retry is int ? retry : 60,
    );
  }

  @override
  String toString() =>
      'DeviceVerificationCodeResult(sent: $sent, retryAfter: $retryAfter)';
}
