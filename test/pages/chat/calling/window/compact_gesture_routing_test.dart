import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/models/call_types.dart';
import 'package:openim_live/src/widgets/call_compact_surface.dart';

const _windowKey = ValueKey('floating-call-window');
const _videoKey = ValueKey('local-video-hit-region');

Widget _host(Widget child) => ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ),
    );

class _GestureProbe {
  int restores = 0, parentDrags = 0, focuses = 0, cameraScales = 0;
}

/// LiveKit checks dart:io Platform, so a Windows widget test cannot activate
/// its Android/iOS branch using debugDefaultTargetPlatformOverride. This
/// fixture uses the exact recognizer types of that branch: a video child with
/// onTapDown and onScaleStart/onScaleUpdate, inside the real compact surface.
/// It tests routing, not native focus, camera zoom, or rendered camera frames.
class _MobileVideoFloat extends StatefulWidget {
  const _MobileVideoFloat(this.probe);
  final _GestureProbe probe;

  @override
  State<_MobileVideoFloat> createState() => _MobileVideoFloatState();
}

class _MobileVideoFloatState extends State<_MobileVideoFloat> {
  Offset offset = const Offset(160, 40);

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned(
          left: offset.dx,
          top: offset.dy,
          width: 110,
          height: 196,
          child: GestureDetector(
            key: _windowKey,
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.probe.restores++,
            onPanUpdate: (details) {
              widget.probe.parentDrags++;
              setState(() => offset += details.delta);
            },
            child: CallCompactSurface(
              state: CallState.call,
              duration: 0,
              video: GestureDetector(
                onTapDown: (_) => widget.probe.focuses++,
                onScaleStart: (_) => widget.probe.cameraScales++,
                onScaleUpdate: (_) {},
                child: const ColoredBox(
                  key: _videoKey,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      ]);
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets('compact video tap reaches restore, not camera focus',
      (tester) async {
    final probe = _GestureProbe();
    await tester.pumpWidget(_host(_MobileVideoFloat(probe)));
    await tester.tapAt(tester.getCenter(find.byKey(_videoKey)));
    await tester.pump();

    expect(probe.restores, 1);
    expect(probe.focuses, 0);
    expect(probe.cameraScales, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact video drag moves window without restore or camera zoom',
      (tester) async {
    final probe = _GestureProbe();
    await tester.pumpWidget(_host(_MobileVideoFloat(probe)));
    final before = tester.getRect(find.byKey(_windowKey));
    await tester.dragFrom(
        tester.getCenter(find.byKey(_videoKey)), const Offset(-60, 50));
    await tester.pump();
    final after = tester.getRect(find.byKey(_windowKey));

    expect(probe.parentDrags, greaterThan(0));
    expect(after.left, lessThan(before.left));
    expect(after.top, greaterThan(before.top));
    expect(probe.restores, 0);
    expect(probe.focuses, 0);
    expect(probe.cameraScales, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact status text also restores without reaching video input',
      (tester) async {
    final probe = _GestureProbe();
    await tester.pumpWidget(_host(_MobileVideoFloat(probe)));
    final label = find.descendant(
        of: find.byType(CallCompactSurface), matching: find.byType(Text));
    expect(label, findsOneWidget);
    await tester.tap(label);
    await tester.pump();

    expect(probe.restores, 1);
    expect(probe.focuses, 0);
    expect(probe.cameraScales, 0);
    expect(tester.takeException(), isNull);
  });
}
