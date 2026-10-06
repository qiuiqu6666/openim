import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'chat_toolbox_tokens.dart';

/// Original 99chat artwork, preserving the padding within each 128px canvas.
class ChatToolboxIcon extends StatelessWidget {
  const ChatToolboxIcon({
    super.key,
    required this.id,
    this.asset = '',
    this.symbol,
    this.enabled = true,
  });

  final String id;
  final String asset;
  final IconData? symbol;
  final bool enabled;

  static const _assets = {
    'album': 'photo.svg',
    'camera': 'screen.svg',
    'call': 'video-call.svg',
    'card': 'card.svg',
    'file': 'file.svg',
    'favorites': 'favorites.png',
    'red-packet': 'red_packet.png',
    'transfer': 'transfer.png',
    'group_live': 'group_live.png',
  };

  @override
  Widget build(BuildContext context) {
    var color = ChatToolboxTokens.iconColor(context);
    if (!enabled) {
      color = color.withValues(alpha: ChatToolboxTokens.disabledOpacity);
    }
    final reference = _assets[id];
    final iconAsset =
        reference == null ? asset : 'assets/chat_toolbox/$reference';
    if (reference == null && symbol != null) {
      return Icon(symbol, size: ChatToolboxTokens.symbolSize, color: color);
    }
    if (iconAsset.isEmpty) {
      return const SizedBox.square(dimension: ChatToolboxTokens.iconSize);
    }
    if (iconAsset.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        iconAsset,
        package: 'openim_common',
        width: ChatToolboxTokens.iconSize,
        height: ChatToolboxTokens.iconSize,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return Image.asset(
      iconAsset,
      package: 'openim_common',
      width: ChatToolboxTokens.iconSize,
      height: ChatToolboxTokens.iconSize,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}
