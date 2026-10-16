import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/media_browser/on_demand_image.dart';
import 'package:openim_common/src/widgets/media_browser/on_demand_video.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('original is never constructed before tap: $brightness',
        (tester) async {
      var originals = 0;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
            body: OnDemandImage(
          preview: (_) => const Text('preview'),
          original: (_) {
            originals++;
            return const Text('original');
          },
        )),
      ));
      expect(originals, 0);
      expect(find.text('preview'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(originals, 1);
      expect(find.text('original'), findsOneWidget);
    });
  }
  testWidgets('poster does not construct player until user plays',
      (tester) async {
    var players = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OnDemandVideo(
      autoPlay: false,
      poster: const Text('poster'),
      player: (_) {
        players++;
        return const Text('player');
      },
    ))));
    await tester.pump(const Duration(seconds: 5));
    expect(players, 0);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(players, 1);
    expect(find.text('poster'), findsNothing);
  });
}
