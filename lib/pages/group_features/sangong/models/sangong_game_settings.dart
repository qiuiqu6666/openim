// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
class SangongHandRule {
  const SangongHandRule({
    required this.label,
    required this.odds,
    required this.bankerRakePoints,
    required this.playerRakePoints,
  });

  final String label;
  final double odds;
  final int bankerRakePoints;
  final int playerRakePoints;

  factory SangongHandRule.fromJson(Map<String, dynamic> json) {
    return SangongHandRule(
      label: json['label']?.toString() ?? '',
      odds: _readDouble(json['odds'], fallback: 1.0),
      bankerRakePoints: _readBankerRake(json),
      playerRakePoints: _readInt(
        json['playerRakePoints'] ?? json['player_rake_points'],
        fallback: 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        if (label.trim().isNotEmpty) 'label': label.trim(),
        'odds': odds,
        'bankerRakePoints': bankerRakePoints,
        'playerRakePoints': playerRakePoints,
      };

  SangongHandRule copyWith({
    String? label,
    double? odds,
    int? bankerRakePoints,
    int? playerRakePoints,
  }) {
    return SangongHandRule(
      label: label ?? this.label,
      odds: odds ?? this.odds,
      bankerRakePoints: bankerRakePoints ?? this.bankerRakePoints,
      playerRakePoints: playerRakePoints ?? this.playerRakePoints,
    );
  }
}

class SangongPointRule extends SangongHandRule {
  const SangongPointRule({
    required this.point,
    required super.label,
    required super.odds,
    required super.bankerRakePoints,
    required super.playerRakePoints,
  });

  final int point;

  factory SangongPointRule.fromJson(Map<String, dynamic> json) {
    final point = _readInt(json['point'], fallback: 0);
    final label = json['label']?.toString().trim();
    return SangongPointRule(
      point: point,
      label: label != null && label.isNotEmpty ? label : '$point点',
      odds: _readDouble(json['odds'], fallback: 1.0),
      bankerRakePoints: _readBankerRake(json, fallback: 6),
      playerRakePoints: _readInt(
        json['playerRakePoints'] ?? json['player_rake_points'],
        fallback: point == 9 ? 2 : 0,
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'point': point,
        if (label.trim().isNotEmpty) 'label': label.trim(),
        'odds': odds,
        'bankerRakePoints': bankerRakePoints,
        'playerRakePoints': playerRakePoints,
      };

  @override
  SangongPointRule copyWith({
    String? label,
    double? odds,
    int? bankerRakePoints,
    int? playerRakePoints,
  }) {
    return SangongPointRule(
      point: point,
      label: label ?? this.label,
      odds: odds ?? this.odds,
      bankerRakePoints: bankerRakePoints ?? this.bankerRakePoints,
      playerRakePoints: playerRakePoints ?? this.playerRakePoints,
    );
  }
}

class SangongGameSettings {
  const SangongGameSettings({
    required this.doorCount,
    required this.minBet,
    required this.maxBet,
    required this.points,
    required this.pair,
    required this.maxHand,
    this.imGroupGameId = '',
    this.imGroupAdminStatsId = '',
    this.imBotUserId = '',
  });

  final int doorCount;
  final int minBet;
  final int maxBet;
  final List<SangongPointRule> points;
  final SangongHandRule pair;
  final SangongHandRule maxHand;
  final String imGroupGameId;
  final String imGroupAdminStatsId;
  final String imBotUserId;

  /// 服务端允许配置的单注上限最大值。
  static const int maxMaxBet = 99999999;

  /// `maxBet == 0` 表示不限制单注上限。
  bool get maxBetUnlimited => maxBet == 0;

  static List<SangongPointRule> defaultPoints() {
    return List<SangongPointRule>.generate(
      10,
      (index) => SangongPointRule(
        point: index,
        label: '$index点',
        odds: index == 9 ? 1.2 : 1.0,
        bankerRakePoints: index == 9 ? 5 : 6,
        playerRakePoints: index == 9 ? 2 : 0,
      ),
    );
  }

  factory SangongGameSettings.defaults() {
    return SangongGameSettings(
      doorCount: 6,
      minBet: 20,
      maxBet: 80000,
      points: defaultPoints(),
      pair: const SangongHandRule(
        label: '对子',
        odds: 1.5,
        bankerRakePoints: 5,
        playerRakePoints: 0,
      ),
      maxHand: const SangongHandRule(
        label: '1.00',
        odds: 1.0,
        bankerRakePoints: 8,
        playerRakePoints: 0,
      ),
    );
  }

  factory SangongGameSettings.fromJson(Map<String, dynamic> json) {
    final defaults = SangongGameSettings.defaults();
    final rawPoints = json['points'];
    final parsedPoints = <SangongPointRule>[];
    if (rawPoints is List) {
      for (final item in rawPoints) {
        if (item is Map) {
          parsedPoints.add(
            SangongPointRule.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final pointsByValue = {
      for (final point in parsedPoints) point.point: point,
    };
    final mergedPoints = List<SangongPointRule>.generate(10, (index) {
      return pointsByValue[index] ?? defaults.points[index];
    });

    final pairRaw = json['pair'];
    final maxHandRaw = json['maxHand'] ?? json['max_hand'];

    return SangongGameSettings(
      doorCount: _readInt(
        json['doorCount'] ?? json['door_count'],
        fallback: defaults.doorCount,
      ),
      minBet: _readInt(json['minBet'] ?? json['min_bet'],
          fallback: defaults.minBet),
      maxBet: _readInt(json['maxBet'] ?? json['max_bet'],
          fallback: defaults.maxBet),
      points: mergedPoints,
      pair: pairRaw is Map
          ? SangongHandRule.fromJson(Map<String, dynamic>.from(pairRaw))
          : defaults.pair,
      maxHand: maxHandRaw is Map
          ? SangongHandRule.fromJson(Map<String, dynamic>.from(maxHandRaw))
          : defaults.maxHand,
      imGroupGameId: json['imGroupGameId']?.toString().trim() ??
          json['im_group_game_id']?.toString().trim() ??
          '',
      imGroupAdminStatsId: json['imGroupAdminStatsId']?.toString().trim() ??
          json['im_group_admin_stats_id']?.toString().trim() ??
          '',
      imBotUserId: json['imBotUserId']?.toString().trim() ??
          json['im_bot_user_id']?.toString().trim() ??
          '',
    );
  }

  Map<String, dynamic> toJson() => {
        'doorCount': doorCount,
        'minBet': minBet,
        'maxBet': maxBet,
        'points': points.map((e) => e.toJson()).toList(),
        'pair': pair.toJson(),
        'maxHand': maxHand.toJson(),
        if (imGroupGameId.trim().isNotEmpty)
          'imGroupGameId': imGroupGameId.trim(),
        if (imGroupAdminStatsId.trim().isNotEmpty)
          'imGroupAdminStatsId': imGroupAdminStatsId.trim(),
        if (imBotUserId.trim().isNotEmpty) 'imBotUserId': imBotUserId.trim(),
      };

  SangongGameSettings copyWith({
    int? doorCount,
    int? minBet,
    int? maxBet,
    List<SangongPointRule>? points,
    SangongHandRule? pair,
    SangongHandRule? maxHand,
    String? imGroupGameId,
    String? imGroupAdminStatsId,
    String? imBotUserId,
  }) {
    return SangongGameSettings(
      doorCount: doorCount ?? this.doorCount,
      minBet: minBet ?? this.minBet,
      maxBet: maxBet ?? this.maxBet,
      points: points ?? this.points,
      pair: pair ?? this.pair,
      maxHand: maxHand ?? this.maxHand,
      imGroupGameId: imGroupGameId ?? this.imGroupGameId,
      imGroupAdminStatsId: imGroupAdminStatsId ?? this.imGroupAdminStatsId,
      imBotUserId: imBotUserId ?? this.imBotUserId,
    );
  }

  /// 规则页「庄抽水」默认比例（取 0 点配置，与各点数默认同档）。
  int get defaultBankerRakePoints {
    if (points.isNotEmpty) {
      return points.first.bankerRakePoints;
    }
    return pair.bankerRakePoints;
  }

  /// 庄流水「水」= 抢注 × 庄抽水% ÷ 100（四舍五入）。
  int computeBankerWater(
    int totalBetAmount, {
    int? bankerRakePoints,
  }) {
    final rate = bankerRakePoints ?? defaultBankerRakePoints;
    if (totalBetAmount <= 0 || rate <= 0) {
      return 0;
    }
    return ((totalBetAmount * rate) / 100).round();
  }
}

int _readBankerRake(Map<String, dynamic> json, {int fallback = 0}) {
  if (json.containsKey('bankerRakePoints') ||
      json.containsKey('banker_rake_points')) {
    return _readInt(
      json['bankerRakePoints'] ?? json['banker_rake_points'],
      fallback: fallback,
    );
  }
  return _readInt(json['rakePoints'] ?? json['rake_points'],
      fallback: fallback);
}

double _readDouble(dynamic value, {required double fallback}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _readInt(dynamic value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
