import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../chat_background_local_service.dart';
import '../settings_draft_store.dart';
import '../widgets/settings_widgets.dart';

class FontSizePage extends StatelessWidget {
  const FontSizePage({super.key, required this.store});

  final SettingsDraftStore store;

  static const List<double> presets = <double>[0.9, 1.0, 1.12, 1.24];

  static int indexForScale(double scale) {
    var best = 0;
    var distance = (presets.first - scale).abs();
    for (var i = 1; i < presets.length; i++) {
      final next = (presets[i] - scale).abs();
      if (next < distance) {
        best = i;
        distance = next;
      }
    }
    return best;
  }

  static String labelFor(BuildContext context, int index) {
    const zh = ['小', '标准', '较大', '超大'];
    const en = ['Small', 'Default', 'Large', 'Extra Large'];
    final values = Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
    return values[index.clamp(0, values.length - 1).toInt()];
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final dark = settingsIsDark(context);
          final background = AppTokens.background(dark: dark);
          final surface = AppTokens.surface(dark: dark);
          final text = AppTokens.textPrimary(dark: dark);
          final secondary = AppTokens.textSecondary(dark: dark);
          final divider = AppTokens.border(dark: dark);
          final scale = presets[store.fontSizeIndex.clamp(0, 3).toInt()];
          final overlay = AppSystemBars.styleFor(surface);

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlay,
            child: Scaffold(
              backgroundColor: surface,
              body: SafeArea(
                child: Column(
                  children: [
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.noScaling,
                      ),
                      child: _ChatPreviewNavBar(
                        dark: dark,
                        surface: surface,
                        text: text,
                        secondary: secondary,
                        divider: divider,
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _ChatBackgroundPreview(store: store, dark: dark),
                          MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              textScaler: TextScaler.linear(scale),
                            ),
                            child: ListView(
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(0, 18, 0, 4),
                              children: [
                                _PreviewMessageRow(
                                  dark: dark,
                                  isMine: false,
                                  text: settingsText(
                                    context,
                                    zh: '没问题，那我六点半出发。',
                                    en: 'Sounds good. I’ll head out at 6:30.',
                                  ),
                                  time: '10:26',
                                ),
                                _PreviewMessageRow(
                                  dark: dark,
                                  isMine: true,
                                  text: settingsText(
                                    context,
                                    zh: '好呀，我先订位置，到了给你发消息。',
                                    en: 'Sure. I’ll book a table and message you when I arrive.',
                                  ),
                                  time: '10:25',
                                ),
                                _PreviewMessageRow(
                                  dark: dark,
                                  isMine: false,
                                  text: settingsText(
                                    context,
                                    zh: '今天下班一起去吃火锅吗？',
                                    en: 'Want to grab hot pot after work today?',
                                  ),
                                  time: '10:24',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.noScaling,
                      ),
                      child: _FontSliderPanel(
                        dark: dark,
                        surface: surface,
                        text: text,
                        secondary: secondary,
                        divider: divider,
                        selectedIndex: store.fontSizeIndex,
                        onChanged: (index) {
                          store.setFontSizeIndex(index);
                          DataSp.putChatFontSizeFactor(presets[index]);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _ChatPreviewNavBar extends StatelessWidget {
  const _ChatPreviewNavBar({
    required this.dark,
    required this.surface,
    required this.text,
    required this.secondary,
    required this.divider,
    required this.onBack,
  });

  final bool dark;
  final Color surface;
  final Color text;
  final Color secondary;
  final Color divider;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Container(
        height: 56,
        decoration: BoxDecoration(
          color: surface,
          border: Border(bottom: BorderSide(color: divider, width: 0.7)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppTokens.accent,
                size: 20,
              ),
            ),
            AvatarView(
              url: '',
              text: settingsText(context, zh: '小美', en: 'Amy'),
              width: 40,
              height: 40,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settingsText(context, zh: '小美', en: 'Amy'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    settingsText(context, zh: '在线', en: 'Online'),
                    style: TextStyle(color: secondary, fontSize: 12, height: 1.1),
                  ),
                ],
              ),
            ),
            const Icon(Icons.call_outlined, color: AppTokens.accent, size: 22),
            const SizedBox(width: 18),
            const Icon(Icons.videocam_outlined, color: AppTokens.accent, size: 24),
            const SizedBox(width: 18),
            const Icon(Icons.more_horiz_rounded, color: AppTokens.accent, size: 24),
            const SizedBox(width: 12),
          ],
        ),
      );
}

class _ChatBackgroundPreview extends StatelessWidget {
  const _ChatBackgroundPreview({required this.store, required this.dark});

  final SettingsDraftStore store;
  final bool dark;

  static const _colors = <String, Color>{
    'color:f1f1f1': Color(0xFFF1F1F1),
    'color:cfeccb': Color(0xFFCFECCB),
    'color:bedbff': Color(0xFFBEDBFF),
    'color:f9c9d2': Color(0xFFF9C9D2),
    'color:fff3b6': Color(0xFFFFF3B6),
    'color:d9b8e8': Color(0xFFD9B8E8),
  };

  @override
  Widget build(BuildContext context) {
    final persisted = ChatBackgroundLocalService.global();
    final persistedColor = ChatBackgroundLocalService.colorOf(persisted);
    final color = persistedColor ??
        _colors[store.chatBackgroundId] ??
        (dark ? const Color(0xFF15171B) : const Color(0xFFF3F5F8));
    ImageProvider? image;
    if (store.chatBackgroundId == 'gallery' &&
        store.chatBackgroundImageBytes != null) {
      image = MemoryImage(store.chatBackgroundImageBytes!);
    } else {
      final asset = ChatBackgroundLocalService.assetOf(persisted) ??
          switch (store.chatBackgroundId) {
            'asset:beauty' => 'assets/images/chat_backgrounds/beauty.png',
            'asset:scenery' => 'assets/images/chat_backgrounds/scenery.png',
            'asset:car' => 'assets/images/chat_backgrounds/car.png',
            _ => null,
          };
      final file = ChatBackgroundLocalService.fileOf(persisted);
      if (asset != null) {
        image = AssetImage(asset, package: 'openim_common');
      } else if (file != null && File(file).existsSync()) {
        image = FileImage(File(file));
      }
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        image: image == null
            ? null
            : DecorationImage(image: image, fit: BoxFit.cover),
      ),
    );
  }
}

class _PreviewMessageRow extends StatelessWidget {
  const _PreviewMessageRow({
    required this.dark,
    required this.isMine,
    required this.text,
    required this.time,
  });

  final bool dark;
  final bool isMine;
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: EdgeInsets.only(left: isMine ? 58 : 16, right: isMine ? 16 : 58),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isMine) ...[
              AvatarView(
                url: '',
                text: settingsText(context, zh: '小美', en: 'Amy'),
                width: 40,
                height: 40,
              ),
              const SizedBox(width: 13),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isMine
                      ? (dark ? const Color(0xFF26384F) : const Color(0xFFDCEEFF))
                      : AppTokens.surface(dark: dark),
                  borderRadius: isMine
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(2),
                          bottomLeft: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        )
                      : const BorderRadius.only(
                          topLeft: Radius.circular(2),
                          topRight: Radius.circular(10),
                          bottomLeft: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        ),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Text(
                      text,
                      style: TextStyle(
                        color: AppTokens.textPrimary(dark: dark),
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        color: AppTokens.textSecondary(dark: dark),
                        fontSize: 11,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _FontSliderPanel extends StatelessWidget {
  const _FontSliderPanel({
    required this.dark,
    required this.surface,
    required this.text,
    required this.secondary,
    required this.divider,
    required this.selectedIndex,
    required this.onChanged,
  });

  final bool dark;
  final Color surface;
  final Color text;
  final Color secondary;
  final Color divider;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTokens.rLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  settingsText(context, zh: '当前', en: 'Current'),
                  style: TextStyle(color: secondary, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Text(
                  FontSizePage.labelFor(context, selectedIndex),
                  style: TextStyle(
                    color: text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTokens.accent,
                inactiveTrackColor: divider,
                thumbColor: AppTokens.accent,
                overlayColor: AppTokens.accent.withOpacity(0.14),
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                value: selectedIndex.toDouble(),
                divisions: FontSizePage.presets.length - 1,
                min: 0,
                max: (FontSizePage.presets.length - 1).toDouble(),
                onChanged: (value) => onChanged(value.round()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: List.generate(FontSizePage.presets.length, (index) {
                  final selected = index == selectedIndex;
                  return Expanded(
                    child: Align(
                      alignment: index == 0
                          ? Alignment.centerLeft
                          : index == FontSizePage.presets.length - 1
                              ? Alignment.centerRight
                              : Alignment.center,
                      child: Text(
                        FontSizePage.labelFor(context, index),
                        style: TextStyle(
                          color: selected ? text : secondary,
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      );
}
