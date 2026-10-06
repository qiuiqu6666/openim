// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
/// Participation is a share allocation, not a balance deduction.
class SangongCoBankFlowEntry {
  SangongCoBankFlowEntry.fromJson(Map<String, dynamic> json)
      : roundId = json['roundId']?.toString() ?? '',
        sessionId = json['sessionId']?.toString() ?? '',
        periodNo = json['periodNo']?.toString() ?? '',
        imUserId = json['imUserId']?.toString() ?? '',
        nickname = json['nickname']?.toString() ?? '',
        amount = num.tryParse('${json['amount']}') ?? 0,
        sharePercent = num.tryParse('${json['sharePercent']}') ?? 0,
        poolTotal = num.tryParse('${json['poolTotal']}') ?? 0,
        settledAmount = num.tryParse('${json['settledAmount']}') ?? 0,
        isMainBanker = json['isMainBanker'] == true;

  final String roundId, sessionId, periodNo, imUserId, nickname;
  final num amount, sharePercent, poolTotal, settledAmount;
  final bool isMainBanker;
}
