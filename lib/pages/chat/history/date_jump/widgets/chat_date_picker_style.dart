import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;

/// The jump calendar shares chat controls' blue and neutral surfaces.
abstract final class ChatDatePickerStyle {
  static const maxWidth = 360.0;
  static const titleSize = 20.0;
  static const actionHeight = 48.0;
  static const compactWidth = 340.0;
  static const compactCalendarMaxScale = 1.5;

  static ThemeData calendarTheme(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final text = AppTokens.textPrimary(dark: dark);
    final muted = AppTokens.textSecondary(dark: dark);
    final disabled = muted.withValues(alpha: .6);
    Color foreground(Set<WidgetState> states, {bool today = false}) {
      if (states.contains(WidgetState.disabled)) return disabled;
      if (states.contains(WidgetState.selected)) return AppTokens.onAccent;
      return today ? AppTokens.accent : text;
    }

    Color background(Set<WidgetState> states) =>
        states.contains(WidgetState.selected) &&
                !states.contains(WidgetState.disabled)
            ? AppTokens.accent
            : Colors.transparent;

    return theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(primary: AppTokens.accent),
      datePickerTheme: theme.datePickerTheme.copyWith(
        subHeaderForegroundColor: muted,
        toggleButtonTextStyle: theme.textTheme.bodyMedium?.copyWith(
            fontSize: AppTokens.captionFontSize, fontWeight: FontWeight.w500),
        weekdayStyle: theme.textTheme.bodyMedium?.copyWith(color: muted),
        dayStyle: theme.textTheme.bodyMedium?.copyWith(
            fontSize: AppTokens.secondaryFontSize, fontWeight: FontWeight.w500),
        dayForegroundColor: WidgetStateProperty.resolveWith(foreground),
        todayForegroundColor: WidgetStateProperty.resolveWith(
            (states) => foreground(states, today: true)),
        dayBackgroundColor: WidgetStateProperty.resolveWith(background),
        todayBackgroundColor: WidgetStateProperty.resolveWith(background),
        todayBorder: const BorderSide(color: AppTokens.accent),
      ),
    );
  }
}
