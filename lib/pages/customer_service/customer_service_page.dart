import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:url_launcher/url_launcher.dart';

import '../mine/settings/widgets/settings_widgets.dart';
import 'content/customer_service_content.dart';
import 'customer_service_controller.dart';
import 'customer_service_tokens.dart';
import 'media/customer_service_media_picker.dart';
import 'media/customer_service_media_preview.dart';
import 'widgets/customer_service_categories.dart';
import 'widgets/customer_service_composer.dart';
import 'widgets/customer_service_faq_panel.dart';
import 'widgets/customer_service_message_view.dart';

/// Native FAQ and visitor chat inside the fixed-height customer-service sheet.
/// This page owns even an injected controller; transports never outlive it.
class CustomerServicePage extends StatefulWidget {
  const CustomerServicePage({super.key, this.controller, this.guest = false});
  final CustomerServiceController? controller;
  final bool guest;

  @override
  State<CustomerServicePage> createState() => _CustomerServicePageState();
}

class _CustomerServicePageState extends State<CustomerServicePage>
    with WidgetsBindingObserver {
  late final CustomerServiceController _controller;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = CustomerServiceMediaPicker();
  bool _picking = false, _routeActive = true, _foreground = true;
  bool _historyReady = false, _canvasInteracted = false, _userScrolling = false;
  int _entryCount = 0, _latestRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller ??
        CustomerServiceController.forCurrentAccount(guest: widget.guest);
    _controller.addListener(_onChange);
    unawaited(_controller.initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = ModalRoute.isCurrentOf(context) ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncActivity();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncActivity();
  }

  @override
  void didChangeMetrics() {
    if (!_userScrolling && _isNearLatest) _scrollToLatest();
  }

  bool get _isNearLatest =>
      !_scroll.hasClients ||
      !_scroll.position.hasContentDimensions ||
      _scroll.position.extentAfter < 80;

  void _syncActivity() {
    if (_routeActive && _foreground) {
      _controller.resume();
    } else {
      _controller.suspend();
    }
  }

  void _onChange() {
    if (!mounted) return;
    final count = _controller.entries.length;
    final restoredHistory = !_historyReady && _controller.historyReady;
    final shouldScroll = (restoredHistory && count > 0 && !_canvasInteracted) ||
        (count != _entryCount &&
            !_userScrolling &&
            _isNearLatest &&
            (_historyReady || !_canvasInteracted));
    _historyReady = _controller.historyReady;
    _entryCount = count;
    if (shouldScroll) _scrollToLatest();
  }

  void _scrollToLatest() {
    final request = ++_latestRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canFollowLatest(request)) unawaited(_followLatest(request));
    });
  }

  bool _canFollowLatest(int request) =>
      mounted &&
      _scroll.hasClients &&
      request == _latestRequest &&
      !_userScrolling;

  void _cancelFollowingLatest() {
    _latestRequest++;
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.pixels);
  }

  Future<void> _followLatest(int request) async {
    final latest = _scroll.position.maxScrollExtent;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(latest);
    } else {
      await _scroll.animateTo(latest,
          duration: CustomerServiceTokens.sheetDuration,
          curve: Curves.easeOutCubic);
    }
    if (!_canFollowLatest(request)) return;
    WidgetsBinding.instance.ensureVisualUpdate();
    await WidgetsBinding.instance.endOfFrame;
    // Lazy message heights can update the estimated tail during scrolling.
    // Reconcile after layout while this request still owns following latest.
    while (_canFollowLatest(request) && _scroll.position.extentAfter > 1) {
      final before = _scroll.position.pixels;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      WidgetsBinding.instance.ensureVisualUpdate();
      await WidgetsBinding.instance.endOfFrame;
      if (_canFollowLatest(request) && _scroll.position.pixels == before) {
        break;
      }
    }
  }

  void _send() {
    if (!_controller.canSend || _input.text.trim().isEmpty) return;
    final text = _input.text;
    _input.clear();
    unawaited(_controller.sendText(text));
    _scrollToLatest();
  }

  Future<void> _attach() async {
    if (_picking || !_controller.canSend) return;
    _picking = true;
    FocusScope.of(context).unfocus();
    try {
      final type = await showSettingsActionSheet<String>(context,
          title: customerServiceText(context, zh: '添加附件', en: 'Add attachment'),
          actions: [
            SettingsAction(
                customerServiceText(context, zh: '图片', en: 'Photos'), 'image'),
            SettingsAction(
                customerServiceText(context, zh: '视频', en: 'Videos'), 'video'),
          ]);
      if (!mounted || !_controller.canSend || type == null) return;
      final uploads = await _picker.pick(context,
          video: type == 'video',
          isActive: () => mounted && _controller.canSend);
      for (final upload in uploads) {
        if (!mounted || !_controller.canSend) break;
        final sending = _controller.sendUpload(upload);
        _scrollToLatest();
        await sending;
      }
    } catch (_) {
      if (mounted) {
        IMViews.showToast(customerServiceText(context,
            zh: '无法读取或发送附件，请检查权限后重试',
            en: 'Unable to send the attachment. Check access and retry.'));
      }
    } finally {
      _picking = false;
    }
  }

  Future<void> _openOfficialURL() async {
    final raw = _controller.officialURL.trim();
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null ||
        uri.host.isEmpty ||
        !const ['http', 'https'].contains(uri.scheme)) {
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Unable to open the website');
      }
    } catch (_) {
      if (mounted) {
        IMViews.showToast(customerServiceText(context,
            zh: '无法打开官方网站', en: 'Unable to open the official website'));
      }
    }
  }

  @override
  void dispose() {
    _latestRequest++;
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChange);
    _controller.dispose();
    _input.dispose();
    _scroll.dispose();
    unawaited(_picker.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => ColoredBox(
          color: CustomerServiceTokens.background(context),
          child: LayoutBuilder(builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context)
                .scale(CustomerServiceTokens.faqFontSize);
            final inputHeight = math.min(
                constraints.maxHeight,
                math.max(
                    CustomerServiceTokens.inputMinHeight, scale * 1.5 + 40));
            final remainder =
                math.max(0.0, constraints.maxHeight - inputHeight);
            final headerHeight = math.min(
                CustomerServiceCategories.preferredHeight(
                    context, constraints.maxWidth),
                remainder * .6);
            return Column(children: [
              SizedBox(
                key: const ValueKey('customer-service-header'),
                height: headerHeight,
                child: SingleChildScrollView(
                  child: CustomerServiceCategories(
                    selectedId: _controller.selectedCategoryId,
                    onSelected: (id) {
                      _canvasInteracted = true;
                      _cancelFollowingLatest();
                      _controller.selectCategory(id);
                      if (_scroll.hasClients) _scroll.jumpTo(0);
                    },
                  ),
                ),
              ),
              Expanded(child: _body(context)),
              SizedBox(
                height: inputHeight,
                child: SingleChildScrollView(
                  child: CustomerServiceComposer(
                    controller: _input,
                    enabled: _controller.canSend,
                    onSend: _send,
                    onAttach: _attach,
                  ),
                ),
              ),
            ]);
          }),
        ),
      );

  Widget _body(BuildContext context) {
    final entries = _controller.entries;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _canvasInteracted = _userScrolling = true;
          _latestRequest++;
        } else if (notification is ScrollEndNotification) {
          _userScrolling = false;
        }
        return false;
      },
      child: CustomScrollView(
        key: const ValueKey('customer-service-messages'),
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: CustomerServiceFaqPanel(
              category: customerServiceCategories.firstWhere(
                  (category) => category.id == _controller.selectedCategoryId,
                  orElse: () => customerServiceCategories.first),
              questionId: _controller.questionId,
              onQuestion: (id) {
                _canvasInteracted = true;
                _cancelFollowingLatest();
                _controller.selectQuestion(id);
              },
              onBack: () {
                _canvasInteracted = true;
                _cancelFollowingLatest();
                _controller.selectQuestion(null);
              },
              officialURL: _controller.officialURL,
              onOpenOfficialURL: _openOfficialURL,
            ),
          ),
          if (_controller.error != null)
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
              child: Row(children: [
                Expanded(
                    child: Text(
                        customerServiceText(context,
                            zh: '客服连接暂时不可用，请重试',
                            en:
                                'Unable to connect to customer service. Retry.'),
                        style: TextStyle(
                            color: CustomerServiceTokens.text(context),
                            fontSize: CustomerServiceTokens.chipFontSize))),
                TextButton(
                    onPressed:
                        _controller.loading ? null : _controller.initialize,
                    child: Text(
                        customerServiceText(context, zh: '重试', en: 'Retry'))),
              ]),
            )),
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.s3),
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (_, index) {
                final entry = entries[index];
                return CustomerServiceMessageView(
                  key: ValueKey(entry.key),
                  entry: entry,
                  onRetry: () => _controller.retry(entry),
                  onOpenMedia: (
                      {required url,
                      required path,
                      required thumbnail,
                      required video,
                      required name,
                      required file}) async {
                    FocusScope.of(context).unfocus();
                    try {
                      await openCustomerServiceMedia(context,
                          url: url,
                          path: path,
                          thumbnail: thumbnail,
                          video: video,
                          name: name,
                          file: file);
                    } catch (_) {
                      if (context.mounted && mounted) {
                        IMViews.showToast(customerServiceText(context,
                            zh: '无法打开附件，请重试',
                            en: 'Unable to open the attachment. Retry.'));
                      }
                    }
                  },
                );
              },
            ),
          ),
          if (_controller.loading)
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.all(AppTokens.s3),
              child: Text(
                  customerServiceText(context,
                      zh: '正在连接客服…', en: 'Connecting to customer service…'),
                  style: TextStyle(
                      color: CustomerServiceTokens.secondaryText(context),
                      fontSize: CustomerServiceTokens.chipFontSize)),
            )),
          if (_controller.agentTyping)
            SliverToBoxAdapter(
                child: Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.all(AppTokens.s2),
                      child: Text(
                          customerServiceText(context,
                              zh: '客服正在输入…', en: 'The agent is typing…'),
                          style: TextStyle(
                              color: CustomerServiceTokens.secondaryText(
                                  context))),
                    ))),
        ],
      ),
    );
  }
}
