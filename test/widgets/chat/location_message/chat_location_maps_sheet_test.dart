import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:openim_common/src/widgets/chat/location_message/detail/chat_location_maps_sheet.dart';

void main() {
  testWidgets('installed apps have icons, selection returns the matching index',
      (tester) async {
    int? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            selected = await showModalBottomSheet<int>(
              context: context,
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
    await tester.pumpAndSettle();
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
