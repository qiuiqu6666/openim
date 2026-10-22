import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/bingo/bingo_draw.dart';
import 'package:openim/pages/group_features/bingo/bingo_history_table.dart';
import 'bingo_fixture.dart';

void main() {
  testWidgets('history stays a compact single-row table on narrow screens',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
          width: 360,
          child: BingoHistoryTable(
            draws: [BingoDraw.fromResponse(bingoResponse())],
          )),
    ))));
    expect(find.text('115059821'), findsOneWidget);
    expect(find.text('115059822'), findsNothing);
    expect(find.text('142'), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);
    expect(find.text('时间'), findsNothing);
    expect(find.text('2026-10-22 18:35:00'), findsNothing);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(-1600, 0));
    await tester.pumpAndSettle();
    expect(find.text('尾量').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
