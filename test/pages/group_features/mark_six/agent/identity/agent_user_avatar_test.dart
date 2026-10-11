import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/group_features/mark_six/agent/identity/agent_avatar_directory.dart';
import 'package:openim/pages/group_features/mark_six/agent/identity/agent_user_avatar.dart';
import 'package:openim/pages/group_features/mark_six/agent/pages/agent_descendants_page.dart';
import 'package:openim/pages/group_features/mark_six/agent/pages/agent_descendant_detail_page.dart';
import 'package:openim/pages/group_features/mark_six/agent/widgets/agent_descendant_tile.dart';
import '../../mark_six_fixtures.dart';

Future<void> _mount(WidgetTester tester, Widget child,
    {bool dark = false}) async {
  Styles.isDark = dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const channel = MethodChannel('flutter_openim_sdk');
  setUp(() => Get.testMode = true);
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'downline list and detail obtain visible users from SDK, dark=$dark',
        (tester) async {
      final requested = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getUsersInfo');
        final ids = List<String>.from(call.arguments['userIDList'] as List);
        requested.addAll(ids);
        // Test the AvatarView input without starting an external image download.
        return jsonEncode([
          for (final id in ids.reversed)
            {'userID': id, 'faceURL': 'sdk-avatar:$id'},
        ]);
      });
      final api = MarkSixFakeApi(respond: (_, path, query, __) {
        final rows = [
          for (var i = 0; i < 100; i++)
            {
              'userId': 'im_$i',
              'displayName': '下级$i',
              'playerNo': 1000 + i,
              'balance': 100 - i,
              'directParentUserId': 'self'
            },
        ];
        if (path.endsWith('/descendants')) {
          return {
            'userId': 'self',
            'page': query['page'],
            'total': 2055,
            'hasMore': true,
            'items': rows
          };
        }
        if (path.endsWith('/descendants/im_0')) return {'item': rows.first};
        return markSixFixtureResponse(path, query);
      });
      await _mount(
          tester, AgentDescendantsPage(featureContext: markSixContext(api)),
          dark: dark);
      final avatars = tester.widgetList<AvatarView>(find.byType(AvatarView));
      expect(avatars, isNotEmpty);
      expect(avatars.first.url, 'sdk-avatar:im_0');
      expect(requested, isNotEmpty);
      expect(requested.length, lessThan(100));
      expect(requested.every((id) => id.startsWith('im_')), isTrue);
      await tester.tap(find.text('总流水'));
      await tester.pumpAndSettle();
      expect(requested.toSet().length, requested.length);
      await tester.enterText(find.byType(TextField), '下级0');
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AgentDescendantTile),
        matching: find.text('下级0'),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AgentDescendantDetailPage), findsOneWidget);
      expect(tester.widget<AvatarView>(find.byType(AvatarView).first).url,
          'sdk-avatar:im_0');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
      'explicit IM ID takes precedence and a previous row cannot overwrite its photo',
      (tester) async {
    final pending = Completer<List<PublicUserInfo>>();
    final calls = <List<String>>[];
    final directory = AgentAvatarDirectory(markSixContext(MarkSixFakeApi()),
        loadUsers: (ids) {
      calls.add(ids);
      return calls.length == 1
          ? pending.future
          : Future.value([
              PublicUserInfo(userID: 'im_new', faceURL: 'sdk-avatar:new'),
            ]);
    });
    addTearDown(directory.dispose);
    Widget row(String id) => Scaffold(
            body: AgentUserAvatar(
          directory: directory,
          name: '下级',
          item: {
            'userId': 'business-id',
            'imUserId': id,
            'playerNo': 10671,
            'avatarUrl': '',
            'faceURL': 'existing-photo'
          },
        ));
    await _mount(tester, row('im_old'));
    expect(tester.widget<AvatarView>(find.byType(AvatarView)).url,
        'existing-photo');
    await _mount(tester, row('im_new'));
    pending.complete([PublicUserInfo(userID: 'im_old', faceURL: 'old-photo')]);
    await tester.pumpAndSettle();
    expect(calls, [
      ['im_old'],
      ['im_new']
    ]);
    expect(tester.widget<AvatarView>(find.byType(AvatarView)).url,
        'sdk-avatar:new');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
