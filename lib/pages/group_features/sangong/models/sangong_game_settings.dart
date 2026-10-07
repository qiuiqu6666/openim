/// The editable rules used by the Go settlement engine. Payout is fixed at
/// 1:1; only the banker pays rake on total player stakes, rounded down.
class SangongGameSettings {
  const SangongGameSettings({
    required this.doorCount,
    required this.minBet,
    required this.maxBet,
    required this.rakePercent,
  });

  final int doorCount;
  final int minBet;
  final int maxBet;
  final int rakePercent;
  static const int maxMaxBet = 99999999;
  bool get maxBetUnlimited => maxBet == 0;

  factory SangongGameSettings.defaults() => const SangongGameSettings(
      doorCount: 6, minBet: 0, maxBet: 99999999, rakePercent: 6);

  factory SangongGameSettings.fromJson(Map<String, dynamic> json) {
    int requiredInt(String key) {
      final value = json[key];
      if (value is! int) throw FormatException('Invalid game rule: $key');
      return value;
    }

    final rules = SangongGameSettings(
      doorCount: requiredInt('doorCount'),
      minBet: requiredInt('minBet'),
      maxBet: requiredInt('maxBet'),
      rakePercent: requiredInt('rakePercent'),
    );
    if (!rules.isValid) throw const FormatException('Invalid game rules');
    return rules;
  }

  bool get isValid =>
      doorCount >= 2 &&
      doorCount <= 10 &&
      minBet >= 0 &&
      maxBet >= 0 &&
      (maxBet == 0 || maxBet >= minBet) &&
      rakePercent >= 0 &&
      rakePercent <= 100;

  Map<String, dynamic> toJson() => {
        'doorCount': doorCount,
        'minBet': minBet,
        'maxBet': maxBet,
        'rakePercent': rakePercent,
      };

  SangongGameSettings copyWith(
          {int? doorCount, int? minBet, int? maxBet, int? rakePercent}) =>
      SangongGameSettings(
        doorCount: doorCount ?? this.doorCount,
        minBet: minBet ?? this.minBet,
        maxBet: maxBet ?? this.maxBet,
        rakePercent: rakePercent ?? this.rakePercent,
      );
}
