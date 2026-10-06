import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/moments_ui_fixture.dart';
import 'support/moments_ui_host.dart';

final _exportPreview =
    Platform.environment['EXPORT_MOMENTS_UI_PREVIEW'] == '1' ||
        const String.fromEnvironment('EXPORT_MOMENTS_UI_PREVIEW') == '1';

Future<void> _loadFonts() async {
  final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
  for (final family in [
    'MomentsPreviewFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

Future<void> _export(WidgetTester tester,
    {required MomentsUiSurface surface,
    required bool dark,
    bool friend = false}) async {
  await tester.runAsync(_loadFonts);
  final fixture = MomentsUiFixture();
  addTearDown(fixture.dispose);
  await prepareMomentsUiPhotos(tester, fixture);
  final key = GlobalKey();
  await mountMomentsUi(tester,
      fixture: fixture,
      surface: surface,
      dark: dark,
      authorId: friend ? momentsUiFriend.userId : null,
      profileUser: friend ? momentsUiFriend : null,
      devicePixelRatio: 2,
      fontFamily: 'MomentsPreviewFont',
      previewKey: key,
      settle: false);

  await tester.pumpAndSettle();
  await settleVisibleMomentsUiMedia(tester);
  expect(tester.takeException(), isNull);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(
      tester.widgetList<RawImage>(find.byType(RawImage)),
      everyElement(isA<RawImage>().having(
          (image) => image.image, 'decoded visible pixels', isNotNull)));
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final name = friend ? 'friend-profile' : surface.name;
      final output = File(
          'docs/previews/moments-99chat-$name-${dark ? 'dark' : 'light'}.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });

  for (final surface in MomentsUiSurface.values) {
    for (final dark in [false, true]) {
      testWidgets('export actual ${surface.name} ($dark)',
          (tester) => _export(tester, surface: surface, dark: dark),
          skip: !_exportPreview);
    }
  }
  for (final dark in [false, true]) {
    testWidgets(
        'export actual friend profile ($dark)',
        (tester) => _export(tester,
            surface: MomentsUiSurface.profile, dark: dark, friend: true),
        skip: !_exportPreview);
  }
}
