import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/folders/conversation_folder_swipe_region.dart';

Widget _host(
        {required bool enabled,
        required ValueChanged<int> onSwipe,
        Widget? child}) =>
    MaterialApp(
      home: Scaffold(
          body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 375,
          height: 600,
          child: ConversationFolderSwipeRegion(
            enabled: enabled,
            onSwipe: onSwipe,
            child: child ?? const ColoredBox(color: Colors.white),
          ),
        ),
      )),
    );

void main() {
  test('short and vertical gestures do not change folders', () {
    expect(
        conversationFolderSwipeDirection(
            deltaX: -200, deltaY: 0, viewportWidth: 375),
        0);
    expect(
        conversationFolderSwipeDirection(
            deltaX: -300, deltaY: 250, viewportWidth: 375),
        0);
    expect(
        conversationFolderSwipeDirection(
            deltaX: -300, deltaY: 0, viewportWidth: 375),
        1);
    expect(
        conversationFolderSwipeDirection(
            deltaX: 300, deltaY: 0, viewportWidth: 375),
        -1);
  });

  test('folder navigation includes All and stops at both boundaries', () {
    final folders = ['work', 'family'];
    expect(
        conversationFolderAfterSwipe(
            folderIds: folders, selectedFolderId: null, direction: -1),
        (changed: false, folderId: null));
    expect(
        conversationFolderAfterSwipe(
            folderIds: folders, selectedFolderId: null, direction: 1),
        (changed: true, folderId: 'work'));
    expect(
        conversationFolderAfterSwipe(
            folderIds: folders, selectedFolderId: 'work', direction: -1),
        (changed: true, folderId: null));
    expect(
        conversationFolderAfterSwipe(
            folderIds: folders, selectedFolderId: 'family', direction: 1),
        (changed: false, folderId: 'family'));
    expect(
        conversationFolderAfterSwipe(
            folderIds: [], selectedFolderId: null, direction: 1),
        (changed: false, folderId: null));
  });

  testWidgets('the Listener observes long swipes without taking child drags',
      (tester) async {
    final directions = <int>[];
    var childDrags = 0;
    await tester.pumpWidget(_host(
      enabled: true,
      onSwipe: directions.add,
      child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (_) => childDrags++,
          child: const ColoredBox(color: Colors.white)),
    ));
    await tester.drag(
        find.byType(ConversationFolderSwipeRegion), const Offset(-300, 0));
    await tester.pump();
    expect(directions, [1]);
    expect(childDrags, greaterThan(0));
  });

  testWidgets('short swipe, vertical swipe and disabled region stay unchanged',
      (tester) async {
    final directions = <int>[];
    await tester.pumpWidget(_host(enabled: true, onSwipe: directions.add));
    final region = find.byType(ConversationFolderSwipeRegion);
    await tester.drag(region, const Offset(-200, 0));
    await tester.drag(region, const Offset(-300, 250));
    expect(directions, isEmpty);
    await tester.pumpWidget(_host(enabled: false, onSwipe: directions.add));
    await tester.drag(region, const Offset(-300, 0));
    expect(directions, isEmpty);
  });

  testWidgets('cancel or disabling a pending pointer prevents navigation',
      (tester) async {
    final directions = <int>[];
    await tester.pumpWidget(_host(enabled: true, onSwipe: directions.add));
    var gesture = await tester.startGesture(const Offset(350, 300));
    await gesture.moveTo(const Offset(30, 300));
    await gesture.cancel();
    expect(directions, isEmpty);

    gesture = await tester.startGesture(const Offset(350, 300));
    await gesture.moveTo(const Offset(30, 300));
    await tester.pumpWidget(_host(enabled: false, onSwipe: directions.add));
    await gesture.up();
    expect(directions, isEmpty);

    await tester.pumpWidget(_host(enabled: true, onSwipe: directions.add));
    gesture = await tester.startGesture(const Offset(350, 300));
    await gesture.moveTo(const Offset(30, 300));
    await gesture.up();
    expect(directions, [1]);
    expect(tester.takeException(), isNull);
  });
}
