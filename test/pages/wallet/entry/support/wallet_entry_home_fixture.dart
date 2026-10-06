import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/pages/home/home_view.dart';
import 'package:openim/pages/mine/mine_logic.dart';
import 'package:openim/pages/wallet/entry/wallet_entry_coordinator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../support/conversation_live_fixture.dart';

class _Home extends GetxController implements HomeLogic {
  @override
  final unhandledCount = 0.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account extends GetxController implements IMController {
  @override
  final userInfo = UserFullInfo(userID: 'viewer', nickname: 'Viewer').obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conversations extends GetxController
    with ConversationLiveFixture
    implements ConversationLogic {
  @override
  final list = <ConversationInfo>[].obs;
  @override
  final folders = <ChatFolder>[].obs;
  @override
  final organizerLoading = false.obs;
  @override
  final organizerError = RxnString();
  @override
  final popCtrl = CustomPopupMenuController();
  @override
  bool get isSessionActive => true;
  @override
  String? get imSdkStatus => null;
  @override
  bool get isFailedSdkStatus => false;
  @override
  bool get reInstall => false;
  @override
  bool isArchived(ConversationInfo info) => false;
  @override
  bool isGroupChat(ConversationInfo info) => info.isGroupChat;
  @override
  String? folderID(ConversationInfo info) => null;
  @override
  Future<void> refreshOrganizer() async {}
  @override
  void globalSearch() {}
  @override
  void addFriend() {}
  @override
  void addGroup() {}
  @override
  void createGroup() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void onClose() {
    popCtrl.dispose();
    super.onClose();
  }
}

Future<void> mountWalletEntryHome(WidgetTester tester,
    {required WalletEntryCoordinator coordinator, bool dark = false}) async {
  Get.testMode = true;
  SharedPreferences.setMockInitialValues({});
  await SpUtil().init();
  OpenIM.iMManager.userID = 'viewer';
  Styles.isDark = dark;
  addTearDown(() {
    Styles.isDark = false;
    Get.reset();
  });
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Get.put<HomeLogic>(_Home());
  Get.put<IMController>(_Account());
  Get.put<ConversationLogic>(_Conversations());
  Get.put<MineLogic>(MineLogic());
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: EasyLoading.init(),
      home: HomePage(walletEntry: coordinator),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder walletEntryTab(String label) => find.descendant(
    of: find.byType(BottomNavigationBar), matching: find.text(label));

int selectedWalletEntryTab(WidgetTester tester) => tester
    .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
    .currentIndex;
