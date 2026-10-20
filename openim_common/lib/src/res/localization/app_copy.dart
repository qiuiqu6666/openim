import 'dart:ui';

import 'package:get/get.dart';

import 'traditional_copy.dart';

/// Localizes application-owned copy only. Never converts arbitrary user content.
///
/// Exact catalog matches are intentional: nicknames, chat messages, identifiers
/// and server payloads must not undergo character-by-character conversion.
class AppCopy {
  AppCopy._();

  static bool isTraditional([Locale? locale]) {
    final value = locale ?? Get.locale ?? Get.deviceLocale;
    if (value?.languageCode.toLowerCase() != 'zh') return false;
    final script = value?.scriptCode?.toLowerCase();
    if (script == 'hans') return false;
    return script == 'hant' ||
        const {'TW', 'HK', 'MO'}.contains(value?.countryCode?.toUpperCase());
  }

  static String text(String source, {Locale? locale}) =>
      isTraditional(locale) ? traditionalCopy[source] ?? source : source;

  /// Localize known local error messages at presentation time, after callers
  /// have inspected their original codes/types. Preserve diagnostic context.
  static String error(Object error, {Locale? locale}) {
    final rendered = error.toString();
    final Object? message = error is StateError
        ? error.message
        : error is FormatException
            ? error.message
            : null;
    if (message is String && message.isNotEmpty) {
      return rendered.replaceFirst(message, text(message, locale: locale));
    }
    return text(rendered, locale: locale);
  }

  /// Translate the template before inserting values, preserving them verbatim.
  /// A single replacement pass also prevents values resembling placeholders
  /// from being interpreted as another template instruction.
  static String format(String source, List<Object?> values, {Locale? locale}) =>
      text(source, locale: locale).replaceAllMapped(
        RegExp(r'\{#(\d+)\}'),
        (match) {
          final index = int.parse(match[1]!);
          return index < values.length ? '${values[index]}' : match[0]!;
        },
      );
}
