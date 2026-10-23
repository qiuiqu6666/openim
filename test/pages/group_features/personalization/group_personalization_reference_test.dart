import 'dart:io';
import 'package:openim/pages/group_features/personalization/group_personalization_style.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:openim/pages/group_features/personalization/group_personalization_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/personalization/group_personalization.dart';
import 'package:openim/pages/group_features/personalization/group_personalization_editor.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets(
      'reference layout keeps all thirteen icons in two rows and working',
      (tester) async {
    tester.view.physicalSize = const Size(469, 838);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = Styles.isDark;
    Styles.isDark = false;
    addTearDown(() => Styles.isDark = previous);
    var appearance =
        const GroupPersonalization(color: 0xFFDC2626, iconKey: 'robot');
    var saved = false;
    final boundaryKey = GlobalKey();
    if (const bool.fromEnvironment('CAPTURE_REFERENCE')) {
      await tester.runAsync(() async {
        final chinese = FontLoader('ReferenceChinese')
          ..addFont(Future.value(ByteData.sublistView(
              await File('C:/Windows/Fonts/msyh.ttc').readAsBytes())));
        await chinese.load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
        await (FontLoader('packages/cupertino_icons/CupertinoIcons')
              ..addFont(rootBundle
                  .load('packages/cupertino_icons/assets/CupertinoIcons.ttf')))
            .load();
      });
    }
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
            theme: ThemeData(
                fontFamily: const bool.fromEnvironment('CAPTURE_REFERENCE')
                    ? 'ReferenceChinese'
                    : null),
            home: StatefulBuilder(
                builder: (context, update) => RepaintBoundary(
                    key: boundaryKey,
                    child: GroupPersonalizationEditor(
                      name: '太6了123123',
                      appearance: appearance,
                      busy: false,
                      onChanged: (value) => update(() => appearance = value),
                      onUpload: () {},
                      onSave: () => saved = true,
                    ))))));
    await tester.runAsync(() => precacheImage(
        const AssetImage(GroupPersonalizationStyle.previewBackground),
        boundaryKey.currentContext!));
    await tester.runAsync(() => precacheImage(
        const AssetImage(GroupPersonalizationArtwork.asset),
        boundaryKey.currentContext!));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('自定义颜色'), findsNothing);
    expect(tester.getTopLeft(find.byTooltip('图标 机器人')).dy,
        tester.getTopLeft(find.byTooltip('图标 足球')).dy);
    expect(tester.getTopLeft(find.byTooltip('图标 火箭')).dy,
        tester.getTopLeft(find.byTooltip('图标 樱花')).dy);
    if (const bool.fromEnvironment('CAPTURE_REFERENCE')) {
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('E:/openim/group-personalization-preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('昵称后'));
    await tester.pump();
    expect(appearance.iconPosition, GroupIconPosition.after);
    await tester.tap(find.byTooltip('图标 樱花'));
    await tester.pump();
    expect(appearance.iconKey, 'flower');
    expect(appearance.iconPosition, GroupIconPosition.after);
    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    expect(saved, isTrue);
  });
}
