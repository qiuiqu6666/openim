import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/identity/group_name_label.dart';
import 'package:openim/pages/group_features/personalization/group_personalization.dart';
import 'package:openim/pages/group_features/personalization/group_personalization_artwork.dart';
import 'package:openim/pages/group_features/personalization/group_icon_position_picker.dart';

void main() {
  test('position survives metadata and legacy values default to before', () {
    final ex = const GroupPersonalization(
            iconKey: 'star', iconPosition: GroupIconPosition.after)
        .mergeInto('{"other":true}');
    expect(
        GroupPersonalization.fromEx(ex).iconPosition, GroupIconPosition.after);
    expect(GroupPersonalization.metadata(ex)['other'], true);
    for (final field in ['', ',"iconPosition":"invalid"']) {
      expect(
          GroupPersonalization.fromEx(
                  '{"groupPersonalization":{"version":1$field}}')
              .iconPosition,
          GroupIconPosition.before);
    }
  });

  for (final position in GroupIconPosition.values) {
    testWidgets('name renders icon ${position.name} with bounded long name',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 160,
                  child: GroupNameLabel(
                      name: 'a very long group nickname',
                      ex: GroupPersonalization(
                              iconKey: 'star', iconPosition: position)
                          .mergeInto(null))))));
      final iconX =
          tester.getCenter(find.byType(GroupPersonalizationArtwork)).dx;
      final textX =
          tester.getCenter(find.text('a very long group nickname')).dx;
      expect(iconX < textX, position == GroupIconPosition.before);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('picker supports large text and disabled state in $brightness',
        (tester) async {
      var value = GroupIconPosition.before;
      var busy = false;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: StatefulBuilder(
              builder: (context, update) => Scaffold(
                  body: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: const TextScaler.linear(2)),
                      child: SizedBox(
                          width: 280,
                          child: GroupIconPositionPicker(
                              value: value,
                              onChanged: busy
                                  ? null
                                  : (next) => update(() {
                                        value = next;
                                        busy = true;
                                      }))))))));
      await tester.tap(find.text('昵称后'));
      await tester.pumpAndSettle();
      expect(value, GroupIconPosition.after);
      await tester.tap(find.text('昵称前'));
      await tester.pump();
      expect(value, GroupIconPosition.after);
      expect(tester.takeException(), isNull);
    });
  }
}
