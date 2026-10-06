import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/profile_panel_fixture.dart';
import 'support/profile_panel_host.dart';

final _exportPreview =
    Platform.environment['EXPORT_USER_PROFILE_PREVIEW'] == '1' ||
        const String.fromEnvironment('EXPORT_USER_PROFILE_PREVIEW') == '1';

Future<void> _loadFonts() async {
  final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
  for (final family in [
    'ProfilePreviewFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
  });

  for (final friend in [true, false]) {
    for (final dark in [false, true]) {
      testWidgets(
          'export actual ${friend ? 'friend' : 'stranger'} profile ($dark)',
          (tester) async {
        await tester.runAsync(_loadFonts);
        final fixture = ProfilePanelFixture(friend: friend);
        final moments = profileMomentsRepository();
        final contacts = ProfileContactsFixture();
        addTearDown(moments.dispose);
        addTearDown(contacts.stars.dispose);
        final key = GlobalKey();
        await mountProfilePanel(tester,
            fixture: fixture,
            moments: moments,
            contacts: contacts,
            dark: dark,
            fontFamily: 'ProfilePreviewFont',
            previewKey: key);
        expect(tester.takeException(), isNull);
        expect(find.text('详细资料'), findsOneWidget);
        expect(find.byType(GlassAppBar), findsOneWidget);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final suffix = friend ? '' : '-stranger';
            final output = File(
                'docs/previews/user-profile-99chat$suffix-${dark ? 'dark' : 'light'}.png');
            await output.parent.create(recursive: true);
            await output.writeAsBytes(png!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        Get.reset();
      }, skip: !_exportPreview);
    }
  }
}
