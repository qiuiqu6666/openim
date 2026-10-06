import '../../../../services/fund_models.dart';

/// Ephemeral SMS proof. Callers must not persist or log it.
class FundSecurityProof {
  const FundSecurityProof({this.challengeID, this.code, this.expiresAt});
  final String? challengeID, code;
  final int? expiresAt;
  bool get isExpired =>
      expiresAt != null && DateTime.now().millisecondsSinceEpoch >= expiresAt!;

  Map<String, dynamic> toJson() {
    if (challengeID == null && code == null) return {};
    if (challengeID == null ||
        challengeID!.trim().isEmpty ||
        code == null ||
        !RegExp(r'^\d{6}$').hasMatch(code!)) {
      throw const FormatException('请重新获取本次交易验证码');
    }
    return {'verifyChallengeID': challengeID, 'verifyCode': code};
  }
}

class FundSecurityCheck {
  const FundSecurityCheck({
    required this.smsRequired,
    required this.reasons,
    required this.blockedUntil,
    required this.phoneMasked,
    required this.currency,
    required this.smsThreshold,
    required this.cooldownHours,
  });
  final bool smsRequired;
  final List<String> reasons;
  final int blockedUntil, cooldownHours;
  final String phoneMasked, currency, smsThreshold;

  factory FundSecurityCheck.fromJson(Map<String, dynamic> json) {
    final required = json['smsRequired'];
    final reasons = json['reasons'];
    if (required is! bool ||
        reasons is! List ||
        reasons.any((value) => value is! String)) {
      throw const FormatException('安全验证信息不完整');
    }
    final currency = _string(json, 'currency');
    final threshold = _string(json, 'smsThreshold');
    final parsed = FundAmount.parse(threshold, FundCurrency.parse(currency));
    if (parsed.units.isNegative) {
      throw const FormatException('安全验证信息不完整');
    }
    return FundSecurityCheck(
      smsRequired: required,
      reasons: List<String>.unmodifiable(reasons.cast<String>()),
      blockedUntil: _integer(json, 'blockedUntil'),
      phoneMasked: _string(json, 'phoneMasked'),
      currency: currency,
      smsThreshold: threshold,
      cooldownHours: _integer(json, 'cooldownHours'),
    );
  }
}

class FundSecurityChallenge {
  const FundSecurityChallenge({
    required this.challengeID,
    required this.expiresAt,
    required this.retryAfterSeconds,
    required this.phoneMasked,
  });
  final String challengeID, phoneMasked;
  final int expiresAt, retryAfterSeconds;

  factory FundSecurityChallenge.fromJson(Map<String, dynamic> json) {
    final challengeID = _string(json, 'challengeID');
    final phone = _string(json, 'phoneMasked');
    final expires = _integer(json, 'expiresAt');
    if (challengeID.trim().isEmpty || phone.trim().isEmpty || expires == 0) {
      throw const FormatException('短信验证信息不完整');
    }
    return FundSecurityChallenge(
      challengeID: challengeID,
      expiresAt: expires,
      retryAfterSeconds: _integer(json, 'retryAfterSeconds'),
      phoneMasked: phone,
    );
  }
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw const FormatException('安全验证信息不完整');
  return value;
}

int _integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw const FormatException('安全验证信息不完整');
  }
  return value;
}
