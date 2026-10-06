import 'dart:ui' as ui;
import '../../data/group_feature_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:openim_common/openim_common.dart';
import '../sangong_scope.dart';
import '../widgets/authorization/privilege_route_guard.dart';
export 'package:openim_common/openim_common.dart' show AppTokens;

/// Source layout translations without depending on Tencent's locale singleton.
class AppI18n {
  const AppI18n(this.locale);
  final Locale locale;
  static AppI18n of(BuildContext context) =>
      AppI18n(Localizations.localeOf(context));
  static AppI18n get current => AppI18n(ui.PlatformDispatcher.instance.locale);
  String t(
      {required String zhHans,
      String? zhHant,
      required String en,
      String? ja,
      String? ko}) {
    if (locale.languageCode == 'zh') {
      return locale.scriptCode == 'Hant' ||
              ['TW', 'HK', 'MO'].contains(locale.countryCode)
          ? zhHant ?? zhHans
          : zhHans;
    }
    return en;
  }

  String format(
      {required String zhHans,
      String? zhHant,
      required String en,
      String? ja,
      String? ko,
      Map<String, String> vars = const {}}) {
    var result = t(zhHans: zhHans, zhHant: zhHant, en: en, ja: ja, ko: ko);
    for (final entry in vars.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }
}

class AppColors {
  static const primaryBlue = AppTokens.accent;
  static const primaryRed = AppTokens.walletDanger;
  static const success = AppTokens.success;
  static const warning = AppTokens.warning;
  static Color background({required bool dark}) =>
      AppTokens.background(dark: dark);
  static Color card({required bool dark}) => AppTokens.surface(dark: dark);
  static Color surfaceAlt({required bool dark}) =>
      AppTokens.surfaceAlt(dark: dark);
  static Color text({required bool dark}) => AppTokens.textPrimary(dark: dark);
  static Color subText({required bool dark}) =>
      AppTokens.textSecondary(dark: dark);
  static Color line({required bool dark}) => AppTokens.border(dark: dark);
}

class SangongFloatTheme {
  const SangongFloatTheme({this.primaryColor, this.weakBackgroundColor});
  final Color? primaryColor;
  final Color? weakBackgroundColor;
  factory SangongFloatTheme.of(BuildContext context) => SangongFloatTheme(
        primaryColor: AppTokens.accent,
        weakBackgroundColor: AppTokens.background(
            dark: Theme.of(context).brightness == Brightness.dark),
      );
}

/// OpenIM identifiers remain opaque: the Tencent group_/@ normalization is not
/// applicable to an OpenIM group or user identifier.
class ChatIdFormat {
  static String normalizeGroupId(String input) => input.trim();
  static String rawUserUid(String input) => input.trim();
}

class ToastUtils {
  static void toast(String message, {BuildContext? context}) {
    if (context != null && !context.mounted) return;
    if (context != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    } else {
      IMViews.showToast(message);
    }
  }
}

class DioErrorMessage {
  static String sanitizeUserText(String? value, {required String fallback}) =>
      value?.trim().isNotEmpty == true ? value!.trim() : fallback;
  static String loadFailed() => '加载失败，请重试';
  static String forApp(Object error) {
    if (error is GroupFeatureException) return error.message;
    if (error is DioException) {
      if (error.error is GroupFeatureException) {
        return (error.error as GroupFeatureException).message;
      }
      if (error.error is StateError) {
        return (error.error as StateError).message.toString();
      }
      final data = error.response?.data;
      if (data is Map) {
        for (final field in ['errMsg', 'message', 'msg', 'error']) {
          final value = data[field];
          if (value is String && value.trim().isNotEmpty) return value.trim();
        }
      }
      if (error.response?.statusCode == 404) return '三公接口暂不可用，请稍后重试';
      if (error.response?.statusCode == 403) return '没有此操作权限';
      if (error.type == DioExceptionType.cancel) return '账号或群上下文已变化，请重新进入';
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return '网络连接失败，请重试';
      }
      return error.error is String ? error.error.toString() : '请求失败，请重试';
    }
    if (error is StateError) return error.message.toString();
    if (error is FormatException) return '返回数据格式无效，请重试';
    return '请求失败，请重试';
  }
}

/// Reuses the app's loading component. Pages retain their own busy guards.
class AppHud {
  static AppHudSession begin() {
    EasyLoading.show();
    return AppHudSession();
  }
}

class AppHudSession {
  bool _ended = false;
  Future<void> end() async {
    if (!_ended) {
      _ended = true;
      await EasyLoading.dismiss();
    }
  }
}

class AppDialog {
  static Future<bool> confirm(
      {required BuildContext context,
      required String title,
      required String message,
      String cancelText = '取消',
      String confirmText = '确定',
      bool destructive = false,
      bool barrierDismissible = false,
      Widget Function(BuildContext, Widget)? dialogWrapper}) async {
    final runtime = SangongScope.read(context);
    final featureContext = runtime.featureContext;
    if (!runtime.isCurrent) return false;
    final result = await showCupertinoDialog<bool>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (dialogContext) {
          final dialog = CupertinoAlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                CupertinoDialogAction(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(cancelText)),
                CupertinoDialogAction(
                    isDefaultAction: true,
                    isDestructiveAction: destructive,
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(confirmText))
              ]);
          return SangongPrivilegeRouteGuard(
            featureContext: featureContext,
            refreshOnEntry: false,
            isCurrent: () => runtime.isCurrent,
            builder: (_) => SangongScope(
                runtime: runtime,
                child: dialogWrapper?.call(dialogContext, dialog) ?? dialog),
          );
        });
    return result == true;
  }

  static Future<String?> prompt(
      {required BuildContext context,
      required String title,
      String? message,
      String? placeholder,
      String initialValue = '',
      String cancelText = '取消',
      String confirmText = '确定',
      int? maxLength,
      TextInputType? keyboardType,
      List<TextInputFormatter>? inputFormatters,
      bool barrierDismissible = true,
      bool allowEmpty = false,
      Widget Function(BuildContext, Widget)? dialogWrapper}) async {
    final runtime = SangongScope.read(context);
    final featureContext = runtime.featureContext;
    if (!runtime.isCurrent) return null;
    return showCupertinoDialog<String>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (dialogContext) {
          final prompt = _SangongPrompt(
              title: title,
              message: message,
              placeholder: placeholder,
              initialValue: initialValue,
              cancelText: cancelText,
              confirmText: confirmText,
              maxLength: maxLength,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              allowEmpty: allowEmpty);
          return SangongPrivilegeRouteGuard(
            featureContext: featureContext,
            refreshOnEntry: false,
            isCurrent: () => runtime.isCurrent,
            builder: (_) => SangongScope(
                runtime: runtime,
                child: dialogWrapper?.call(dialogContext, prompt) ?? prompt),
          );
        });
  }

  static Future<void> showLoading({String text = '加载中...'}) =>
      EasyLoading.show(status: text);
  static void hideLoading() {
    EasyLoading.dismiss();
  }
}

class _SangongPrompt extends StatefulWidget {
  const _SangongPrompt(
      {required this.title,
      this.message,
      this.placeholder,
      required this.initialValue,
      required this.cancelText,
      required this.confirmText,
      this.maxLength,
      this.keyboardType,
      this.inputFormatters,
      required this.allowEmpty});
  final String title, initialValue, cancelText, confirmText;
  final String? message, placeholder;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool allowEmpty;
  @override
  State<_SangongPrompt> createState() => _SangongPromptState();
}

class _SangongPromptState extends State<_SangongPrompt> {
  late final _controller = TextEditingController(text: widget.initialValue);
  bool _closing = false;
  void _finish([bool submit = true]) {
    if (_closing) return;
    final value = _controller.text.trim();
    if (submit && !widget.allowEmpty && value.isEmpty) return;
    _closing = true;
    Navigator.of(context).pop(submit ? value : null);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
          title: Text(widget.title),
          content: Column(children: [
            if (widget.message != null) Text(widget.message!),
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: CupertinoTextField(
                    controller: _controller,
                    autofocus: true,
                    placeholder: widget.placeholder,
                    maxLength: widget.maxLength,
                    keyboardType: widget.keyboardType,
                    inputFormatters: widget.inputFormatters,
                    onSubmitted: (_) => _finish()))
          ]),
          actions: [
            CupertinoDialogAction(
                onPressed: () => _finish(false),
                child: Text(widget.cancelText)),
            CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: _finish,
                child: Text(widget.confirmText))
          ]);
}
