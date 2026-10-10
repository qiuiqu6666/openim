import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

ThemeData buildAppThemeData(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final surface = dark ? const Color(0xFF202A36) : Colors.white;
  final foreground = dark ? const Color(0xFFE8EDF5) : const Color(0xFF0C1C33);
  final base = ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0089FF),
            brightness: brightness,
            surface: surface)
        .copyWith(onSurface: foreground),
  );
  return base.copyWith(
    scaffoldBackgroundColor:
        dark ? const Color(0xFF141D27) : const Color(0xFFF8F9FA),
    canvasColor: surface,
    cardColor: surface,
    appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        systemOverlayStyle: AppSystemBars.styleFor(surface)),
    textSelectionTheme:
        const TextSelectionThemeData().copyWith(cursorColor: Colors.blue),
    checkboxTheme: const CheckboxThemeData().copyWith(
      checkColor: WidgetStateProperty.all(base.colorScheme.onPrimary),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return base.colorScheme.onSurface.withValues(alpha: .38);
        }
        if (states.contains(WidgetState.selected)) {
          return base.colorScheme.primary;
        }
        return surface;
      }),
      side: BorderSide(color: base.colorScheme.outline, width: 1),
    ),
    dialogTheme: const DialogThemeData().copyWith(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4.0),
          ),
        ),
        textStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 16.sp,
            color: foreground,
          ),
        ),
        foregroundColor: WidgetStatePropertyAll(foreground),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData().copyWith(
        color: base.colorScheme.primary,
        linearTrackColor: base.colorScheme.surfaceContainerHighest,
        circularTrackColor: base.colorScheme.surfaceContainerHighest),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: CupertinoColors.systemBlue,
      barBackgroundColor: surface,
      applyThemeToAll: true,
      textTheme: const CupertinoTextThemeData().copyWith(
        navActionTextStyle:
            TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
        actionTextStyle:
            TextStyle(color: CupertinoColors.systemBlue, fontSize: 17.sp),
        textStyle: TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
        navLargeTitleTextStyle:
            TextStyle(color: CupertinoColors.label, fontSize: 20.sp),
        navTitleTextStyle:
            TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
        pickerTextStyle:
            TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
        tabLabelTextStyle:
            TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
        dateTimePickerTextStyle:
            TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
      ),
    ),
  );
}
