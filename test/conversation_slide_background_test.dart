import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/conversation_view.dart';
import 'package:openim_common/openim_common.dart';
import 'support/conversation_live_fixture.dart';

class _Logic extends GetxController
    with ConversationLiveFixture
    implements ConversationLogic {
  @override
  final list = <ConversationInfo>[
    ConversationInfo(conversationID: 'group', conversationType: 3),
  ].obs;
  @override
  final organizerLoading = false.obs;
  @override
  final organizerError = RxnString();
  @override
  bool isArchived(ConversationInfo info) => true;
  @override
  bool isGroupChat(ConversationInfo info) => true;
  @override
  bool isNotDisturb(ConversationInfo info) => false;
  @override
  String? folderID(ConversationInfo info) => null;
  @override
  int getUnreadCount(ConversationInfo info) => 0;
  @override
  String getShowName(ConversationInfo info) => 'Test group';
  @override
  String getContent(ConversationInfo info) => 'Message';
  @override
  String getTime(ConversationInfo info) => '18:29';
  @override
  String? getPrefixTag(ConversationInfo info) => '';
  @override
  Future<void> refreshOrganizer() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('slide background returns with row (dark=$dark)',
        (tester) async {
      OpenIM.iMManager.userID = 'self';
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = false);
      final logic = _Logic();
      Get.put<ConversationLogic>(logic);
      addTearDown(Get.reset);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: RepaintBoundary(
            key: boundaryKey,
            child: const ConversationPage(groupChats: true, archivedOnly: true),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final row = find.byType(Slidable);
      final originalRect = tester.getRect(find.text('Test group'));

      Future<List<int>> backgroundPixels() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = (await tester.runAsync(() => boundary.toImage()))!;
        final bytes = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
        final rowRect = tester.getRect(row);
        // Sample the empty lower band across the entire row, including both edges.
        final y = (rowRect.bottom - 5).floor();
        final pixels = <int>[];
        for (var x = 2; x < image.width - 2; x += 5) {
          pixels.add(bytes.getUint32((y * image.width + x) * 4));
        }
        image.dispose();
        return pixels;
      }

      final baseline = await backgroundPixels();
      for (final dx in [-150.0, 150.0, -100.0, 100.0]) {
        await tester.drag(row, Offset(dx, 0));
        await tester.pump(const Duration(milliseconds: 50));
        logic.list.single.isPinned = true;
        logic.list.refresh();
        await tester.pump();
        logic.list.single.isPinned = false;
        logic.list.refresh();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.tapAt(const Offset(180, 600));
        await tester.pumpAndSettle();
        expect(tester.widget<Slidable>(row).controller!.ratio, 0);
        expect(tester.getRect(find.text('Test group')), originalRect);
        expect(await backgroundPixels(), baseline);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
