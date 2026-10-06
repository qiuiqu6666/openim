/// Validates the structures used by the agent pages before DTO defaults can
/// turn a malformed response into zero balances or an empty team.
class SangongAgentResponse {
  static const _memberNumbers = <String>[
    'userId',
    'parentUserId',
    'levelNo',
    'balance',
    'rebatePct',
    'rebatePer10000',
    'playerTurnover',
    'bankerTurnover',
    'totalTurnover',
    'latestPlayerTurnover',
    'latestBankerTurnover',
    'todayUp',
    'todayDown',
    'todayProfitLoss',
    'todayRebate',
    'batchTotalTurnover',
    'batchUp',
    'batchDown',
    'batchProfitLoss',
    'batchRebate',
    'pendingRebate',
    'maxNegative',
    'max_negative_balance',
    'rebate_pct',
    'rebate_per_10000',
  ];

  static num? number(dynamic value) {
    final parsed = value is num ? value : num.tryParse('$value');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static void members(Map<String, dynamic> data) {
    _members(data['members']);
    _optionalMap(data, 'session');
    final agent = _optionalMap(data, 'agent');
    if (agent != null) _numbers(agent, _memberNumbers);
  }

  static void dashboard(Map<String, dynamic> data) {
    final summary = _requiredMap(data['summary']);
    _members(data['members']);
    _optionalMap(data, 'batch');
    _numbers(summary, const [
      'totalBalance',
      'totalTurnover',
      'playerTurnover',
      'bankerTurnover',
      'memberCount',
      'directMemberCount',
      'totalUp',
      'totalDown',
      'totalProfitLoss',
      'profitLoss',
      'rebateAmount',
      'pendingRebate',
    ]);
  }

  static void memberDashboard(Map<String, dynamic> data, String requestedId) {
    final member = _requiredMap(data['member']);
    _member(member);
    if ('${member['imUserId']}'.trim() != requestedId.trim()) {
      throw const FormatException('Unexpected Sangong member identity');
    }
    _optionalMap(data, 'batch');
  }

  static void daily(Map<String, dynamic> data) {
    final days = data['days'];
    if (days is! List) {
      throw const FormatException('Invalid Sangong daily records');
    }
    for (final raw in days) {
      final day = _requiredMap(raw);
      if (day['businessDate']?.toString().trim().isNotEmpty != true) {
        throw const FormatException('Missing Sangong business date');
      }
      _numbers(day, const [
        'balance',
        'profitLoss',
        'playerTurnover',
        'bankerTurnover',
        'totalTurnover',
        'totalUp',
        'totalDown',
        'rebate',
        'totalRebate',
      ]);
    }
  }

  static void _members(dynamic value) {
    if (value is! List) {
      throw const FormatException('Invalid Sangong team members');
    }
    for (final item in value) {
      _member(_requiredMap(item));
    }
  }

  static void _member(Map<dynamic, dynamic> member) {
    if (member['imUserId']?.toString().trim().isNotEmpty != true) {
      throw const FormatException('Missing Sangong member identity');
    }
    _numbers(member, _memberNumbers);
  }

  static Map<dynamic, dynamic> _requiredMap(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Invalid Sangong agent response');
    }
    return value;
  }

  static Map<dynamic, dynamic>? _optionalMap(
      Map<String, dynamic> data, String field) {
    final value = data[field];
    return value == null ? null : _requiredMap(value);
  }

  static void _numbers(Map<dynamic, dynamic> data, List<String> fields) {
    for (final field in fields) {
      final value = data[field];
      if (value != null && number(value) == null) {
        throw FormatException('Invalid Sangong numeric field: $field');
      }
    }
  }
}
