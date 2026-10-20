import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:openim_common/src/widgets/liquid_glass_surface.dart';
import 'package:openim_common/src/res/app_tokens.dart';
import 'package:openim_common/src/widgets/chat/location_message/detail/chat_location_maps_sheet.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('four map apps per row at width=$width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: ChatLocationMapsSheet(
            maps: List.generate(
                5,
                (i) => AvailableMap(
                      mapName: 'Map $i',
                      mapType: MapType.apple,
                      icon: 'packages/map_launcher/assets/icons/apple.svg',
                    ))),
      )));
      await tester.pumpAndSettle();
      final icons = find.byType(SvgPicture);
      final first = tester.getTopLeft(icons.at(0));
      for (var i = 1; i < 4; i++) {
        expect(tester.getTopLeft(icons.at(i)).dy, closeTo(first.dy, .1));
      }
      expect(tester.getTopLeft(icons.at(4)).dy, greaterThan(first.dy));
      expect(tester.getTopLeft(icons.at(4)).dx, closeTo(first.dx, .1));
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    testWidgets('map sheet is opaque and icons rounded dark=$dark',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Scaffold(
            body: ChatLocationMapsSheet(maps: [
          AvailableMap(
              mapName: 'Maps',
              mapType: MapType.apple,
              icon: 'packages/map_launcher/assets/icons/apple.svg'),
        ])),
      ));
      await tester.pumpAndSettle();
      final sheet = find.byType(ChatLocationMapsSheet);
      expect(
          find.descendant(of: sheet, matching: find.byType(LiquidGlassSurface)),
          findsNothing);
      final surface = tester.widget<Material>(
          find.descendant(of: sheet, matching: find.byType(Material)).first);
      expect(surface.color, AppTokens.surface(dark: dark));
      final clip = tester.widget<ClipRRect>(find
          .ancestor(
              of: find.byType(SvgPicture), matching: find.byType(ClipRRect))
          .first);
      expect(clip.borderRadius, BorderRadius.circular(AppTokens.rLg));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('installed apps have icons, selection returns the matching index',
      (tester) async {
    int? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            selected = await showModalBottomSheet<int>(
              context: context,
              useSafeArea: true,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => ChatLocationMapsSheet(maps: [
                AvailableMap(
                    mapName: 'Maps',
                    mapType: MapType.apple,
                    icon: 'packages/map_launcher/assets/icons/apple.svg'),
                AvailableMap(
                    mapName: 'Google Maps',
                    mapType: MapType.google,
                    icon: 'packages/map_launcher/assets/icons/google.svg'),
              ]),
            );
          },
          child: const Text('Open'),
        );
      })),
    ));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final enteringTop =
        tester.getTopLeft(find.byType(ChatLocationMapsSheet)).dy;
    await tester.pumpAndSettle();
    final sheet = find.byType(ChatLocationMapsSheet);
    final surface =
        find.descendant(of: sheet, matching: find.byType(Material)).first;
    expect(tester.getTopLeft(sheet).dy, lessThan(enteringTop));
    expect(
        tester.getRect(surface).bottom,
        closeTo(tester.view.physicalSize.height / tester.view.devicePixelRatio,
            .1));
    final material = tester.widget<Material>(surface);
    expect((material.borderRadius! as BorderRadius).bottomLeft, Radius.zero);
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.text('Get directions in browser'), findsNothing);
    await tester.tap(find.text('Google Maps'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.byType(ChatLocationMapsSheet), findsNothing);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });
}
