import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class Styles {
  Styles._();

  static bool isDark = false;

  static Color get c_0089FF =>
      isDark ? const Color(0xFF64B5FF) : const Color(0xFF0089FF);
  static Color get c_0C1C33 =>
      isDark ? const Color(0xFFE8EDF5) : const Color(0xFF0C1C33);
  static Color get c_8E9AB0 =>
      isDark ? const Color(0xFFA7B4C7) : const Color(0xFF8E9AB0);
  static Color get c_E8EAEF =>
      isDark ? const Color(0xFF394352) : const Color(0xFFE8EAEF);
  static Color get c_FF381F => const Color(0xFFFF381F);
  static Color get c_FFFFFF =>
      isDark ? const Color(0xFF202A36) : const Color(0xFFFFFFFF);
  static Color get c_18E875 => const Color(0xFF18E875);
  static Color get c_F0F2F6 =>
      isDark ? const Color(0xFF17212C) : const Color(0xFFF0F2F6);
  static Color get c_000000 =>
      isDark ? const Color(0xFFF4F7FB) : const Color(0xFF000000); //
  static Color get c_92B3E0 => const Color(0xFF92B3E0);
  static Color get c_F2F8FF =>
      isDark ? const Color(0xFF203C56) : const Color(0xFFF2F8FF);
  static Color get c_F8F9FA =>
      isDark ? const Color(0xFF141D27) : const Color(0xFFF8F9FA);
  static Color get c_6085B1 =>
      isDark ? const Color(0xFFA5C5ED) : const Color(0xFF6085B1);
  static Color get c_FFB300 => const Color(0xFFFFB300);
  static Color get presenceOnline => isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32);
  static Color get c_FFE1DD =>
      isDark ? const Color(0xFF50302F) : const Color(0xFFFFE1DD);
  static Color get c_707070 =>
      isDark ? const Color(0xFFB0BAC8) : const Color(0xFF707070);

  static Color get c_92B3E0_opacity50 => c_92B3E0.withOpacity(.5);
  static Color get c_E8EAEF_opacity50 => c_E8EAEF.withOpacity(.5);
  static Color get c_F4F5F7 =>
      isDark ? const Color(0xFF1A2530) : const Color(0xFFF4F5F7);
  static Color get c_CCE7FE =>
      isDark ? const Color(0xFF284864) : const Color(0xFFCCE7FE);

  static Color get c_FFFFFF_opacity0 => Colors.white.withOpacity(.0);
  static Color get c_FFFFFF_opacity70 => Colors.white.withOpacity(.7);
  static Color get c_FFFFFF_opacity50 => Colors.white.withOpacity(.5);
  static Color get c_0089FF_opacity10 => c_0089FF.withOpacity(.1);
  static Color get c_0089FF_opacity20 => c_0089FF.withOpacity(.2);
  static Color get c_0089FF_opacity50 => c_0089FF.withOpacity(.5);
  static Color get c_FF381F_opacity10 => c_FF381F.withOpacity(.1);
  static Color get c_8E9AB0_opacity13 => c_8E9AB0.withOpacity(.13);
  static Color get c_8E9AB0_opacity15 => c_8E9AB0.withOpacity(.15);
  static Color get c_8E9AB0_opacity16 => c_8E9AB0.withOpacity(.16);
  static Color get c_8E9AB0_opacity30 => c_8E9AB0.withOpacity(.3);
  static Color get c_8E9AB0_opacity50 => c_8E9AB0.withOpacity(.5);
  static Color get c_0C1C33_opacity30 => c_0C1C33.withOpacity(.3);
  static Color get c_0C1C33_opacity60 => c_0C1C33.withOpacity(.6);
  static Color get c_0C1C33_opacity85 => c_0C1C33.withOpacity(.85);
  static Color get c_0C1C33_opacity80 => c_0C1C33.withOpacity(.8);
  static Color get c_FF381F_opacity70 => c_FF381F.withOpacity(.7);
  static Color get c_000000_opacity70 => c_000000.withOpacity(.7);
  static Color get c_000000_opacity15 => c_000000.withOpacity(.15);
  static Color get c_000000_opacity12 => c_000000.withOpacity(.12);
  static Color get c_000000_opacity4 => c_000000.withOpacity(.04);

  static TextStyle get ts_FFFFFF_21sp => TextStyle(
        color: Colors.white,
        fontSize: 21.sp,
      );
  static TextStyle get ts_FFFFFF_20sp_medium => TextStyle(
        color: Colors.white,
        fontSize: 20.sp,
        fontWeight: FontWeight.w500,
      );
  static TextStyle get ts_FFFFFF_18sp_medium => TextStyle(
        color: Colors.white,
        fontSize: 18.sp,
        fontWeight: FontWeight.w500,
      );
  static TextStyle get ts_FFFFFF_17sp => TextStyle(
        color: Colors.white,
        fontSize: 17.sp,
      );
  static TextStyle get ts_FFFFFF_opacity70_17sp => TextStyle(
        color: c_FFFFFF_opacity70,
        fontSize: 17.sp,
      );
  static TextStyle get ts_FFFFFF_17sp_semibold => TextStyle(
        color: Colors.white,
        fontSize: 17.sp,
        fontWeight: FontWeight.w600,
      );
  static TextStyle get ts_FFFFFF_17sp_medium => TextStyle(
        color: Colors.white,
        fontSize: 17.sp,
        fontWeight: FontWeight.w500,
      );
  static TextStyle get ts_FFFFFF_16sp => TextStyle(
        color: Colors.white,
        fontSize: 16.sp,
      );
  static TextStyle get ts_FFFFFF_14sp => TextStyle(
        color: Colors.white,
        fontSize: 14.sp,
      );
  static TextStyle get ts_FFFFFF_opacity70_14sp => TextStyle(
        color: c_FFFFFF_opacity70,
        fontSize: 14.sp,
      );
  static TextStyle get ts_FFFFFF_14sp_medium => TextStyle(
        color: Colors.white,
        fontSize: 14.sp,
        fontWeight: FontWeight.w500,
      );
  static TextStyle get ts_FFFFFF_12sp => TextStyle(
        color: Colors.white,
        fontSize: 12.sp,
      );
  static TextStyle get ts_FFFFFF_10sp => TextStyle(
        color: Colors.white,
        fontSize: 10.sp,
      );

  static TextStyle get ts_8E9AB0_10sp_semibold => TextStyle(
        color: c_8E9AB0,
        fontSize: 10.sp,
        fontWeight: FontWeight.w600,
      );
  static TextStyle get ts_8E9AB0_10sp => TextStyle(
        color: c_8E9AB0,
        fontSize: 10.sp,
      );
  static TextStyle get ts_8E9AB0_12sp => TextStyle(
        color: c_8E9AB0,
        fontSize: 12.sp,
      );
  static TextStyle get ts_8E9AB0_13sp => TextStyle(
        color: c_8E9AB0,
        fontSize: 13.sp,
      );
  static TextStyle get ts_8E9AB0_14sp => TextStyle(
        color: c_8E9AB0,
        fontSize: 14.sp,
      );
  static TextStyle get ts_8E9AB0_15sp => TextStyle(
        color: c_8E9AB0,
        fontSize: 15.sp,
      );
  static TextStyle get ts_8E9AB0_16sp => TextStyle(
        color: c_8E9AB0,
        fontSize: 16.sp,
      );
  static TextStyle get ts_8E9AB0_17sp => TextStyle(
        color: c_8E9AB0,
        fontSize: 17.sp,
      );
  static TextStyle get ts_8E9AB0_opacity50_17sp => TextStyle(
        color: c_8E9AB0_opacity50,
        fontSize: 17.sp,
      );

  static TextStyle get ts_0C1C33_10sp => TextStyle(
        color: c_0C1C33,
        fontSize: 10.sp,
      );
  static TextStyle get ts_0C1C33_12sp => TextStyle(
        color: c_0C1C33,
        fontSize: 12.sp,
      );
  static TextStyle get ts_0C1C33_12sp_medium => TextStyle(
        color: c_0C1C33,
        fontSize: 12.sp,
        fontWeight: FontWeight.w500,
      );
  static TextStyle get ts_0C1C33_14sp => TextStyle(
        color: c_0C1C33,
        fontSize: 14.sp,
      );
  static TextStyle get ts_0C1C33_14sp_medium => TextStyle(
        color: c_0C1C33,
        fontSize: 14.sp,
        fontWeight: FontWeight.w500,
      );
  static TextStyle get ts_0C1C33_17sp => TextStyle(
        color: c_0C1C33,
        fontSize: 17.sp,
      );
  static TextStyle get ts_0C1C33_17sp_medium => TextStyle(
        color: c_0C1C33,
        fontSize: 17.sp,
        fontWeight: FontWeight.w500,
      );
  static TextStyle get ts_0C1C33_17sp_semibold => TextStyle(
        color: c_0C1C33,
        fontSize: 17.sp,
        fontWeight: FontWeight.w600,
      );
  static TextStyle get ts_0C1C33_20sp => TextStyle(
        color: c_0C1C33,
        fontSize: 20.sp,
      );
  static TextStyle get ts_0C1C33_20sp_medium => TextStyle(
        color: c_0C1C33,
        fontSize: 20.sp,
        fontWeight: FontWeight.w500,
      );
  static TextStyle get ts_0C1C33_20sp_semibold => TextStyle(
        color: c_0C1C33,
        fontSize: 20.sp,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get ts_0089FF_10sp_semibold => TextStyle(
        color: c_0089FF,
        fontSize: 10.sp,
        fontWeight: FontWeight.w600,
      );
  static TextStyle get ts_0089FF_10sp => TextStyle(
        color: c_0089FF,
        fontSize: 10.sp,
      );
  static TextStyle get ts_0089FF_12sp => TextStyle(
        color: c_0089FF,
        fontSize: 12.sp,
      );
  static TextStyle get ts_0089FF_14sp => TextStyle(
        color: c_0089FF,
        fontSize: 14.sp,
      );
  static TextStyle get ts_0089FF_16sp => TextStyle(
        color: c_0089FF,
        fontSize: 16.sp,
      );
  static TextStyle get ts_0089FF_16sp_medium => TextStyle(
        color: c_0089FF,
        fontSize: 16.sp,
        fontWeight: FontWeight.w500,
      );
  static TextStyle get ts_0089FF_17sp => TextStyle(
        color: c_0089FF,
        fontSize: 17.sp,
      );
  static TextStyle get ts_0089FF_17sp_semibold => TextStyle(
        color: c_0089FF,
        fontSize: 17.sp,
        fontWeight: FontWeight.w600,
      );
  static TextStyle get ts_0089FF_17sp_medium => TextStyle(
        color: c_0089FF,
        fontSize: 17.sp,
        fontWeight: FontWeight.w500,
      );
  static TextStyle get ts_0089FF_14sp_medium => TextStyle(
        color: c_0089FF,
        fontSize: 14.sp,
        fontWeight: FontWeight.w500,
      );

  static TextStyle get ts_0089FF_22sp_semibold => TextStyle(
        color: c_0089FF,
        fontSize: 22.sp,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get ts_FF381F_17sp => TextStyle(
        color: c_FF381F,
        fontSize: 17.sp,
      );
  static TextStyle get ts_FF381F_14sp => TextStyle(
        color: c_FF381F,
        fontSize: 14.sp,
      );
  static TextStyle get ts_FF381F_12sp => TextStyle(
        color: c_FF381F,
        fontSize: 12.sp,
      );
  static TextStyle get ts_FF381F_10sp => TextStyle(
        color: c_FF381F,
        fontSize: 10.sp,
      );

  static TextStyle get ts_6085B1_17sp_medium => TextStyle(
        color: c_6085B1,
        fontSize: 17.sp,
        fontWeight: FontWeight.w500,
      );
  static TextStyle get ts_6085B1_17sp => TextStyle(
        color: c_6085B1,
        fontSize: 17.sp,
      );
  static TextStyle get ts_6085B1_12sp => TextStyle(
        color: c_6085B1,
        fontSize: 12.sp,
      );
  static TextStyle get ts_6085B1_14sp => TextStyle(
        color: c_6085B1,
        fontSize: 14.sp,
      );
}
