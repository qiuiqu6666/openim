import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';
import 'package:openim_live/src/widgets/call_surface/call_full_screen_surface.dart';
import 'package:openim_live/src/widgets/incoming_call/incoming_call_view.dart';
import 'package:openim_live/src/widgets/live_button.dart';

const _preview = bool.fromEnvironment('INCOMING_CALL_PREVIEW');
const _boundary = ValueKey('incoming-call-preview');

Widget _host({
  required Brightness brightness,
  required TargetPlatform platform,
  required CallType type,
  double textScale = 1,
  VoidCallback? accept,
}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
            brightness: brightness,
            platform: platform,
            fontFamily: _preview ? 'IncomingPreviewFont' : null),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: page!,
        ),
        home: RepaintBoundary(
          key: _boundary,
          child: CallFullScreenSurface(
            child: IncomingCallView(
              userID: 'peer',
              userInfo: UserInfo(userID: 'peer', nickname: '来电联系人'),
              callType: type,
              onAccept: accept ?? () {},
              onReject: () {},
              onMinimize: () {},
            ),
          ),
        ),
      ),
    );

Future<void> _paint(WidgetTester tester) async {
  final context = tester.element(find.byType(IncomingCallView));
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  await tester.runAsync(() async {
    await Future.wait(
        images.map((image) => precacheImage(image.image, context)));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!_preview) return;
    final font = ByteData.sublistView(
        await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
    await (FontLoader('IncomingPreviewFont')..addFont(Future.value(font)))
        .load();
  });
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final type in CallType.values) {
        testWidgets('99chat incoming geometry $brightness $platform $type',
            (tester) async {
          tester.view.physicalSize = const Size(375, 812);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
              _host(brightness: brightness, platform: platform, type: type));
          await _paint(tester);
          expect(find.byType(BottomSheetView), findsNothing);
          expect(find.text('打开通话'), findsNothing);
          final avatar = tester.getRect(find.byType(AvatarView));
          expect(avatar, const Rect.fromLTWH(132.5, 203, 110, 110));
          expect(tester.getTopLeft(find.text('来电联系人')).dy, 333);
          final hint = type == CallType.audio ? '邀请你语音通话' : '邀请你视频通话';
          expect(
              tester.getTopLeft(find.text(hint)).dy, closeTo(812 * 2 / 3, .01));
          final actions =
              tester.widgetList<LiveButton>(find.byType(LiveButton)).toList();
          expect(actions.map((e) => e.text), [StrRes.hangUp, StrRes.pickUp]);
          for (final action in actions) {
            final image = find.descendant(
                of: find.byWidget(action), matching: find.byType(Image));
            expect(tester.getSize(image), const Size(60, 60));
            expect(tester.getRect(find.byWidget(action)).bottom, 762);
          }
          final boundary =
              tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final pixels =
                  (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                      .buffer
                      .asUint8List();
              expect(pixels.sublist(0, 4), [45, 45, 45, 255]);
              // Check actual button pixels, including PNG decode and fade completion.
              for (final action in actions) {
                final rect = tester.getRect(find.byWidget(action));
                final x = rect.center.dx.round();
                final y = (rect.top + 10).round();
                final offset = (y * 375 + x) * 4;
                final r = pixels[offset], g = pixels[offset + 1];
                expect(action.text == StrRes.hangUp ? r > g + 50 : g > r + 50,
                    isTrue);
              }
              if (_preview && platform == TargetPlatform.iOS) {
                final file = File(
                    'build/incoming-call-preview/${brightness.name}-${type.name}.png');
                await file.parent.create(recursive: true);
                final png =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                await file.writeAsBytes(png!.buffer.asUint8List());
              }
            } finally {
              image.dispose();
            }
          });
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('landscape and large text can reach and use incoming actions',
      (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var accepted = 0;
    await tester.pumpWidget(_host(
        brightness: Brightness.dark,
        platform: TargetPlatform.android,
        type: CallType.video,
        textScale: 2,
        accept: () => accepted++));
    await _paint(tester);
    await tester.ensureVisible(find.text(StrRes.pickUp));
    await tester.pumpAndSettle();
    await tester.tap(find.text(StrRes.pickUp));
    expect(accepted, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
