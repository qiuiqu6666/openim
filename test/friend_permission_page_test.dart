import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/mine/settings/pages/friend_permission_page.dart';
import 'package:openim/pages/mine/settings/pages/add_friend_privacy_page.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/contacts/presence_label.dart';
import 'package:openim/pages/contacts/presence_store.dart';

class _Service extends StubSettingsService {
  @override
  bool get supportsFriendPermissions => true;
  final load = Completer<Map<String, int>>();
  Completer<void> save = Completer<void>();
  int writes = 0;
  @override
  Future<Map<String, int>> getFriendPermissions() => load.future;
  @override
  Future<void> updateAllowAddFriend(bool allowed) {
    writes++;
    return save.future;
  }

  @override
  Future<void> updateFriendDiscovery(
      {bool? qrCode,
      bool? businessCard,
      bool? group,
      bool? phone,
      bool? uid,
      bool? account,
      bool? email}) {
    writes++;
    return save.future;
  }
}

const snapshot = {
  'allowAddFriend': 0,
  'allowAddByQRCode': 2,
  'allowAddByCard': 1,
  'allowAddByGroup': 1,
  'allowAddByPhone': 2,
  'allowAddByUserID': 1
};
Widget host(Widget child) => ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (context, _) => MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: EasyLoading.init(),
        home: child));
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });
  testWidgets(
      'remote load, successful save and rejected save preserve confirmed values',
      (tester) async {
    final service = _Service();
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester
        .pumpWidget(host(FriendPermissionPage(store: store, service: service)));
    expect(tester.widget<AppSwitch>(find.byType(AppSwitch).first).onChanged,
        isNull);
    final initialPosition = tester.getTopLeft(find.text('允许别人添加我'));
    final initialBlacklistPosition = tester.getTopLeft(find.text('黑名单'));
    service.load.complete(snapshot);
    await tester.pump();
    expect(tester.getTopLeft(find.text('允许别人添加我')), initialPosition);
    expect(tester.getTopLeft(find.text('黑名单')), initialBlacklistPosition);
    expect(store.allowAddFriend, false);
    expect(store.allowQrCode, false);
    expect(store.allowPhone, false);
    var toggle = tester.widget<AppSwitch>(find.byType(AppSwitch).first);
    toggle.onChanged!(true);
    toggle.onChanged!(true);
    await tester.pump();
    expect(tester.getTopLeft(find.text('允许别人添加我')), initialPosition);
    expect(tester.getTopLeft(find.text('黑名单')), initialBlacklistPosition);
    expect(service.writes, 1);
    expect(store.allowAddFriend, false);
    service.save.complete();
    await tester.pump();
    expect(store.allowAddFriend, true);
    EasyLoading.dismiss();
    await tester.pumpAndSettle();
    service.save = Completer<void>();
    toggle = tester.widget<AppSwitch>(find.byType(AppSwitch).first);
    toggle.onChanged!(false);
    await tester.pump();
    service.save.completeError(StateError('offline'));
    await tester.pump();
    expect(store.allowAddFriend, true);
    expect(service.writes, 2);
    expect(find.textContaining('保存失败'), findsOneWidget);
    EasyLoading.dismiss();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'read display hides only read indicators and preserves sent status',
      (tester) async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(host(const Scaffold(
        body: ChatItemContainer(
      id: 'message',
      isBubbleBg: true,
      isISend: true,
      hasRead: true,
      isSending: false,
      isSendFailed: false,
      child: Text('hello'),
    ))));
    expect(
        tester
            .widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon))
            .isRead,
        true);
    store.setReadReceipts(false);
    await tester.pump();
    final status =
        tester.widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon));
    expect(status.isRead, false);
    expect(status.semanticLabel, StrRes.sentSuccessfully);
    store.setReadReceipts(true);
    await tester.pump();
    expect(
        tester
            .widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon))
            .isRead,
        true);
  });
  testWidgets('channel failure keeps value and only one write can run',
      (tester) async {
    final service = _Service();
    final store = SettingsDraftStore()..syncFriendPermissions(snapshot);
    addTearDown(store.dispose);
    await tester
        .pumpWidget(host(AddFriendPrivacyPage(store: store, service: service)));
    final toggle = tester.widget<AppSwitch>(find.byType(AppSwitch).first);
    toggle.onChanged!(true);
    toggle.onChanged!(true);
    await tester.pump();
    expect(service.writes, 1);
    service.save.completeError(StateError('failed'));
    await tester.pump();
    expect(store.allowQrCode, false);
    EasyLoading.dismiss();
    await tester.pumpAndSettle();
  });
  testWidgets(
      'online display updates immediately and preferences are account scoped',
      (tester) async {
    await DataSp.putLoginCertificate(
        LoginCertificate.fromJson({'userID': 'one', 'chatToken': 'chat'}));
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(host(
        Scaffold(body: PresenceLabel(presence: UserPresence(true, null)))));
    expect(find.byType(Text), findsOneWidget);
    store.setShowOnlineStatus(false);
    store.setReadReceipts(false);
    await tester.pump();
    expect(find.byType(Text), findsNothing);
    expect(FriendDisplayPreferences.showReadReceipts, false);
    final restored = SettingsDraftStore();
    expect(restored.showOnlineStatus, false);
    restored.dispose();
    await DataSp.putLoginCertificate(
        LoginCertificate.fromJson({'userID': 'two', 'chatToken': 'chat'}));
    expect(FriendDisplayPreferences.showOnlineStatus, true);
    expect(FriendDisplayPreferences.showReadReceipts, true);
    await DataSp.putLoginCertificate(
        LoginCertificate.fromJson({'userID': 'one', 'chatToken': 'chat'}));
    expect(FriendDisplayPreferences.showOnlineStatus, false);
  });
}
