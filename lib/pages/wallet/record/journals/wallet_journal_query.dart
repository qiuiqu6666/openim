/// Immutable filters for the authenticated user's cursor-based ledger feed.
class WalletJournalQuery {
  const WalletJournalQuery({
    this.currency,
    this.bizType,
    this.type,
    this.direction,
    this.startTime,
    this.endTime,
    this.limit = 20,
    this.cursor,
  });

  final String? currency;
  final String? bizType;
  final String? type;
  final String? direction;
  final int? startTime;
  final int? endTime;
  final int limit;
  final String? cursor;

  WalletJournalQuery withCursor(String? cursor) => WalletJournalQuery(
        currency: currency,
        bizType: bizType,
        type: type,
        direction: direction,
        startTime: startTime,
        endTime: endTime,
        limit: limit,
        cursor: cursor,
      );

  Map<String, dynamic> toQueryParameters() {
    if (limit < 1 ||
        limit > 100 ||
        (currency != null &&
            !const ['USDT', 'TRX', 'BI99'].contains(currency)) ||
        (direction != null &&
            !const ['income', 'expense', 'freeze', 'unfreeze', 'neutral']
                .contains(direction))) {
      throw const FormatException('无效的资金明细筛选参数');
    }
    return {
      if (currency != null) 'currency': currency,
      if (bizType != null) 'bizType': bizType,
      if (type != null) 'type': type,
      if (direction != null) 'direction': direction,
      if (startTime != null) 'startTime': startTime,
      if (endTime != null) 'endTime': endTime,
      'limit': limit,
      // Cursor is opaque: preserve it exactly and omit it for a first page.
      if (cursor != null && cursor!.isNotEmpty) 'cursor': cursor,
    };
  }
}
