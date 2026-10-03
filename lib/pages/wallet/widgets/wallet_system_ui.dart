import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const List<Color> kDecorativePageGradientColorsLight = [
  Color(0xFFFCFCFE),
  Color(0xFFFAF9FD),
  Color(0xFFFAFBFC),
];

const List<Color> kDecorativePageGradientColorsDark = [
  Color(0xFF1C1830),
  Color(0xFF171A24),
  Color(0xFF131820),
  Color(0xFF101114),
];

const List<double> kDecorativePageGradientStopsDark = [0, 0.36, 0.72, 1];

Color decorativePageStatusBarColor({required bool dark}) =>
    dark
        ? kDecorativePageGradientColorsDark.first
        : kDecorativePageGradientColorsLight.first;

/// 钱包 / 我的 Tab 装饰渐变顶色决定状态栏图标明暗，避免透明背景误判。
SystemUiOverlayStyle decorativeMainTabOverlayStyle({
  required bool dark,
  required Color navigationBarBackground,
}) {
  return immersiveOverlayForColors(
    statusBarBackground: decorativePageStatusBarColor(dark: dark),
    navigationBarBackground: navigationBarBackground,
  );
}

/// 全局 edge-to-edge：系统栏透明，由 [statusBarBackground] / [navigationBarBackground] 决定图标明暗。
SystemUiOverlayStyle immersiveOverlayForColors({
  required Color statusBarBackground,
  Color? navigationBarBackground,
}) {
  final navBackground = navigationBarBackground ?? statusBarBackground;
  final statusDark =
      ThemeData.estimateBrightnessForColor(statusBarBackground) ==
          Brightness.dark;
  final navDark =
      ThemeData.estimateBrightnessForColor(navBackground) == Brightness.dark;

  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: statusDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: statusDark ? Brightness.dark : Brightness.light,
    systemNavigationBarIconBrightness:
        navDark ? Brightness.light : Brightness.dark,
  );
}

/// 认证流：顶部品牌渐变 + 底部白卡片，状态栏浅色图标、导航栏深色图标。
const SystemUiOverlayStyle authImmersiveOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.dark,
);

/// 认证子页（白底表单）：状态栏/导航栏均用深色图标。
SystemUiOverlayStyle authFormImmersiveOverlayStyle({Color background = Colors.white}) {
  return immersiveOverlayForColors(
    statusBarBackground: background,
    navigationBarBackground: background,
  );
}

/// 弹窗/遮罩统一透明度。
const Color kImmersiveModalBarrierColor = Color(0x73000000);
