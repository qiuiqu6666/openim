import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_management_page.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PreviewApi extends PersonalStickerApi {
  @override
  Future<({List<PersonalSticker> items, String? nextCursor})> page(
          {String? cursor, int limit = 50}) async =>
      (
        items: [
          PersonalSticker.fromJson({
            'id': 'theme-sticker',
            'mediaType': 'image',
            'mediaURL': 'https://example.test/unavailable.png',
            'mimeType': 'image/png',
            'sizeBytes': 10,
            'width': 50,
            'height': 50,
            'sortOrder': 1,
            'version': 1,
            'createdAt': 1,
            'updatedAt': 1,
          }),
        ],
        nextCursor: null,
      );
}

void main() {
  testWidgets('management preview and image error update while dialog is open',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'sticker-theme', 'chatToken': 'sticker-theme-token'}));
    final store = PersonalStickerStore(api: _PreviewApi());
    addTearDown(store.dispose);
    await store.refresh();
    final dark = ValueNotifier(false);
    addTearDown(dark.dispose);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: dark,
      builder: (_, isDark, __) => MaterialApp(
        theme:
            ThemeData(brightness: isDark ? Brightness.dark : Brightness.light),
        home: PersonalStickerManagementPage(store: store, onAdd: () async {}),
      ),
    ));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('management-sticker-theme-sticker')));
    await tester.pumpAndSettle();

    for (final isDark in [false, true, false]) {
      dark.value = isDark;
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget,
          reason: 'Switching theme must keep the preview open.');
      final dialog = find.byType(Dialog);
      final frame = tester.widget<Container>(find.descendant(
          of: dialog,
          matching: find.byWidgetPredicate((widget) =>
              widget is Container && widget.decoration is BoxDecoration)));
      final scheme = Theme.of(tester.element(dialog)).colorScheme;
      expect((frame.decoration! as BoxDecoration).color, scheme.surface);
      final failedImage = tester.widget<Icon>(find.descendant(
        of: dialog,
        matching: find.byIcon(Icons.broken_image_outlined),
      ));
      expect(failedImage.color, scheme.onSurfaceVariant);
      final foreground = failedImage.color!.computeLuminance();
      final background = scheme.surface.computeLuminance();
      final contrast = foreground > background
          ? (foreground + .05) / (background + .05)
          : (background + .05) / (foreground + .05);
      expect(contrast, greaterThan(3));
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          AppTokens.background(dark: isDark));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byTooltip('关闭预览'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('management-sticker-theme-sticker')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
