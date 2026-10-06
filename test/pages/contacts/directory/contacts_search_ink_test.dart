import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/directory/widgets/contacts_search_bar.dart';
import 'package:openim_common/openim_common.dart';

import '../../../support/ink_bounds_test_support.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('contacts search ink stays inside its capsule in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var searches = 0;
      final boundary = GlobalKey();
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme: ThemeData(
            brightness: brightness,
            highlightColor: Colors.red,
            splashColor: Colors.green,
            splashFactory: InkRipple.splashFactory,
          ),
          home: RepaintBoundary(
              key: boundary,
              child:
                  Scaffold(body: ContactsSearchBar(onTap: () => searches++))),
        ),
      ));
      await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey('contacts-search-button'));
      await expectInkWithinSurface(tester,
          boundaryKey: boundary,
          target: target,
          radius: BorderRadius.circular(10));
      expect(searches, 1);
      final rect = tester.getRect(target);
      // The generous original tap area still includes the outside margin.
      await tester.tapAt(Offset(rect.center.dx, rect.top - 4));
      expect(searches, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
