import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/customer_service/widgets/customer_service_categories.dart';
import 'package:openim_common/openim_common.dart';

import '../support/ink_bounds_test_support.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'rounded buttons and action-sheet rows contain pressed ink in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      var calls = 0;
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            highlightColor: Colors.red,
            splashColor: Colors.green,
            splashFactory: InkRipple.splashFactory,
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: Material(
                  child: Column(children: [
                SizedBox(
                    width: 250,
                    child: ImageTextButton(
                      icon: ImageRes.message,
                      text: 'Message',
                      onTap: () => calls++,
                    )),
                SizedBox(
                    width: 250,
                    child: Button(
                      text: 'Pill',
                      radius: 24,
                      onTap: () => calls++,
                    )),
                BottomSheetView(
                    isOverlaySheet: true,
                    onCancel: () => calls++,
                    items: [
                      SheetItem(label: 'First', onTap: () => calls++),
                      SheetItem(label: 'Last', onTap: () => calls++),
                    ]),
                CustomerServiceCategories(
                    selectedId: 'faq', onSelected: (_) => calls++),
              ])),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      for (final (label, radius) in [
        ('Message', 6.0),
        ('Pill', 24.0),
        ('First', 6.0),
        ('Last', 6.0)
      ]) {
        final ink = find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first;
        await expectInkWithinSurface(tester,
            boundaryKey: boundary,
            target: ink,
            radius: label == 'First'
                ? BorderRadius.vertical(top: Radius.circular(radius))
                : label == 'Last'
                    ? BorderRadius.vertical(bottom: Radius.circular(radius))
                    : BorderRadius.circular(radius));
      }
      final hitArea =
          find.byKey(const ValueKey('customer-service-category-auth'));
      final ink = find.descendant(of: hitArea, matching: find.byType(InkWell));
      await expectInkWithinSurface(tester,
          boundaryKey: boundary,
          target: ink,
          radius: BorderRadius.circular(AppTokens.rSm));
      final hitRect = tester.getRect(hitArea);
      expect(hitRect.height, greaterThanOrEqualTo(44));
      await tester.tapAt(Offset(hitRect.center.dx, hitRect.top + 2));
      expect(calls, 6, reason: 'Inner and enlarged targets fire once per tap');
      expect(tester.takeException(), isNull);
    });
  }
}
