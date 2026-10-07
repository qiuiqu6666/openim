// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/models/sangong_account_flow_entry.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_co_bank_flow_entry.dart';

/// `GET /api/v1/admin/tenants` 条目；`tenantId` 等于 `imGroupGameId`。
class SangongTenantInfo {
  const SangongTenantInfo({
    this.tenantId = '',
    this.name = '',
    this.imGroupGameId = '',
    this.imGroupAdminStatsId = '',
    this.imGroupLedgerId = '',
    this.imGroupWaterId = '',
    this.imBotUserId = '',
    this.myRole = '',
    this.isDefault = false,
    this.unclaimed = false,
  });

  final String tenantId;
  final String name;
  final String imGroupGameId;
  final String imGroupAdminStatsId;
  final String imGroupLedgerId;
  final String imGroupWaterId;
  final String imBotUserId;

  /// `owner` | `admin` | 空（未认领可见）
  final String myRole;
  final bool isDefault;
  final bool unclaimed;

  factory SangongTenantInfo.fromJson(Map<String, dynamic> json) {
    final imGroupGameId = (json['imGroupGameId'] ??
            json['im_group_game_id'] ??
            json['tenantId'] ??
            json['tenant_id'] ??
            json['id'] ??
            '')
        .toString()
        .trim();
    final tenantId = (json['tenantId'] ?? json['tenant_id'] ?? imGroupGameId)
        .toString()
        .trim();
    return SangongTenantInfo(
      tenantId: tenantId.isNotEmpty ? tenantId : imGroupGameId,
      name: json['name']?.toString().trim() ?? '',
      imGroupGameId: imGroupGameId,
      imGroupAdminStatsId:
          (json['imGroupAdminStatsId'] ?? json['im_group_admin_stats_id'] ?? '')
              .toString()
              .trim(),
      imGroupLedgerId:
          (json['imGroupLedgerId'] ?? json['im_group_ledger_id'] ?? '')
              .toString()
              .trim(),
      imGroupWaterId:
          (json['imGroupWaterId'] ?? json['im_group_water_id'] ?? '')
              .toString()
              .trim(),
      imBotUserId: (json['imBotUserId'] ?? json['im_bot_user_id'] ?? '')
          .toString()
          .trim(),
      myRole: (json['myRole'] ?? json['my_role'] ?? '').toString().trim(),
      isDefault: _readTenantBool(json['isDefault'] ?? json['is_default']),
      unclaimed: _readTenantBool(json['unclaimed']),
    );
  }

  static bool _readTenantBool(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final v = raw.trim().toLowerCase();
      return v == 'true' || v == '1' || v == 'yes';
    }
    return false;
  }
}

class SangongUserGroupInfo {
  const SangongUserGroupInfo({
    this.groupId,
    this.code = '',
    this.name = '',
  });

  final int? groupId;
  final String code;
  final String name;

  factory SangongUserGroupInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SangongUserGroupInfo();
    }
    return SangongUserGroupInfo(
      groupId:
          _readNullableInt(json['groupId'] ?? json['group_id'] ?? json['id']),
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  String get displayLabel {
    if (name.trim().isNotEmpty) {
      return name.trim();
    }
    if (code.trim().isNotEmpty) {
      return code.trim();
    }
    if (groupId != null && groupId! > 0) {
      return '$groupId';
    }
    return '';
  }
}

class SangongCoBankMember {
  const SangongCoBankMember({
    required this.userId,
    required this.nickname,
    required this.amount,
    required this.sharePercent,
    this.imUserId = '',
  });

  final int userId;
  final String nickname;
  final int amount;
  final double sharePercent;
  final String imUserId;

  factory SangongCoBankMember.fromJson(Map<String, dynamic> json) {
    return SangongCoBankMember(
      userId: _readInt(json['userId'] ?? json['user_id']),
      nickname: json['nickname']?.toString() ?? '',
      amount: _readInt(json['amount']),
      sharePercent: _readDouble(
        json['sharePercent'] ?? json['share_percent'],
      ),
      imUserId:
          json['imUserId']?.toString() ?? json['im_user_id']?.toString() ?? '',
    );
  }
}

class SangongCoBank {
  const SangongCoBank({
    this.poolTotal = 0,
    this.count = 0,
    this.members = const [],
  });

  final int poolTotal;
  final int count;
  final List<SangongCoBankMember> members;

  factory SangongCoBank.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SangongCoBank();
    }
    final rawMembers = json['members'];
    final members = <SangongCoBankMember>[];
    if (rawMembers is List) {
      for (final item in rawMembers) {
        if (item is Map) {
          members.add(
            SangongCoBankMember.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return SangongCoBank(
      poolTotal: _readInt(json['poolTotal'] ?? json['pool_total']),
      count: _readInt(json['count']),
      members: members,
    );
  }

  SangongCoBankMember? memberForImUserId(String imUserId) {
    final target = imUserId.trim();
    if (target.isEmpty) {
      return null;
    }
    for (final member in members) {
      if (member.imUserId.trim() == target) {
        return member;
      }
    }
    return null;
  }

  SangongCoBankMember? memberForUserId(int userId) {
    for (final member in members) {
      if (member.userId == userId) {
        return member;
      }
    }
    return null;
  }
}

class SangongAdminRound {
  const SangongAdminRound({
    required this.id,
    this.periodNo = 0,
    this.bankerNickname = '',
    this.bankerImUserId = '',
    this.bankerDoor,
    this.bankerLimit,
    this.status = '',
    this.betWindowOpenAt = '',
    this.betWindowCloseAt = '',
    this.betWindowCloseMessageId,
    this.settledAt = '',
    this.drawLockedAt = '',
    this.coBank = const SangongCoBank(),
  });

  final int id;
  final int periodNo;
  final String bankerNickname;
  final String bankerImUserId;
  final int? bankerDoor;

  /// 定庄时设置的展示限额；null 或 0 表示不限额展示（不限制下注）。
  final int? bankerLimit;
  final String status;
  final String betWindowOpenAt;
  final String betWindowCloseAt;
  final int? betWindowCloseMessageId;
  final String settledAt;
  final String drawLockedAt;
  final SangongCoBank coBank;

  bool get hasBankerLimitDisplay => bankerLimit != null && bankerLimit! > 0;

  bool get hasBetWindowOpen => betWindowOpenAt.trim().isNotEmpty;

  bool get hasBetWindowClose => betWindowCloseAt.trim().isNotEmpty;

  bool get isSettled => status.trim().toLowerCase() == 'settled';

  bool get isVoided => status.trim().toLowerCase() == 'voided';

  bool get isRoundClosed => isSettled || isVoided;

  /// 当前局已结算时可冲正重结（下一期开出后 current 不再是本局）。
  bool get canVoidResettle => isSettled;

  /// 已发定庄通知且尚未截止下注。
  bool get canSubmitBets => hasBetWindowOpen && !hasBetWindowClose;

  /// 统计弹窗确认截止：已定庄且本局未结算（含重新截止）。
  bool get canCutoffBets => hasBetWindowOpen && !isSettled;

  factory SangongAdminRound.fromJson(Map<String, dynamic> json) {
    final coBankRaw = json['coBank'] ?? json['co_bank'];
    return SangongAdminRound(
      id: _readInt(json['id']),
      periodNo: _readInt(json['periodNo'] ?? json['period_no']),
      bankerNickname: json['bankerNickname']?.toString() ??
          json['banker_nickname']?.toString() ??
          '',
      bankerImUserId: json['bankerImUserId']?.toString() ??
          json['banker_im_user_id']?.toString() ??
          '',
      bankerDoor: _readNullableInt(json['bankerDoor'] ?? json['banker_door']),
      bankerLimit: _readNullableInt(
        json['bankerLimit'] ?? json['banker_limit'],
      ),
      status: json['status']?.toString() ?? '',
      betWindowOpenAt: json['betWindowOpenAt']?.toString() ??
          json['bet_window_open_at']?.toString() ??
          '',
      betWindowCloseAt: json['betWindowCloseAt']?.toString() ??
          json['bet_window_close_at']?.toString() ??
          '',
      betWindowCloseMessageId: _readNullableInt(
        json['betWindowCloseMessageId'] ?? json['bet_window_close_message_id'],
      ),
      settledAt:
          json['settledAt']?.toString() ?? json['settled_at']?.toString() ?? '',
      drawLockedAt: json['drawLockedAt']?.toString() ??
          json['draw_locked_at']?.toString() ??
          '',
      coBank: coBankRaw is Map
          ? SangongCoBank.fromJson(Map<String, dynamic>.from(coBankRaw))
          : const SangongCoBank(),
    );
  }
}

Map<int, int> _parseDoorTotalsMap(dynamic raw) {
  final byDoor = <int, int>{};
  if (raw is! Map) {
    return byDoor;
  }
  raw.forEach((key, value) {
    final door = int.tryParse(key.toString());
    if (door != null && door > 0) {
      byDoor[door] = _readInt(value);
    }
  });
  return byDoor;
}

/// `preview.report.users[]`：按玩家汇总（昵称、各门下注、个人合计）。
class SangongBetPreviewUserStat {
  const SangongBetPreviewUserStat({
    this.nickname = '',
    this.faceUrl = '',
    this.imUserId = '',
    this.grandTotal = 0,
    this.doorTotals = const {},
    this.lines = const [],
  });

  final String nickname;
  final String faceUrl;
  final String imUserId;
  final int grandTotal;
  final Map<int, int> doorTotals;

  /// 兼容旧字段：逐条指令原文（新接口以 [doorTotals] 为准）。
  final List<String> lines;

  String get displayName {
    final name = nickname.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final id = imUserId.trim();
    return id.isNotEmpty ? id : '未知用户';
  }

  int get resolvedGrandTotal {
    if (grandTotal > 0) {
      return grandTotal;
    }
    if (doorTotals.isEmpty) {
      return 0;
    }
    return doorTotals.values.fold<int>(0, (sum, value) => sum + value);
  }

  factory SangongBetPreviewUserStat.fromJson(Map<String, dynamic> json) {
    final byDoor = _parseDoorTotalsMap(
      json['doorTotals'] ??
          json['door_totals'] ??
          json['doors'] ??
          json['byDoor'],
    );

    final lines = <String>[];
    final rawLines =
        json['lines'] ?? json['entries'] ?? json['bets'] ?? json['details'];
    if (rawLines is List) {
      for (final item in rawLines) {
        if (item is String) {
          final text = item.trim();
          if (text.isNotEmpty) {
            lines.add(text);
          }
          continue;
        }
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final raw = map['raw'] ??
              map['rawInput'] ??
              map['raw_input'] ??
              map['text'] ??
              map['command'] ??
              map['content'];
          if (raw != null && raw.toString().trim().isNotEmpty) {
            lines.add(raw.toString().trim());
          }
        }
      }
    }

    return SangongBetPreviewUserStat(
      nickname: json['nickname']?.toString() ??
          json['nickName']?.toString() ??
          json['userNickname']?.toString() ??
          json['user_nickname']?.toString() ??
          '',
      imUserId: json['imUserId']?.toString() ??
          json['im_user_id']?.toString() ??
          json['userId']?.toString() ??
          json['user_id']?.toString() ??
          '',
      grandTotal: _readInt(
        json['grandTotal'] ??
            json['grand_total'] ??
            json['total'] ??
            json['amount'],
      ),
      doorTotals: byDoor,
      lines: lines,
    );
  }

  List<int> doorValuesForCount(int doorCount) {
    final count = doorCount.clamp(2, 10);
    return List<int>.generate(count, (index) => doorTotals[index + 1] ?? 0);
  }

  String doorSummary() {
    if (doorTotals.isEmpty) {
      return '';
    }
    final doors = doorTotals.keys.toList()..sort();
    return doors.map((door) => '$door门${doorTotals[door]}').join('  ');
  }

  String detailSummary() {
    final doors = doorSummary();
    if (doors.isNotEmpty) {
      return doors;
    }
    if (lines.isNotEmpty) {
      return lines.join('  ');
    }
    return '';
  }
}

/// `preview.report.entries[]`：按 IM 消息顺序的逐条注单。
class SangongBetPreviewEntry {
  const SangongBetPreviewEntry({
    this.index = 0,
    this.messageId,
    this.msgSeq,
    this.msgTime,
    this.imUserId = '',
    this.nickname = '',
    this.text = '',
    this.doors = const [],
    this.amount = 0,
    this.totalAmount = 0,
    this.doorCount = 0,
    this.status = '',
    this.outcome = '',
    this.source = '',
  });

  final int index;
  final int? messageId;
  final int? msgSeq;
  final int? msgTime;
  final String imUserId;
  final String nickname;
  final String text;
  final List<int> doors;
  final int amount;
  final int totalAmount;
  final int doorCount;
  final String status;
  final String outcome;
  final String source;

  bool get canExclude => msgSeq != null && msgSeq! > 0;

  bool get isAdminSource => source.trim().toLowerCase() == 'admin';

  bool get isPlaced => status.trim().toLowerCase() == 'placed';

  String get displayName {
    final name = nickname.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final id = imUserId.trim();
    return id.isNotEmpty ? id : '未知用户';
  }

  int get resolvedTotalAmount {
    if (totalAmount > 0) {
      return totalAmount;
    }
    return amount;
  }

  factory SangongBetPreviewEntry.fromJson(Map<String, dynamic> json) {
    final doorsRaw = json['doors'];
    final doors = <int>[];
    if (doorsRaw is List) {
      for (final item in doorsRaw) {
        final door = int.tryParse(item.toString());
        if (door != null && door > 0) {
          doors.add(door);
        }
      }
    }
    return SangongBetPreviewEntry(
      index: _readInt(json['index']),
      messageId: _readNullableInt(json['messageId'] ?? json['message_id']),
      msgSeq: _readNullableInt(json['msgSeq'] ?? json['msg_seq']),
      msgTime: _readNullableInt(json['msgTime'] ?? json['msg_time']),
      imUserId:
          json['imUserId']?.toString() ?? json['im_user_id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      doors: doors,
      amount: _readInt(json['amount']),
      totalAmount: _readInt(json['totalAmount'] ?? json['total_amount']),
      doorCount: _readInt(json['doorCount'] ?? json['door_count']),
      status: json['status']?.toString() ?? '',
      outcome: json['outcome']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
    );
  }

  String doorsLabel() {
    if (doors.isEmpty) {
      return '';
    }
    if (doors.length == 1) {
      return '${doors.single}门';
    }
    return '${doors.join('/')}门';
  }
}

List<SangongBetPreviewEntry> _parsePreviewEntries(dynamic raw) {
  if (raw is! List) {
    return const [];
  }
  final entries = <SangongBetPreviewEntry>[];
  for (final item in raw) {
    if (item is Map) {
      entries.add(
        SangongBetPreviewEntry.fromJson(Map<String, dynamic>.from(item)),
      );
    }
  }
  return entries;
}

List<SangongBetPreviewUserStat> _parsePreviewUserStats(dynamic raw) {
  if (raw is! List) {
    return const [];
  }
  final users = <SangongBetPreviewUserStat>[];
  for (final item in raw) {
    if (item is Map) {
      users.add(
        SangongBetPreviewUserStat.fromJson(Map<String, dynamic>.from(item)),
      );
    }
  }
  return users;
}

/// `preview.report`：各门/整局汇总 + 按玩家明细。
class SangongBetPreviewReport {
  const SangongBetPreviewReport({
    this.grandTotal = 0,
    this.betCount = 0,
    this.doorTotals = const {},
    this.users = const [],
    this.entries = const [],
    this.entryCount = 0,
  });

  final int grandTotal;
  final int betCount;
  final Map<int, int> doorTotals;
  final List<SangongBetPreviewUserStat> users;
  final List<SangongBetPreviewEntry> entries;
  final int entryCount;

  factory SangongBetPreviewReport.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SangongBetPreviewReport();
    }
    final users = _parsePreviewUserStats(
      json['users'] ??
          json['userStats'] ??
          json['user_stats'] ??
          json['userTotals'] ??
          json['user_totals'],
    );
    final entries = _parsePreviewEntries(json['entries']);
    final entryCount = _readInt(
      json['entryCount'] ?? json['entry_count'],
      fallback: entries.length,
    );
    return SangongBetPreviewReport(
      grandTotal: _readInt(json['grandTotal'] ?? json['grand_total']),
      betCount: _readInt(json['betCount'] ?? json['bet_count']),
      doorTotals: _parseDoorTotalsMap(
        json['doorTotals'] ?? json['door_totals'],
      ),
      users: users,
      entries: entries,
      entryCount: entryCount,
    );
  }

  List<int> doorValuesForCount(int doorCount) {
    final count = doorCount.clamp(2, 10);
    return List<int>.generate(count, (index) => doorTotals[index + 1] ?? 0);
  }
}

/// `POST /admin/betting/preview` 返回的 `preview` 节点。
class SangongBetPreview {
  const SangongBetPreview({
    this.report = const SangongBetPreviewReport(),
    this.pendingMessageCount = 0,
    this.excludedAfterCutoff = 0,
    this.cutoffMessageId = 0,
    this.cutoffMsgSeq,
    this.untilMessageId,
    this.untilMsgSeq,
    this.previewCloseMsgTime = '',
    this.previewCloseAt = '',
    this.excludedMsgSeqs = const [],
    this.excludedManualCount = 0,
  });

  final SangongBetPreviewReport report;
  final int pendingMessageCount;
  final int excludedAfterCutoff;
  final int cutoffMessageId;
  final int? cutoffMsgSeq;
  final int? untilMessageId;
  final int? untilMsgSeq;
  final String previewCloseMsgTime;
  final String previewCloseAt;
  final List<int> excludedMsgSeqs;
  final int excludedManualCount;

  factory SangongBetPreview.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SangongBetPreview();
    }
    final reportRaw = json['report'];
    var report = reportRaw is Map
        ? SangongBetPreviewReport.fromJson(
            Map<String, dynamic>.from(reportRaw),
          )
        : const SangongBetPreviewReport();
    if (report.users.isEmpty) {
      final fallbackUsers = _parsePreviewUserStats(
        json['users'] ?? json['userStats'] ?? json['user_stats'],
      );
      if (fallbackUsers.isNotEmpty) {
        report = SangongBetPreviewReport(
          grandTotal: report.grandTotal,
          betCount: report.betCount,
          doorTotals: report.doorTotals,
          users: fallbackUsers,
        );
      }
    }
    return SangongBetPreview(
      report: report,
      pendingMessageCount: _readInt(
        json['pendingMessageCount'] ?? json['pending_message_count'],
      ),
      excludedAfterCutoff: _readInt(
        json['excludedAfterCutoff'] ?? json['excluded_after_cutoff'],
      ),
      cutoffMessageId: _readInt(
        json['cutoffMessageId'] ?? json['cutoff_message_id'],
      ),
      cutoffMsgSeq: _readNullableInt(
        json['cutoffMsgSeq'] ?? json['cutoff_msg_seq'],
      ),
      untilMessageId: _readNullableInt(
        json['untilMessageId'] ?? json['until_message_id'],
      ),
      untilMsgSeq: _readNullableInt(
        json['untilMsgSeq'] ?? json['until_msg_seq'],
      ),
      previewCloseMsgTime: json['previewCloseMsgTime']?.toString() ??
          json['preview_close_msg_time']?.toString() ??
          '',
      previewCloseAt: json['previewCloseAt']?.toString() ??
          json['preview_close_at']?.toString() ??
          '',
      excludedMsgSeqs: _readIntList(
        json['excludedMsgSeqs'] ?? json['excluded_msg_seqs'],
      ),
      excludedManualCount: _readInt(
        json['excludedManualCount'] ?? json['excluded_manual_count'],
      ),
    );
  }
}

class SangongBetPreviewResult {
  const SangongBetPreviewResult({
    this.preview = const SangongBetPreview(),
  });

  final SangongBetPreview preview;

  factory SangongBetPreviewResult.fromJson(Map<String, dynamic> json) {
    final previewRaw = json['preview'];
    return SangongBetPreviewResult(
      preview: previewRaw is Map
          ? SangongBetPreview.fromJson(Map<String, dynamic>.from(previewRaw))
          : const SangongBetPreview(),
    );
  }
}

/// `POST /admin/reports/bet-image|settle-image|settle-bill|trend-image|users/points-image` 通用响应。
class SangongReportImageResult {
  const SangongReportImageResult({
    this.ok = false,
    this.sent = false,
    this.queued = false,
    this.reportId = '',
    this.type = '',
    this.mode = '',
    this.periodNo = 0,
    this.roundId,
    this.untilMessageId,
    this.untilMsgSeq,
    this.betCount = 0,
    this.grandTotal = 0,
    this.pendingMessageCount = 0,
    this.excludedAfterCutoff = 0,
    this.rowCount = 0,
    this.doorCount = 0,
    this.message = '',
  });

  final bool ok;
  final bool sent;
  final bool queued;
  final String reportId;
  final String type;
  final String mode;
  final int periodNo;
  final int? roundId;
  final int? untilMessageId;
  final int? untilMsgSeq;
  final int betCount;
  final int grandTotal;
  final int pendingMessageCount;
  final int excludedAfterCutoff;
  final int rowCount;
  final int doorCount;
  final String message;

  bool get isPreview => mode.trim().toLowerCase() == 'preview';

  factory SangongReportImageResult.fromJson(Map<String, dynamic> json) {
    return SangongReportImageResult(
      ok: _readBool(json['ok']),
      sent: _readBool(json['sent']),
      queued: json['queued'] == true,
      reportId: json['reportId']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      mode: json['mode']?.toString() ?? '',
      periodNo: _readInt(json['periodNo'] ?? json['period_no']),
      roundId: _readNullableInt(json['roundId'] ?? json['round_id']),
      untilMessageId: _readNullableInt(
        json['untilMessageId'] ?? json['until_message_id'],
      ),
      untilMsgSeq:
          _readNullableInt(json['untilMsgSeq'] ?? json['until_msg_seq']),
      betCount: _readInt(json['betCount'] ?? json['bet_count']),
      grandTotal: _readInt(json['grandTotal'] ?? json['grand_total']),
      pendingMessageCount: _readInt(
        json['pendingMessageCount'] ?? json['pending_message_count'],
      ),
      excludedAfterCutoff: _readInt(
        json['excludedAfterCutoff'] ?? json['excluded_after_cutoff'],
      ),
      rowCount: _readInt(json['rowCount'] ?? json['row_count']),
      doorCount: _readInt(json['doorCount'] ?? json['door_count']),
      message: json['message']?.toString() ??
          json['msg']?.toString() ??
          json['error']?.toString() ??
          '',
    );
  }
}

class SangongQuickSetupBankerParsed {
  const SangongQuickSetupBankerParsed({
    this.door = 0,
    this.limit = 0,
    this.limited = false,
    this.text = '',
  });

  final int door;

  /// 定庄展示限额（写入 round.bankerLimit，非合庄金额）。
  final int limit;
  final bool limited;
  final String text;

  factory SangongQuickSetupBankerParsed.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SangongQuickSetupBankerParsed();
    }
    final limitRaw = json['limit'] ?? json['amount'];
    return SangongQuickSetupBankerParsed(
      door: _readInt(json['door']),
      limit: _readInt(limitRaw),
      limited: _readBool(json['limited']),
      text: json['text']?.toString() ?? '',
    );
  }
}

/// 合庄占比展示（保留 2 位小数，与接口一致）。
String formatSangongSharePercent(double value) {
  return value.toStringAsFixed(2);
}

class SangongQuickSetupBankerResult {
  const SangongQuickSetupBankerResult({
    this.ok = false,
    this.action = '',
    this.messageId,
    this.newRound = false,
    this.replaced = false,
    this.sent = false,
    this.restarted = false,
    this.parsed = const SangongQuickSetupBankerParsed(),
    this.round,
  });

  final bool ok;
  final String action;
  final int? messageId;
  final bool newRound;
  final bool replaced;
  final bool sent;
  final bool restarted;
  final SangongQuickSetupBankerParsed parsed;
  final SangongAdminRound? round;

  factory SangongQuickSetupBankerResult.fromJson(Map<String, dynamic> json) {
    final parsedRaw = json['parsed'];
    final roundRaw = json['round'];
    return SangongQuickSetupBankerResult(
      ok: _readBool(json['ok']),
      action: json['action']?.toString() ?? '',
      messageId: _readNullableInt(json['messageId'] ?? json['message_id']),
      newRound: _readBool(json['newRound'] ?? json['new_round']),
      replaced: _readBool(json['replaced']),
      sent: _readBool(json['sent']),
      restarted: _readBool(json['restarted']),
      parsed: parsedRaw is Map
          ? SangongQuickSetupBankerParsed.fromJson(
              Map<String, dynamic>.from(parsedRaw),
            )
          : const SangongQuickSetupBankerParsed(),
      round: roundRaw is Map
          ? SangongAdminRound.fromJson(Map<String, dynamic>.from(roundRaw))
          : null,
    );
  }
}

class SangongBetSubmitRecutoffInfo {
  const SangongBetSubmitRecutoffInfo({
    this.cancelled = 0,
    this.requeued = 0,
  });

  final int cancelled;
  final int requeued;

  factory SangongBetSubmitRecutoffInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SangongBetSubmitRecutoffInfo();
    }
    return SangongBetSubmitRecutoffInfo(
      cancelled: _readInt(json['cancelled'] ?? json['cancelledCount']),
      requeued: _readInt(json['requeued'] ?? json['requeuedCount']),
    );
  }
}

class SangongBetSubmitRecallSummary {
  const SangongBetSubmitRecallSummary({
    this.recalled = 0,
    this.failed = 0,
  });

  final int recalled;
  final int failed;

  factory SangongBetSubmitRecallSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SangongBetSubmitRecallSummary();
    }
    return SangongBetSubmitRecallSummary(
      recalled: _readInt(
        json['recalled'] ??
            json['recalledCount'] ??
            json['success'] ??
            json['successCount'],
      ),
      failed: _readInt(json['failed'] ?? json['failedCount']),
    );
  }
}

class SangongBetSubmitResult {
  const SangongBetSubmitResult({
    this.placedCount = 0,
    this.refundedAmount = 0,
    this.collectionReady = false,
    this.failedCount = 0,
    this.isRecutoff = false,
    this.cutoffMessageId = 0,
    this.cutoffMsgSeq,
    this.previousCloseAt = '',
    this.previousCloseMsgTime = '',
    this.previousCutoffMessageId,
    this.recutoff,
    this.recallSummary,
    this.round,
  });

  final int placedCount;
  final int refundedAmount;
  final bool collectionReady;
  final int failedCount;
  final bool isRecutoff;
  final int cutoffMessageId;
  final int? cutoffMsgSeq;
  final String previousCloseAt;
  final String previousCloseMsgTime;
  final int? previousCutoffMessageId;
  final SangongBetSubmitRecutoffInfo? recutoff;
  final SangongBetSubmitRecallSummary? recallSummary;
  final SangongAdminRound? round;

  factory SangongBetSubmitResult.fromJson(Map<String, dynamic> json) {
    final submitRaw = json['submit'];
    final submit = submitRaw is Map
        ? Map<String, dynamic>.from(submitRaw)
        : const <String, dynamic>{};
    final roundRaw = json['round'];
    final recutoffRaw = submit['recutoff'] ?? json['recutoff'];
    final recallRaw = submit['recallSummary'] ??
        submit['recall_summary'] ??
        json['recallSummary'] ??
        json['recall_summary'];
    return SangongBetSubmitResult(
      placedCount: _readInt(submit['placedCount'] ?? submit['placed_count']),
      failedCount: _readInt(submit['failedCount'] ?? submit['failed_count']),
      isRecutoff: _readBool(submit['isRecutoff'] ?? submit['is_recutoff']),
      cutoffMessageId: _readInt(
        submit['cutoffMessageId'] ?? submit['cutoff_message_id'],
      ),
      cutoffMsgSeq: _readNullableInt(
        submit['cutoffMsgSeq'] ?? submit['cutoff_msg_seq'],
      ),
      previousCloseAt: submit['previousCloseAt']?.toString() ??
          submit['previous_close_at']?.toString() ??
          '',
      previousCloseMsgTime: submit['previousCloseMsgTime']?.toString() ??
          submit['previous_close_msg_time']?.toString() ??
          '',
      previousCutoffMessageId: _readNullableInt(
        submit['previousCutoffMessageId'] ??
            submit['previous_cutoff_message_id'],
      ),
      recutoff: recutoffRaw is Map
          ? SangongBetSubmitRecutoffInfo.fromJson(
              Map<String, dynamic>.from(recutoffRaw),
            )
          : null,
      recallSummary: recallRaw is Map
          ? SangongBetSubmitRecallSummary.fromJson(
              Map<String, dynamic>.from(recallRaw),
            )
          : null,
      round: roundRaw is Map
          ? SangongAdminRound.fromJson(Map<String, dynamic>.from(roundRaw))
          : null,
    );
  }
}

class SangongDoorDraw {
  const SangongDoorDraw({
    required this.door,
    this.amount = '',
    this.rawInput = '',
    this.handLabel = '',
    this.handType = '',
  });

  final int door;
  final String amount;
  final String rawInput;
  final String handLabel;
  final String handType;

  factory SangongDoorDraw.fromJson(Map<String, dynamic> json) {
    return SangongDoorDraw(
      door: _readInt(json['door']),
      amount: json['amount']?.toString() ?? '',
      rawInput:
          json['rawInput']?.toString() ?? json['raw_input']?.toString() ?? '',
      handLabel:
          json['handLabel']?.toString() ?? json['hand_label']?.toString() ?? '',
      handType:
          json['handType']?.toString() ?? json['hand_type']?.toString() ?? '',
    );
  }
}

class SangongDrawStatus {
  const SangongDrawStatus({
    this.roundId = 0,
    this.doorCount = 6,
    this.bankerDoor,
    this.drawLockedAt = '',
    this.requiredDoors = const [],
    this.missingDoors = const [],
    this.complete = false,
    this.draws = const [],
  });

  final int roundId;
  final int doorCount;
  final int? bankerDoor;
  final String drawLockedAt;
  final List<int> requiredDoors;
  final List<int> missingDoors;
  final bool complete;
  final List<SangongDoorDraw> draws;

  List<int> get doorsToEnter {
    if (requiredDoors.isNotEmpty) {
      return List<int>.from(requiredDoors);
    }
    final count = doorCount.clamp(2, 10);
    return List<int>.generate(count, (i) => i + 1);
  }

  SangongDoorDraw? drawForDoor(int door) {
    for (final draw in draws) {
      if (draw.door == door) {
        return draw;
      }
    }
    return null;
  }

  factory SangongDrawStatus.fromJson(Map<String, dynamic> json) {
    final drawsRaw = json['draws'];
    final requiredRaw = json['requiredDoors'] ?? json['required_doors'];
    final missingRaw = json['missingDoors'] ?? json['missing_doors'];
    return SangongDrawStatus(
      roundId: _readInt(json['roundId'] ?? json['round_id']),
      doorCount: _readInt(json['doorCount'] ?? json['door_count'], fallback: 6),
      bankerDoor: _readNullableInt(json['bankerDoor'] ?? json['banker_door']),
      drawLockedAt: json['drawLockedAt']?.toString() ??
          json['draw_locked_at']?.toString() ??
          '',
      requiredDoors: _readIntList(requiredRaw),
      missingDoors: _readIntList(missingRaw),
      complete: json['complete'] == true,
      draws: drawsRaw is List
          ? drawsRaw
              .whereType<Map>()
              .map(
                  (e) => SangongDoorDraw.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class SangongDrawMutationResult {
  const SangongDrawMutationResult({
    this.draw = const SangongDrawStatus(),
    this.round,
  });

  final SangongDrawStatus draw;
  final SangongAdminRound? round;

  factory SangongDrawMutationResult.fromJson(Map<String, dynamic> json) {
    final drawRaw = json['draw'];
    final roundRaw = json['round'];
    return SangongDrawMutationResult(
      draw: drawRaw is Map
          ? SangongDrawStatus.fromJson(Map<String, dynamic>.from(drawRaw))
          : const SangongDrawStatus(),
      round: roundRaw is Map
          ? SangongAdminRound.fromJson(Map<String, dynamic>.from(roundRaw))
          : null,
    );
  }
}

class SangongDrawInput {
  const SangongDrawInput({
    required this.door,
    required this.amount,
  });

  final int door;
  final String amount;

  Map<String, dynamic> toJson() => {
        'door': door,
        'amount': amount,
      };
}

class SangongDrawFetchResult {
  const SangongDrawFetchResult({
    this.draw = const SangongDrawStatus(),
    this.round,
  });

  final SangongDrawStatus draw;
  final SangongAdminRound? round;

  factory SangongDrawFetchResult.fromJson(Map<String, dynamic> json) {
    final drawRaw = json['draw'];
    final roundRaw = json['round'];
    return SangongDrawFetchResult(
      draw: drawRaw is Map
          ? SangongDrawStatus.fromJson(Map<String, dynamic>.from(drawRaw))
          : const SangongDrawStatus(),
      round: roundRaw is Map
          ? SangongAdminRound.fromJson(Map<String, dynamic>.from(roundRaw))
          : null,
    );
  }
}

/// 冲正后用于重录：清空已录开彩，保留门数 / 庄门。
SangongDrawStatus sangongEmptyDrawStatusForResettle(SangongDrawStatus source) {
  final doors = source.doorsToEnter;
  return SangongDrawStatus(
    roundId: source.roundId,
    doorCount: source.doorCount,
    bankerDoor: source.bankerDoor,
    drawLockedAt: '',
    requiredDoors: doors,
    missingDoors: doors,
    complete: false,
    draws: const [],
  );
}

class SangongVoidedBalanceEntry {
  const SangongVoidedBalanceEntry({
    this.userId = 0,
    this.delta = 0,
    this.role = '',
  });

  final int userId;
  final int delta;
  final String role;

  factory SangongVoidedBalanceEntry.fromJson(Map<String, dynamic> json) {
    return SangongVoidedBalanceEntry(
      userId: _readInt(json['userId'] ?? json['user_id']),
      delta: _readInt(json['delta']),
      role: json['role']?.toString() ?? '',
    );
  }
}

class SangongVoidedSettlementInfo {
  const SangongVoidedSettlementInfo({
    this.roundId = 0,
    this.periodNo = 0,
    this.voided = const [],
  });

  final int roundId;
  final int periodNo;
  final List<SangongVoidedBalanceEntry> voided;

  factory SangongVoidedSettlementInfo.fromJson(Map<String, dynamic> json) {
    final listRaw = json['voided'];
    return SangongVoidedSettlementInfo(
      roundId: _readInt(json['roundId'] ?? json['round_id']),
      periodNo: _readInt(json['periodNo'] ?? json['period_no']),
      voided: listRaw is List
          ? listRaw
              .whereType<Map>()
              .map(
                (e) => SangongVoidedBalanceEntry.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
          : const [],
    );
  }
}

/// `POST /admin/rounds/{id}/void-settlement`
class SangongVoidSettlementResult {
  const SangongVoidSettlementResult({
    this.ok = false,
    this.voided = const SangongVoidedSettlementInfo(),
    this.round,
  });

  final bool ok;
  final SangongVoidedSettlementInfo voided;
  final SangongAdminRound? round;

  factory SangongVoidSettlementResult.fromJson(Map<String, dynamic> json) {
    final voidedRaw = json['voided'];
    final roundRaw = json['round'];
    return SangongVoidSettlementResult(
      ok: json['ok'] == true,
      voided: voidedRaw is Map
          ? SangongVoidedSettlementInfo.fromJson(
              Map<String, dynamic>.from(voidedRaw),
            )
          : const SangongVoidedSettlementInfo(),
      round: roundRaw is Map
          ? SangongAdminRound.fromJson(Map<String, dynamic>.from(roundRaw))
          : null,
    );
  }
}

/// `POST /admin/rounds/{id}/resettle`
class SangongResettleResult {
  const SangongResettleResult({
    this.ok = false,
    this.voided = const SangongVoidedSettlementInfo(),
    this.settlement = const {},
    this.round,
  });

  final bool ok;
  final SangongVoidedSettlementInfo voided;
  final Map<String, dynamic> settlement;
  final SangongAdminRound? round;

  factory SangongResettleResult.fromJson(Map<String, dynamic> json) {
    final voidedRaw = json['voided'];
    final settlementRaw = json['settlement'];
    final roundRaw = json['round'];
    return SangongResettleResult(
      ok: json['ok'] == true,
      voided: voidedRaw is Map
          ? SangongVoidedSettlementInfo.fromJson(
              Map<String, dynamic>.from(voidedRaw),
            )
          : const SangongVoidedSettlementInfo(),
      settlement: settlementRaw is Map
          ? Map<String, dynamic>.from(settlementRaw)
          : const {},
      round: roundRaw is Map
          ? SangongAdminRound.fromJson(Map<String, dynamic>.from(roundRaw))
          : null,
    );
  }
}

class SangongAdminSession {
  const SangongAdminSession({
    this.status = '',
    this.session,
    this.round,
    this.message = '',
  });

  final String status;
  final SangongSessionInfo? session;
  final SangongAdminRound? round;
  final String message;

  bool get isRunning {
    final top = status.trim().toLowerCase();
    if (top == 'running') {
      return true;
    }
    if (top == 'idle') {
      return false;
    }
    return session?.isRunning ?? false;
  }

  int get periodNo => session?.periodNo ?? 0;

  factory SangongAdminSession.fromJson(Map<String, dynamic> json) {
    final roundRaw = json['round'];
    final sessionRaw = json['session'];
    return SangongAdminSession(
      status: json['status']?.toString() ?? '',
      session: sessionRaw is Map
          ? SangongSessionInfo.fromJson(Map<String, dynamic>.from(sessionRaw))
          : null,
      round: roundRaw is Map
          ? SangongAdminRound.fromJson(Map<String, dynamic>.from(roundRaw))
          : null,
      message: json['message']?.toString() ?? '',
    );
  }
}

class SangongSessionInfo {
  const SangongSessionInfo({
    this.id = 0,
    this.status = '',
    this.periodNo = 0,
    this.currentRoundId,
    this.startedAt = '',
  });

  final int id;
  final String status;
  final int periodNo;
  final int? currentRoundId;
  final String startedAt;

  bool get isRunning => status.trim().toLowerCase() == 'running';

  factory SangongSessionInfo.fromJson(Map<String, dynamic> json) {
    return SangongSessionInfo(
      id: _readInt(json['id']),
      status: json['status']?.toString() ?? '',
      periodNo: _readInt(json['periodNo'] ?? json['period_no']),
      currentRoundId: _readNullableInt(
        json['currentRoundId'] ?? json['current_round_id'],
      ),
      startedAt:
          json['startedAt']?.toString() ?? json['started_at']?.toString() ?? '',
    );
  }
}

class SangongSessionMutationResult {
  const SangongSessionMutationResult({
    this.message = '',
    this.status = '',
    this.session,
    this.round,
  });

  final String message;
  final String status;
  final SangongSessionInfo? session;
  final SangongAdminRound? round;

  factory SangongSessionMutationResult.fromJson(Map<String, dynamic> json) {
    final sessionRaw = json['session'];
    final roundRaw = json['round'];
    return SangongSessionMutationResult(
      message: json['message']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      session: sessionRaw is Map
          ? SangongSessionInfo.fromJson(Map<String, dynamic>.from(sessionRaw))
          : null,
      round: roundRaw is Map
          ? SangongAdminRound.fromJson(Map<String, dynamic>.from(roundRaw))
          : null,
    );
  }
}

class SangongAdminUserReport {
  const SangongAdminUserReport({
    this.userId,
    required this.imUserId,
    this.balance = 0,
    this.group = const SangongUserGroupInfo(),
    this.nickname = '',
    this.faceUrl = '',
    this.childrenCount = 0,
    this.rebatePer10000 = 0,
    this.maxNegative = 0,
  });

  final int? userId;
  final String imUserId;
  final int balance;
  final SangongUserGroupInfo group;
  final String nickname;
  final String faceUrl;
  final int childrenCount;
  final int rebatePer10000;
  final int maxNegative;

  factory SangongAdminUserReport.fromJson(Map<String, dynamic> json) {
    final groupRaw = json['group'];
    return SangongAdminUserReport(
      userId: _readNullableInt(json['userId'] ?? json['user_id']),
      imUserId:
          json['imUserId']?.toString() ?? json['im_user_id']?.toString() ?? '',
      balance: _readInt(json['balance']),
      group: groupRaw is Map
          ? SangongUserGroupInfo.fromJson(Map<String, dynamic>.from(groupRaw))
          : SangongUserGroupInfo(
              groupId: _readNullableInt(json['groupId'] ?? json['group_id']),
              name: json['groupName']?.toString() ??
                  json['group_name']?.toString() ??
                  '',
            ),
      nickname: json['nickname']?.toString() ?? '',
      faceUrl: json['faceUrl']?.toString() ??
          json['face_url']?.toString() ??
          json['avatarUrl']?.toString() ??
          '',
      childrenCount: _readInt(json['childrenCount'] ?? json['children_count']),
      rebatePer10000:
          _readInt(json['rebatePer10000'] ?? json['rebate_per_10000']),
      maxNegative:
          _readInt(json['maxNegative'] ?? json['max_negative_balance']),
    );
  }
}

class SangongAdminUserReportPage {
  const SangongAdminUserReportPage({
    required this.users,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
  });

  final List<SangongAdminUserReport> users;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

class SangongUserGroup {
  const SangongUserGroup({
    required this.id,
    required this.name,
    this.code = '',
  });

  final int id;
  final String name;
  final String code;

  factory SangongUserGroup.fromJson(Map<String, dynamic> json) {
    return SangongUserGroup(
      id: _readInt(json['id'] ?? json['groupId'] ?? json['group_id']),
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
    );
  }
}

/// 上下分流水记录（credit/debit 成功响应 `ledger`、user-flow `ledgerFlow[]`）。
class SangongLedgerRecord {
  const SangongLedgerRecord({
    this.ledgerId,
    this.imUserId = '',
    this.operator = '',
    this.type = '',
    this.typeLabel = '',
    this.note = '',
    this.balanceChange = 0,
    this.balanceAfter = 0,
    this.createdAt = '',
  });

  final int? ledgerId;
  final String imUserId;
  final String operator;
  final String type;
  final String typeLabel;
  final String note;
  final int balanceChange;
  final int balanceAfter;
  final String createdAt;

  factory SangongLedgerRecord.fromJson(Map<String, dynamic> json) {
    return SangongLedgerRecord(
      ledgerId:
          _readNullableInt(json['ledgerId'] ?? json['ledger_id'] ?? json['id']),
      imUserId:
          json['imUserId']?.toString() ?? json['im_user_id']?.toString() ?? '',
      operator: json['operator']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      typeLabel:
          json['typeLabel']?.toString() ?? json['type_label']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      balanceChange: _readInt(
        json['balanceChange'] ?? json['balance_change'] ?? json['amount'],
      ),
      balanceAfter: _readInt(
        json['balanceAfter'] ?? json['balance_after'] ?? json['balance'],
      ),
      createdAt:
          json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
    );
  }
}

class SangongBalanceMutationResult {
  const SangongBalanceMutationResult({
    required this.balance,
    this.group = const SangongUserGroupInfo(),
    this.ledger,
  });

  final int balance;
  final SangongUserGroupInfo group;
  final SangongLedgerRecord? ledger;

  factory SangongBalanceMutationResult.fromJson(Map<String, dynamic> json) {
    final groupRaw = json['group'];
    final ledgerRaw = json['ledger'];
    return SangongBalanceMutationResult(
      balance: _readInt(json['balance']),
      group: groupRaw is Map
          ? SangongUserGroupInfo.fromJson(Map<String, dynamic>.from(groupRaw))
          : SangongUserGroupInfo(
              groupId: _readNullableInt(json['groupId'] ?? json['group_id']),
              name: json['groupName']?.toString() ??
                  json['group_name']?.toString() ??
                  '',
            ),
      ledger: ledgerRaw is Map
          ? SangongLedgerRecord.fromJson(Map<String, dynamic>.from(ledgerRaw))
          : null,
    );
  }

  factory SangongBalanceMutationResult.fromResponse(Map<String, dynamic> json) {
    final ledgerRaw = json['ledger'];
    final ledger = ledgerRaw is Map
        ? SangongLedgerRecord.fromJson(Map<String, dynamic>.from(ledgerRaw))
        : null;
    final user = json['user'];
    if (user is Map) {
      final parsed = SangongBalanceMutationResult.fromJson(
        Map<String, dynamic>.from(user),
      );
      return SangongBalanceMutationResult(
        balance: parsed.balance,
        group: parsed.group,
        ledger: ledger ?? parsed.ledger,
      );
    }
    final parsed = SangongBalanceMutationResult.fromJson(json);
    return SangongBalanceMutationResult(
      balance: parsed.balance,
      group: parsed.group,
      ledger: ledger ?? parsed.ledger,
    );
  }
}

bool _readBool(dynamic value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final text = value?.toString().trim().toLowerCase() ?? '';
  if (text == 'true' || text == '1' || text == 'yes' || text == 'on') {
    return true;
  }
  if (text == 'false' || text == '0' || text == 'no' || text == 'off') {
    return false;
  }
  return fallback;
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

double _readDouble(dynamic value, {double fallback = 0}) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _readNullableInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  final parsed = int.tryParse(value.toString());
  return parsed;
}

List<int> _readIntList(dynamic value) {
  if (value is! List) {
    return const [];
  }
  return value.map((e) => _readInt(e)).where((e) => e > 0).toList();
}

List<T> _parseJsonList<T>(
  dynamic raw,
  T Function(Map<String, dynamic> json) mapper, {
  List<String> keys = const [],
}) {
  dynamic source = raw;
  if (source is Map) {
    for (final key in keys) {
      final nested = source[key];
      if (nested is List) {
        source = nested;
        break;
      }
    }
  }
  if (source is! List) {
    return const [];
  }
  final items = <T>[];
  for (final item in source) {
    if (item is Map) {
      items.add(mapper(Map<String, dynamic>.from(item)));
    }
  }
  return items;
}

/// 用户下注明细（`flow.betFlow[]`）。
class SangongUserBetFlowEntry {
  const SangongUserBetFlowEntry({
    this.userId,
    this.imUserId = '',
    this.nickname = '',
    this.sessionId = 0,
    this.roundId = 0,
    this.periodNo = 0,
    this.door = 0,
    this.betAmount = 0,
    this.net,
    this.settled = false,
    this.compare = '',
    this.settledAt = '',
    this.betAt = '',
  });

  final int? userId;
  final String imUserId;
  final String nickname;
  final int sessionId;
  final int roundId;
  final int periodNo;
  final int door;
  final int betAmount;
  final int? net;
  final bool settled;
  final String compare;
  final String settledAt;
  final String betAt;

  factory SangongUserBetFlowEntry.fromJson(Map<String, dynamic> json) {
    return SangongUserBetFlowEntry(
      userId: _readNullableInt(json['userId'] ?? json['user_id']),
      imUserId:
          json['imUserId']?.toString() ?? json['im_user_id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      sessionId: _readInt(json['sessionId'] ?? json['session_id']),
      roundId: _readInt(json['roundId'] ?? json['round_id']),
      periodNo: _readInt(json['periodNo'] ?? json['period_no']),
      door: _readInt(json['door']),
      betAmount: _readInt(
        json['betAmount'] ?? json['bet_amount'] ?? json['amount'],
      ),
      net: _readNullableInt(json['net'] ?? json['winLoss'] ?? json['win_loss']),
      betAt: [
        json['betAt'],
        json['bet_at'],
        json['placedAt'],
        json['placed_at'],
        json['createdAt'],
        json['created_at']
      ]
          .map((value) => value?.toString().trim() ?? '')
          .firstWhere((value) => value.isNotEmpty, orElse: () => ''),
      settled: json['settled'] == true,
      compare: json['compare']?.toString() ?? '',
      settledAt:
          json['settledAt']?.toString() ?? json['settled_at']?.toString() ?? '',
    );
  }

  String get doorLabel => door > 0 ? '$door门' : '';
}

/// 用户庄/合庄流水（`flow.bankerFlow[]`）。
class SangongUserBankerFlowEntry {
  const SangongUserBankerFlowEntry({
    this.userId,
    this.imUserId = '',
    this.nickname = '',
    this.sessionId = 0,
    this.roundId = 0,
    this.periodNo = 0,
    this.role = '',
    this.roleLabel = '',
    this.totalBetAmount = 0,
    this.bankerRakePoints,
    this.packageAmount = 0,
    this.sharePercent = 0,
    this.net = 0,
    this.settledAt = '',
  });

  final int? userId;
  final String imUserId;
  final String nickname;
  final int sessionId;
  final int roundId;
  final int periodNo;
  final String role;
  final String roleLabel;
  final int totalBetAmount;
  final int? bankerRakePoints;
  final int packageAmount;
  final double sharePercent;
  final int net;
  final String settledAt;

  factory SangongUserBankerFlowEntry.fromJson(Map<String, dynamic> json) {
    return SangongUserBankerFlowEntry(
      userId: _readNullableInt(json['userId'] ?? json['user_id']),
      imUserId:
          json['imUserId']?.toString() ?? json['im_user_id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      sessionId: _readInt(json['sessionId'] ?? json['session_id']),
      roundId: _readInt(json['roundId'] ?? json['round_id']),
      periodNo: _readInt(json['periodNo'] ?? json['period_no']),
      role: json['role']?.toString() ?? '',
      roleLabel:
          json['roleLabel']?.toString() ?? json['role_label']?.toString() ?? '',
      totalBetAmount: _readInt(
        json['totalBetAmount'] ??
            json['total_bet_amount'] ??
            json['doorTotal'] ??
            json['door_total'],
      ),
      bankerRakePoints: _readNullableInt(
        json['bankerRakePoints'] ??
            json['banker_rake_points'] ??
            json['rakePoints'] ??
            json['rake_points'],
      ),
      packageAmount: _readInt(
        json['packageAmount'] ??
            json['package_amount'] ??
            json['poolAmount'] ??
            json['pool_amount'],
      ),
      sharePercent: _readDouble(
        json['sharePercent'] ?? json['share_percent'],
      ),
      net: _readInt(json['net'] ?? json['winLoss'] ?? json['win_loss']),
      settledAt:
          json['settledAt']?.toString() ?? json['settled_at']?.toString() ?? '',
    );
  }

  String get displayRoleLabel {
    final label = roleLabel.trim();
    if (label.isNotEmpty) {
      return label;
    }
    final normalized = role.trim().toLowerCase();
    if (normalized == 'co_bank' || normalized.contains('co')) {
      return '合庄';
    }
    if (normalized == 'banker' || normalized.contains('bank')) {
      return '庄家';
    }
    return role.trim().isNotEmpty ? role.trim() : '庄';
  }
}

/// 用户上下分记录（`flow.ledgerFlow[]`）。
class SangongUserLedgerFlowEntry {
  const SangongUserLedgerFlowEntry({
    this.ledgerId,
    this.userId,
    this.imUserId = '',
    this.nickname = '',
    this.operator = '',
    this.type = '',
    this.typeLabel = '',
    this.note = '',
    this.balanceChange = 0,
    this.balanceAfter = 0,
    this.createdAt = '',
  });

  final int? ledgerId;
  final int? userId;
  final String imUserId;
  final String nickname;
  final String operator;
  final String type;
  final String typeLabel;
  final String note;
  final int balanceChange;
  final int balanceAfter;
  final String createdAt;

  bool get isCredit {
    final normalized = type.trim().toLowerCase();
    return normalized == 'credit' || balanceChange > 0;
  }

  bool get isDebit {
    final normalized = type.trim().toLowerCase();
    return normalized == 'debit' || balanceChange < 0;
  }

  factory SangongUserLedgerFlowEntry.fromJson(Map<String, dynamic> json) {
    return SangongUserLedgerFlowEntry(
      ledgerId:
          _readNullableInt(json['ledgerId'] ?? json['ledger_id'] ?? json['id']),
      userId: _readNullableInt(json['userId'] ?? json['user_id']),
      imUserId:
          json['imUserId']?.toString() ?? json['im_user_id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      operator: json['operator']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      typeLabel:
          json['typeLabel']?.toString() ?? json['type_label']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      balanceChange: _readInt(
        json['balanceChange'] ?? json['balance_change'] ?? json['amount'],
      ),
      balanceAfter: _readInt(
        json['balanceAfter'] ?? json['balance_after'] ?? json['balance'],
      ),
      createdAt:
          json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
    );
  }

  String get displayTypeLabel {
    final label = typeLabel.trim();
    if (label.isNotEmpty) {
      return label;
    }
    if (isCredit) {
      return '上分';
    }
    if (isDebit) {
      return '下分';
    }
    final trimmed = type.trim();
    return trimmed.isNotEmpty ? trimmed : '调整';
  }
}

/// `GET /admin/reports/user-flow` 的 `section` 参数。
enum SangongUserFlowSection {
  all('all'),
  bet('bet'),
  banker('banker'),
  ledger('ledger');

  const SangongUserFlowSection(this.value);

  final String value;
}

/// `flow.counts`：各分类条数核对。
class SangongUserFlowCounts {
  const SangongUserFlowCounts({
    this.bet = 0,
    this.banker = 0,
    this.ledger = 0,
  });

  final int bet;
  final int banker;
  final int ledger;

  factory SangongUserFlowCounts.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SangongUserFlowCounts();
    }
    return SangongUserFlowCounts(
      bet: _readInt(json['bet'] ?? json['betFlow'] ?? json['bet_flow']),
      banker:
          _readInt(json['banker'] ?? json['bankerFlow'] ?? json['banker_flow']),
      ledger:
          _readInt(json['ledger'] ?? json['ledgerFlow'] ?? json['ledger_flow']),
    );
  }
}

/// `GET /admin/reports/user-flow` 响应 `flow` 节点。
class SangongUserFlowReport {
  const SangongUserFlowReport({
    this.entries = const [],
    this.hasUnifiedEntries = false,
    this.betEntries = const [],
    this.scoreEntries = const [],
    this.explicitBankerEntries,
    this.coBankFlow = const [],
    this.scope = 'all',
    this.sessionId,
    this.startedAt = '',
    this.imUserId = '',
    this.userId,
    this.nickname = '',
    this.section = SangongUserFlowSection.all,
    this.counts = const SangongUserFlowCounts(),
    this.betFlow = const [],
    this.bankerFlow = const [],
    this.ledgerFlow = const [],
  });

  final List<SangongAccountFlowEntry> entries, betEntries, scoreEntries;
  final List<SangongAccountFlowEntry>? explicitBankerEntries;
  final List<SangongCoBankFlowEntry> coBankFlow;
  final bool hasUnifiedEntries;
  final String scope;
  final int? sessionId;
  final String startedAt;
  final String imUserId;
  final int? userId;
  final String nickname;
  final SangongUserFlowSection section;
  final SangongUserFlowCounts counts;
  final List<SangongUserBetFlowEntry> betFlow;
  final List<SangongUserBankerFlowEntry> bankerFlow;
  final List<SangongUserLedgerFlowEntry> ledgerFlow;

  /// Main and co-banker settlements share this exact ledger type.
  List<SangongAccountFlowEntry> get bankerEntries =>
      explicitBankerEntries ??
      entries
          .where((entry) => entry.type == 'settle_banker')
          .toList(growable: false);

  bool get isAllHistory =>
      scope.trim().toLowerCase() == 'all' &&
      (sessionId == null || sessionId! <= 0);

  factory SangongUserFlowReport.fromJson(Map<String, dynamic> json) {
    final flowRaw = json['flow'];
    final flow = flowRaw is Map ? Map<String, dynamic>.from(flowRaw) : json;
    if (flow['entries'] is List || flow['coBankFlow'] is List) {
      final entries =
          _parseJsonList(flow['entries'], SangongAccountFlowEntry.fromJson)
            ..sort((a, b) => b.ledgerId.compareTo(a.ledgerId));
      final bets = flow['betFlow'] is List
          ? _parseJsonList(flow['betFlow'], SangongAccountFlowEntry.fromJson)
          : entries.where((e) => e.isBet).toList(growable: false);
      final bankers = (flow['bankerFlow'] is List
              ? _parseJsonList(
                  flow['bankerFlow'], SangongAccountFlowEntry.fromJson)
              : entries)
          .where((e) => e.type == 'settle_banker')
          .toList(growable: false);
      bets.sort((a, b) => b.ledgerId.compareTo(a.ledgerId));
      bankers.sort((a, b) => b.ledgerId.compareTo(a.ledgerId));
      final scores =
          entries.where((e) => e.isScoreTransfer).toList(growable: false);
      return SangongUserFlowReport(
        hasUnifiedEntries: true,
        explicitBankerEntries: List.unmodifiable(bankers),
        coBankFlow: List.unmodifiable(_parseJsonList(
            flow['coBankFlow'], SangongCoBankFlowEntry.fromJson)),
        entries: List.unmodifiable(entries),
        betEntries: List.unmodifiable(bets),
        scoreEntries: List.unmodifiable(scores),
        nickname: _firstNonEmptyNickname(entries.map((e) => e.nickname)),
        counts: SangongUserFlowCounts(
            bet: bets.length, banker: bankers.length, ledger: scores.length),
      );
    }
    final filtersRaw = flow['filters'];
    final filters = filtersRaw is Map
        ? Map<String, dynamic>.from(filtersRaw)
        : const <String, dynamic>{};
    final sectionRaw = filters['section']?.toString() ?? 'all';
    final section = SangongUserFlowSection.values.firstWhere(
      (e) => e.value == sectionRaw,
      orElse: () => SangongUserFlowSection.all,
    );

    final betFlow = _parseJsonList(
      flow['betFlow'] ?? flow['bet_flow'] ?? flow['bets'],
      SangongUserBetFlowEntry.fromJson,
    );
    final bankerFlow = _parseJsonList(
      flow['bankerFlow'] ?? flow['banker_flow'] ?? flow['banker'],
      SangongUserBankerFlowEntry.fromJson,
    );
    final ledgerFlow = _parseJsonList(
      flow['ledgerFlow'] ??
          flow['ledger_flow'] ??
          flow['balanceChanges'] ??
          flow['balance_changes'],
      SangongUserLedgerFlowEntry.fromJson,
    );

    final nickname = _firstNonEmptyNickname([
      ...betFlow.map((e) => e.nickname),
      ...bankerFlow.map((e) => e.nickname),
      ...ledgerFlow.map((e) => e.nickname),
    ]);

    final countsRaw = flow['counts'];
    final counts = countsRaw is Map
        ? SangongUserFlowCounts.fromJson(
            Map<String, dynamic>.from(countsRaw),
          )
        : const SangongUserFlowCounts();

    return SangongUserFlowReport(
      scope: flow['scope']?.toString() ?? 'all',
      sessionId: _readNullableInt(flow['sessionId'] ?? flow['session_id']),
      startedAt:
          flow['startedAt']?.toString() ?? flow['started_at']?.toString() ?? '',
      imUserId: filters['imUserId']?.toString() ??
          filters['im_user_id']?.toString() ??
          '',
      userId: _readNullableInt(filters['userId'] ?? filters['user_id']),
      nickname: nickname,
      section: section,
      counts: counts,
      betFlow: betFlow,
      bankerFlow: bankerFlow,
      ledgerFlow: ledgerFlow,
    );
  }
}

String _firstNonEmptyNickname(Iterable<String> names) {
  for (final name in names) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}
