class VerificationCodeResult {
  const VerificationCodeResult(
      {required this.captchaVerified,
      required this.sent,
      this.retryAfter = 60});
  final bool captchaVerified;
  final bool sent;
  final int retryAfter;
  factory VerificationCodeResult.fromJson(dynamic data) {
    if (data is! Map ||
        data['captchaVerifyResult'] is! bool ||
        data['bizResult'] is! bool) {
      throw const FormatException('Invalid verification response');
    }
    final captcha = data['captchaVerifyResult'] == true;
    final biz = data['bizResult'] == true;
    if (biz && !captcha) {
      throw const FormatException('Invalid verification result');
    }
    final retry = data['retryAfter'];
    if (retry != null && (retry is! int || retry < 1 || retry > 86400)) {
      throw const FormatException('Invalid resend interval');
    }
    return VerificationCodeResult(
        captchaVerified: captcha,
        sent: captcha && biz,
        retryAfter: retry is int ? retry : 60);
  }
  Map<String, bool> get sdkResult =>
      {'captchaResult': captchaVerified, 'bizResult': sent};
}
