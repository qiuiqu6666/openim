import 'package:openim_common/localization.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../res/app_tokens.dart';

class InAppBrowserPage extends StatefulWidget {
  const InAppBrowserPage({super.key, required this.uri});
  final Uri uri;

  @override
  State<InAppBrowserPage> createState() => _InAppBrowserPageState();
}

class _InAppBrowserPageState extends State<InAppBrowserPage> {
  WebViewController? _controller;
  Timer? _timeout;
  late Uri _uri = widget.uri;
  int _generation = 0;
  bool _loading = true;
  String? _title;
  int _titleRequest = 0;
  bool _failed = false;
  bool _canGoBack = false;
  bool _goingBack = false;
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool _allowed(Uri? uri) =>
      uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    if (_supported && _allowed(_uri)) unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _titleRequest++;
    _timeout?.cancel();
    setState(() {
      _failed = false;
      _loading = true;
      _canGoBack = false;
      _title = null;
    });
    bool active() => mounted && generation == _generation;
    void fail() {
      if (!active()) return;
      _timeout?.cancel();
      setState(() => _failed = true);
    }

    void startTimeout() {
      _timeout?.cancel();
      _timeout = Timer(const Duration(seconds: 30), fail);
    }

    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (_allowed(Uri.tryParse(request.url))) {
            return NavigationDecision.navigate;
          }
          if (active() && request.isMainFrame) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_text(AppCopy.text('此链接不支持在应用内打开'),
                  'This link cannot be opened inside the app.')),
            ));
          }
          return NavigationDecision.prevent;
        },
        onPageStarted: (url) {
          if (!active() || _failed) return;
          _titleRequest++;
          setState(() {
            _title = null;
            _uri = Uri.tryParse(url) ?? _uri;
            _loading = true;
          });
          startTimeout();
        },
        onPageFinished: (_) async {
          if (!active() || _failed) return;
          unawaited(_readTitle(controller, generation));
          _timeout?.cancel();
          try {
            final back = await controller.canGoBack();
            if (active() && !_failed) {
              setState(() {
                _loading = false;
                _canGoBack = back;
              });
            }
          } catch (_) {
            fail();
          }
        },
        onUrlChange: (change) async {
          final uri = Uri.tryParse(change.url ?? '');
          if (!active() || !_allowed(uri)) return;
          setState(() => _uri = uri!);
          unawaited(_readTitle(controller, generation));
          try {
            final back = await controller.canGoBack();
            if (active()) setState(() => _canGoBack = back);
          } catch (_) {/* A closing platform view may no longer respond. */}
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) fail();
        },
        onHttpError: (error) {
          if (error.request?.uri == _uri) fail();
        },
      ));
      if (!active()) return;
      setState(() => _controller = controller);
      startTimeout();
      await controller.loadRequest(_uri);
    } catch (_) {
      fail();
    }
  }

  Future<void> _readTitle(WebViewController controller, int generation) async {
    final request = ++_titleRequest;
    try {
      final title = (await controller.getTitle())?.trim();
      if (!mounted ||
          generation != _generation ||
          request != _titleRequest ||
          _failed) {
        return;
      }
      // Some sites return their address as the document title.
      final isAddress = title == _uri.toString() ||
          title == _uri.host ||
          title?.startsWith('https://') == true ||
          title?.startsWith('http://') == true;
      setState(() => _title =
          title != null && title.isNotEmpty && !isAddress ? title : null);
    } catch (_) {
      // Missing metadata must not turn an otherwise readable page into an error.
    }
  }

  Future<void> _back() async {
    if (_goingBack) return;
    _goingBack = true;
    try {
      if (_controller != null && !_failed && await _controller!.canGoBack()) {
        await _controller!.goBack();
      } else if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    } finally {
      _goingBack = false;
    }
  }

  Future<void> _refresh() async {
    if (_failed || _controller == null) return _load();
    try {
      await _controller!.reload();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final invalid = !_allowed(_uri);
    final recovery = _failed || !_supported || invalid;
    return PopScope(
      canPop: !_canGoBack || recovery,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        backgroundColor: AppTokens.surface(dark: dark),
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: AppTokens.surface(dark: dark),
          foregroundColor: AppTokens.textPrimary(dark: dark),
          leading: IconButton(
              tooltip: _text('返回', 'Back'),
              color: AppTokens.accent,
              onPressed: _back,
              icon: const Icon(Icons.arrow_back_ios_new_rounded)),
          title: Text(_title ?? _text(AppCopy.text('网页'), 'Web page'),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
                tooltip: _text(AppCopy.text('刷新'), 'Refresh'),
                color: AppTokens.accent,
                onPressed: _supported && !invalid ? _refresh : null,
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: SafeArea(
            child: Column(children: [
          if (!recovery && _loading)
            LinearProgressIndicator(
                color: AppTokens.accent,
                value: MediaQuery.disableAnimationsOf(context) ? 1 : null,
                semanticsLabel: _text(AppCopy.text('网页加载中'), 'Loading page')),
          Expanded(
              child: recovery
                  ? Center(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(AppTokens.s7),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(
                                invalid
                                    ? _text(
                                        AppCopy.text('链接无效'), 'Invalid link')
                                    : !_supported
                                        ? _text(AppCopy.text('当前平台暂不支持内嵌网页'),
                                            'Embedded web pages are not supported on this platform.')
                                        : _text(AppCopy.text('网页加载失败，请检查网络后重试'),
                                            'Unable to load the page. Check your connection and retry.'),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge),
                            if (_supported && !invalid) ...[
                              const SizedBox(height: AppTokens.s5),
                              TextButton(
                                  onPressed: _load,
                                  child: Text(
                                      _text(AppCopy.text('重新加载'), 'Retry'))),
                            ],
                          ])))
                  : _controller == null
                      ? const SizedBox.expand()
                      : WebViewWidget(
                          key: ValueKey(_generation),
                          controller: _controller!)),
        ])),
      ),
    );
  }
}
