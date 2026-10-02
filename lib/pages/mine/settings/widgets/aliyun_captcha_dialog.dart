import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../verification_code_result.dart';
import 'aliyun_captcha_html.dart';
import 'settings_widgets.dart';

Future<VerificationCodeResult?> showAliyunCaptcha(BuildContext context,
    Future<VerificationCodeResult> Function(String) request) {
  return showDialog<VerificationCodeResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) => _CaptchaDialog(request: request));
}

class _CaptchaDialog extends StatefulWidget {
  const _CaptchaDialog({required this.request});
  final Future<VerificationCodeResult> Function(String) request;
  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<_CaptchaDialog> {
  WebViewController? _controller;
  Timer? _timeout;
  bool _ready = false, _checking = false, _closing = false;
  bool _cancelRequested = false;
  String? _error;
  int _generation = 0;
  VerificationCodeResult? _result;
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  String text(String zh, String en) => settingsText(context, zh: zh, en: en);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null && _supported) _load();
  }

  void _load() {
    final generation = ++_generation;
    _ready = false;
    _error = null;
    final locale = Localizations.localeOf(context);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('CaptchaBridge', onMessageReceived: (message) {
        if (mounted && generation == _generation) {
          _message(message.message, generation);
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) => request.isMainFrame &&
                request.url != 'about:blank' &&
                request.url.replaceFirst(RegExp(r'/+$'), '') !=
                    Config.appAuthUrl.replaceFirst(RegExp(r'/+$'), '')
            ? NavigationDecision.prevent
            : NavigationDecision.navigate,
        onWebResourceError: (error) {
          if (error.isForMainFrame == true &&
              mounted &&
              generation == _generation) {
            _loadError();
          }
        },
      ));
    _controller = controller;
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 25), () {
      if (mounted && generation == _generation && !_ready) _loadError();
    });
    controller
        .loadHtmlString(
            aliyunCaptchaHtml(
              language: locale.languageCode == 'zh'
                  ? (locale.countryCode == 'TW' ? 'tw' : 'cn')
                  : 'en',
            ),
            baseUrl: Config.appAuthUrl)
        .catchError((Object _) {
      if (mounted && generation == _generation) _loadError();
    });
  }

  void _loadError() => setState(() {
        _error = text('验证加载失败，请检查网络后重试',
            'Could not load verification. Check your connection and retry.');
        _ready = false;
      });

  Future<void> _message(String raw, int generation) async {
    if (_closing) return;
    dynamic message;
    try {
      message = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (message is! Map) return;
    switch (message['type']) {
      case 'ready':
        _timeout?.cancel();
        setState(() {
          _ready = true;
        });
        return;
      case 'error':
        if (kDebugMode) {
          debugPrint('[Captcha] SDK initialization/resource error');
        }
        _loadError();
        return;
      case 'close':
        if (message['reason'] == 'verifyComplete') return;
        if (_checking) {
          _cancelRequested = true;
        } else {
          _finish();
        }
        return;
      case 'complete':
        if (message['bizResult'] == true && _result?.sent == true) {
          _finish();
        }
        return;
      case 'verify':
        final id = message['id'], param = message['captchaVerifyParam'];
        if (!_ready ||
            _checking ||
            id is! int ||
            param is! String ||
            param.isEmpty) {
          return;
        }
        setState(() {
          _checking = true;
          _error = null;
        });
        if (kDebugMode) {
          debugPrint('[Captcha] SDK proof received; requesting verification');
        }
        var reload = false;
        var sdkResult = <String, bool>{
          'captchaResult': false,
          'bizResult': false
        };
        try {
          final result = await widget.request(param);
          if (!mounted || generation != _generation) return;
          if (kDebugMode) {
            debugPrint(
                '[Captcha] backend captchaVerified=${result.captchaVerified}, sent=${result.sent}, retryAfter=${result.retryAfter}');
          }
          _result = result;
          sdkResult = result.sdkResult;
          reload = result.captchaVerified && !result.sent;
          if (!result.sent) {
            final error = result.captchaVerified
                ? text('短信发送失败，请重新验证后重试',
                    'SMS could not be sent. Verify again to retry.')
                : text('验证未通过或服务超时，请重新验证',
                    'Verification failed or timed out. Please retry.');
            if (result.captchaVerified) showSettingsMessage(context, error);
          }
        } catch (error) {
          if (kDebugMode) {
            final code = error is (int, String) ? error.$1 : null;
            debugPrint(
                '[Captcha] request failed: type=${error.runtimeType}, errCode=$code');
          }
          reload = true;
          if (!mounted || generation != _generation) return;
          final errorText = settingsErrorMessage(context, error,
              fallback: text('发送失败，请重新验证后重试',
                  'Could not send the code. Verify again to retry.'));
          showSettingsMessage(context, errorText);
        }
        if (!mounted || generation != _generation) return;
        try {
          await _controller!.runJavaScript(
              'window.resolveCaptchaRequest(${jsonEncode(id)},${jsonEncode(sdkResult)});');
        } catch (_) {
          if (mounted && _result?.sent == true) {
            _finish();
            return;
          }
          reload = true;
          _error = text('验证连接中断，请重试',
              'Verification connection interrupted. Please retry.');
        }
        if (_closing) return;
        if (mounted) {
          setState(() {
            _checking = false;
            if (reload && !_cancelRequested) {
              final error = _error;
              _load();
              _error = error;
            }
          });
        }
        // A sent code must not become resendable if the SDK completion callback is lost.
        if (mounted && (_result?.sent == true || _cancelRequested)) {
          _finish();
        }
    }
  }

  void _finish() {
    if (!mounted || _closing) return;
    _closing = true;
    Navigator.of(context).pop(_result);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_checking,
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox.expand(
              child: Stack(children: [
            if (_supported)
              Positioned.fill(
                  child: Offstage(
                offstage: !_ready,
                child: WebViewWidget(
                    key: ValueKey(_generation), controller: _controller!),
              )),
            // The SDK owns the normal verification UI, mask, close button and errors.
            // Native controls are only a recovery path before the SDK is available.
            if (!_ready || !_supported)
              Positioned.fill(
                  child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: const EdgeInsets.all(AppTokens.s7),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (_supported && _error == null)
                          LoadingView.indicator(),
                        if (_error != null)
                          Text(_error!, textAlign: TextAlign.center),
                        if (!_supported)
                          Text(
                              text('当前平台暂不支持安全验证，请使用 Android 或 iOS 客户端',
                                  'Use the Android or iOS app to complete security verification.'),
                              textAlign: TextAlign.center),
                        if (_error != null)
                          const SizedBox(height: AppTokens.s5),
                        if (_supported && _error != null)
                          TextButton(
                              onPressed: () => setState(_load),
                              child: Text(text('重新加载', 'Reload'))),
                      ]),
                    ),
                  ),
                ),
              )),
            if (_checking)
              const Positioned.fill(
                  child: AbsorbPointer(child: SizedBox.expand())),
          ])),
        ),
      );
}
