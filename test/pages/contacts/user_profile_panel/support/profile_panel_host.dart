import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart' show GroupInfo;
import 'package:get/get.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile_panel_view.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';

import 'profile_panel_fixture.dart';

ThemeData profilePanelTheme(bool dark, {String? fontFamily}) {
  final brightness = dark ? Brightness.dark : Brightness.light;
  final surface = dark ? const Color(0xFF202A36) : Colors.white;
  final foreground = dark ? const Color(0xFFE8EDF5) : const Color(0xFF0C1C33);
  final label = TextStyle(
      color: CupertinoColors.label, fontSize: 17, fontFamily: fontFamily);
  return ThemeData(
    fontFamily: fontFamily,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0089FF),
            brightness: brightness,
            surface: surface)
        .copyWith(onSurface: foreground),
    scaffoldBackgroundColor:
        dark ? const Color(0xFF141D27) : const Color(0xFFF8F9FA),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: CupertinoColors.systemBlue,
      applyThemeToAll: true,
      textTheme: const CupertinoTextThemeData().copyWith(
          textStyle: label,
          actionTextStyle: label.copyWith(color: CupertinoColors.systemBlue)),
    ),
  );
}

Future<void> mountProfilePanel(
  WidgetTester tester, {
  required ProfilePanelFixture fixture,
  required MomentsRepository moments,
  ProfileContactsFixture? contacts,
  bool dark = false,
  Locale locale = const Locale('zh', 'CN'),
  Size size = const Size(375, 812),
  double textScale = 1,
  bool reducedMotion = false,
  String? fontFamily,
  GlobalKey? previewKey,
  bool settle = true,
  GroupFeatureStore? groupFeatureStore,
  Future<List<GroupInfo>> Function()? loadGameGroups,
}) async {
  Get.testMode = true;
  Styles.isDark = dark;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => Styles.isDark = false);
  GetTags.createUserProfileTag();
  addTearDown(GetTags.destroyUserProfileTag);
  Get.put<UserProfilePanelLogic>(fixture, tag: GetTags.userProfile);
  if (contacts != null) Get.put<ContactsLogic>(contacts);
  addTearDown(Get.reset);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) {
      final app = GetMaterialApp(
        debugShowCheckedModeBanner: false,
        translations: TranslationService(),
        locale: locale,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: profilePanelTheme(dark, fontFamily: fontFamily),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 34),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
        home: UserProfilePanelPage(
            momentsRepository: moments,
            groupFeatureStore: groupFeatureStore,
            loadGameGroups: loadGameGroups),
      );
      return previewKey == null
          ? app
          : RepaintBoundary(key: previewKey, child: app);
    },
  ));
  if (settle) await tester.pumpAndSettle();
}
