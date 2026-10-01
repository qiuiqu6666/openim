import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/global_search/global_search_logic.dart';
import 'package:openim/pages/global_search/global_search_view.dart';
import 'package:openim_common/openim_common.dart';

class SearchFixture extends GlobalSearchSource {
  final pending = <String, Completer<List<FriendInfo>>>{};
  bool failGroups = false;
  @override
  Future<List<FriendInfo>> friends(String query) =>
      (pending[query] = Completer<List<FriendInfo>>()).future;
  @override
  Future<List<GroupInfo>> groups(String query) async {
    if (failGroups) throw StateError('offline');
    return [];
  }

  @override
  Future<List<ConversationInfo>> conversations(String query) async => [];
  @override
  Future<List<SearchResultItems>> messages(String query, bool files) async =>
      [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);
  test(
      'new queries and clear invalidate pending results; partial failures remain retryable',
      () async {
    final source = SearchFixture()..failGroups = true;
    final logic = Get.put(GlobalSearchLogic(source: source));
    logic.searchCtrl.text = 'old';
    final old = logic.search();
    logic.searchCtrl.text = 'new';
    final newer = logic.search();
    source.pending['new']!.complete([FriendInfo(userID: '2', nickname: 'new')]);
    await newer;
    source.pending['old']!.complete([FriendInfo(userID: '1', nickname: 'old')]);
    await old;
    expect(logic.contactsList.single.nickname, 'new');
    expect(logic.failures, contains(2));
    source.failGroups = false;
    final retry = logic.search();
    source.pending['new']!.complete([]);
    await retry;
    expect(logic.failures, isEmpty);
    logic.searchCtrl.text = 'pending';
    final pending = logic.search();
    logic.searchCtrl.clear();
    source.pending['pending']!.complete([FriendInfo(userID: '3')]);
    await pending;
    expect(logic.contactsList, isEmpty);
    expect(logic.loading.value, isFalse);
  });

  for (final brightness in Brightness.values) {
    testWidgets('search renders and switches categories in ${brightness.name}',
        (tester) async {
      final source = SearchFixture();
      final logic = Get.put(GlobalSearchLogic(source: source));
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme: ThemeData(brightness: brightness),
          home: GlobalSearchPage(),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '好友');
      await tester.pump(const Duration(milliseconds: 350));
      source.pending['好友']!
          .complete([FriendInfo(userID: '1', nickname: '测试好友')]);
      await tester.pumpAndSettle();
      expect(find.text('测试好友'), findsOneWidget);
      logic.index.value = 2;
      await tester.pumpAndSettle();
      expect(find.text('测试好友'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
