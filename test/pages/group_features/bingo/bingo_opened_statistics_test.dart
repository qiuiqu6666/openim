import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/bingo/bingo_draw.dart';
import 'package:openim/pages/group_features/bingo/bingo_opened_statistics.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_opened_statistics.dart';

void main() {
  testWidgets('reuses statistics with a 100-period cap and separate tie counts', (tester) async {
    final draws = List.generate(101, (i) => BingoDraw(
      issue: '$i', drawTime: DateTime(2026), closeTime: DateTime(2026),
      regular: const [],
      special: i == 0
        ? const BingoBall(49, '马', Colors.green, bigSmall: '平', oddEven: '平')
        : const BingoBall(34, '鸡', Colors.red, bigSmall: '大', oddEven: '双'),
    ));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SingleChildScrollView(child: BingoOpenedStatistics(draws: draws)))));
    expect(find.byType(MarkSixOpenedStatistics), findsOneWidget);
    expect(find.text('基本类型（100期）'), findsOneWidget);
    void count(String key, String value) {
      expect(find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(value)), findsOneWidget);
    }
    count('opened-cell-size-平', '1');
    count('opened-cell-parity-平', '1');
    count('opened-cell-combination-大双', '99');
    count('opened-cell-wave-红', '99');
    count('opened-cell-zodiac-鸡', '99');
    expect(tester.takeException(), isNull);
  });
}
