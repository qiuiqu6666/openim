import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/media_browser/media_reading_viewport.dart';

void main() {
  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets('reading edges clear chrome and system insets at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const childKey = ValueKey('reading-area');
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.fromLTRB(20, 44, 20, 34)),
          child: MediaReadingViewport(child: SizedBox.expand(key: childKey)),
        ),
      ));
      final insets = tester
          .widget<MediaReadingInsets>(find.byType(MediaReadingInsets))
          .insets;
      expect(insets.top, 44 + MediaReadingViewport.toolbarExtent);
      expect(insets.bottom, 34 + MediaReadingViewport.toolbarExtent);
      expect(insets.left, 20);
      expect(insets.right, 20);
      expect(tester.getSize(find.byKey(childKey)), size,
          reason: 'Insets preserve the full-screen gesture hit area');
      expect(tester.takeException(), isNull);
    });
  }
}
