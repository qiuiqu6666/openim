import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/widgets/group_chat_feature_surface.dart';
import 'package:openim/pages/group_features/widgets/group_feature_actions.dart';
import 'package:openim/services/account_privilege/account_privilege_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sangong/sangong_test_support.dart';

const _session = AccountPrivilegeSession(
    userID: 'owner',
    chatToken: 'fixture-chat-token',
    baseUrl: 'https://fixture.example');

SangongTestApi _api() {
  final api = SangongTestApi();
  api.respond = (call) {
    if (call.path.endsWith('/feature-capabilities')) {
      final segments = Uri.parse(call.path).pathSegments;
      return {
        'groupID': segments[segments.length - 2],
        'capabilityVersion': 1,
      };
    }
    return sangongFixtureResponse(call);
  };
  return api;
}

GroupFeatureStore _store(SangongTestApi api, AccountPrivilegeAccess privilege,
        {bool Function()? current}) =>
    GroupFeatureStore(
        api: api,
        accountPrivilege: privilege,
        sessionCurrent: current ?? () => true,
        fetchGroups: (_) async => [])
      ..seed(GroupInfo(groupID: 'g', ex: '{"gameType":4}'));

Widget _app(GroupFeatureStore store,
        {String groupID = 'g',
        String userID = 'owner',
        bool dark = false,
        bool surface = true}) =>
    ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: Scaffold(
                body: ListenableBuilder(
                    listenable: store,
                    builder: (context, _) {
                      final feature = store.context(
                          id: groupID,
                          name: '群聊',
                          userID: userID,
                          admin: false,
                          current: () => true);
                      final body = Builder(
                          builder: (context) => Column(children: [
                                if (surface)
                                  for (final action
                                      in GroupFeatureActions.items(
                                          context, feature))
                                    Text(action.text),
                                TextButton(
                                    key: const ValueKey('open-group-features'),
                                    onPressed: () => unawaited(
                                        GroupFeatureActions.open(context, store,
                                            feature.readCurrentContext)),
                                    child: const Text('群功能入口')),
                              ]));
                      return surface
                          ? GroupChatFeatureSurface(
                              store: store,
                              featureContext: feature,
                              child: body)
                          : body;
                    }))));

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    testWidgets(
        'entering group refreshes a foreground admin grant and does not repeat on rebuild dark=$dark',
        (tester) async {
      var serverAllowed = false;
      var reads = 0;
      final privilege = AccountPrivilegeStore(
          session: () => _session,
          fetchProfile: (_) async {
            reads++;
            return UserFullInfo(userID: 'owner', isPrivileged: serverAllowed);
          });
      final api = _api();
      final store = _store(api, privilege);
      addTearDown(() async {
        await _unmount(tester);
        store.dispose();
        privilege.dispose();
      });
      await privilege.refresh();
      expect(privilege.allows(userID: 'owner', baseUrl: api.baseUrl), isFalse);
      serverAllowed = true;
      await tester.pumpWidget(_app(store, dark: dark));
      await flushSangong(tester);
      expect(reads, 2);
      expect(find.text('三公运营'), findsOneWidget);
      expect(find.text('三公代理'), findsOneWidget);
      expect(api.count('/feature-capabilities'), 1);
      await tester.pumpWidget(_app(store, dark: dark));
      await flushSangong(tester);
      expect(reads, 2);
      expect(api.count('/feature-capabilities'), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failed group-entry refresh clears a previous grant dark=$dark',
        (tester) async {
      var failed = false;
      final privilege = AccountPrivilegeStore(
          session: () => _session,
          fetchProfile: (_) async {
            if (failed) throw StateError('profile unavailable');
            return UserFullInfo(userID: 'owner', isPrivileged: true);
          });
      final api = _api();
      final store = _store(api, privilege);
      addTearDown(() async {
        await _unmount(tester);
        store.dispose();
        privilege.dispose();
      });
      await privilege.refresh();
      failed = true;
      await tester.pumpWidget(_app(store, dark: dark));
      await flushSangong(tester);
      expect(privilege.allows(userID: 'owner', baseUrl: api.baseUrl), isFalse);
      expect(find.text('三公运营'), findsNothing);
      expect(find.text('三公代理'), findsNothing);
      expect(find.text('群功能入口'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switching the group binding refreshes once per group',
      (tester) async {
    var reads = 0;
    final privilege = AccountPrivilegeStore(
        session: () => _session,
        fetchProfile: (_) async {
          reads++;
          return UserFullInfo(userID: 'owner', isPrivileged: true);
        });
    final api = _api();
    final store = _store(api, privilege);
    addTearDown(() async {
      await _unmount(tester);
      store.dispose();
      privilege.dispose();
    });
    await tester.pumpWidget(_app(store, groupID: 'first'));
    await flushSangong(tester);
    await tester.pumpWidget(_app(store, groupID: 'second'));
    await flushSangong(tester);
    expect(reads, 2);
    expect(api.count('/feature-capabilities'), 2);
    expect(find.text('三公运营'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old account read cannot clear the new account group entries',
      (tester) async {
    var session = _session;
    final oldRead = Completer<UserFullInfo?>();
    final oldPrivilege = AccountPrivilegeStore(
        session: () => session, fetchProfile: (_) => oldRead.future);
    final oldApi = _api();
    final oldStore =
        _store(oldApi, oldPrivilege, current: () => session.userID == 'owner');
    final newPrivilege = AccountPrivilegeStore(
        session: () => session,
        fetchProfile: (request) async =>
            UserFullInfo(userID: request.userID, isPrivileged: true));
    final newApi = _api();
    final newStore = _store(newApi, newPrivilege,
        current: () => session.userID == 'new-owner');
    addTearDown(() async {
      await _unmount(tester);
      oldStore.dispose();
      newStore.dispose();
      oldPrivilege.dispose();
      newPrivilege.dispose();
    });
    await tester.pumpWidget(_app(oldStore, groupID: 'old-group'));
    await flushSangong(tester);
    session = const AccountPrivilegeSession(
        userID: 'new-owner',
        chatToken: 'new-chat-token',
        baseUrl: 'https://fixture.example');
    await tester
        .pumpWidget(_app(newStore, groupID: 'new-group', userID: 'new-owner'));
    await flushSangong(tester);
    expect(find.text('三公运营'), findsOneWidget);
    oldRead.complete(UserFullInfo(userID: 'owner', isPrivileged: false));
    await flushSangong(tester);
    expect(find.text('三公运营'), findsOneWidget);
    expect(newPrivilege.allows(userID: 'new-owner', baseUrl: newApi.baseUrl),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final failed in [false, true]) {
    testWidgets('group feature sheet refreshes full profile failed=$failed',
        (tester) async {
      var reads = 0;
      var serverChanged = false;
      final privilege = AccountPrivilegeStore(
          session: () => _session,
          fetchProfile: (_) async {
            reads++;
            if (serverChanged && failed) {
              throw StateError('profile unavailable');
            }
            return UserFullInfo(
                userID: 'owner', isPrivileged: failed || serverChanged);
          });
      final api = _api();
      final store = _store(api, privilege);
      addTearDown(() async {
        await _unmount(tester);
        store.dispose();
        privilege.dispose();
      });
      await privilege.refresh();
      serverChanged = true;
      await tester.pumpWidget(_app(store, surface: false));
      await tester.tap(find.byKey(const ValueKey('open-group-features')));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('群功能'), findsOneWidget);
      expect(find.text('三公运营'), failed ? findsNothing : findsOneWidget);
      expect(find.text('三公代理'), failed ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
