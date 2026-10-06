import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/settings/storage/conversation_storage_page.dart';
import 'package:openim/pages/mine/settings/pages/storage_media_repository.dart';
import 'package:openim/pages/mine/settings/storage/widgets/storage_media_thumbnail.dart';
import 'package:openim/pages/mine/settings/storage/widgets/storage_media_tile.dart';

import '../../../../support/performance/render_test_fakes.dart';

class _Source extends ListBase<StorageMediaItem> {
  _Source(int count)
      : values = List.generate(
          count,
          (i) => StorageMediaItem(
            id: 'item-$i',
            message: Message(clientMsgID: 'item-$i'),
            conversationID: 'conversation',
            conversationName: 'Storage',
            conversationFaceURL: null,
            type: StorageMediaType.file,
            bytes: 10,
            time: DateTime(2026, 8, 15, 12).subtract(Duration(minutes: i)),
            localPaths: const [],
            cachedURLs: const [],
          ),
        );
  final List<StorageMediaItem> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => values.length = value;
  @override
  StorageMediaItem operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, StorageMediaItem value) => values[index] = value;
}

Future<ValueNotifier<int>> _pumpStorage(WidgetTester tester, _Source source,
    {Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final revision = ValueNotifier(0);
  await tester.pumpWidget(renderTestHost(
    ConversationStoragePage(
      name: 'Storage',
      conversationID: 'conversation',
      source: source,
      revision: revision,
      repository: StorageMediaRepository(),
      onRemoved: (_) {},
    ),
    brightness: brightness,
  ));
  await tester.pumpAndSettle();
  addTearDown(revision.dispose);
  return revision;
}

void main() {
  tearDown(Get.reset);

  testWidgets('1000 items mount only viewport tiles and stay lazy on scroll',
      (tester) async {
    await _pumpStorage(tester, _Source(1000));
    expect(find.byType(StorageMediaThumbnail).evaluate().length, lessThan(60));
    expect(find.byType(SliverGrid), findsWidgets);
    expect(find.byType(GridView), findsNothing);
    final scroll =
        tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    scroll.controller!.jumpTo(2000);
    await tester.pumpAndSettle();
    expect(find.byType(StorageMediaThumbnail).evaluate().length, lessThan(60));
    expect(find.byKey(const ValueKey('item-0')), findsNothing);
  });

  testWidgets('selection reuses catalog and thumbnail, revision removes IDs',
      (tester) async {
    final source = _Source(1000);
    final revision =
        await _pumpStorage(tester, source, brightness: Brightness.dark);
    final reads = source.reads;
    final thumbnail = tester.widget<StorageMediaThumbnail>(
        find.byWidgetPredicate(
            (w) => w is StorageMediaThumbnail && w.item.id == 'item-0'));
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('item-0')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(source.reads, reads,
        reason: 'Selection must not refilter or resort the source');
    expect(
        tester.widget<StorageMediaThumbnail>(find.byWidgetPredicate(
            (w) => w is StorageMediaThumbnail && w.item.id == 'item-0')),
        same(thumbnail));
    source.values.removeAt(0);
    revision.value++;
    await tester.pumpAndSettle();
    expect(source.reads, greaterThan(reads));
    expect(find.byKey(const ValueKey('item-0')), findsNothing);
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.textContaining('999 items'), findsOneWidget);
  });

  testWidgets('drag selection keeps contiguous range and cancels its timer',
      (tester) async {
    await _pumpStorage(tester, _Source(30));
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const ValueKey('item-0'))));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture
        .moveTo(tester.getCenter(find.byKey(const ValueKey('item-4'))));
    await tester.pump();
    expect(find.text('5 selected'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(5));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag at edge scrolls into lazily mounted rows', (tester) async {
    await _pumpStorage(tester, _Source(1000));
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const ValueKey('item-0'))));
    await tester.pump(const Duration(milliseconds: 600));
    final view = tester.getRect(find.byType(CustomScrollView));
    await gesture.moveTo(Offset(view.left + 40, view.bottom - 4));
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final scroll =
        tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    expect(scroll.controller!.offset, greaterThan(0));
    expect(find.byType(StorageMediaTile).evaluate().length, lessThan(60));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
