import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/media_browser/media_thumbnail_hero.dart';
import 'package:openim_common/src/widgets/photo_browser_hero.dart';

void main() {
  for (final dragged in [false, true]) {
    testWidgets('return flight hides when chat is popped / dragged=$dragged',
        (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final slide = GlobalKey<ExtendedImageSlidePageState>();
      const pictureKey = ValueKey('full-picture');
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('conversations')),
      ));
      navigator.currentState!.push<void>(MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: Center(
            child: MediaThumbnailHero(
              tag: 'picture',
              child: SizedBox(width: 80, height: 80),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      navigator.currentState!.push<void>(PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => ExtendedImageSlidePage(
          key: slide,
          child: HeroWidget(
            tag: 'picture',
            slidePagekey: slide,
            child: const SizedBox.expand(key: pictureKey),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      if (dragged) {
        slide.currentState!.slide(const Offset(0, 160));
        await tester.pump();
      }
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byKey(pictureKey), findsOneWidget,
          reason: 'Normal return still paints the full picture shuttle');
      navigator.currentState!.pop();
      await tester.pump();
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byKey(pictureKey), findsNothing,
            reason: 'The shuttle must not paint over the conversation list');
      }
      await tester.pumpAndSettle();
      expect(find.text('conversations'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
