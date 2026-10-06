import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_management_page.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_panel.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReorderApi extends PersonalStickerApi {
  List<String>? savedOrder;

  @override
  Future<({List<PersonalSticker> items, String? nextCursor})> page(
          {String? cursor, int limit = 50}) async =>
      (
        items: [
          for (var index = 1; index <= 3; index++)
            PersonalSticker.fromJson({
              'id': 'st_$index',
              'mediaType': 'image',
              'mediaURL': 'https://example.test/$index.png',
              'thumbnailURL': null,
              'mimeType': 'image/png',
              'sizeBytes': 10,
              'width': 50,
              'height': 50,
              'durationMs': null,
              'sortOrder': index,
              'version': 1,
              'createdAt': 1,
              'updatedAt': 1,
            }),
        ],
        nextCursor: null,
      );

  @override
  Future<void> reorder(List<String> ids) async => savedOrder = List.of(ids);
}

void main() {
  testWidgets('custom stickers start with a dashed add tile in four columns',
      (tester) async {
    var added = false;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    final store = PersonalStickerStore();
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: PersonalStickerPanel(
              store: store,
              onAdd: () async => added = true,
              onSend: (_) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('添加的单个表情'), findsOneWidget);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
    await tester.tap(find.byTooltip('管理表情'));
    await tester.pumpAndSettle();
    expect(find.text('添加的单个表情 (0)'), findsOneWidget);
    final managementGrid = tester.widget<GridView>(find.byType(GridView).last);
    expect(
      (managementGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      4,
    );
    final managementDelegate = managementGrid.gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;
    expect(managementDelegate.childAspectRatio, 1);
    expect(managementDelegate.crossAxisSpacing, 10);
    expect(managementDelegate.mainAxisSpacing, 2);
    final addTile =
        tester.getSize(find.byKey(const ValueKey('management-add-tile')));
    expect(addTile.width, closeTo(addTile.height, 1));
    final gridWidth = tester.getSize(find.byType(GridView).last).width;
    expect(addTile.width, lessThan((gridWidth - 16 - 30) / 4));
    await tester.tap(find.text('整理'));
    await tester.pumpAndSettle();
    expect(find.text('移动'), findsNothing);
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sticker-add-tile')));
    await tester.pumpAndSettle();
    expect(find.text('添加的单个表情 (0)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('management-add-tile')));
    expect(added, isTrue);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('long press drag saves the new sticker order', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'drag-user', 'chatToken': 'drag-token'}));
    final api = _ReorderApi();
    final store = PersonalStickerStore(api: api);
    await store.refresh();
    await tester.pumpWidget(MaterialApp(
      home: PersonalStickerManagementPage(store: store, onAdd: () async {}),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('整理'));
    await tester.pumpAndSettle();
    final source = find.byKey(const ValueKey('sticker-drag-st_1'));
    final target = find.byKey(const ValueKey('sticker-drag-st_2'));
    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    expect(api.savedOrder, isNull);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('management-sticker-st_1')))
          .dx,
      greaterThan(tester
          .getTopLeft(find.byKey(const ValueKey('management-sticker-st_2')))
          .dx),
    );
    await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('sticker-target-3'))));
    await tester.pump();
    expect(api.savedOrder, isNull);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('management-sticker-st_1')))
          .dx,
      greaterThan(tester
          .getTopLeft(find.byKey(const ValueKey('management-sticker-st_3')))
          .dx),
    );
    final leftSlot =
        tester.getRect(find.byKey(const ValueKey('sticker-target-2')));
    final rightSlot =
        tester.getRect(find.byKey(const ValueKey('sticker-target-3')));
    await gesture.moveTo(
        Offset((leftSlot.right + rightSlot.left) / 2, leftSlot.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(api.savedOrder, ['st_2', 'st_3', 'st_1']);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('chat sticker panel reflects management order after closing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'panel-order-user', 'chatToken': 'panel-order-token'}));
    final api = _ReorderApi();
    final store = PersonalStickerStore(api: api);
    await store.refresh();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 350,
          child: PersonalStickerPanel(
              store: store, onAdd: () async {}, onSend: (_) async {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理表情'));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sticker-drag-st_1'))));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('sticker-target-3'))));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    final second =
        tester.getTopLeft(find.byKey(const ValueKey('sticker-st_2')));
    final first = tester.getTopLeft(find.byKey(const ValueKey('sticker-st_1')));
    expect(second.dx, lessThan(first.dx));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 350,
          child: PersonalStickerPanel(
              store: store, onAdd: () async {}, onSend: (_) async {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('sticker-st_2'))).dx,
      lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('sticker-st_1'))).dx),
    );
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
