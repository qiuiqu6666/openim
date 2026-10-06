// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
double _agentRebateDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _agentRebateInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _agentRebateBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1';
}

Map<String, dynamic> _agentRebateMap(dynamic value) {
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}

/// 三公服务返回的代理入口上下文。
class AgentEntryContextDto {
  const AgentEntryContextDto({
    required this.showAgentEntry,
    this.tenantId = '',
    this.agentImUserId = '',
    this.agentImGroupId = '',
    this.userId = '',
    this.rebatePct = 0,
    this.balance = 0,
    this.playerCount = 0,
    this.directPlayerCount = 0,
    this.pendingAgentRebate = 0,
    this.nickname = '',
  });

  final bool showAgentEntry;
  final String tenantId;
  final String agentImUserId;
  final String agentImGroupId;
  final String userId;
  final double rebatePct;
  final double balance;
  final int playerCount;
  final int directPlayerCount;
  final double pendingAgentRebate;
  final String nickname;

  factory AgentEntryContextDto.fromJson(Map<String, dynamic> json) {
    final agent = _agentRebateMap(json['agent']);
    return AgentEntryContextDto(
      showAgentEntry: _agentRebateBool(json['showAgentEntry']),
      tenantId: json['tenantId']?.toString().trim() ?? '',
      agentImUserId: json['agentImUserId']?.toString().trim() ?? '',
      agentImGroupId: json['agentImGroupId']?.toString().trim() ?? '',
      userId: (json['userId'] ?? agent['userId'])?.toString() ?? '',
      rebatePct: _agentRebateDouble(json['rebatePct'] ?? agent['rebatePct']),
      balance: _agentRebateDouble(json['balance'] ?? agent['balance']),
      playerCount: _agentRebateInt(json['playerCount'] ?? agent['playerCount']),
      directPlayerCount: _agentRebateInt(
        json['directPlayerCount'] ?? agent['directPlayerCount'],
      ),
      pendingAgentRebate: _agentRebateDouble(
        json['pendingAgentRebate'] ?? agent['pendingAgentRebate'],
      ),
      nickname: agent['nickname']?.toString() ?? '',
    );
  }
}

class SangongTeamMemberDto {
  const SangongTeamMemberDto({
    required this.userId,
    required this.parentUserId,
    required this.levelNo,
    required this.imUserId,
    required this.nickname,
    required this.avatarUrl,
    required this.balance,
    required this.rebatePct,
    required this.rebatePer10000,
    required this.playerTurnover,
    required this.bankerTurnover,
    this.totalTurnover,
    this.latestPlayerTurnover = 0,
    this.latestBankerTurnover = 0,
    required this.todayUp,
    required this.todayDown,
    required this.todayProfitLoss,
    required this.todayRebate,
    required this.batchTotalTurnover,
    required this.batchUp,
    required this.batchDown,
    required this.batchProfitLoss,
    required this.batchRebate,
    this.pendingRebate = 0,
  });

  final int userId;
  final int parentUserId;
  final int levelNo;
  final String imUserId;
  final String nickname;
  final String avatarUrl;
  final double balance;
  final double rebatePct;
  final double rebatePer10000;
  final double playerTurnover;
  final double bankerTurnover;
  final double? totalTurnover;
  final double latestPlayerTurnover;
  final double latestBankerTurnover;
  final double todayUp;
  final double todayDown;
  final double todayProfitLoss;
  final double todayRebate;
  final double batchTotalTurnover;
  final double batchUp;
  final double batchDown;
  final double batchProfitLoss;
  final double batchRebate;
  final double pendingRebate;

  double get displayTotalTurnover =>
      totalTurnover ?? (playerTurnover + bankerTurnover);

  factory SangongTeamMemberDto.fromJson(Map<String, dynamic> json) {
    return SangongTeamMemberDto(
      userId: _agentRebateInt(json['userId']),
      parentUserId: _agentRebateInt(json['parentUserId']),
      levelNo: _agentRebateInt(json['levelNo']),
      imUserId: json['imUserId']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      balance: _agentRebateDouble(json['balance']),
      rebatePct: _agentRebateDouble(json['rebatePct']),
      rebatePer10000: _agentRebateDouble(json['rebatePer10000']),
      playerTurnover: _agentRebateDouble(json['playerTurnover']),
      bankerTurnover: _agentRebateDouble(json['bankerTurnover']),
      totalTurnover: json.containsKey('totalTurnover')
          ? _agentRebateDouble(json['totalTurnover'])
          : null,
      latestPlayerTurnover: _agentRebateDouble(json['latestPlayerTurnover']),
      latestBankerTurnover: _agentRebateDouble(json['latestBankerTurnover']),
      todayUp: _agentRebateDouble(json['todayUp']),
      todayDown: _agentRebateDouble(json['todayDown']),
      todayProfitLoss: _agentRebateDouble(json['todayProfitLoss']),
      todayRebate: _agentRebateDouble(json['todayRebate']),
      batchTotalTurnover: _agentRebateDouble(json['batchTotalTurnover']),
      batchUp: _agentRebateDouble(json['batchUp']),
      batchDown: _agentRebateDouble(json['batchDown']),
      batchProfitLoss: _agentRebateDouble(json['batchProfitLoss']),
      batchRebate: _agentRebateDouble(json['batchRebate']),
      pendingRebate: _agentRebateDouble(json['pendingRebate']),
    );
  }
}

class SangongTeamAgentDto {
  const SangongTeamAgentDto({
    this.userId = 0,
    this.imUserId = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.balance = 0,
    this.maxNegative = 0,
    this.rebatePct = 0,
    this.rebatePer10000 = 0,
  });

  final int userId;
  final String imUserId;
  final String nickname;
  final String avatarUrl;
  final double balance;
  final double maxNegative;
  final double rebatePct;
  final double rebatePer10000;

  /// 前端可见的可划转近似值：余额 + 可负额度（不含 reserved）。
  double get transferAvailable => balance + maxNegative;

  SangongTeamAgentDto copyWith({
    double? balance,
    double? maxNegative,
  }) {
    return SangongTeamAgentDto(
      userId: userId,
      imUserId: imUserId,
      nickname: nickname,
      avatarUrl: avatarUrl,
      balance: balance ?? this.balance,
      maxNegative: maxNegative ?? this.maxNegative,
      rebatePct: rebatePct,
      rebatePer10000: rebatePer10000,
    );
  }

  factory SangongTeamAgentDto.fromJson(Map<String, dynamic> json) {
    return SangongTeamAgentDto(
      userId: _agentRebateInt(json['userId'] ?? json['user_id']),
      imUserId:
          json['imUserId']?.toString() ?? json['im_user_id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatarUrl:
          json['avatarUrl']?.toString() ?? json['avatar_url']?.toString() ?? '',
      balance: _agentRebateDouble(json['balance']),
      maxNegative: _agentRebateDouble(
        json['maxNegative'] ?? json['max_negative_balance'],
      ),
      rebatePct: _agentRebateDouble(json['rebatePct'] ?? json['rebate_pct']),
      rebatePer10000: _agentRebateDouble(
        json['rebatePer10000'] ?? json['rebate_per_10000'],
      ),
    );
  }
}

class SangongTeamMembersDto {
  const SangongTeamMembersDto({
    required this.tenantId,
    required this.direct,
    required this.aggregation,
    required this.sessionId,
    required this.batchNo,
    required this.businessDate,
    required this.sessionStatus,
    required this.members,
    this.userId = 0,
    this.agent,
  });

  final String tenantId;
  final int userId;
  final bool direct;
  final String aggregation;
  final int sessionId;
  final String batchNo;
  final String businessDate;
  final String sessionStatus;
  final SangongTeamAgentDto? agent;
  final List<SangongTeamMemberDto> members;

  factory SangongTeamMembersDto.fromJson(Map<String, dynamic> json) {
    final session = _agentRebateMap(json['session']);
    final rawMembers = json['members'];
    final agentRaw = json['agent'];
    return SangongTeamMembersDto(
      tenantId: json['tenantId']?.toString() ?? '',
      userId: _agentRebateInt(json['userId'] ?? json['user_id']),
      direct: _agentRebateBool(json['direct']),
      aggregation: json['aggregation']?.toString() ?? '',
      sessionId: _agentRebateInt(session['id']),
      batchNo: session['batchNo']?.toString() ?? '',
      businessDate: session['businessDate']?.toString() ?? '',
      sessionStatus: session['status']?.toString() ?? '',
      agent: agentRaw is Map
          ? SangongTeamAgentDto.fromJson(Map<String, dynamic>.from(agentRaw))
          : null,
      members: rawMembers is List
          ? rawMembers
              .whereType<Map>()
              .map((item) => SangongTeamMemberDto.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : const <SangongTeamMemberDto>[],
    );
  }
}

/// 金额统一按整数展示（不显示小数点）。
String formatAgentRebateAmount(num value) => value.round().toString();

List<AgentDescendantHistoryItemDto> sortAgentDescendantHistoryNewestFirst(
  Iterable<AgentDescendantHistoryItemDto> items,
) {
  final list = List<AgentDescendantHistoryItemDto>.from(items);
  list.sort((left, right) => right.businessDate.compareTo(left.businessDate));
  return list;
}

/// 反水历史按业务日倒序（最新在上）。
List<AgentRebateHistoryDayDto> sortAgentRebateHistoryDaysNewestFirst(
  Iterable<AgentRebateHistoryDayDto> days,
) {
  final list = List<AgentRebateHistoryDayDto>.from(days);
  list.sort((left, right) => right.businessDate.compareTo(left.businessDate));
  return list;
}

/// `rebateRate` 为万分比：`50` → `0.5%`（待反水 = flow × rate ÷ 10000）。
String formatAgentRebateRate(num rate) {
  final percent = rate / 100;
  if (percent == percent.roundToDouble()) {
    return '${percent.toStringAsFixed(0)}%';
  }
  final fixed = percent.toStringAsFixed(2);
  final trimmed = fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(
        RegExp(r'\.$'),
        '',
      );
  return '$trimmed%';
}

/// `GET /me/robot/groups/{groupId}` 群机器码绑定状态。
class RobotGroupBindingDto {
  const RobotGroupBindingDto({
    this.groupId = '',
    this.bound = false,
    this.enabled = false,
    this.robotId = '',
    this.machineCodeMasked,
  });

  final String groupId;
  final bool bound;
  final bool enabled;
  final String robotId;
  final String? machineCodeMasked;

  bool get isReady => bound && enabled;

  factory RobotGroupBindingDto.fromJson(Map<String, dynamic> json) {
    return RobotGroupBindingDto(
      groupId: json['groupId']?.toString() ?? '',
      bound: _agentRebateBool(json['bound']),
      enabled: _agentRebateBool(json['enabled']),
      robotId: json['robotId']?.toString() ?? '',
      machineCodeMasked: json['machineCodeMasked']?.toString(),
    );
  }
}

class AgentPlayerDto {
  const AgentPlayerDto({
    required this.userId,
    required this.playerNo,
    required this.displayName,
    required this.playerType,
    required this.levelNo,
    required this.balance,
    required this.rebateRate,
    required this.isAgent,
  });

  final String userId;
  final String playerNo;
  final String displayName;
  final String playerType;
  final int levelNo;
  final double balance;
  final double rebateRate;
  final bool isAgent;

  factory AgentPlayerDto.fromJson(Map<String, dynamic> json) {
    return AgentPlayerDto(
      userId: json['userId']?.toString() ?? '',
      playerNo: json['playerNo']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      playerType: json['playerType']?.toString() ?? '',
      levelNo: _agentRebateInt(json['levelNo']),
      balance: _agentRebateDouble(json['balance']),
      rebateRate: _agentRebateDouble(json['rebateRate']),
      isAgent: _agentRebateBool(json['isAgent']),
    );
  }
}

class AgentRebateSummaryDto {
  const AgentRebateSummaryDto({
    this.agentWxid,
    this.agentNo,
    this.agentName,
    required this.agentCount,
    required this.playerCount,
    required this.totalBalance,
    required this.totalFlow,
    required this.playerProfitLoss,
    required this.platformProfitLoss,
    required this.totalUp,
    required this.totalDown,
    required this.totalRebated,
    required this.pendingRebate,
    required this.agentDifferenceRebate,
    required this.estimatedTotalRebate,
    required this.agentPendingFlow,
    required this.agentPendingRebate,
    this.dataTime,
  });

  final String? agentWxid;
  final String? agentNo;
  final String? agentName;
  final int agentCount;
  final int playerCount;
  final double totalBalance;
  final double totalFlow;
  final double playerProfitLoss;
  final double platformProfitLoss;
  final double totalUp;
  final double totalDown;
  final double totalRebated;
  final double pendingRebate;
  final double agentDifferenceRebate;
  final double estimatedTotalRebate;
  final double agentPendingFlow;
  final double agentPendingRebate;
  final DateTime? dataTime;

  factory AgentRebateSummaryDto.fromJson(Map<String, dynamic> json) {
    return AgentRebateSummaryDto(
      agentWxid: json['agentWxid']?.toString(),
      agentNo: json['agentNo']?.toString(),
      agentName: json['agentName']?.toString(),
      agentCount: _agentRebateInt(json['agentCount']),
      playerCount: _agentRebateInt(json['playerCount']),
      totalBalance: _agentRebateDouble(json['totalBalance']),
      totalFlow: _agentRebateDouble(json['totalFlow']),
      playerProfitLoss: _agentRebateDouble(json['playerProfitLoss']),
      platformProfitLoss: _agentRebateDouble(json['platformProfitLoss']),
      totalUp: _agentRebateDouble(json['totalUp']),
      totalDown: _agentRebateDouble(json['totalDown']),
      totalRebated: _agentRebateDouble(json['totalRebated']),
      pendingRebate: _agentRebateDouble(json['pendingRebate']),
      agentDifferenceRebate: _agentRebateDouble(json['agentDifferenceRebate']),
      estimatedTotalRebate: _agentRebateDouble(json['estimatedTotalRebate']),
      agentPendingFlow: _agentRebateDouble(json['agentPendingFlow']),
      agentPendingRebate: _agentRebateDouble(json['agentPendingRebate']),
      dataTime: DateTime.tryParse(json['dataTime']?.toString() ?? ''),
    );
  }
}

/// 当前页面「个人反水」区块（代理自身玩家维度）。
class AgentRebatePersonalDto {
  const AgentRebatePersonalDto({
    required this.balance,
    required this.totalFlow,
    required this.totalProfitLoss,
    required this.totalRebate,
    required this.pendingRebate,
    required this.agentPendingRebate,
  });

  final double balance;
  final double totalFlow;
  final double totalProfitLoss;

  /// 个人反水汇总 / 已反水。
  final double totalRebate;
  final double pendingRebate;

  /// 下级级差相关。
  final double agentPendingRebate;

  factory AgentRebatePersonalDto.fromJson(Map<String, dynamic> json) {
    return AgentRebatePersonalDto(
      balance: _agentRebateDouble(json['balance']),
      totalFlow: _agentRebateDouble(json['totalFlow']),
      totalProfitLoss: _agentRebateDouble(json['totalProfitLoss']),
      totalRebate: _agentRebateDouble(json['totalRebate']),
      pendingRebate: _agentRebateDouble(json['pendingRebate']),
      agentPendingRebate: _agentRebateDouble(json['agentPendingRebate']),
    );
  }
}

class AgentRebateCurrentDto {
  const AgentRebateCurrentDto({
    required this.userId,
    required this.summary,
    this.personal,
  });

  final String userId;
  final AgentRebateSummaryDto summary;
  final AgentRebatePersonalDto? personal;

  factory AgentRebateCurrentDto.fromJson(Map<String, dynamic> json) {
    final personalRaw =
        json['personal'] ?? json['personalSummary'] ?? json['self'];
    return AgentRebateCurrentDto(
      userId: json['userId']?.toString() ?? '',
      summary: AgentRebateSummaryDto.fromJson(_agentRebateMap(json['summary'])),
      personal: personalRaw is Map
          ? AgentRebatePersonalDto.fromJson(
              Map<String, dynamic>.from(personalRaw),
            )
          : null,
    );
  }
}

class AgentRebateHistoryDayDto {
  const AgentRebateHistoryDayDto({
    required this.businessDate,
    required this.summary,
  });

  final String businessDate;
  final AgentRebateSummaryDto summary;

  factory AgentRebateHistoryDayDto.fromJson(Map<String, dynamic> json) {
    return AgentRebateHistoryDayDto(
      businessDate: json['businessDate']?.toString() ?? '',
      summary: AgentRebateSummaryDto.fromJson(json),
    );
  }
}

class AgentRebateHistoryDto {
  const AgentRebateHistoryDto({
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.total,
  });

  final String userId;
  final String startDate;
  final String endDate;
  final List<AgentRebateHistoryDayDto> days;
  final AgentRebateSummaryDto total;

  factory AgentRebateHistoryDto.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    return AgentRebateHistoryDto(
      userId: json['userId']?.toString() ?? '',
      startDate: json['startDate']?.toString() ?? '',
      endDate: json['endDate']?.toString() ?? '',
      days: rawDays is List
          ? rawDays
              .whereType<Map>()
              .map(
                (day) => AgentRebateHistoryDayDto.fromJson(
                  Map<String, dynamic>.from(day),
                ),
              )
              .toList(growable: false)
          : const [],
      total: AgentRebateSummaryDto.fromJson(_agentRebateMap(json['total'])),
    );
  }
}

class AgentRebateExportTaskDto {
  const AgentRebateExportTaskDto({
    required this.taskNo,
    required this.taskStatus,
    required this.progress,
    required this.isAsync,
    this.fileName,
    this.errorMessage,
    this.downloadPath,
  });

  final String taskNo;
  final String taskStatus;
  final int progress;
  final bool isAsync;
  final String? fileName;
  final String? errorMessage;
  final String? downloadPath;

  bool get isCompleted => taskStatus.toUpperCase() == 'COMPLETED';
  bool get isFailed => taskStatus.toUpperCase() == 'FAILED';
  bool get isPending {
    final status = taskStatus.toUpperCase();
    return status == 'PENDING' || status == 'RUNNING';
  }

  factory AgentRebateExportTaskDto.fromJson(Map<String, dynamic> json) {
    return AgentRebateExportTaskDto(
      taskNo: json['taskNo']?.toString() ?? '',
      taskStatus: json['taskStatus']?.toString() ?? '',
      progress: _agentRebateInt(json['progress']),
      isAsync: _agentRebateBool(json['async']),
      fileName: json['fileName']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      downloadPath: json['downloadPath']?.toString(),
    );
  }
}

class AgentRebateApplyDto {
  const AgentRebateApplyDto({
    required this.userId,
    required this.playerNo,
    required this.settlementType,
    required this.requestId,
    required this.taskId,
    required this.leaseToken,
    required this.databaseGeneration,
    required this.status,
    required this.flowToConsume,
    required this.rebateAmount,
    required this.existing,
  });

  final String userId;
  final String playerNo;
  final String settlementType;
  final String requestId;
  final String taskId;
  final String leaseToken;
  final String databaseGeneration;
  final String status;
  final double flowToConsume;
  final double rebateAmount;
  final bool existing;

  bool get isPending {
    final normalized = status.toUpperCase();
    return normalized == 'PENDING' || normalized == 'PROCESSING';
  }

  bool get isSuccess => status.toUpperCase() == 'SUCCESS';
  bool get isFailed => status.toUpperCase() == 'FAILED';
  bool get isNone => status.isEmpty || status.toUpperCase() == 'NONE';

  factory AgentRebateApplyDto.fromJson(Map<String, dynamic> json) {
    return AgentRebateApplyDto(
      userId: json['userId']?.toString() ?? '',
      playerNo: json['playerNo']?.toString() ?? '',
      settlementType: json['settlementType']?.toString() ?? '',
      requestId: json['requestId']?.toString() ?? '',
      taskId: json['taskId']?.toString() ?? '',
      leaseToken: json['leaseToken']?.toString() ?? '',
      databaseGeneration: json['databaseGeneration']?.toString() ?? '',
      status: json['status']?.toString() ?? 'NONE',
      flowToConsume: _agentRebateDouble(json['flowToConsume']),
      rebateAmount: _agentRebateDouble(json['rebateAmount']),
      existing: _agentRebateBool(json['existing']),
    );
  }
}

class AgentRebateDownload {
  const AgentRebateDownload({required this.bytes, required this.fileName});

  final List<int> bytes;
  final String fileName;
}

enum AgentDescendantScope {
  all('all'),
  direct('direct');

  const AgentDescendantScope(this.apiValue);

  final String apiValue;

  static AgentDescendantScope fromValue(dynamic value) {
    return value?.toString().toLowerCase() == direct.apiValue ? direct : all;
  }
}

class AgentDescendantItemDto {
  const AgentDescendantItemDto({
    required this.userId,
    required this.playerNo,
    required this.displayName,
    required this.playerType,
    required this.levelNo,
    required this.isAgent,
    required this.directParentUserId,
    required this.directParentNo,
    required this.balance,
    required this.totalFlow,
    required this.usedFlow,
    required this.remainingFlow,
    required this.totalUp,
    required this.totalDown,
    required this.playerProfitLoss,
    required this.platformProfitLoss,
    required this.rebateRate,
    required this.totalRebated,
    required this.pendingRebate,
  });

  final String userId;
  final String playerNo;
  final String displayName;
  final String playerType;
  final int levelNo;
  final bool isAgent;
  final String directParentUserId;
  final String directParentNo;
  final double balance;
  final double totalFlow;
  final double usedFlow;
  final double remainingFlow;
  final double totalUp;
  final double totalDown;
  final double playerProfitLoss;
  final double platformProfitLoss;
  final double rebateRate;
  final double totalRebated;
  final double pendingRebate;

  factory AgentDescendantItemDto.fromJson(Map<String, dynamic> json) {
    return AgentDescendantItemDto(
      userId: json['userId']?.toString() ?? '',
      playerNo: json['playerNo']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      playerType: json['playerType']?.toString() ?? '',
      levelNo: _agentRebateInt(json['levelNo']),
      isAgent: _agentRebateBool(json['isAgent']),
      directParentUserId: json['directParentUserId']?.toString() ?? '',
      directParentNo: json['directParentNo']?.toString() ?? '',
      balance: _agentRebateDouble(json['balance']),
      totalFlow: _agentRebateDouble(json['totalFlow']),
      usedFlow: _agentRebateDouble(json['usedFlow']),
      remainingFlow: _agentRebateDouble(json['remainingFlow']),
      totalUp: _agentRebateDouble(json['totalUp']),
      totalDown: _agentRebateDouble(json['totalDown']),
      playerProfitLoss: _agentRebateDouble(json['playerProfitLoss']),
      platformProfitLoss: _agentRebateDouble(json['platformProfitLoss']),
      rebateRate: _agentRebateDouble(json['rebateRate']),
      totalRebated: _agentRebateDouble(json['totalRebated']),
      pendingRebate: _agentRebateDouble(json['pendingRebate']),
    );
  }
}

class AgentDescendantsDto {
  const AgentDescendantsDto({
    required this.userId,
    required this.scope,
    required this.total,
    required this.items,
    this.page = 1,
    this.pageSize = 0,
    this.count = 0,
    this.hasMore = false,
  });

  final String userId;
  final AgentDescendantScope scope;
  final int total;
  final int page;
  final int pageSize;
  final int count;
  final bool hasMore;
  final List<AgentDescendantItemDto> items;

  factory AgentDescendantsDto.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map(
              (item) => AgentDescendantItemDto.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((item) => item.userId.isNotEmpty)
            .toList(growable: false)
        : const <AgentDescendantItemDto>[];
    final page = json.containsKey('page') ? _agentRebateInt(json['page']) : 1;
    final pageSize = json.containsKey('pageSize')
        ? _agentRebateInt(json['pageSize'])
        : items.length;
    final count = json.containsKey('count')
        ? _agentRebateInt(json['count'])
        : items.length;
    final hasMore =
        json.containsKey('hasMore') ? _agentRebateBool(json['hasMore']) : false;
    return AgentDescendantsDto(
      userId: json['userId']?.toString() ?? '',
      scope: AgentDescendantScope.fromValue(json['scope']),
      total: json.containsKey('total')
          ? _agentRebateInt(json['total'])
          : items.length,
      page: page < 1 ? 1 : page,
      pageSize: pageSize < 0 ? 0 : pageSize,
      count: count < 0 ? 0 : count,
      hasMore: hasMore,
      items: items,
    );
  }
}

class AgentDescendantTreeNodeDto {
  const AgentDescendantTreeNodeDto({
    required this.item,
    required this.childCount,
    required this.descendantCount,
    required this.children,
  });

  final AgentDescendantItemDto item;
  final int childCount;
  final int descendantCount;
  final List<AgentDescendantTreeNodeDto> children;

  factory AgentDescendantTreeNodeDto.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    final children = rawChildren is List
        ? rawChildren
            .whereType<Map>()
            .map(
              (child) => AgentDescendantTreeNodeDto.fromJson(
                Map<String, dynamic>.from(child),
              ),
            )
            .where((child) => child.item.userId.isNotEmpty)
            .toList(growable: false)
        : const <AgentDescendantTreeNodeDto>[];
    return AgentDescendantTreeNodeDto(
      item: AgentDescendantItemDto.fromJson(_agentRebateMap(json['item'])),
      childCount: json.containsKey('childCount')
          ? _agentRebateInt(json['childCount'])
          : children.length,
      descendantCount: json.containsKey('descendantCount')
          ? _agentRebateInt(json['descendantCount'])
          : children.fold<int>(
              0,
              (total, child) => total + 1 + child.descendantCount,
            ),
      children: children,
    );
  }
}

class AgentFirstLevelAgentGroupDto {
  const AgentFirstLevelAgentGroupDto({
    required this.agent,
    required this.children,
    required this.descendantCount,
    required this.descendants,
  });

  final AgentDescendantItemDto agent;
  final List<AgentDescendantTreeNodeDto> children;
  final int descendantCount;
  final List<AgentDescendantItemDto> descendants;

  factory AgentFirstLevelAgentGroupDto.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    final children = rawChildren is List
        ? rawChildren
            .whereType<Map>()
            .map(
              (child) => AgentDescendantTreeNodeDto.fromJson(
                Map<String, dynamic>.from(child),
              ),
            )
            .where((child) => child.item.userId.isNotEmpty)
            .toList(growable: false)
        : const <AgentDescendantTreeNodeDto>[];
    final rawDescendants = json['descendants'];
    final descendants = rawDescendants is List
        ? rawDescendants
            .whereType<Map>()
            .map(
              (item) => AgentDescendantItemDto.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((item) => item.userId.isNotEmpty)
            .toList(growable: false)
        : const <AgentDescendantItemDto>[];
    return AgentFirstLevelAgentGroupDto(
      agent: AgentDescendantItemDto.fromJson(_agentRebateMap(json['agent'])),
      children: children,
      descendantCount: json.containsKey('descendantCount')
          ? _agentRebateInt(json['descendantCount'])
          : descendants.length,
      descendants: descendants,
    );
  }
}

class AgentFirstLevelAgentsDto {
  const AgentFirstLevelAgentsDto({
    required this.userId,
    required this.agentCount,
    required this.descendantTotal,
    required this.agents,
  });

  final String userId;
  final int agentCount;
  final int descendantTotal;
  final List<AgentFirstLevelAgentGroupDto> agents;

  factory AgentFirstLevelAgentsDto.fromJson(Map<String, dynamic> json) {
    final userId = json['userId']?.toString().trim() ?? '';
    final rawAgents = json['agents'];
    final parsedAgents = rawAgents is List
        ? rawAgents
            .whereType<Map>()
            .map(
              (group) => AgentFirstLevelAgentGroupDto.fromJson(
                Map<String, dynamic>.from(group),
              ),
            )
            .where((group) => group.agent.userId.isNotEmpty)
            .toList(growable: false)
        : const <AgentFirstLevelAgentGroupDto>[];
    // agents 是服务端明确返回的可见集合。客户端不能再按直属关系过滤，
    // 否则历史数据缺少/写错 directParentUserId 时，接口有记录但页面会丢人。
    final agents = parsedAgents;
    return AgentFirstLevelAgentsDto(
      userId: userId,
      agentCount: agents.length,
      descendantTotal: agents.fold<int>(
        0,
        (total, group) => total + group.descendantCount,
      ),
      agents: agents,
    );
  }

  /// 用 `/me/agent/descendants` 的扁平全量（含非代理）组装「我的下级」分组。
  /// `first-level-agents` 只返回一级代理，直属普通玩家及其下级不会出现在该接口里。
  factory AgentFirstLevelAgentsDto.fromDescendants(AgentDescendantsDto data) {
    final me = data.userId.trim();
    final byId = <String, AgentDescendantItemDto>{};
    for (final item in data.items) {
      final id = item.userId.trim();
      if (id.isEmpty) continue;
      byId.putIfAbsent(id, () => item);
    }
    final items = byId.values.toList(growable: false);

    bool isRoot(AgentDescendantItemDto item) {
      final parent = item.directParentUserId.trim();
      return parent.isEmpty ||
          parent == me ||
          parent == item.userId.trim() ||
          !byId.containsKey(parent);
    }

    final roots = items.where(isRoot).toList();
    final rootIds = <String>{
      for (final root in roots) root.userId.trim(),
    };
    final nested = <String, List<AgentDescendantItemDto>>{
      for (final id in rootIds) id: <AgentDescendantItemDto>[],
    };

    String? owningRootId(AgentDescendantItemDto item) {
      final visiting = <String>{item.userId.trim()};
      var parent = item.directParentUserId.trim();
      while (parent.isNotEmpty && parent != me) {
        if (rootIds.contains(parent)) return parent;
        if (!visiting.add(parent)) return null;
        final node = byId[parent];
        if (node == null) return null;
        parent = node.directParentUserId.trim();
      }
      return null;
    }

    final unassigned = <AgentDescendantItemDto>[];
    for (final item in items) {
      if (rootIds.contains(item.userId.trim())) continue;
      final owner = owningRootId(item);
      if (owner == null) {
        unassigned.add(item);
      } else {
        nested[owner]!.add(item);
      }
    }
    for (final item in unassigned) {
      final id = item.userId.trim();
      if (!rootIds.add(id)) continue;
      roots.add(item);
      nested[id] = <AgentDescendantItemDto>[];
    }

    final groups = [
      for (final root in roots)
        AgentFirstLevelAgentGroupDto(
          agent: root,
          children: const <AgentDescendantTreeNodeDto>[],
          descendantCount: nested[root.userId.trim()]!.length,
          descendants: nested[root.userId.trim()]!,
        ),
    ];
    return AgentFirstLevelAgentsDto(
      userId: me,
      agentCount: groups.length,
      descendantTotal: groups.fold<int>(
        0,
        (total, group) => total + group.descendantCount,
      ),
      agents: groups,
    );
  }
}

class AgentDescendantDetailDto {
  const AgentDescendantDetailDto({
    required this.userId,
    required this.item,
    required this.directChildCount,
    required this.descendantCount,
    this.teamTotalUp = 0,
    this.teamTotalDown = 0,
  });

  final String userId;
  final AgentDescendantItemDto item;
  final int directChildCount;
  final int descendantCount;

  /// 「他 + 他的线」合计上分，来自 `GET /me/agent/descendants/{userId}`。
  final double teamTotalUp;

  /// 「他 + 他的线」合计下分。
  final double teamTotalDown;

  factory AgentDescendantDetailDto.fromJson(Map<String, dynamic> json) {
    final item = AgentDescendantItemDto.fromJson(_agentRebateMap(json['item']));
    final teamUp = json['teamTotalUp'] ?? json['team_total_up'];
    final teamDown = json['teamTotalDown'] ?? json['team_total_down'];
    return AgentDescendantDetailDto(
      userId: json['userId']?.toString() ?? '',
      item: item,
      directChildCount: _agentRebateInt(json['directChildCount']),
      descendantCount: _agentRebateInt(json['descendantCount']),
      teamTotalUp: teamUp != null ? _agentRebateDouble(teamUp) : item.totalUp,
      teamTotalDown:
          teamDown != null ? _agentRebateDouble(teamDown) : item.totalDown,
    );
  }
}

class AgentDescendantHistoryItemDto {
  const AgentDescendantHistoryItemDto({
    required this.businessDate,
    required this.userId,
    required this.playerNo,
    required this.displayName,
    required this.playerType,
    required this.directParentUserId,
    required this.balance,
    required this.totalFlow,
    required this.totalUp,
    required this.totalDown,
    required this.playerProfitLoss,
    required this.platformProfitLoss,
    required this.totalRebated,
    required this.pendingRebate,
    required this.rebateRate,
  });

  final String businessDate;
  final String userId;
  final String playerNo;
  final String displayName;
  final String playerType;
  final String directParentUserId;
  final double balance;
  final double totalFlow;
  final double totalUp;
  final double totalDown;
  final double playerProfitLoss;
  final double platformProfitLoss;
  final double totalRebated;
  final double pendingRebate;
  final double rebateRate;

  factory AgentDescendantHistoryItemDto.fromJson(Map<String, dynamic> json) {
    return AgentDescendantHistoryItemDto(
      businessDate: json['businessDate']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      playerNo: json['playerNo']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      playerType: json['playerType']?.toString() ?? '',
      directParentUserId: json['directParentUserId']?.toString() ?? '',
      balance: _agentRebateDouble(json['balance']),
      totalFlow: _agentRebateDouble(json['totalFlow']),
      totalUp: _agentRebateDouble(json['totalUp']),
      totalDown: _agentRebateDouble(json['totalDown']),
      playerProfitLoss: _agentRebateDouble(json['playerProfitLoss']),
      platformProfitLoss: _agentRebateDouble(json['platformProfitLoss']),
      totalRebated: _agentRebateDouble(json['totalRebated']),
      pendingRebate: _agentRebateDouble(json['pendingRebate']),
      rebateRate: _agentRebateDouble(json['rebateRate']),
    );
  }
}

class AgentDescendantsHistoryDto {
  const AgentDescendantsHistoryDto({
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.targetUserId,
    required this.total,
    required this.items,
  });

  final String userId;
  final String startDate;
  final String endDate;
  final String? targetUserId;
  final int total;
  final List<AgentDescendantHistoryItemDto> items;

  factory AgentDescendantsHistoryDto.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map(
              (item) => AgentDescendantHistoryItemDto.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((item) => item.userId.isNotEmpty)
            .toList(growable: false)
        : const <AgentDescendantHistoryItemDto>[];
    final target = json['targetUserId']?.toString().trim();
    return AgentDescendantsHistoryDto(
      userId: json['userId']?.toString() ?? '',
      startDate: json['startDate']?.toString() ?? '',
      endDate: json['endDate']?.toString() ?? '',
      targetUserId: target == null || target.isEmpty ? null : target,
      total: json.containsKey('total')
          ? _agentRebateInt(json['total'])
          : items.length,
      items: items,
    );
  }
}
