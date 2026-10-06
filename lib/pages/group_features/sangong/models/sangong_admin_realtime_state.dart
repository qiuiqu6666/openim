// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'dart:convert';

import 'package:openim/pages/group_features/sangong/models/group_game_round_status.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_game_settings.dart';

/// 各门下注金额汇总（键为门号 1 起）。
class SangongDoorBetTotals {
  const SangongDoorBetTotals({
    this.byDoor = const {},
    this.grandTotal = 0,
  });

  final Map<int, int> byDoor;
  final int grandTotal;

  factory SangongDoorBetTotals.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SangongDoorBetTotals();
    }
    final rawTotals = json['doorTotals'] ?? json['door_totals'];
    final byDoor = <int, int>{};
    if (rawTotals is Map) {
      rawTotals.forEach((key, value) {
        final door = int.tryParse(key.toString());
        if (door != null && door > 0) {
          byDoor[door] = _readInt(value);
        }
      });
    }
    return SangongDoorBetTotals(
      byDoor: byDoor,
      grandTotal: _readInt(json['grandTotal'] ?? json['grand_total']),
    );
  }

  List<int> valuesForDoorCount(int doorCount) {
    final count = doorCount.clamp(2, 10);
    return List<int>.generate(count, (index) => byDoor[index + 1] ?? 0);
  }
}

class SangongPendingBetSummary {
  /// 下注窗口内、余额充足的 IM 预录入指令，按门汇总金额（截止前未落注）。
  /// 支持 `234.200`、`全200` 等多门解析（服务端解析）。
  /// 本局结算后自动清空；下一局重新开窗时亦会清除残留预录入。
  const SangongPendingBetSummary({
    this.open = false,
    this.messageCount = 0,
    this.doorTotals = const SangongDoorBetTotals(),
  });

  final bool open;
  final int messageCount;
  final SangongDoorBetTotals doorTotals;

  factory SangongPendingBetSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SangongPendingBetSummary();
    }
    return SangongPendingBetSummary(
      open: json['open'] == true,
      messageCount: _readInt(json['messageCount'] ?? json['message_count']),
      doorTotals: SangongDoorBetTotals.fromJson(json),
    );
  }
}

class SangongPlacedBetSummary {
  const SangongPlacedBetSummary({
    this.doorTotals = const SangongDoorBetTotals(),
    this.betCount = 0,
  });

  final SangongDoorBetTotals doorTotals;
  final int betCount;

  factory SangongPlacedBetSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SangongPlacedBetSummary();
    }
    return SangongPlacedBetSummary(
      doorTotals: SangongDoorBetTotals.fromJson(json),
      betCount: _readInt(json['betCount'] ?? json['bet_count']),
    );
  }
}

/// `GET /admin/events/snapshot` 与 SSE `event: state` 的完整快照。
class SangongAdminRealtimeState {
  SangongAdminRealtimeState({
    this.version = 0,
    this.at = '',
    this.status = '',
    this.round,
    this.lastSettledRound,
    SangongGameSettings? settings,
    this.draw,
    this.pending = const SangongPendingBetSummary(),
    this.placed = const SangongPlacedBetSummary(),
  }) : settings = settings ?? SangongGameSettings.defaults();

  final int version;
  final String at;
  final String status;
  final SangongAdminRound? round;

  /// 最近一局已结算。设置页「冲正重结」只看有无此字段做文案；提交不走它的 id。
  final SangongAdminRound? lastSettledRound;
  final SangongGameSettings settings;
  final SangongDrawStatus? draw;
  final SangongPendingBetSummary pending;
  final SangongPlacedBetSummary placed;

  int get doorCount => settings.doorCount.clamp(2, 10);

  /// The reference stream sends complete, versioned snapshots. Missing fields
  /// must not silently become an idle six-door game or freeze subsequent SSE.
  factory SangongAdminRealtimeState.fromRequiredJson(
      Map<String, dynamic> json) {
    final version = int.tryParse('${json['version']}');
    final rawSettings = json['settings'];
    final count = rawSettings is Map
        ? int.tryParse(
            '${rawSettings['doorCount'] ?? rawSettings['door_count']}')
        : null;
    if (version == null ||
        version <= 0 ||
        count == null ||
        count < 2 ||
        count > 10) {
      throw const FormatException('Invalid complete Sangong realtime snapshot');
    }
    return SangongAdminRealtimeState.fromJson(json);
  }

  factory SangongAdminRealtimeState.fromJson(Map<String, dynamic> json) {
    final roundRaw = json['round'];
    final lastSettledRaw =
        json['lastSettledRound'] ?? json['last_settled_round'];
    final settingsRaw = json['settings'];
    final drawRaw = json['draw'];
    final pendingRaw = json['pending'];
    final placedRaw = json['placed'];
    return SangongAdminRealtimeState(
      version: _readInt(json['version']),
      at: json['at']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      round: roundRaw is Map
          ? SangongAdminRound.fromJson(Map<String, dynamic>.from(roundRaw))
          : null,
      lastSettledRound: lastSettledRaw is Map
          ? SangongAdminRound.fromJson(
              Map<String, dynamic>.from(lastSettledRaw))
          : null,
      settings: settingsRaw is Map
          ? SangongGameSettings.fromJson(Map<String, dynamic>.from(settingsRaw))
          : SangongGameSettings.defaults(),
      draw: drawRaw is Map
          ? SangongDrawStatus.fromJson(Map<String, dynamic>.from(drawRaw))
          : null,
      pending: pendingRaw is Map
          ? SangongPendingBetSummary.fromJson(
              Map<String, dynamic>.from(pendingRaw),
            )
          : const SangongPendingBetSummary(),
      placed: placedRaw is Map
          ? SangongPlacedBetSummary.fromJson(
              Map<String, dynamic>.from(placedRaw),
            )
          : const SangongPlacedBetSummary(),
    );
  }

  /// 映射群聊状态条：
  /// - 下注窗口内（[SangongAdminRound.canSubmitBets]）：展示 [pending] 预录入；
  /// - 已截止：展示 [placed] 已落注；
  /// - 窗口未开或局间空档：忽略残留 [pending]/[placed]，展示空。
  GroupGameRoundStatus toGroupGameRoundStatus() {
    final round = this.round;
    final SangongDoorBetTotals totals;
    if (round?.canSubmitBets == true) {
      totals = pending.doorTotals;
    } else if (round?.hasBetWindowClose == true) {
      totals = placed.doorTotals;
    } else {
      totals = const SangongDoorBetTotals();
    }
    final doorBetTotals = totals.valuesForDoorCount(doorCount);
    return GroupGameRoundStatus(
      bankerName: round?.bankerNickname ?? '',
      bankerDoor: round?.bankerDoor,
      bankerLimit: round?.bankerLimit,
      totalBetCount: doorBetTotals.fold<int>(0, (sum, amount) => sum + amount),
      doorBetTotals: doorBetTotals,
    );
  }

  static SangongAdminRealtimeState? tryParseEventData(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return null;
      }
      final map = Map<String, dynamic>.from(decoded);
      final stateRaw = map['state'] ?? map;
      if (stateRaw is Map) {
        return SangongAdminRealtimeState.fromJson(
          Map<String, dynamic>.from(stateRaw),
        );
      }
    } catch (_) {}
    return null;
  }
}

int _readInt(dynamic value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
