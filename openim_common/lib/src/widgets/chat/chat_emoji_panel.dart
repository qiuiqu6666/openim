import 'dart:math' as math;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_composer_palette.dart';

enum _EmojiSection { all, favorites, gestures }

class ChatEmojiPanel extends StatefulWidget {
  const ChatEmojiPanel({
    super.key,
    required this.onEmojiSelected,
    required this.onBackspace,
    required this.onSend,
    required this.canSend,
    this.stickerPanel,
  });

  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onBackspace;
  final VoidCallback onSend;
  final bool canSend;
  final Widget? stickerPanel;

  @override
  State<ChatEmojiPanel> createState() => _ChatEmojiPanelState();
}

class _ChatEmojiPanelState extends State<ChatEmojiPanel> {
  static const _recentKey = 'chat_recent_emoji';
  static const _favoriteKey = 'chat_favorite_emoji';
  static const _fallbackEmoji = {
    '😀',
    '😁',
    '😂',
    '😊',
    '😍',
    '😎',
    '😭',
    '👍',
    '❤️'
  };
  static const _suggested = [
    '😂',
    '🤣',
    '😊',
    '😁',
    '😅',
    '🤭',
    '🤦',
    '🥹',
    '😭',
    '🥰',
    '😍',
    '😘',
    '😎',
    '🤔',
    '🙄',
    '😏',
    '👍',
    '🙏',
    '👏',
    '💪',
    '❤️',
    '🌹',
    '🎉',
    '🔥',
    '🤝',
    '👀',
    '👋',
    '💯',
    '🍉',
    '🧧',
    '🐶',
    '✨',
  ];
  static const _gestures = [
    '👍',
    '👎',
    '👏',
    '🙏',
    '🤝',
    '💪',
    '👋',
    '👌',
    '✌️',
    '🤞',
    '🫰',
    '🤟',
    '🤘',
    '👊',
    '✊',
    '🙌',
    '👐',
    '🤲',
    '👉',
    '👈',
    '👆',
    '👇',
    '🫶',
    '🤦',
  ];
  static final _all = <emoji_picker.Emoji>[
    for (final glyph in _suggested)
      emoji_picker.emojiSetChinese
              .expand((section) => section.emoji)
              .where((emoji) => emoji.emoji == glyph)
              .firstOrNull ??
          emoji_picker.Emoji(glyph, glyph),
    for (final section in emoji_picker.emojiSetChinese)
      for (final emoji in section.emoji)
        if (!_suggested.contains(emoji.emoji)) emoji,
  ];

  SharedPreferences? _prefs;
  List<String> _recent = [];
  List<String> _favorites = [];
  _EmojiSection _section = _EmojiSection.all;
  Set<String>? _supportedEmoji;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadSupportedEmoji();
  }

  Future<void> _loadSupportedEmoji() async {
    try {
      final categories = await emoji_picker.EmojiPickerUtils()
          .filterUnsupported(emoji_picker.emojiSetChinese);
      if (!mounted) return;
      setState(() {
        _supportedEmoji = {
          for (final category in categories)
            for (final emoji in category.emoji) emoji.emoji,
        };
      });
    } catch (_) {
      // Keep the panel usable if the platform compatibility channel fails.
      if (!mounted) return;
      setState(() => _supportedEmoji = _fallbackEmoji);
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      if (_recent.isEmpty) _recent = prefs.getStringList(_recentKey) ?? [];
      if (_favorites.isEmpty) {
        _favorites = prefs.getStringList(_favoriteKey) ?? [];
      }
    });
  }

  void _select(String emoji) {
    widget.onEmojiSelected(emoji);
    setState(() {
      _recent =
          [emoji, ..._recent.where((item) => item != emoji)].take(24).toList();
    });
    _prefs?.setStringList(_recentKey, _recent);
  }

  void _toggleFavorite(String emoji) {
    setState(() {
      if (_favorites.contains(emoji)) {
        _favorites.remove(emoji);
      } else {
        _favorites.insert(0, emoji);
      }
    });
    _prefs?.setStringList(_favoriteKey, _favorites);
  }

  List<String> get _visibleEmoji {
    final supported = _supportedEmoji;
    if (supported == null) return [];
    if (_section == _EmojiSection.favorites) {
      return _favorites.where(supported.contains).toList();
    }
    if (_section == _EmojiSection.gestures) {
      return _gestures.where(supported.contains).toList();
    }
    return _all.map((emoji) => emoji.emoji).where(supported.contains).toList();
  }

  Widget _emojiCell(String emoji) => InkWell(
        key: ValueKey('emoji-$emoji'),
        onTap: () => _select(emoji),
        onLongPress: () => _toggleFavorite(emoji),
        child: Center(child: Text(emoji, style: TextStyle(fontSize: 27.sp))),
      );

  @override
  Widget build(BuildContext context) {
    final visible = _visibleEmoji;
    final recent = (_recent.isEmpty ? _suggested : _recent)
        .where((emoji) => _supportedEmoji?.contains(emoji) ?? false)
        .take(_recent.isEmpty ? 8 : 24)
        .toList();
    final colors = Theme.of(context).colorScheme;
    final panelColor = chatComposerSurface(context);
    final showingStickers =
        _section == _EmojiSection.favorites && widget.stickerPanel != null;
    return Container(
      height: math.min(280.h, MediaQuery.sizeOf(context).height * .36),
      color: panelColor,
      child: Column(children: [
        Container(
          height: 50.h,
          decoration: BoxDecoration(
            color: panelColor,
            border: Border(
              top: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .35),
                  width: .5),
            ),
          ),
          child: Row(children: [
            _tab(Icons.sentiment_satisfied_alt_outlined, 'sdkEmojiPanel'.tr,
                _EmojiSection.all),
            _tab(Icons.favorite_border, 'sdkFavoriteEmoji'.tr,
                _EmojiSection.favorites),
            _tab(Icons.back_hand_outlined, 'sdkGestureEmoji'.tr,
                _EmojiSection.gestures),
          ]),
        ),
        if (showingStickers)
          Expanded(child: widget.stickerPanel!)
        else
          Expanded(
            child: CustomScrollView(slivers: [
              if (_section == _EmojiSection.all) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 4.h),
                    child: Text(
                      _recent.isEmpty
                          ? 'sdkSuggestedEmoji'.tr
                          : 'sdkRecentEmoji'.tr,
                      style: TextStyle(
                          color: colors.onSurfaceVariant, fontSize: 13.sp),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 44.h,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: recent.length,
                      itemBuilder: (_, index) => SizedBox(
                        width: 44.w,
                        child: _emojiCell(recent[index]),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 4.h),
                    child: Text('sdkAllEmoji'.tr,
                        style: TextStyle(
                            color: colors.onSurfaceVariant, fontSize: 13.sp)),
                  ),
                ),
              ],
              if (_supportedEmoji == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text('sdkEmojiEmpty'.tr,
                        style: TextStyle(color: colors.onSurfaceVariant)),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  sliver: SliverGrid.builder(
                    itemCount: visible.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (_, index) => _emojiCell(visible[index]),
                  ),
                ),
            ]),
          ),
        if (!showingStickers)
          Container(
            height: 48.h,
            color: panelColor,
            padding: EdgeInsets.only(right: 10.w),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              IconButton(
                tooltip: 'sdkEmojiBackspace'.tr,
                onPressed: widget.onBackspace,
                icon: const Icon(Icons.backspace_outlined),
              ),
              8.horizontalSpace,
              FilledButton(
                onPressed: widget.canSend ? widget.onSend : null,
                child: Text('sdkEmojiSend'.tr),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _tab(IconData icon, String tooltip, _EmojiSection section) {
    final selected = _section == section;
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 46.w,
      height: 42.h,
      margin: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: selected ? colors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(11.r),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: () => setState(() => _section = section),
        icon: Icon(icon,
            size: 23.w,
            color: selected ? colors.onSurface : colors.onSurfaceVariant),
      ),
    );
  }
}
