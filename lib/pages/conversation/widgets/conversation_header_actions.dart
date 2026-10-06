// Adapted from 99chat's home_page.dart, customer_service_icon.dart and
// archivedEditIconSvg in conversation.dart (Apache License 2.0).
// Source: https://github.com/qiuiqu6666/99chat
// Changes: page-owned callbacks keep the existing OpenIM business flow.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openim_common/openim_common.dart';

/// The home header's support, edit and plus actions, in reference order.
class ConversationHeaderActions extends StatelessWidget {
  const ConversationHeaderActions({
    super.key,
    required this.editing,
    required this.onSupport,
    required this.onToggleEditing,
    required this.plusKey,
    required this.plusTurns,
    required this.onPlus,
  });

  final bool editing;
  final VoidCallback onSupport;
  final VoidCallback onToggleEditing;
  final GlobalKey plusKey;
  final double plusTurns;
  final VoidCallback onPlus;

  static const _supportSize = 26.0;
  static const _tapSize = 48.0;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (editing) {
      return ConversationEditButton(editing: true, onPressed: onToggleEditing);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: zh ? '在线客服' : 'Customer Service',
          onPressed: onSupport,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: _tapSize,
            minHeight: _tapSize,
          ),
          icon: SvgPicture.string(
            _customerServiceIconSvg,
            width: _supportSize,
            height: _supportSize,
            fit: BoxFit.contain,
            colorFilter: const ColorFilter.mode(
              AppTokens.accent,
              BlendMode.srcIn,
            ),
          ),
        ),
        ConversationEditButton(editing: false, onPressed: onToggleEditing),
        MainTabPlusButton(
          buttonKey: plusKey,
          turns: plusTurns,
          onPressed: onPlus,
        ),
      ],
    );
  }
}

/// The same edit/done control is used by the main feed and archived page.
class ConversationEditButton extends StatelessWidget {
  const ConversationEditButton({
    super.key,
    required this.editing,
    required this.onPressed,
  });

  final bool editing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (editing) {
      return TextButton(
        onPressed: onPressed,
        child: Text(zh ? '完成' : 'Done',
            style: const TextStyle(color: AppTokens.accent)),
      );
    }
    return IconButton(
      tooltip: zh ? '编辑' : 'Edit',
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: SvgPicture.string(_archivedEditIconSvg,
          width: AppTokens.s7, height: AppTokens.s7),
    );
  }
}

const _customerServiceIconSvg = '''
<svg viewBox="75 55 800 785" xmlns="http://www.w3.org/2000/svg">
  <path d="M515.6 770.2c48.4 0 91.3-31.3 106.2-77.4 1-3.1-0.4-6.4-3.4-7.8-3-1.3-6.5-0.2-8.1 2.6-0.2 0.3-17.2 27.8-83.7 36.8-9.5 1.3-19.2 2-28.8 2-46.5 0-67.3-17.6-67.5-17.7-2.4-2.1-5.9-2.1-8.4-0.1-2.4 2-3 5.6-1.3 8.3 20.4 32.8 56.7 53.2 95 53.3z" fill="#662D91"/>
  <path d="M808.3 398.9c-45.7-123.7-164-212.1-303.2-212.1-138.6 0-256.6 87.6-302.6 210.5-2.4-2.7-4.9-5.3-7.6-7.6C221 239.9 349.9 126 505.3 126c154.7 0 283.2 112.8 310.2 261.5-2.8 3.6-5.2 7.4-7.2 11.4z m64.6-40.5c-0.6 0-1.1 0.1-1.7 0.1C832.3 190 683.5 64.3 505.2 64.3 322 64.3 169.8 197 136.1 372.5c-33.5 6.2-57.9 35.5-57.7 69.6v139.5c0 39.1 31.4 70.8 70.1 70.8 21.8 0 41.1-10.3 53.9-26.1C233.4 708 296 774 376.2 809c1-2 2.2-3.9 3.5-5.7 1.3-1.6 2.7-3 3.9-3 1.2 0 2.4 0.4 3.4 1.1-18.5-13.8-85.2-84.4-99.7-183.1-6.3-43.4 26.2-86.1 64.1-93.1 60.8-11.3 121.3-24.2 182.1-35.3 38.7-7 65.1-28.3 81.2-63.6 3.8-8.3 9.3-25 11.8-49 0.6-3.6 3.7-6.3 7.4-6.3 2.4 0 4.6 1.2 6 3.1l1.7-1c24 34.8 71.5 111.9 78.3 193.1 7.8 92.9 3.5 156.5-67.6 221.6l-0.3 0.3c-1 1.1-1.6 2.5-1.6 4 0 1.9 1 3.7 2.6 4.7 0.6 0.2 1.2 0.6 1.8 0.8 0.5 0.1 0.9 0.2 1.4 0.3 0.5 0 0.9-0.1 1.3-0.3 1-0.5 2-1.1 3-1.7 72.6-40.1 127.2-106.4 152.5-185.4a72.29 72.29 0 0 0 45.2 30.2c-30 136.9-152.2 222.7-303.5 235.6-9.6-23.4-32.4-38.6-57.6-38.5-34.2 0-62 27.1-62 60.5s27.8 60.5 62 60.5c26.6 0.1 50.3-16.9 58.7-42.1 175.1-14.2 315.5-118.3 344.8-280 26.7-11 44.1-37 44.1-65.9V429.9c0.2-39.5-32-71.5-71.8-71.5z" fill="#662D91"/>
</svg>
''';

const _archivedEditIconSvg = '''
<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <path d="M897.39456 416.256v448.64c0 35.968-23.04 64-59.2 64H183.92256c-36.096 0-55.936-28.032-55.936-64V150.848c0-36.032 19.84-56 55.936-56h456.256a32 32 0 0 0 0-64H153.97056C99.76256 30.912 63.98656 78.72 63.98656 132.672v773.76c0 54.016 35.776 86.4 89.984 86.4h718.016c54.208 0 89.984-32.384 89.984-86.4V416.256a32.256 32.256 0 1 0-64.512 0z m-464.384 263.04l548.096-548.48a36.864 36.864 0 0 0 0-52.352 37.312 37.312 0 0 0-52.608 0l-548.032 548.48a36.736 36.736 0 0 0 0 52.352 37.44 37.44 0 0 0 52.544 0z" fill="#1D86F0"/>
</svg>
''';
