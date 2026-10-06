import 'wallet_journal_entry.dart';

/// A server-ordered page without an invented total or offset.
class WalletJournalPage {
  WalletJournalPage({
    required List<WalletJournalEntry> items,
    required this.limit,
    required this.hasMore,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<WalletJournalEntry> items;
  final int limit;
  final bool hasMore;
  final String nextCursor;

  factory WalletJournalPage.fromJson(Map<String, dynamic> json) {
    final values = json['items'];
    final limit = json['limit'];
    final hasMore = json['hasMore'];
    final cursor = json['nextCursor'];
    if (values is! List ||
        limit is! int ||
        limit < 1 ||
        limit > 100 ||
        values.length > limit ||
        hasMore is! bool ||
        cursor is! String ||
        (hasMore && cursor.isEmpty)) {
      throw const FormatException('Invalid journal page');
    }
    return WalletJournalPage(
      items: [
        for (final value in values)
          if (value is Map)
            WalletJournalEntry.fromJson(Map<String, dynamic>.from(value))
          else
            throw const FormatException('Invalid journal item'),
      ],
      limit: limit,
      hasMore: hasMore,
      nextCursor: cursor,
    );
  }
}
