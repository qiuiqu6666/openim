import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:open_filex/open_filex.dart';
import 'package:openim_common/openim_common.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/controller/im_controller.dart';
import '../../routes/app_navigator.dart';
import '../contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'attachments/ai_assistant_attachments.dart';
import 'attachments/ai_assistant_file_cache.dart';
import 'controller/ai_assistant_controller.dart';
import 'controller/ai_assistant_reply.dart';
import 'data/ai_assistant_api.dart';
import 'localization/ai_assistant_composer_hint.dart';
import 'models/ai_assistant_models.dart';
import 'navigation/ai_assistant_header.dart';
import 'picking/ai_assistant_picker.dart';
import 'presentation/ai_assistant_widgets.dart';
import 'presentation/history/ai_assistant_message_list.dart';
import 'search/ai_assistant_search.dart';

/// Layout adapted from 99chat's Apache-2.0 assistant; see README.md.
/// An injected controller remains owned by its caller.
class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key, this.controller});
  final AiAssistantController? controller;
  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage>
    with WidgetsBindingObserver {
  late final AiAssistantController _controller;
  final _input = TextEditingController(), _search = TextEditingController();
  final _inputFocus = FocusNode(), _searchFocus = FocusNode();
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  final _fileCache = <String, Uint8List>{};
  final _fileRequests = <String>{};
  final _fileCancel = CancelToken();
  Worker? _identityWorker;
  AiAssistantReply? _observedReply;
  AiAssistantException? _shownError;
  bool _searching = false, _picking = false, _followsBottom = true;
  bool _scrollScheduled = false, _animateScroll = false;
  int _activeMatch = 0;
  List<int> _matches = [];

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AiAssistantController();
    _controller.addListener(_changed);
    _positions.itemPositions.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    if (Get.isRegistered<IMController>()) {
      _identityWorker = ever(Get.find<IMController>().userInfo, (_) {
        _controller.checkSession();
        if (mounted) setState(() {});
      });
    }
    unawaited(_controller.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.checkSession();
  }

  void _changed() {
    if (!mounted) return;
    if (!identical(_observedReply, _controller.reply)) {
      _observedReply?.visible.removeListener(_onReplyText);
      _observedReply = _controller.reply;
      _observedReply?.visible.addListener(_onReplyText);
    }
    if (!_controller.current) {
      _fileCancel.cancel('session_boundary');
      _fileCache.clear();
      _input.clear();
      _search.clear();
    }
    _rebuildMatches();
    setState(() {});
    final error = _controller.error;
    if (error != null && !identical(error, _shownError)) {
      _shownError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.current) _toast(error.message);
      });
    }
    if (_followsBottom) _scrollToEnd();
  }

  void _onReplyText() {
    if (_searching && mounted && _controller.current) {
      final previous = _matches;
      _rebuildMatches();
      if (!listEquals(previous, _matches)) setState(() {});
    }
    if (_followsBottom && mounted && _controller.current) _scrollToEnd();
  }

  void _onScroll() {
    final positions = _positions.itemPositions.value;
    if (!_searching) {
      _followsBottom = positions.any((p) =>
          p.index == 0 && p.itemTrailingEdge > 0 && p.itemTrailingEdge <= 1.05);
    }
    if (_controller.hasMore &&
        positions.any((p) =>
            p.index == _controller.messages.length - 1 &&
            p.itemLeadingEdge < 1)) {
      unawaited(_controller.loadHistory(older: true));
    }
  }

  void _scrollToEnd({bool force = false}) {
    if (!force && !_followsBottom) return;
    _animateScroll |= force;
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      final animate = _animateScroll;
      _animateScroll = false;
      if (!mounted ||
          !_controller.current ||
          !_scroll.isAttached ||
          _controller.messages.isEmpty ||
          !(ModalRoute.of(context)?.isCurrent ?? true) ||
          (!animate && !_followsBottom)) {
        return;
      }
      // Stream updates share one frame and never restart a scroll animation.
      if (!animate || MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(index: 0);
      } else {
        unawaited(_scroll.scrollTo(
            index: 0,
            duration: AiMetrics.scrollAnimationDuration,
            curve: Curves.easeOut));
      }
    });
  }

  void _focusInput() {
    _inputFocus.requestFocus();
    _followsBottom = true;
    _scrollToEnd(force: true);
  }

  List<AiAssistantMessage> get _searchMessages {
    final list = List<AiAssistantMessage>.of(_controller.messages);
    if (_controller.replying && list.isNotEmpty) {
      list[list.length - 1] = _controller.reply!.visible.value;
    }
    return list;
  }

  void _rebuildMatches() {
    _matches = _searching
        ? AiAssistantSearch.matchIndexes(_searchMessages, _search.text)
        : [];
    _activeMatch =
        _matches.isEmpty ? 0 : _activeMatch.clamp(0, _matches.length - 1);
  }

  void _toggleSearch(bool value) {
    _searchFocus.unfocus();
    setState(() {
      _searching = value;
      _search.clear();
      _activeMatch = 0;
      _matches = [];
    });
    if (value) _searchFocus.requestFocus();
  }

  void _queryChanged() {
    setState(_rebuildMatches);
    _jumpToMatch();
  }

  void _stepMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _activeMatch = (_activeMatch + delta) % _matches.length);
    _jumpToMatch();
  }

  void _jumpToMatch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.isAttached || _matches.isEmpty) return;
      _scroll.jumpTo(
          index: _controller.messages.length - 1 - _matches[_activeMatch],
          alignment: .35);
    });
  }

  Future<void> _selectTool(String id) async {
    if (id == 'summarize' && _controller.selectedTool != id) {
      final card =
          await pickAiCard(context, kind: AiCardPickerKind.conversation);
      if (!mounted || !_controller.current || card == null) return;
      _controller.selectTool(id);
      if (!_controller.addCard(card)) {
        _toast(
            _text('已添加或附件数量超过限制', 'Already added or attachment limit reached'));
      }
    } else {
      _controller.selectTool(id);
    }
    if (mounted) _focusInput();
  }

  Future<void> _more() async {
    final action = await AiMoreSheet.show(context);
    if (!mounted || !_controller.current || action == null) return;
    final card = await pickAiCard(context,
        kind: action == 'friend'
            ? AiCardPickerKind.friend
            : AiCardPickerKind.group);
    if (!mounted || !_controller.current || card == null) return;
    if (!_controller.addCard(card)) {
      _toast(
          _text('已添加或附件数量超过限制', 'Already added or attachment limit reached'));
    }
    _focusInput();
  }

  Future<void> _pickFiles(bool images) async {
    if (_picking || !_controller.current) return;
    _picking = true;
    _inputFocus.unfocus();
    try {
      final files = await (images
          ? AiAssistantAttachments.images()
          : AiAssistantAttachments.files());
      if (!mounted || !_controller.current || files.isEmpty) return;
      if (!_controller.addFiles(files)) {
        _toast(_text('一次最多添加8个内容', 'You can add at most 8 items'));
      }
      _focusInput();
    } on AiAssistantException catch (error) {
      if (mounted && _controller.current) _toast(error.message);
    } catch (_) {
      if (mounted && _controller.current) {
        _toast(_text(
            '无法打开选择器，请检查权限', 'Unable to open picker. Check permissions.'));
      }
    } finally {
      _picking = false;
    }
  }

  Future<void> _overflow() async {
    final action = await AiMoreSheet.overflow(context);
    if (!mounted || !_controller.current || action != 'clear') return;
    _controller.stopReply();
    await _controller.clearHistory();
  }

  Future<void> _copy(AiAssistantMessage message) async {
    final text = AiAssistantSearch.copyText(message);
    if (text.isEmpty) return;
    if (await AiMoreSheet.copy(context) != 'copy' ||
        !mounted ||
        !_controller.current) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast(_text('已复制', 'Copied'));
  }

  Future<void> _send() async {
    if (await _controller.send(_input.text,
        languageCode: Localizations.localeOf(context).languageCode)) {
      if (!mounted) return;
      _input.clear();
      _followsBottom = true;
      _scrollToEnd(force: true);
    }
  }

  void _cardTap(AiAssistantCardRef card) {
    if (!_controller.current) return;
    if (card.kind == AiAssistantCardKind.group) {
      AppNavigator.startGroupProfilePanel(
          groupID: card.id, joinGroupMethod: JoinGroupMethod.search);
    } else {
      AppNavigator.startUserProfilePane(userID: card.id);
    }
  }

  Future<void> _fileTap(AiAssistantFileRef file) async {
    if (!_controller.current) return;
    final path = file.localPath;
    if (path != null && path.isNotEmpty) {
      await OpenFilex.open(path);
      return;
    }
    _toast(_text('原文件暂不可用', 'Original file is unavailable'));
  }

  Future<void> _needFile(String id) async {
    if (!_controller.serviceEnabled ||
        !_controller.current ||
        _fileCache.containsKey(id) ||
        !_fileRequests.add(id)) {
      return;
    }
    try {
      final bytes =
          await _controller.api.downloadFile(id, cancelToken: _fileCancel);
      if (!mounted || !_controller.current) return;
      if (cacheAiAssistantFile(_fileCache, id, bytes)) {
        setState(() {});
      }
    } catch (_) {
    } finally {
      _fileRequests.remove(id);
    }
  }

  String _text(String zh, String en) =>
      AiAssistantI18n.of(context).t(zhHans: zh, en: en);
  void _toast(String text) {
    if (text.isEmpty || !mounted) return;
    unawaited(IMViews.showToast(text));
  }

  String get _hint => aiAssistantComposerHint(
      AiAssistantI18n.of(context), _controller.selectedTool);

  Widget _assistant(AiAssistantMessage message, bool dark, String query) {
    Widget bubble(AiAssistantMessage value) => AiAssistantBubble(
        dark: dark,
        i18n: AiAssistantI18n.of(context),
        message: value,
        query: query,
        fileCache: _fileCache,
        onNeedFile: (id) => unawaited(_needFile(id)),
        imageBytes: _fileCache[AiAssistantApi.fileIdFromUrl(value.imageUrl)],
        onComingSoon: (_) =>
            _toast(_text('AI 服务尚未接入', 'AI service is not connected yet')),
        onLongPress: () => unawaited(_copy(value)));
    final reply = _controller.reply;
    if (reply != null &&
        _controller.replying &&
        identical(message, _controller.messages.last)) {
      return ValueListenableBuilder<AiAssistantMessage>(
          valueListenable: reply.visible,
          builder: (_, value, __) => bubble(value));
    }
    return bubble(message);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final i18n = AiAssistantI18n.of(context);
    final media = MediaQuery.of(context);
    final toolbar = math.max(
        kToolbarHeight,
        media.textScaler.scale(AiMetrics.font17) * 1.2 +
            media.textScaler.scale(AiMetrics.font11) * 1.2 +
            AiMetrics.space12);
    final user = Get.isRegistered<IMController>()
        ? Get.find<IMController>().userInfo.value
        : null;
    final query = _searching ? _search.text : '';
    return AppSystemBars(
        background: AiPalette.headerBg(dark),
        navigationBackground: AiPalette.canvasBg(dark),
        child: PopScope(
          canPop: !_searching,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _searching) _toggleSearch(false);
          },
          child: Scaffold(
              backgroundColor: AiPalette.transparent,
              resizeToAvoidBottomInset: false,
              appBar: AiAssistantHeader(
                  dark: dark,
                  searching: _searching,
                  toolbarHeight: toolbar,
                  searchController: _search,
                  searchFocus: _searchFocus,
                  onQuery: _queryChanged,
                  matches: _matches.length,
                  activeMatch: _activeMatch,
                  onStep: _stepMatch,
                  onSearch: () => _toggleSearch(true),
                  onOverflow: () => unawaited(_overflow()),
                  onBack: () {
                    if (_searching) {
                      _toggleSearch(false);
                    } else {
                      Navigator.of(context).maybePop();
                    }
                  }),
              body: Stack(children: [
                Positioned.fill(
                    child: IgnorePointer(child: AiCanvasBackdrop(dark: dark))),
                SafeArea(
                    top: false,
                    bottom: false,
                    child: Column(children: [
                      Expanded(
                          child: AiAssistantMessageList(
                              dark: dark,
                              messages: _controller.messages,
                              historyLoaded: _controller.historyLoaded,
                              welcomeVisible: _controller.welcomeVisible,
                              scrollController: _scroll,
                              positions: _positions,
                              onStart: _focusInput,
                              onDismissWelcome: () =>
                                  unawaited(_controller.dismissWelcome()),
                              messageBuilder: (message) => message.role ==
                                      AiAssistantRole.user
                                  ? AiUserBubble(
                                      dark: dark,
                                      message: message,
                                      query: query,
                                      fileCache: _fileCache,
                                      faceUrl: user?.faceURL ?? '',
                                      showName:
                                          user?.nickname ?? user?.userID ?? '',
                                      ownerId: user?.userID ?? '',
                                      onCardTap: _cardTap,
                                      onFileTap: (file) =>
                                          unawaited(_fileTap(file)),
                                      onLongPress: () =>
                                          unawaited(_copy(message)))
                                  : _assistant(message, dark, query))),
                      AiQuickChipBar(
                          dark: dark,
                          i18n: i18n,
                          selectedId: _controller.selectedTool,
                          onSelected: (id) => unawaited(_selectTool(id))),
                      if (_controller.drafts.isNotEmpty)
                        AiDraftBar(
                            dark: dark,
                            i18n: i18n,
                            drafts: _controller.drafts,
                            onRemove: _controller.removeDraft),
                      Padding(
                          padding: EdgeInsets.fromLTRB(
                              AiMetrics.space12,
                              AiMetrics.space8,
                              AiMetrics.space12,
                              math.max(
                                      AiMetrics.space10, media.padding.bottom) +
                                  media.viewInsets.bottom),
                          child: AiInputBar(
                              dark: dark,
                              hint: _hint,
                              controller: _input,
                              focusNode: _inputFocus,
                              onAdd: () => unawaited(_more()),
                              onImage: () => unawaited(_pickFiles(true)),
                              onAttach: () => unawaited(_pickFiles(false)),
                              onSubmit: () => unawaited(_send()),
                              onStop: _controller.stopReply,
                              replying: _controller.replying)),
                    ])),
                if (_controller.guideVisible)
                  Positioned.fill(
                      child: AiFirstGuide(
                          onFinished: () =>
                              unawaited(_controller.dismissGuide()))),
              ])),
        ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _identityWorker?.dispose();
    _observedReply?.visible.removeListener(_onReplyText);
    _controller.removeListener(_changed);
    _positions.itemPositions.removeListener(_onScroll);
    _fileCancel.cancel('dispose');
    if (widget.controller == null) _controller.dispose();
    _input.dispose();
    _search.dispose();
    _inputFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }
}
