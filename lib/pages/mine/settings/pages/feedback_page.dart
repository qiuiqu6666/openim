import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openim_common/openim_common.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../settings_service.dart';
import '../widgets/settings_widgets.dart';
import '../../../customer_service/customer_service.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({
    super.key,
    required this.service,
    this.embedded = false,
  });

  final SettingsService service;
  final bool embedded;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  static const _maxContentLength = 2000;
  static const _maxScreenshots = 5;
  static const _blue = Color(0xFF218CFF);

  final _controller = TextEditingController();
  final List<SettingsFeedbackAttachment> _attachments = [];
  String _type = 'suggestion';
  bool _submitting = false;
  bool _picking = false;
  bool _submitted = false;
  bool _includeDiagnostics = false;
  String? _clientRequestID;
  int? _submittedFingerprint;
  String? _feedbackID;
  bool _logFailed = false;
  bool _uploadingLogs = false;
  Future<void> _uploadLogs() async {
    if (_uploadingLogs || _feedbackID == null || _clientRequestID == null) {
      return;
    }
    setState(() => _uploadingLogs = true);
    try {
      await widget.service.uploadFeedbackLogs(_feedbackID!, _clientRequestID!);
      if (mounted) setState(() => _logFailed = false);
    } catch (_) {
      if (mounted) {
        setState(() => _logFailed = true);
        showSettingsMessage(
            context,
            settingsText(context,
                zh: '反馈已提交，日志上传失败，可重试',
                en: 'Feedback submitted. Log upload failed. You can retry.'));
      }
    } finally {
      if (mounted) setState(() => _uploadingLogs = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onContentChanged)
      ..dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      !_picking &&
      _controller.text.trim().isNotEmpty &&
      _controller.text.trim().runes.length <= _maxContentLength;

  Future<void> _pickImages() async {
    if (_picking || _attachments.length >= _maxScreenshots) return;
    setState(() => _picking = true);
    try {
      final remain = _maxScreenshots - _attachments.length;
      final assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: remain,
          requestType: RequestType.image,
          sortPathsByModifiedDate: true,
          filterOptions: PMFilter.defaultValue(containsPathModified: true),
        ),
      );
      if (!mounted || assets == null || assets.isEmpty) return;

      final next = <SettingsFeedbackAttachment>[];
      for (final asset in assets.take(remain)) {
        final bytes = await asset.thumbnailDataWithSize(
          const ThumbnailSize(1800, 1800),
          quality: 94,
        );
        if (bytes == null || bytes.isEmpty) continue;
        if (bytes.lengthInBytes > 10 * 1024 * 1024) {
          if (mounted) {
            showSettingsMessage(
              context,
              settingsText(
                context,
                zh: '单张截图不能超过 10MB',
                en: 'Each screenshot must be smaller than 10 MB.',
              ),
            );
          }
          continue;
        }
        next.add(
          SettingsFeedbackAttachment(
            filename: '${asset.id}.jpg',
            bytes: bytes,
          ),
        );
      }
      if (!mounted || next.isEmpty) return;
      setState(() {
        final available = _maxScreenshots - _attachments.length;
        _attachments.addAll(next.take(available));
      });
    } catch (_) {
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(
          context,
          zh: '无法读取图片，请检查相册权限后重试',
          en: 'Unable to read photos. Check photo permissions and try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusManager.instance.primaryFocus?.unfocus();

    if (!widget.service.supportsFeedback) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '提交反馈', en: 'Submit feedback'),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final fingerprint = Object.hash(_type, _controller.text.trim(),
          _includeDiagnostics, Object.hashAll(_attachments));
      if (_clientRequestID == null || fingerprint != _submittedFingerprint) {
        _clientRequestID = const Uuid().v4();
        _submittedFingerprint = fingerprint;
      }
      _feedbackID = await widget.service.createFeedback(
        clientRequestID: _clientRequestID!,
        type: _type,
        content: _controller.text.trim(),
        attachments: List.unmodifiable(_attachments),
        includeSDKLogs: _includeDiagnostics,
      );
      if (!mounted) return;
      if (_includeDiagnostics) await _uploadLogs();
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _submitted = true);
    } catch (error) {
      if (error is (int, String) && error.$1 == 20046) _clientRequestID = null;
      if (!mounted) return;
      showSettingsError(
          context,
          error,
          settingsText(context,
              zh: '提交失败，请稍后重试', en: 'Submission failed. Please retry.'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedSwitcher(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.03, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: _submitted
          ? _FeedbackSuccessView(
              key: const ValueKey('feedback-success'),
              onDone: () => Navigator.of(context).maybePop(),
              logFailed: _logFailed,
              uploadingLogs: _uploadingLogs,
              retryLogs: _uploadLogs,
            )
          : _buildForm(context),
    );
  }

  Widget _buildForm(BuildContext context) {
    final dark = settingsIsDark(context);
    final text = AppTokens.textPrimary(dark: dark);
    final muted = dark ? const Color(0xFFADB8CB) : const Color(0xFF748198);
    final fill = dark ? const Color(0xFF242D3C) : const Color(0xFFF4F6F9);
    final card = dark ? const Color(0xFF192331) : Colors.white;
    final background = dark ? const Color(0xFF101A28) : const Color(0xFFF3F9FF);
    final appBarBackground =
        dark ? const Color(0xFF101A28) : const Color(0xFFF5FAFF);

    return Scaffold(
      key: const ValueKey('feedback-form'),
      backgroundColor: background,
      appBar: widget.embedded
          ? null
          : GlassAppBar(
              toolbarHeight: kToolbarHeight,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: true,
              backgroundColor: appBarBackground,
              surfaceTintColor: Colors.transparent,
              leading: Navigator.of(context).canPop()
                  ? IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: _blue,
                        size: 22,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
              title: Text(
                settingsText(context, zh: '意见反馈', en: 'Feedback'),
                style: TextStyle(
                  color: text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                IconButton(
                  key: const ValueKey('feedback-customer-service'),
                  tooltip: settingsText(
                    context,
                    zh: '在线客服',
                    en: 'Customer service',
                  ),
                  onPressed: () => showCustomerServiceSheet(context),
                  icon: SvgPicture.string(
                    _customerServiceIconSvg,
                    width: 26,
                    height: 26,
                    fit: BoxFit.contain,
                    colorFilter: const ColorFilter.mode(
                      _blue,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF122B45), Color(0xFF101A28)]
                : const [
                    Color(0xFFF5FAFF),
                    Color(0xFFF7FBFF),
                    Color(0xFFEDF6FF),
                  ],
          ),
        ),
        child: SafeArea(
          top: widget.embedded,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(context, dark: dark, text: text, muted: muted),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionHeading(
                            context,
                            title: settingsText(
                              context,
                              zh: '反馈类型',
                              en: 'Feedback type',
                            ),
                            trailing: settingsText(
                              context,
                              zh: '请选择问题的类型',
                              en: 'Choose a category',
                            ),
                            text: text,
                            muted: muted,
                          ),
                          _buildTypeGrid(
                            context,
                            fill: fill,
                            text: text,
                            muted: muted,
                            dark: dark,
                          ),
                          const SizedBox(height: 26),
                          _sectionHeading(
                            context,
                            title: settingsText(
                              context,
                              zh: '反馈内容',
                              en: 'Your feedback',
                            ),
                            trailing:
                                '${_controller.text.characters.length}/$_maxContentLength',
                            text: text,
                            muted: muted,
                          ),
                          TextField(
                            controller: _controller,
                            enabled: !_submitting,
                            minLines: 5,
                            maxLines: 10,
                            maxLength: _maxContentLength,
                            cursorColor: _blue,
                            style: TextStyle(
                              color: text,
                              fontSize: 15,
                              height: 1.6,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: fill,
                              counterText: '',
                              hintText: settingsText(
                                context,
                                zh: '请详细描述您的问题或建议（必填）',
                                en: 'Describe your issue or suggestion (required)',
                              ),
                              hintStyle: TextStyle(
                                color: muted,
                                fontSize: 15,
                                height: 1.6,
                              ),
                              contentPadding: const EdgeInsets.all(16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide:
                                    const BorderSide(color: _blue, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          _sectionHeading(
                            context,
                            title: settingsText(
                              context,
                              zh: '相关截图（选填）',
                              en: 'Screenshots (optional)',
                            ),
                            trailing: '${_attachments.length}/$_maxScreenshots',
                            text: text,
                            muted: muted,
                          ),
                          _buildScreenshots(
                            context,
                            fill: fill,
                            muted: muted,
                            dark: dark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: Colors.transparent,
                      child: CheckboxListTile(
                        key: const ValueKey('feedback-diagnostics'),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        activeColor: _blue,
                        value: _includeDiagnostics,
                        onChanged: _submitting
                            ? null
                            : (value) => setState(
                                  () => _includeDiagnostics = value ?? false,
                                ),
                        title: Text(
                          settingsText(
                            context,
                            zh: '附带 SDK 运行日志',
                            en: 'Attach diagnostic report',
                          ),
                          style: TextStyle(
                            color: text,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          settingsText(
                            context,
                            zh: '附带 SDK 运行日志，帮助排查问题。日志可能包含设备和运行信息。',
                            en: 'Attach SDK runtime logs to help investigate. Logs may contain device and runtime information.',
                          ),
                          style: TextStyle(
                            color: muted,
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: _canSubmit
                            ? const LinearGradient(
                                colors: [Color(0xFF40B2FF), _blue],
                              )
                            : null,
                        color: _canSubmit
                            ? null
                            : (dark
                                ? const Color(0xFF2A3A4F)
                                : const Color(0xFFDDE7F2)),
                      ),
                      child: ElevatedButton(
                        key: const ValueKey('feedback-submit'),
                        onPressed: _canSubmit ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: muted,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          minimumSize: const Size.fromHeight(52),
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 20,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : Text(
                                settingsText(
                                  context,
                                  zh: '提交',
                                  en: 'Submit',
                                ),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined, color: muted, size: 17),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            settingsText(
                              context,
                              zh: '我们会严格保护您的隐私信息。',
                              en: 'We will strictly protect your private information.',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: muted,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(
    BuildContext context, {
    required bool dark,
    required Color text,
    required Color muted,
  }) {
    final expandedText = MediaQuery.textScalerOf(context).scale(13) > 17;
    final badges = <Widget>[
      _heroBadge(
        Icons.shield_rounded,
        settingsText(context, zh: '认真倾听', en: 'We listen'),
        muted,
      ),
      _heroBadge(
        Icons.bolt_rounded,
        settingsText(context, zh: '欢迎建议', en: 'Ideas welcome'),
        muted,
      ),
      _heroBadge(
        Icons.circle,
        settingsText(context, zh: '持续优化', en: 'Keep improving'),
        muted,
      ),
    ];

    return CustomPaint(
      key: const ValueKey('feedback-hero-backdrop'),
      painter: _FeedbackHeroBackdrop(dark: dark),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 22, 8, 2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stackIllustration = !expandedText &&
                constraints.maxWidth >= 310 &&
                Localizations.localeOf(context).languageCode == 'zh';
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: settingsText(
                          context,
                          zh: '您的意见',
                          en: 'Your feedback ',
                        ),
                      ),
                      TextSpan(
                        text: settingsText(
                          context,
                          zh: '很重要',
                          en: 'matters',
                        ),
                        style: const TextStyle(color: _blue),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    color: text,
                    fontSize: 25,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  settingsText(
                    context,
                    zh: '每一条反馈，都能帮助我们做得更好',
                    en: 'Every piece of feedback helps us improve.',
                  ),
                  style: TextStyle(color: muted, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 20),
                expandedText
                    ? Wrap(spacing: 12, runSpacing: 8, children: badges)
                    : Row(
                        children: [
                          for (var i = 0; i < badges.length; i++) ...[
                            if (i > 0)
                              Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 5),
                                width: 1,
                                height: 16,
                                color: dark
                                    ? const Color(0xFF3A4B60)
                                    : const Color(0xFFD0DEED),
                              ),
                            Expanded(child: badges[i]),
                          ],
                        ],
                      ),
              ],
            );

            final illustration = _FeedbackAssetIllustration(
              key: const ValueKey('feedback-hero-image'),
              asset: 'assets/images/feedback_hero.png',
              size: stackIllustration ? 180 : 150,
              fallback: _FeedbackHeroIllustration(
                dark: dark,
                size: stackIllustration ? 180 : 150,
              ),
            );
            if (!stackIllustration) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(alignment: Alignment.centerRight, child: illustration),
                  copy,
                ],
              );
            }
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -18,
                  top: -20,
                  bottom: -18,
                  width: constraints.maxWidth * .42,
                  child: illustration,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 140),
                  child: SizedBox(
                    width: constraints.maxWidth * .69,
                    child: copy,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _heroBadge(IconData icon, String label, Color muted) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 19,
          height: 22,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 22, color: _blue),
              Icon(
                icon == Icons.shield_rounded
                    ? Icons.check_rounded
                    : icon == Icons.bolt_rounded
                        ? Icons.bolt_rounded
                        : Icons.favorite_rounded,
                size: icon == Icons.bolt_rounded ? 11 : 12,
                color: Colors.white,
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: muted, fontSize: 10.5, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeading(
    BuildContext context, {
    required String title,
    required String trailing,
    required Color text,
    required Color muted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(
            title,
            style: TextStyle(
              color: text,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            trailing,
            style: TextStyle(color: muted, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeGrid(
    BuildContext context, {
    required Color fill,
    required Color text,
    required Color muted,
    required bool dark,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = scale > 1.4 || constraints.maxWidth < 250 ? 2 : 3;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        const items = <(String, IconData)>[
          ('suggestion', Icons.lightbulb_outline_rounded),
          ('bug', Icons.bug_report_outlined),
          ('other', Icons.more_horiz_rounded),
        ];
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items.map((item) {
            final selected = _type == item.$1;
            final label = switch (item.$1) {
              'bug' => settingsText(context, zh: '错误', en: 'Bug'),
              'other' => settingsText(context, zh: '其他', en: 'Other'),
              _ => settingsText(context, zh: '建议', en: 'Suggestion'),
            };
            return SizedBox(
              width: width,
              child: Semantics(
                selected: selected,
                button: true,
                child: Material(
                  color: selected
                      ? (dark
                          ? const Color(0xFF173E65)
                          : const Color(0xFFE8F4FF))
                      : fill,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _submitting
                        ? null
                        : () => setState(() => _type = item.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? _blue : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            item.$2,
                            color: selected ? _blue : muted,
                            size: 27,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected ? _blue : text,
                              fontSize: 14,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildScreenshots(
    BuildContext context, {
    required Color fill,
    required Color muted,
    required bool dark,
  }) {
    final screenshots = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (var i = 0; i < _attachments.length; i++) _attachmentTile(i),
        if (_attachments.length < _maxScreenshots)
          SizedBox(
            width: 100,
            child: Material(
              color: fill,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _submitting || _picking ? null : _pickImages,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: dark
                          ? const Color(0xFF46546A)
                          : const Color(0xFFD7DFEB),
                    ),
                  ),
                  child: Center(
                    child: _picking
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.add_rounded, color: muted, size: 36),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final help = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          settingsText(
            context,
            zh: '上传相关截图，帮助我们更快定位问题',
            en: 'Add screenshots to help us understand the issue.',
          ),
          style: TextStyle(color: muted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 4),
        Text(
          settingsText(
            context,
            zh: '支持 JPG、PNG、WEBP，单张不超过 10MB',
            en: 'JPG, PNG or WEBP · Up to 10 MB each',
          ),
          style: TextStyle(color: muted, fontSize: 13, height: 1.5),
        ),
      ],
    );

    if (_attachments.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [screenshots, const SizedBox(height: 12), help],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 100, child: screenshots),
        const SizedBox(width: 14),
        Expanded(child: help),
      ],
    );
  }

  Widget _attachmentTile(int index) {
    final item = _attachments[index];
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                item.bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFFF4F6F9),
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: settingsText(context, zh: '删除图片', en: 'Remove image'),
              onPressed: _submitting
                  ? null
                  : () => setState(() => _attachments.removeAt(index)),
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                minimumSize: const Size(48, 48),
                foregroundColor: Colors.white,
              ),
              padding: const EdgeInsets.fromLTRB(22, 4, 4, 22),
              icon: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 22,
                  child: Icon(Icons.close_rounded, size: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackHeroBackdrop extends CustomPainter {
  const _FeedbackHeroBackdrop({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final wave = Path()
      ..moveTo(-16, size.height * .12)
      ..cubicTo(
        size.width * .15,
        -20,
        size.width * .43,
        size.height * .17,
        size.width * .62,
        size.height * .04,
      )
      ..cubicTo(
        size.width * .83,
        -size.height * .25,
        size.width * .9,
        size.height * .05,
        size.width + 16,
        size.height * .04,
      )
      ..lineTo(size.width + 16, size.height + 22)
      ..lineTo(-16, size.height + 22)
      ..close();
    canvas.drawPath(
      wave,
      Paint()
        ..shader = LinearGradient(
          colors: dark
              ? const [Color(0xFF173550), Color(0xFF1A3D64)]
              : const [Color(0xFFEAF5FF), Color(0xFFDDEEFF)],
        ).createShader(rect),
    );
    final orb = Offset(size.width * .93, size.height * .86);
    canvas.drawCircle(
      orb,
      13,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.5, -.5),
          colors: dark
              ? const [Color(0xFF547C86), Color(0x00173550)]
              : const [Color(0xFFE5FFF4), Color(0x0052CCF2)],
        ).createShader(Rect.fromCircle(center: orb, radius: 13)),
    );
  }

  @override
  bool shouldRepaint(_FeedbackHeroBackdrop oldDelegate) =>
      oldDelegate.dark != dark;
}

class _FeedbackAssetIllustration extends StatelessWidget {
  const _FeedbackAssetIllustration({
    super.key,
    required this.asset,
    required this.size,
    required this.fallback,
  });

  final String asset;
  final double size;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _FeedbackHeroIllustration extends StatelessWidget {
  const _FeedbackHeroIllustration({required this.dark, required this.size});

  final bool dark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bubble = dark ? const Color(0xFF173E65) : const Color(0xFFE8F4FF);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * .78,
            height: size * .64,
            decoration: BoxDecoration(
              color: bubble,
              borderRadius: BorderRadius.circular(size * .22),
            ),
          ),
          Icon(
            Icons.forum_rounded,
            size: size * .42,
            color: _FeedbackPageState._blue,
          ),
          Positioned(
            right: size * .08,
            top: size * .12,
            child: Container(
              width: size * .26,
              height: size * .26,
              decoration: const BoxDecoration(
                color: Color(0xFF40B2FF),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: size * .13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackSuccessView extends StatelessWidget {
  const _FeedbackSuccessView(
      {super.key,
      required this.onDone,
      this.logFailed = false,
      this.uploadingLogs = false,
      required this.retryLogs});
  final bool logFailed;
  final bool uploadingLogs;
  final VoidCallback retryLogs;

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final background = AppTokens.surface(dark: dark);
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      (constraints.maxHeight - 64).clamp(0.0, double.infinity),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: _FeedbackAssetIllustration(
                            key: const ValueKey('feedback-success-image'),
                            asset: 'assets/images/feedback_success.png',
                            size: 210,
                            fallback: _FeedbackHeroIllustration(
                              dark: dark,
                              size: 210,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Semantics(
                          liveRegion: true,
                          header: true,
                          child: Text(
                            settingsText(
                              context,
                              zh: '提交成功',
                              en: 'Submitted successfully',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTokens.textPrimary(dark: dark),
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          settingsText(
                            context,
                            zh: '感谢您的反馈！\n我们会尽快处理，并持续优化产品体验。',
                            en: 'Thank you for your feedback!\nWe will review it as soon as possible and keep improving your experience.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTokens.textSecondary(dark: dark),
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                        if (logFailed)
                          TextButton.icon(
                              onPressed: uploadingLogs ? null : retryLogs,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(settingsText(context,
                                  zh: uploadingLogs ? '正在上传日志…' : '日志上传失败，点击重试',
                                  en: uploadingLogs
                                      ? 'Uploading logs…'
                                      : 'Retry log upload'))),
                        const SizedBox(height: 60),
                        ElevatedButton(
                          key: const ValueKey('feedback-success-done'),
                          onPressed: onDone,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: dark
                                ? const Color(0xFF176DD9)
                                : _FeedbackPageState._blue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size.fromHeight(50),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            settingsText(
                              context,
                              zh: '我知道了',
                              en: 'Got it',
                            ),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

const String _customerServiceIconSvg = r'''
<svg viewBox="75 55 800 785" xmlns="http://www.w3.org/2000/svg">
  <path d="M515.6 770.2c48.4 0 91.3-31.3 106.2-77.4 1-3.1-0.4-6.4-3.4-7.8-3-1.3-6.5-0.2-8.1 2.6-0.2 0.3-17.2 27.8-83.7 36.8-9.5 1.3-19.2 2-28.8 2-46.5 0-67.3-17.6-67.5-17.7-2.4-2.1-5.9-2.1-8.4-0.1-2.4 2-3 5.6-1.3 8.3 20.4 32.8 56.7 53.2 95 53.3z" fill="#662D91"/>
  <path d="M808.3 398.9c-45.7-123.7-164-212.1-303.2-212.1-138.6 0-256.6 87.6-302.6 210.5-2.4-2.7-4.9-5.3-7.6-7.6C221 239.9 349.9 126 505.3 126c154.7 0 283.2 112.8 310.2 261.5-2.8 3.6-5.2 7.4-7.2 11.4z m64.6-40.5c-0.6 0-1.1 0.1-1.7 0.1C832.3 190 683.5 64.3 505.2 64.3 322 64.3 169.8 197 136.1 372.5c-33.5 6.2-57.9 35.5-57.7 69.6v139.5c0 39.1 31.4 70.8 70.1 70.8 21.8 0 41.1-10.3 53.9-26.1C233.4 708 296 774 376.2 809c1-2 2.2-3.9 3.5-5.7 1.3-1.6 2.7-3 3.9-3 1.2 0 2.4 0.4 3.4 1.1-18.5-13.8-85.2-84.4-99.7-183.1-6.3-43.4 26.2-86.1 64.1-93.1 60.8-11.3 121.3-24.2 182.1-35.3 38.7-7 65.1-28.3 81.2-63.6 3.8-8.3 9.3-25 11.8-49 0.6-3.6 3.7-6.3 7.4-6.3 2.4 0 4.6 1.2 6 3.1l1.7-1c24 34.8 71.5 111.9 78.3 193.1 7.8 92.9 3.5 156.5-67.6 221.6l-0.3 0.3c-1 1.1-1.6 2.5-1.6 4 0 1.9 1 3.7 2.6 4.7 0.6 0.2 1.2 0.6 1.8 0.8 0.5 0.1 0.9 0.2 1.4 0.3 0.5 0 0.9-0.1 1.3-0.3 1-0.5 2-1.1 3-1.7 72.6-40.1 127.2-106.4 152.5-185.4a72.29 72.29 0 0 0 45.2 30.2c-30 136.9-152.2 222.7-303.5 235.6-9.6-23.4-32.4-38.6-57.6-38.5-34.2 0-62 27.1-62 60.5s27.8 60.5 62 60.5c26.6 0.1 50.3-16.9 58.7-42.1 175.1-14.2 315.5-118.3 344.8-280 26.7-11 44.1-37 44.1-65.9V429.9c0.2-39.5-32-71.5-71.8-71.5z" fill="#662D91"/>
</svg>
''';
