// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
/// 群聊三公当前局状态（实时数据由后续接口填充）。
class GroupGameRoundStatus {
  const GroupGameRoundStatus({
    this.bankerName = '',
    this.bankerDoor,
    this.bankerLimit,
    this.totalBetCount = 0,
    this.doorBetTotals = const [],
  });

  /// 当前局庄家显示名（非群名）。
  final String bankerName;

  /// 庄家本局选择的门（1 起），未选时为 null。
  final int? bankerDoor;

  /// 定庄展示限额（round.bankerLimit）；null 或 0 表示不限额展示。
  final int? bankerLimit;

  /// 本局下注总金额（各门合计）。
  final int totalBetCount;

  /// 各门下注合计，下标 0 对应 1 门。
  final List<int> doorBetTotals;

  bool get hasBankerLimitDisplay => bankerLimit != null && bankerLimit! > 0;

  String formatStatusLine() {
    final name = bankerName.trim();
    final door = bankerDoor;
    final doorPart = door != null && door >= 1 ? '$door包' : '包';
    final base = '庄【$name】$doorPart共$totalBetCount注';
    if (hasBankerLimitDisplay) {
      return '$base 限制$bankerLimit注';
    }
    return base;
  }

  List<int> doorValuesForCount(int doorCount) {
    final count = doorCount.clamp(2, 10);
    if (doorBetTotals.length == count) {
      return doorBetTotals;
    }
    return List<int>.filled(count, 0);
  }

  GroupGameRoundStatus copyWith({
    String? bankerName,
    int? bankerDoor,
    bool clearBankerDoor = false,
    int? bankerLimit,
    bool clearBankerLimit = false,
    int? totalBetCount,
    List<int>? doorBetTotals,
  }) {
    return GroupGameRoundStatus(
      bankerName: bankerName ?? this.bankerName,
      bankerDoor: clearBankerDoor ? null : (bankerDoor ?? this.bankerDoor),
      bankerLimit: clearBankerLimit ? null : (bankerLimit ?? this.bankerLimit),
      totalBetCount: totalBetCount ?? this.totalBetCount,
      doorBetTotals: doorBetTotals ?? this.doorBetTotals,
    );
  }
}
