import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/add_by_search/add_by_search_logic.dart';
import 'package:openim/pages/contacts/add_by_search/add_by_search_view.dart';
import 'package:openim/pages/contacts/search/contact_search_source.dart';
import 'package:openim_common/openim_common.dart';

class _Source extends ContactSearchSource {
  final groupReplies = <Completer<List<GroupInfo>>>[];
  final userReplies = <Completer<List<UserFullInfo>?>>[];
  final pages = <(String, int)>[];
  @override
  Future<List<GroupInfo>> groups(String keyword) {
    final reply = Completer<List<GroupInfo>>();
    groupReplies.add(reply);
    return reply.future;
  }

  @override
  Future<List<UserFullInfo>?> users(String keyword, int page, {int? way}) {
    pages.add((keyword, page));
    final reply = Completer<List<UserFullInfo>?>();
    userReplies.add(reply);
    return reply.future;
  }
}

Widget _overlay() => MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(initialEntries: [
          OverlayEntry(
            builder: (_) => GetMaterialApp(home: const Scaffold()),
          )
        ]),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    Get.routing.args = {'searchType': SearchType.group};
  });
  tearDown(() {
    LoadingView.singleton.dismiss();
    Get.reset();
  });

  for (final brightness in Brightness.values) {
    testWidgets('page shows loading, empty and retry in $brightness',
        (tester) async {
      Get.routing.args = {'searchType': SearchType.user};
      final source = _Source();
      final logic = Get.put(AddContactsBySearchLogic(source: source));
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          theme: ThemeData(brightness: brightness),
          home: AddContactsBySearchPage(),
        ),
      ));
      await tester.enterText(find.byType(TextField), 'query');
      await tester.pump();
      expect(find.text(StrRes.noFoundUser), findsNothing);
      expect(find.text('Searching…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 350));
      source.userReplies.single.complete([]);
      await tester.pump();
      await tester.pump();
      expect(find.text(StrRes.noFoundUser), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'next');
      await tester.pump(const Duration(milliseconds: 350));
      source.userReplies.last.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump();
      expect(find.text(StrRes.noFoundUser), findsNothing);
      await tester.tap(find.text('Search failed. Tap to retry.'));
      expect(source.pages, [('query', 1), ('next', 1), ('next', 1)]);
      source.userReplies.last
          .complete([UserFullInfo(userID: 'found', nickname: 'Result')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Result'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      logic.onClose();
    });
  }

  testWidgets(
      'typing searches automatically and never shows premature empty state',
      (tester) async {
    Get.routing.args = {'searchType': SearchType.user};
    final source = _Source();
    final logic = AddContactsBySearchLogic(source: source)..onInit();
    logic.searchCtrl.text = '@first';
    expect(logic.isNotFoundUser, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    logic.searchCtrl.text = '@second';
    await tester.pump(const Duration(milliseconds: 349));
    expect(source.pages, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(source.pages, [('@second', 1)]);
    expect(logic.status.value, ContactSearchStatus.loading);
    expect(logic.isNotFoundUser, isFalse);
    source.userReplies.single.complete([UserFullInfo(userID: 'found')]);
    await tester.pump();
    expect(logic.userInfoList.single.userID, 'found');
    expect(logic.isNotFoundUser, isFalse);
    logic.onClose();
  });

  testWidgets('submit cancels debounce and does not duplicate a pending search',
      (tester) async {
    Get.routing.args = {'searchType': SearchType.user};
    final source = _Source();
    final logic = AddContactsBySearchLogic(source: source)..onInit();
    logic.searchCtrl.text = 'query';
    logic.search();
    logic.search();
    await tester.pump(const Duration(seconds: 1));
    expect(source.pages, [('query', 1)]);
    source.userReplies.single.complete([]);
    await tester.pump();
    expect(logic.isNotFoundUser, isTrue);
    logic.searchCtrl.clear();
    expect(logic.isNotFoundUser, isFalse);
    logic.onClose();
  });

  testWidgets('failure is distinct from empty and can be retried',
      (tester) async {
    Get.routing.args = {'searchType': SearchType.user};
    final source = _Source();
    final logic = AddContactsBySearchLogic(source: source)..onInit();
    logic.searchCtrl.text = 'query';
    final pending = logic.searchUser();
    source.userReplies.single.completeError(StateError('offline'));
    await pending;
    expect(logic.status.value, ContactSearchStatus.error);
    expect(logic.isNotFoundUser, isFalse);
    final retry = logic.searchUser();
    source.userReplies.last.complete([]);
    await retry;
    expect(logic.isNotFoundUser, isTrue);
    logic.onClose();
  });

  for (final end in ['clear', 'close', 'account']) {
    testWidgets('scheduled search is cancelled after $end', (tester) async {
      Get.routing.args = {'searchType': SearchType.user};
      final source = _Source();
      final logic = AddContactsBySearchLogic(source: source)..onInit();
      logic.searchCtrl.text = 'query';
      switch (end) {
        case 'clear':
          logic.searchCtrl.clear();
        case 'close':
          logic.onClose();
        case 'account':
          OpenIM.iMManager.userID = 'other';
      }
      await tester.pump(const Duration(seconds: 1));
      expect(source.pages, isEmpty);
      if (end != 'close') logic.onClose();
    });
  }

  testWidgets('IME composition waits until text is committed', (tester) async {
    Get.routing.args = {'searchType': SearchType.user};
    final source = _Source();
    final logic = AddContactsBySearchLogic(source: source)..onInit();
    logic.searchCtrl.value = const TextEditingValue(
        text: 'query', composing: TextRange(start: 0, end: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(source.pages, isEmpty);
    logic.searchCtrl.value = const TextEditingValue(text: 'query');
    await tester.pump(const Duration(milliseconds: 350));
    expect(source.pages, [('query', 1)]);
    source.userReplies.single.complete([]);
    await tester.pump();
    logic.onClose();
  });

  test('an old group search cannot overwrite the current query', () async {
    final source = _Source();
    final logic = AddContactsBySearchLogic(source: source)..onInit();
    logic.searchCtrl.text = 'old';
    final old = logic.searchGroup();
    logic.searchCtrl.text = 'new';
    final current = logic.searchGroup();
    source.groupReplies[1].complete([GroupInfo(groupID: 'new')]);
    await current;
    source.groupReplies[0].complete([GroupInfo(groupID: 'old')]);
    await old;
    expect(logic.groupInfoList.single.groupID, 'new');
    logic.onClose();
  });

  for (final end in ['clear', 'close', 'account']) {
    test('group results are discarded after $end', () async {
      final source = _Source();
      final logic = AddContactsBySearchLogic(source: source)..onInit();
      logic.searchCtrl.text = 'query';
      final pending = logic.searchGroup();
      switch (end) {
        case 'clear':
          logic.searchCtrl.clear();
        case 'close':
          logic.onClose();
        case 'account':
          OpenIM.iMManager.userID = 'other';
      }
      source.groupReplies.single.complete([GroupInfo(groupID: 'late')]);
      await pending;
      expect(logic.groupInfoList, isEmpty);
      if (end != 'close') logic.onClose();
    });
  }

  testWidgets(
      'late old user page cannot enter the next query or advance its page',
      (tester) async {
    await tester.pumpWidget(_overlay());
    Get.routing.args = {'searchType': SearchType.user};
    final source = _Source();
    final logic = AddContactsBySearchLogic(source: source)..onInit();
    logic.searchCtrl.text = 'old';
    final first = logic.searchUser();
    await tester.pump(const Duration(milliseconds: 2));
    source.userReplies[0]
        .complete(List.generate(20, (i) => UserFullInfo(userID: 'old$i')));
    await first;
    final more = logic.loadMoreUser();
    await tester.pump(const Duration(milliseconds: 2));
    expect(source.pages.last, ('old', 2));
    logic.searchCtrl.text = 'new';
    final current = logic.searchUser();
    await tester.pump(const Duration(milliseconds: 2));
    source.userReplies[2].complete([UserFullInfo(userID: 'new')]);
    await current;
    source.userReplies[1].complete([UserFullInfo(userID: 'old-page2')]);
    await more;
    expect(logic.pageNo, 1);
    expect(logic.userInfoList.map((e) => e.userID), ['new']);
    logic.onClose();
  });

  testWidgets(
      'duplicate load-more requests share one pending page and append unique users',
      (tester) async {
    await tester.pumpWidget(_overlay());
    Get.routing.args = {'searchType': SearchType.user};
    final source = _Source();
    final logic = AddContactsBySearchLogic(source: source)..onInit();
    logic.searchCtrl.text = 'query';
    final first = logic.searchUser();
    await tester.pump(const Duration(milliseconds: 2));
    source.userReplies[0]
        .complete(List.generate(20, (i) => UserFullInfo(userID: '$i')));
    await first;
    final more = logic.loadMoreUser();
    final duplicate = logic.loadMoreUser();
    await tester.pump(const Duration(milliseconds: 2));
    expect(source.pages, [('query', 1), ('query', 2)]);
    source.userReplies[1]
        .complete([UserFullInfo(userID: '0'), UserFullInfo(userID: '20')]);
    await more;
    await duplicate;
    expect(logic.userInfoList, hasLength(21));
    expect(logic.pageNo, 2);
    logic.onClose();
  });
}
