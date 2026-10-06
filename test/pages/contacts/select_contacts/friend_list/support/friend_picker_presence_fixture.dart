import 'dart:io';

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/friend_list/friend_list_logic.dart';
import 'package:openim/pages/contacts/select_contacts/friend_list/friend_list_view.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../contact_card/support/contact_card_picker_fixture.dart';

const friendPickerPreviewDirectory =
    String.fromEnvironment('FRIEND_PICKER_PRESENCE_PREVIEW_DIR');
const friendPickerLongName = '阿林特别长的好友备注与英文 Long friend name';

class _IM extends GetxController implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Selection extends SelectContactsLogic {
  _Selection(SelAction value) {
    action = value;
    openSelectedSheet = false;
  }

  @override
  // Only omit route argument initialization; selection actions remain real.
  // ignore: must_call_super
  void onInit() {}

  @override
  void onReady() {}
}

class _Friends extends SelectContactsFromFriendsLogic {
  _Friends(List<ISUserInfo> data) {
    // Match the SDK-backed FriendListLogic initialization after fixture edits.
    SuspensionUtil.setShowSuspensionStatus(data);
    friendList.assignAll(data);
  }

  @override
  // Test data replaces SDK streams; filtering and select-all are unchanged.
  // ignore: must_call_super
  void onInit() {}

  @override
  void onReady() {}

  @override
  // No SDK stream subscriptions were created in this fixture.
  // ignore: must_call_super
  void onClose() {
    searchController.dispose();
  }
}

class FriendPickerPresenceContacts extends ContactCardPickerContacts {
  bool currentSession = true;
  @override
  bool get isCurrentSession => currentSession;
}

List<ISUserInfo> friendPickerSamples() {
  final values = [
    ...cardPickerFriends().take(3),
    ISUserInfo.fromJson({
      'userID': '4001',
      'nickname': '张三',
      'tagIndex': 'Z',
      'namePinyin': 'ZHANG SAN',
    }),
  ];
  SuspensionUtil.setShowSuspensionStatus(values);
  return values;
}

Finder friendPickerRow(String id) =>
    find.byKey(ValueKey('friend-picker-row-$id'));

class FriendPickerPresenceFixture {
  FriendPickerPresenceFixture({
    SelAction action = SelAction.addMember,
    List<ISUserInfo>? data,
  })  : data = data ?? friendPickerSamples(),
        selection = _Selection(action);

  final List<ISUserInfo> data;
  final SelectContactsLogic selection;
  late final SelectContactsFromFriendsLogic friends;
  final contacts = FriendPickerPresenceContacts();
  final navigator = GlobalKey<NavigatorState>();
  final boundary = GlobalKey();

  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double width = 390,
    double textScale = 1,
    String? fontFamily,
    Locale locale = const Locale('zh', 'CN'),
    bool boldText = false,
  }) async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self');
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    FriendDisplayPreferences.setOnlineStatus(true);
    Get.put<IMController>(_IM(), permanent: true);
    Get.put<SelectContactsLogic>(selection, permanent: true);
    friends = _Friends(data);
    Get.put<SelectContactsFromFriendsLogic>(friends, permanent: true);
    Get.put<ContactsLogic>(contacts, permanent: true);
    final oldInterval = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final oldDark = Styles.isDark;
    final dark = brightness == Brightness.dark;
    Styles.isDark = dark;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      Styles.isDark = oldDark;
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      VisibilityDetectorController.instance.updateInterval = oldInterval;
      Get.reset();
    });

    final surface = dark ? const Color(0xFF202A36) : Colors.white;
    final foreground = dark ? const Color(0xFFE8EDF5) : const Color(0xFF0C1C33);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: brightness,
          fontFamily: fontFamily,
          colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF0089FF),
                  brightness: brightness,
                  surface: surface)
              .copyWith(onSurface: foreground),
          canvasColor: surface,
          appBarTheme: const AppBarTheme(scrolledUnderElevation: 0),
        ),
        translations: TranslationService(),
        locale: locale,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale), boldText: boldText),
            child: child!),
        home: const Scaffold(body: Text('父聊天页面')),
      ),
    ));
    navigator.currentState!.push<void>(MaterialPageRoute(
        builder: (_) => RepaintBoundary(
              key: boundary,
              child: SelectContactsFromFriendsPage(),
            )));
    await tester.pumpAndSettle();
  }
}

Future<void> loadFriendPickerPresencePreviewFonts() async {
  if (friendPickerPreviewDirectory.isEmpty) return;
  for (final font in {
    'FriendPickerPreviewCjk': 'C:/Windows/Fonts/msyh.ttc',
    'MaterialIcons':
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    await (FontLoader(font.key)
          ..addFont(File(font.value)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes))))
        .load();
  }
}
