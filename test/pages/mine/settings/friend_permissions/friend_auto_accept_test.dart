import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/mine/settings/pages/friend_permission_page.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';

class Service extends StubSettingsService {
  @override
  bool get supportsFriendPermissions => true;
  final load = Completer<Map<String, int>>();
  Completer<void> save = Completer<void>();
  final writes = <bool>[];
  @override
  Future<Map<String, int>> getFriendPermissions() => load.future;
  @override
  Future<void> updateFriendVerification(bool required) {
    writes.add(required);
    return save.future;
  }
}

Widget host(Widget child, {bool dark = false, double scale = 1}) =>
    ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh')],
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => EasyLoading.init()(
                context,
                MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!)),
            home: child));
AppSwitch toggle(WidgetTester tester) =>
    tester.widget<AppSwitch>(find.byType(AppSwitch).at(1));
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });
  test('missing or malformed server flag cannot enable automatic approval', () {
    for (final value in [null, 1, 'true']) {
      final info = UserFullInfo.fromJson({'autoAcceptFriend': value});
      expect(info.autoAcceptFriend, isNull);
    }
    for (final value in [true, false]) {
      final info = UserFullInfo.fromJson({'autoAcceptFriend': value});
      expect(UserFullInfo.fromJson(info.toJson()).autoAcceptFriend, value);
    }
  });
  testWidgets(
      'confirmed saves only, duplicate taps blocked, disable failure preserves state',
      (tester) async {
    final service = Service();
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester
        .pumpWidget(host(FriendPermissionPage(store: store, service: service)));
    expect(toggle(tester).onChanged, isNull);
    service.load.complete({'allowAddFriend': 1, 'autoAcceptFriend': 0});
    await tester.pump();
    expect(toggle(tester).value, false);
    final callback = toggle(tester).onChanged!;
    callback(true);
    callback(true);
    await tester.pump();
    expect(service.writes, [false]);
    expect(toggle(tester).value, false);
    expect(toggle(tester).onChanged, isNull);
    service.save.complete();
    await tester.pump();
    expect(toggle(tester).value, true);
    EasyLoading.dismiss();
    await tester.pumpAndSettle();
    service.save = Completer<void>();
    toggle(tester).onChanged!(false);
    await tester.pump();
    service.save.completeError(StateError('offline'));
    await tester.pump();
    expect(toggle(tester).value, true);
    expect(service.writes, [false, true]);
    expect(find.textContaining('保存失败'), findsOneWidget);
    EasyLoading.dismiss();
    await tester.pumpAndSettle();
    service.save = Completer<void>();
    toggle(tester).onChanged!(false);
    await tester.pump();
    service.save.complete();
    await tester.pump();
    expect(toggle(tester).value, false);
    EasyLoading.dismiss();
    await tester.pumpAndSettle();
  });
  testWidgets('old backend disabled and saved server setting restored',
      (tester) async {
    for (final supported in [false, true]) {
      final service = Service();
      final store = SettingsDraftStore();
      await tester.pumpWidget(host(FriendPermissionPage(
          key: UniqueKey(), store: store, service: service)));
      service.load.complete(
          {'allowAddFriend': 1, if (supported) 'autoAcceptFriend': 1});
      await tester.pump();
      expect(toggle(tester).value, supported);
      expect(toggle(tester).onChanged != null, supported);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    }
  });
  testWidgets(
      'disabled add permission allows turning off existing auto approval only',
      (tester) async {
    final service = Service();
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester
        .pumpWidget(host(FriendPermissionPage(store: store, service: service)));
    service.load.complete({'allowAddFriend': 0, 'autoAcceptFriend': 1});
    await tester.pump();
    expect(toggle(tester).onChanged, isNotNull);
    toggle(tester).onChanged!(false);
    service.save.complete();
    await tester.pump();
    expect(toggle(tester).onChanged, isNull);
    EasyLoading.dismiss();
    await tester.pumpAndSettle();
  });
  for (final dark in [false, true]) {
    testWidgets('large text and labeled switch in dark=$dark', (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      final service = Service();
      final store = SettingsDraftStore();
      addTearDown(store.dispose);
      await tester.pumpWidget(host(
          FriendPermissionPage(store: store, service: service),
          dark: dark,
          scale: 2));
      service.load.complete({'allowAddFriend': 1, 'autoAcceptFriend': 0});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(RegExp('自动通过好友申请')), findsWidgets);
      semantics.dispose();
    });
  }
  testWidgets('completion after page disposal is ignored', (tester) async {
    final service = Service();
    final store = SettingsDraftStore();
    await tester
        .pumpWidget(host(FriendPermissionPage(store: store, service: service)));
    service.load.complete({'allowAddFriend': 1, 'autoAcceptFriend': 0});
    await tester.pump();
    toggle(tester).onChanged!(true);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    service.save.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
