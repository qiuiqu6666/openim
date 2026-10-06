import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_management_page.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BoundedProbeStore extends PersonalStickerStore {
  final firstPage = Completer<void>();
  int pagingCalls = 0;

  @override
  Future<void> refresh() async {
    nextCursor = 'older';
  }

  @override
  Future<void> loadMore() async {
    pagingCalls++;
    if (pagingCalls == 1) await firstPage.future;
    // Artificially terminate the loop so the regression probe cannot hang.
    if (pagingCalls >= 3) nextCursor = null;
    // The actual disposed store rejects the request without clearing its cursor.
    await super.loadMore();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('leaving sticker management must stop pagination',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    final store = BoundedProbeStore();
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        home: PersonalStickerManagementPage(store: store, onAdd: () async {}),
      ),
    ));
    await tester.pump();
    expect(store.pagingCalls, 1);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    store.firstPage.complete();
    await tester.pump();
    expect(store.pagingCalls, 1,
        reason: 'The page and its store have both been disposed.');
  });
}
