import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';

import '../../../support/unicode/unicode_samples.dart';

void main() {
  for (final sample in unicodeSamples) {
    test('history query and sender name preserve ${sample.name}', () {
      final query = ChatHistorySearchQuery(keyword: sample.text).snapshot();
      final sender = ChatHistorySender(
          userID: 'internal-id',
          displayName: 'fallback',
          nickname: sample.text);
      expect(query.keyword, sample.text);
      expect(sender.name, sample.text);
      expect(sender.userID, 'internal-id');
    });
  }
}
