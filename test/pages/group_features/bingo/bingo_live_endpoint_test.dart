import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/bingo/bingo_repository.dart';

void main() {
  test('live provider decoding smoke check', () async {
    final repository = BingoRepository();
    try {
      final draw = await repository.fetch();
      expect(draw.regular, hasLength(6));
      expect(draw.issue, isNotEmpty);
      final history = await repository.fetchHistory(0);
      expect(history.draws, isNotEmpty);
      expect(history.draws.length, lessThanOrEqualTo(100));
      expect(history.draws.first.regular, hasLength(6));
      if (history.hasMore) {
        final older = await repository.fetchHistory(1);
        expect(older.draws, isNotEmpty);
        expect(
            older.draws.first.drawTime.isBefore(history.draws.first.drawTime),
            isTrue);
      }
      // Small diagnostic; never prints credentials or a full response.
      debugPrint(
          'Bingo live: previous=${draw.issue}, next=${draw.nextIssue}, special=${draw.special.number}, server=${draw.serverTime}');
    } finally {
      repository.dispose();
    }
  }, skip: !const bool.fromEnvironment('LIVE_BINGO'));
}
