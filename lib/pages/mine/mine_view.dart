import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'mine_logic.dart';
import '../../theme/app_theme_controller.dart';

class MinePage extends StatelessWidget {
  final logic = Get.find<MineLogic>();

  MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Styles.c_F8F9FA,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  height: 138.h,
                  width: 1.sw,
                  color: Styles.c_0089FF,
                  child: ImageRes.mineHeaderBg.toImage,
                ),
                Obx(() => _buildMyInfoView()),
              ],
            ),
            10.verticalSpace,
            _buildItemView(
              icon: ImageRes.myInfo,
              label: StrRes.myInfo,
              onTap: logic.viewMyInfo,
              isTopRadius: true,
            ),
            _buildItemView(
              icon: ImageRes.accountSetup,
              label: StrRes.accountSetup,
              onTap: logic.accountSetup,
            ),
            _buildThemeItem(context),
            AnimatedBuilder(
              animation: NavigationGlassController.instance,
              builder: (context, _) => _buildAppearanceItem(
                context,
                icon: Icons.blur_on_outlined,
                label: _themeText(context, '导航玻璃效果', 'Navigation glass'),
                value: _glassModeLabel(
                    context, NavigationGlassController.instance.mode),
                onTap: () => _showGlassPicker(context),
              ),
            ),
            _buildItemView(
              icon: ImageRes.aboutUs,
              label: StrRes.aboutUs,
              onTap: logic.aboutUs,
            ),
            _buildItemView(
              icon: ImageRes.logout,
              label: StrRes.logout,
              onTap: logic.logout,
              isBottomRadius: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyInfoView() => Container(
        height: 98.h,
        margin: EdgeInsets.only(left: 16.w, right: 16.w, top: 90.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        decoration: BoxDecoration(
          color: Styles.c_FFFFFF,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Row(
          children: [
            AvatarView(
              onTap: logic.openPhotoSheet,
              url: logic.imLogic.userInfo.value.faceURL,
              text: logic.imLogic.userInfo.value.nickname,
              width: 48.w,
              height: 48.h,
              textStyle: Styles.ts_FFFFFF_14sp,
            ),
            10.horizontalSpace,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  (logic.imLogic.userInfo.value.nickname ?? '').toText
                    ..style = Styles.ts_0C1C33_17sp_medium
                    ..onTap = logic.editMyName,
                  4.verticalSpace,
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: logic.copyID,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        (logic.imLogic.userInfo.value.userID ?? '').toText
                          ..style = Styles.ts_8E9AB0_14sp,
                        ImageRes.mineCopy.toImage
                          ..width = 16.w
                          ..height = 16.h,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  String _themeText(BuildContext context, String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Widget _buildThemeItem(BuildContext context) => _buildAppearanceItem(
        context,
        icon: Icons.brightness_6_outlined,
        label: _themeText(context, '外观', 'Appearance'),
        value: _modeLabel(context, AppThemeController.instance.mode),
        onTap: () => _showThemePicker(context),
      );

  Widget _buildAppearanceItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) =>
      Container(
        margin: EdgeInsets.symmetric(horizontal: 16.w),
        color: Styles.c_FFFFFF,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: SizedBox(
              height: 56.h,
              child: Row(
                children: [
                  Icon(icon, size: 24.w, color: Styles.c_0C1C33),
                  11.horizontalSpace,
                  Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Styles.ts_0C1C33_17sp)),
                  Text(value, style: Styles.ts_8E9AB0_14sp),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      );

  String _glassModeLabel(BuildContext context, NavigationGlassMode mode) =>
      switch (mode) {
        NavigationGlassMode.automatic => _themeText(context, '自动', 'Automatic'),
        NavigationGlassMode.liquid =>
          _themeText(context, '液态玻璃', 'Liquid glass'),
        NavigationGlassMode.translucent =>
          _themeText(context, '普通半透明', 'Translucent'),
      };

  void _showGlassPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final mode in NavigationGlassMode.values)
            ListTile(
              title: Text(_glassModeLabel(sheetContext, mode)),
              subtitle: mode == NavigationGlassMode.automatic
                  ? Text(_themeText(sheetContext, 'Android 优先流畅，使用普通半透明效果',
                      'Uses translucent navigation on Android for smooth scrolling'))
                  : null,
              selected: mode == NavigationGlassController.instance.mode,
              trailing: mode == NavigationGlassController.instance.mode
                  ? Icon(Icons.check,
                      color: Theme.of(sheetContext).colorScheme.primary)
                  : null,
              onTap: () {
                NavigationGlassController.instance.setMode(mode);
                Navigator.pop(sheetContext);
              },
            ),
        ]),
      ),
    );
  }

  String _modeLabel(BuildContext context, ThemeMode mode) => switch (mode) {
        ThemeMode.system => _themeText(context, '跟随系统', 'System'),
        ThemeMode.light => _themeText(context, '浅色', 'Light'),
        ThemeMode.dark => _themeText(context, '深色', 'Dark'),
      };

  void _showThemePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              ListTile(
                title: Text(_modeLabel(sheetContext, mode)),
                trailing: mode == AppThemeController.instance.mode
                    ? Icon(Icons.check,
                        color: Theme.of(sheetContext).colorScheme.primary)
                    : null,
                selected: mode == AppThemeController.instance.mode,
                onTap: () {
                  AppThemeController.instance.setMode(mode);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemView({
    required String icon,
    required String label,
    bool isTopRadius = false,
    bool isBottomRadius = false,
    Function()? onTap,
  }) =>
      Container(
        margin: EdgeInsets.symmetric(horizontal: 16.w),
        child: Ink(
          decoration: BoxDecoration(
            color: Styles.c_FFFFFF,
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(isTopRadius ? 6.r : 0),
              topLeft: Radius.circular(isTopRadius ? 6.r : 0),
              bottomLeft: Radius.circular(isBottomRadius ? 6.r : 0),
              bottomRight: Radius.circular(isBottomRadius ? 6.r : 0),
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 56.h,
              padding: EdgeInsets.only(left: 12.w, right: 16.w),
              child: Row(
                children: [
                  icon.toImage
                    ..width = 24.w
                    ..height = 24.h,
                  11.horizontalSpace,
                  label.toText..style = Styles.ts_0C1C33_17sp,
                  const Spacer(),
                  ImageRes.rightArrow.toImage
                    ..width = 24.w
                    ..height = 24.h,
                ],
              ),
            ),
          ),
        ),
      );
}
