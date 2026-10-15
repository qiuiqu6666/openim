import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_list/group_list_logic.dart';
import 'package:openim/pages/contacts/group_list/group_list_view.dart';
import 'package:openim/pages/contacts/group_list/search/group_list_search.dart';
import 'package:openim_common/openim_common.dart';

GroupInfo _group(String id, {String owner = 'self', String? name}) => GroupInfo(
    groupID: id, groupName: name ?? id, ownerUserID: owner, memberCount: 18);

Future<void> _mount(WidgetTester tester, GroupListLogic logic,
    {bool dark = false,
    ValueChanged<GroupInfo>? onSelected,
    Set<String>? allowedGroupIDs}) async {
  Get.testMode = true;
  final oldDark = Styles.isDark;
  Styles.isDark = dark;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 812);
  Get.put(logic);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    Get.reset();
    Styles.isDark = oldDark;
    tester.view.reset();
  });
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: GroupListPage(
          logic: logic,
          onSelected: onSelected,
          allowedGroupIDs: allowedGroupIDs),
    ),
  ));
  // The existing pagination footer animates even while idle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _query(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField), value);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('late search responses, clear, and disposal cannot restore old results',
      () async {
    final requests = <Completer<List<GroupInfo>>>[];
    final seeded = <List<GroupInfo>>[];
    final search = GroupListSearch(
        onResults: seeded.add,
        currentUserID: () => 'self',
        findGroups: (_) {
          final request = Completer<List<GroupInfo>>();
          requests.add(request);
          return request.future;
        });
    search.change('old');
    final old = search.run();
    search.change('new');
    final newest = search.run();
    requests[1].complete(
        [_group('new'), _group('new'), _group('joined', owner: 'peer')]);
    await newest;
    requests[0].complete([_group('old')]);
    await old;
    expect(search.groupsFor(created: true).single.groupID, 'new');
    expect(search.groupsFor(created: false).single.groupID, 'joined');
    search.change('cleared');
    final cleared = search.run();
    search.change('');
    requests[2].complete([_group('cleared')]);
    await cleared;
    expect(search.results, isEmpty);
    expect(search.loading.value, isFalse);
    search.change('disposed');
    final disposed = search.run();
    search.dispose();
    requests[3].complete([_group('disposed')]);
    await disposed;
    expect(search.results, isEmpty);
    expect(seeded, hasLength(1),
        reason: 'Only a current response may update group badges and colors.');
  });

  for (final changeAccount in [true, false]) {
    test('search ignores ${changeAccount ? 'account' : 'token'} changes',
        () async {
      var account = 'self';
      var token = 'token';
      final response = Completer<List<GroupInfo>>();
      final search = GroupListSearch(
          currentUserID: () => account,
          currentToken: () => token,
          findGroups: (_) => response.future);
      search.change('query');
      final pending = search.run();
      if (changeAccount) {
        account = 'other';
      } else {
        token = 'new-token';
      }
      response.complete([_group('private')]);
      await pending;
      expect(search.results, isEmpty);
      search.dispose();
    });
  }

  for (final dark in [false, true]) {
    testWidgets('group search combines ownership categories ($dark)',
        (tester) async {
      final created = _group('later-page', name: '项目群');
      final joined = _group('joined-match', owner: 'peer', name: '加入项目群');
      final queries = <String>[];
      var pageLoads = 0;
      GroupInfo? selected;
      final logic = GroupListLogic(
          currentUserID: () => 'self',
          fetchPage: (offset, _) async {
            pageLoads++;
            if (offset > 0) return [];
            return [
              _group('first'),
              _group('joined-first', owner: 'peer'),
              for (var i = 0; i < 9; i++) _group('created-$i'),
              for (var i = 0; i < 9; i++) _group('joined-$i', owner: 'peer'),
            ];
          },
          findGroups: (query) async {
            queries.add(query);
            return query == '项目' ? [created, joined] : [];
          })
        ..count = 20;
      await _mount(tester, logic,
          dark: dark, onSelected: (group) => selected = group);
      expect(find.byKey(const ValueKey('my-groups-search')), findsOneWidget);
      expect(
          logic.iCreatedList.any((group) => group.groupID == 'first'), isTrue);
      await tester.enterText(find.byType(TextField), '项');
      await tester.pump(const Duration(milliseconds: 100));
      await _query(tester, ' 项目 ');
      expect(queries, ['项目']);
      expect(find.byKey(const ValueKey('later-page')), findsOneWidget);
      expect(find.text('共 2 个群聊'), findsOneWidget);
      expect(find.byKey(const ValueKey('first')), findsNothing);
      expect(logic.iCreatedList.first.groupID, 'first');
      expect(find.text(StrRes.iJoinedGroup), findsNothing);
      expect(find.byKey(const ValueKey('joined-match')), findsOneWidget);
      expect(find.byKey(const ValueKey('later-page')), findsOneWidget);
      expect(queries, ['项目']);
      await tester.tap(find.byKey(const ValueKey('joined-match')));
      expect(selected, same(joined));
      await _query(tester, '没有结果');
      expect(find.text(StrRes.searchNotFound), findsOneWidget);
      expect(find.text('共 0 个群聊'), findsOneWidget);
      await tester.tap(find.byWidgetPredicate((widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == ImageRes.clearText));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(logic.index.value, 0);
      expect(logic.search.controller.text, isEmpty);
      expect(logic.iJoinedList.any((group) => group.groupID == 'joined-first'),
          isTrue);
      expect(logic.canLoadMore(false), isFalse);
      expect(pageLoads, 4,
          reason: 'Search does not reload the two ownership pages.');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('search retries failures and preserves disabled group selection',
      (tester) async {
    var fail = true;
    var selected = false;
    final logic = GroupListLogic(
        currentUserID: () => 'self',
        fetchPage: (_, __) async => [],
        findGroups: (_) async {
          if (fail) throw StateError('offline');
          return [_group('blocked')];
        });
    await _mount(tester, logic,
        onSelected: (_) => selected = true, allowedGroupIDs: {});
    await _query(tester, 'blocked');
    expect(find.text('加载失败，请重试'), findsOneWidget);
    expect(find.text('共 0 个群聊'), findsNothing);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('blocked'));
    expect(tester.widget<ListTile>(row).enabled, isFalse);
    await tester.tap(row, warnIfMissed: false);
    expect(selected, isFalse);
    expect(tester.takeException(), isNull);
  });
}
