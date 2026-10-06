import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_management_page.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_panel.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/ink_bounds_test_support.dart';

class _EmptyStickerApi extends PersonalStickerApi {
  @override
  Future<({List<PersonalSticker> items, String? nextCursor})> page(
          {String? cursor, int limit = 50}) async =>
      (items: <PersonalSticker>[], nextCursor: null);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('sticker add tiles contain pressed ink in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await DataSp.init();
      await DataSp.putLoginCertificate(LoginCertificate.fromJson(
          {'userID': 'ink-user', 'chatToken': 'ink-test-token'}));
      final store = PersonalStickerStore(api: _EmptyStickerApi());
      addTearDown(store.dispose);
      await store.refresh();
      var added = 0;
      final boundary = GlobalKey();
      ThemeData theme() => ThemeData(
          brightness: brightness,
          highlightColor: Colors.red,
          splashColor: Colors.green,
          splashFactory: InkRipple.splashFactory);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          theme: theme(),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
                body: PersonalStickerPanel(
              store: store,
              onAdd: () async => added++,
              onSend: (_) async {},
            )),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectInkWithinSurface(tester,
          boundaryKey: boundary,
          target: find.byKey(const ValueKey('sticker-add-tile')),
          radius: BorderRadius.circular(8));
      expect(find.byType(PersonalStickerManagementPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      // Capture the management route's own Material where its ink is painted.
      final routeBoundary = GlobalKey();
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          theme: theme(),
          home: RepaintBoundary(
              key: routeBoundary,
              child: PersonalStickerManagementPage(
                  store: store, onAdd: () async => added++)),
        ),
      ));
      await tester.pumpAndSettle();
      await expectInkWithinSurface(tester,
          boundaryKey: routeBoundary,
          target: find.byKey(const ValueKey('management-add-tile')),
          radius: BorderRadius.circular(8));
      expect(added, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
