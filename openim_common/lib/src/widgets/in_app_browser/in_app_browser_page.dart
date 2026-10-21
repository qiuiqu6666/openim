import 'package:openim_common/localization.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../res/app_tokens.dart';
import '../views.dart';
import 'in_app_browser_share.dart';
import 'in_app_browser_host.dart';
import 'in_app_browser_edge_drag.dart';

class InAppBrowserPage extends StatefulWidget {
  const InAppBrowserPage(
      {super.key,
      required this.uri,
      this.onLocationChanged,
      this.onMetadataChanged,
      this.onEdgeDragStart,
      this.onEdgeDragUpdate,
      this.onEdgeDragEnd,
      this.onEdgeDragCancel});
  final VoidCallback? onEdgeDragStart;
  final ValueChanged<double>? onEdgeDragUpdate;
  final ValueChanged<double>? onEdgeDragEnd;
  final VoidCallback? onEdgeDragCancel;
  final Uri uri;
  final ValueChanged<Uri>? onLocationChanged;
  final void Function(String? title, Uri? icon)? onMetadataChanged;

  @override
  State<InAppBrowserPage> createState() => _InAppBrowserPageState();
}

class _InAppBrowserPageState extends State<InAppBrowserPage> {
  WebViewController? _controller;
  Timer? _timeout;
  late Uri _uri = widget.uri;
  int _generation = 0;
  bool _loading = true;
  bool _atTop = false;
  String? _title;
  int _titleRequest = 0;
  bool _failed = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _goingBack = false;
  final _addressController = TextEditingController();
  final _addressFocus = FocusNode();
  bool _editingAddress = false;
  bool _openingApp = false;

  bool _externalAppLink(Uri? uri) =>
      uri != null &&
      uri.userInfo.isEmpty &&
      uri.host.isNotEmpty &&
      const {'itms-beta', 'testflight', 'itms-apps', 'itms-appss'}
          .contains(uri.scheme);

  Future<void> _openAppLink(Uri uri) async {
    if (_openingApp) return;
    _openingApp = true;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _appLinkFailed();
      }
    } catch (_) {
      _appLinkFailed();
    } finally {
      _openingApp = false;
    }
  }

  void _appLinkFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_text('无法打开外部应用，请确认已安装 TestFlight 或对应应用',
            'Unable to open the app. Check that TestFlight or the required app is installed.'))));
  }

  void _editAddress() {
    _addressController.text = _uri.toString();
    _addressController.selection = TextSelection(
        baseOffset: 0, extentOffset: _addressController.text.length);
    setState(() => _editingAddress = true);
    _addressFocus.requestFocus();
  }

  Future<void> _submitAddress(String value) async {
    final text = value.trim();
    final parsed = Uri.tryParse(text);
    final uri = parsed != null && !parsed.hasScheme
        ? Uri.tryParse('https://$text')
        : parsed;
    if (text.isEmpty || RegExp(r'\s').hasMatch(text) || !_allowed(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_text('请输入有效的 HTTP 或 HTTPS 网址',
              'Enter a valid HTTP or HTTPS address.'))));
      _addressFocus.requestFocus();
      return;
    }
    _addressFocus.unfocus();
    setState(() {
      _editingAddress = false;
      _uri = uri!;
    });
    widget.onLocationChanged?.call(_uri);
    if (!_supported) return;
    if (_failed || _controller == null) {
      await _load();
    } else {
      try {
        await _controller!.loadRequest(uri!);
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      }
    }
  }

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
    _atTop = false;
    _titleRequest++;
    _timeout?.cancel();
    setState(() {
      _failed = false;
      _loading = true;
      _canGoBack = false;
      _canGoForward = false;
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
      await controller.setOnScrollPositionChange((position) {
        if (active()) _atTop = position.y <= 0;
      });
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (!active()) return NavigationDecision.prevent;
          final uri = Uri.tryParse(request.url);
          if (_externalAppLink(uri)) {
            if (request.isMainFrame) unawaited(_openAppLink(uri!));
            return NavigationDecision.prevent;
          }
          if (_allowed(uri)) {
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
          _atTop = false;
          setState(() {
            _title = null;
            _uri = Uri.tryParse(url) ?? _uri;
            _loading = true;
          });
          widget.onLocationChanged?.call(_uri);
          startTimeout();
        },
        onPageFinished: (_) async {
          if (!active() || _failed) return;
          unawaited(_readTitle(controller, generation));
          unawaited(_readScrollPosition(controller, generation));
          _timeout?.cancel();
          try {
            final back = await controller.canGoBack();
            final forward = await controller.canGoForward();
            if (active() && !_failed) {
              setState(() {
                _loading = false;
                _canGoBack = back;
                _canGoForward = forward;
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
          widget.onLocationChanged?.call(_uri);
          unawaited(_readTitle(controller, generation));
          try {
            final back = await controller.canGoBack();
            final forward = await controller.canGoForward();
            if (active()) {
              setState(() {
                _canGoBack = back;
                _canGoForward = forward;
              });
            }
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

  Future<void> _readScrollPosition(
      WebViewController controller, int generation) async {
    try {
      final position = await controller.getScrollPosition();
      if (mounted && generation == _generation) _atTop = position.dy <= 0;
    } catch (_) {
      // Scroll callbacks still work when a platform cannot query its position.
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
      widget.onMetadataChanged?.call(_title, _uri.resolve('/favicon.ico'));
      try {
        final result = await controller.runJavaScriptReturningResult(
            """document.querySelector('link[rel~="icon"]')?.href || ''""");
        var iconUrl = result.toString();
        if (iconUrl.startsWith('"')) {
          iconUrl = jsonDecode(iconUrl) as String;
        }
        if (!mounted ||
            generation != _generation ||
            request != _titleRequest ||
            _failed) {
          return;
        }
        final icon = iconUrl.isEmpty
            ? _uri.resolve('/favicon.ico')
            : _uri.resolve(iconUrl);
        widget.onMetadataChanged?.call(
            _title, _allowed(icon) ? icon : _uri.resolve('/favicon.ico'));
      } catch (_) {
        // The origin favicon remains available when metadata is inaccessible.
      }
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

  Future<void> _forward() async {
    try {
      await _controller?.goForward();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  bool _sharing = false;
  Future<void> _share() async {
    if (_sharing) return;
    final send = InAppBrowserShare.send;
    if (send == null) {
      _actionFailed();
      return;
    }
    setState(() => _sharing = true);
    try {
      final host = InAppBrowserHost.active;
      final count = host == null
          ? await send(_uri, _title)
          : await host.suspendFor(() => send(_uri, _title));
      if (mounted && count > 0) {
        IMViews.showToast(_text('已分享', 'Shared'), centered: true);
      }
    } catch (_) {
      _actionFailed();
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _external() async {
    try {
      if (!await launchUrl(_uri, mode: LaunchMode.externalApplication)) {
        _actionFailed();
      }
    } catch (_) {
      _actionFailed();
    }
  }

  void _actionFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(_text('操作失败，请重试', 'Unable to complete action. Try again.'))));
  }

  @override
  void dispose() {
    _addressController.dispose();
    _addressFocus.dispose();
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
        body: SafeArea(
            top: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(AppTokens.s3),
                child: Row(children: [
                  TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: AppTokens.accent,
                        minimumSize: const Size(AppTokens.minimumTapSize,
                            AppTokens.minimumTapSize)),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(_text('完成', 'Done')),
                  ),
                  Expanded(
                    child: Semantics(
                      button: !_editingAddress,
                      label: _editingAddress
                          ? null
                          : _text('修改网址', 'Edit address'),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _editingAddress ? null : _editAddress,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              minHeight: AppTokens.minimumTapSize),
                          child: Center(
                              child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppTokens.s4,
                                vertical: AppTokens.s2),
                            decoration: BoxDecoration(
                              color: AppTokens.surfaceAlt(dark: dark),
                              borderRadius:
                                  BorderRadius.circular(AppTokens.rSm),
                            ),
                            child: _editingAddress
                                ? TextField(
                                    controller: _addressController,
                                    focusNode: _addressFocus,
                                    keyboardType: TextInputType.url,
                                    textInputAction: TextInputAction.go,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    textDirection: TextDirection.ltr,
                                    style:
                                        Theme.of(context).textTheme.bodyLarge,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                      hintText: _text('输入网址', 'Enter address'),
                                    ),
                                    onSubmitted: _submitAddress,
                                    onTapOutside: (_) {
                                      _addressFocus.unfocus();
                                      setState(() => _editingAddress = false);
                                    },
                                  )
                                : Text(_uri.toString(),
                                    textDirection: TextDirection.ltr,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: AppTokens.textSecondary(
                                              dark: dark),
                                        )),
                          )),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                      tooltip: _text(AppCopy.text('刷新'), 'Refresh'),
                      color: AppTokens.accent,
                      onPressed: _supported && !invalid ? _refresh : null,
                      icon: const Icon(Icons.refresh)),
                ]),
              ),
              if (!recovery && _loading)
                LinearProgressIndicator(
                    color: AppTokens.accent,
                    value: MediaQuery.disableAnimationsOf(context) ? 1 : null,
                    semanticsLabel:
                        _text(AppCopy.text('网页加载中'), 'Loading page')),
              Expanded(
                  child: recovery
                      ? Center(
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(AppTokens.s7),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                        invalid
                                            ? _text(AppCopy.text('链接无效'),
                                                'Invalid link')
                                            : !_supported
                                                ? _text(
                                                    AppCopy.text(
                                                        '当前平台暂不支持内嵌网页'),
                                                    'Embedded web pages are not supported on this platform.')
                                                : _text(
                                                    AppCopy.text(
                                                        '网页加载失败，请检查网络后重试'),
                                                    'Unable to load the page. Check your connection and retry.'),
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge),
                                    if (_supported && !invalid) ...[
                                      const SizedBox(height: AppTokens.s5),
                                      TextButton(
                                          onPressed: _load,
                                          child: Text(_text(
                                              AppCopy.text('重新加载'), 'Retry'))),
                                    ],
                                  ])))
                      : _controller == null
                          ? const SizedBox.expand()
                          : InAppBrowserEdgeDrag(
                              atTop: () => _atTop,
                              onStart: () => widget.onEdgeDragStart?.call(),
                              onUpdate: (delta) =>
                                  widget.onEdgeDragUpdate?.call(delta),
                              onEnd: (velocity) =>
                                  widget.onEdgeDragEnd?.call(velocity),
                              onCancel: () => widget.onEdgeDragCancel?.call(),
                              child: WebViewWidget(
                                  key: ValueKey(_generation),
                                  // Native scrolling retains its gesture arena; the
                                  // edge listener only moves the sheet at the top.
                                  gestureRecognizers: {
                                    Factory<VerticalDragGestureRecognizer>(
                                        VerticalDragGestureRecognizer.new),
                                  },
                                  controller: _controller!))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                        tooltip: _text('返回', 'Back'),
                        color: AppTokens.accent,
                        onPressed: _canGoBack && !recovery ? _back : null,
                        icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                    IconButton(
                        tooltip: _text('前进', 'Forward'),
                        color: AppTokens.accent,
                        onPressed: _canGoForward && !recovery ? _forward : null,
                        icon: const Icon(Icons.arrow_forward_ios_rounded)),
                    Builder(
                        builder: (anchor) => IconButton(
                            tooltip: _text('分享', 'Share'),
                            color: AppTokens.accent,
                            onPressed: invalid || _sharing ? null : _share,
                            icon: const Icon(Icons.ios_share))),
                    IconButton(
                        tooltip: _text('在浏览器中打开', 'Open in browser'),
                        color: AppTokens.accent,
                        onPressed: invalid ? null : _external,
                        icon: const Icon(Icons.explore_outlined)),
                  ],
                ),
              ),
            ])),
      ),
    );
  }
}
