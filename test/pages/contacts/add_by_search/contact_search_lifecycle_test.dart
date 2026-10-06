import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/add_by_search/add_by_search_logic.dart';
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
