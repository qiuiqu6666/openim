import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'announcement_mention_link.dart';

class GroupAnnouncementBanner extends StatefulWidget {
  const GroupAnnouncementBanner(
      {super.key,
      required this.text,
      required this.groupID,
      required this.userID,
      this.version = '',
      this.preferences});
  final String version;
  final String text;
  final String groupID;
  final String userID;
  final SharedPreferences? preferences;

  @override
  State<GroupAnnouncementBanner> createState() =>
      _GroupAnnouncementBannerState();
}

class _GroupAnnouncementBannerState extends State<GroupAnnouncementBanner>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  AnimationController get controller => _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(seconds: 36),
      )..repeat();
  bool _showing = false;
  bool _dismissed = false;
  bool _loaded = false;
  int _loadGeneration = 0;
  String get _dismissKey =>
      'group_announcement_dismissed:${widget.userID}:${widget.groupID}';
  String get _revision => '${widget.version}:${widget.text}';

  String get _readKey =>
      'group_announcement_read:${widget.userID}:${widget.groupID}';

  @override
  void initState() {
    super.initState();
    _resolveVisibility();
  }

  @override
  void didUpdateWidget(covariant GroupAnnouncementBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.version != widget.version ||
        oldWidget.groupID != widget.groupID ||
        oldWidget.userID != widget.userID ||
        oldWidget.preferences != widget.preferences) {
      _resolveVisibility();
    }
  }

  void _resolveVisibility() {
    final prefs = widget.preferences;
    // Production already owns initialized preferences. Resolve before layout so
    // an unchanged announcement cannot briefly collapse the live entry below it.
    _loaded = prefs != null;
    if (prefs != null) {
      _dismissed = prefs.getString(_dismissKey) == _revision;
    }
    final generation = ++_loadGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _loadGeneration) {
        _showUnread(generation);
      }
    });
  }

  Future<void> _showUnread(int generation) async {
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    final revision = _revision;
    final key = _dismissKey;
    final prefs = widget.preferences ?? await SharedPreferences.getInstance();
    if (!mounted ||
        generation != _loadGeneration ||
        revision != _revision ||
        key != _dismissKey) {
      return;
    }
    final dismissed = prefs.getString(key) == revision;
    if (!_loaded || _dismissed != dismissed) {
      setState(() {
        _dismissed = dismissed;
        _loaded = true;
      });
    }
    if (_dismissed || _showing || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (widget.text.trim().isNotEmpty &&
        prefs.getString(_readKey) != widget.text) {
      await _showAnnouncement();
    }
  }

  Future<void> _dismissBanner() async {
    final key = _dismissKey;
    final revision = _revision;
    setState(() => _dismissed = true);
    final prefs = widget.preferences ?? await SharedPreferences.getInstance();
    await prefs.setString(key, revision);
  }

  Future<void> _showAnnouncement() async {
    if (_showing) return;
    _showing = true;
    final text = widget.text;
    final key = _readKey;
    final preferences = widget.preferences;
    try {
      final confirmed = await showGroupAnnouncementSheet(context, text);
      if (confirmed == true) {
        final prefs = preferences ?? await SharedPreferences.getInstance();
        await prefs.setString(key, text);
      }
    } finally {
      _showing = false;
    }
  }

  @override
  void dispose() {
    // Do not invoke the lazy getter during disposal: hidden/short banners
    // may never have needed an animation controller.
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _dismissed) return const SizedBox.shrink();
    final style = Theme.of(context)
        .textTheme
        .bodyMedium!
        .copyWith(color: Styles.c_0089FF);
    final text = widget.text.replaceAll(RegExp(r'\s+'), ' ');
    return Material(
      color: Styles.c_0089FF.withValues(alpha: 0.08),
      child: InkWell(
        onTap: _showAnnouncement,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: LayoutBuilder(builder: (context, constraints) {
            // Keep the normal intrinsic label width and right-edge close action.
            // Only truncate the prefix when scaled text would consume the row.
            final closeWidth = constraints.maxWidth.clamp(0.0, 32.0).toDouble();
            final hasGapRoom = constraints.maxWidth >= 32 + 6 + 8;
            final prefixGap = hasGapRoom ? 6.0 : 0.0;
            final closeGap = hasGapRoom ? 8.0 : 0.0;
            final prefixMaxWidth =
                (constraints.maxWidth - closeWidth - prefixGap - closeGap)
                    .clamp(0.0, constraints.maxWidth)
                    .toDouble();
            return Row(
                key: const ValueKey('group-announcement-row'),
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: prefixMaxWidth),
                    child: Text('群公告：',
                        key: const ValueKey('group-announcement-prefix'),
                        style: style.copyWith(fontWeight: FontWeight.normal),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis),
                  ),
                  SizedBox(width: prefixGap),
                  Expanded(
                      child: LayoutBuilder(
                          key: const ValueKey('group-announcement-content'),
                          builder: (context, constraints) {
                            final painter = TextPainter(
                              text: TextSpan(text: text, style: style),
                              textDirection: Directionality.of(context),
                              textScaler: MediaQuery.textScalerOf(context),
                              maxLines: 1,
                            )..layout();
                            final width = painter.width;
                            final height = painter.height;
                            painter.dispose();
                            if (width <= constraints.maxWidth ||
                                MediaQuery.disableAnimationsOf(context)) {
                              return Text(text,
                                  style: style,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis);
                            }
                            final distance = width + 48;
                            return Semantics(
                              label: widget.text,
                              child: ExcludeSemantics(
                                  child: ClipRect(
                                child: SizedBox(
                                    height: height,
                                    child: AnimatedBuilder(
                                      animation: controller,
                                      builder: (context, _) => Stack(children: [
                                        for (var i = 0; i < 2; i++)
                                          Positioned(
                                            left: distance *
                                                (i - controller.value),
                                            width: width + 1,
                                            child: Text(text,
                                                style: style,
                                                maxLines: 1,
                                                softWrap: false),
                                          ),
                                      ]),
                                    )),
                              )),
                            );
                          })),
                  SizedBox(width: closeGap),
                  SizedBox(
                    width: closeWidth,
                    child: ClipRect(
                        child: IconButton(
                      key: const ValueKey('group-announcement-close'),
                      tooltip: '关闭公告栏',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: _dismissBanner,
                      style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      icon: Icon(Icons.close,
                          size: 18,
                          color: Styles.c_0089FF.withValues(alpha: 0.65)),
                    )),
                  ),
                ]);
          }),
        ),
      ),
    );
  }
}

Future<bool?> showGroupAnnouncementSheet(BuildContext context, String text) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Styles.c_FFFFFF,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * .75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('群公告',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 22),
                Flexible(
                    child: SingleChildScrollView(
                  child: MatchTextView(
                    text: text,
                    textStyle: Theme.of(sheetContext).textTheme.bodyLarge,
                    matchTextStyle: Theme.of(sheetContext)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: Styles.c_0089FF),
                    isSupportCopy: true,
                    patterns: [
                      MatchPattern(
                        type: PatternType.custom,
                        pattern: r'@[\w\u4e00-\u9fff-]+',
                        onTap: (value, _) => AnnouncementMentionLink.open(
                            sheetContext, value,
                            dismissSheet: true),
                      )
                    ],
                  ),
                )),
                const SizedBox(height: 28),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Styles.c_0089FF,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('我知道了',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
