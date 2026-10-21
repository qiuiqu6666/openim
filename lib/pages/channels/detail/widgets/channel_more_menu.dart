import 'package:flutter/material.dart';
import '../../presentation/channel_ui.dart';
import '../../presentation/channel_tokens.dart';

/// GroupProfileButtonArea.asChannelMoreMenu in the reference repository.
class ChannelMoreMenu extends StatelessWidget {
  const ChannelMoreMenu(
      {super.key,
      required this.owner,
      required this.onSelected,
      required this.child});
  final bool owner;
  final ValueChanged<String> onSelected;
  final Widget child;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
      tooltip: channelText(context, '更多', 'More'),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      elevation: 4,
      shadowColor: ChannelTokens.menuShadow,
      color: ChannelTokens.surface(context),
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      menuPadding: const EdgeInsets.all(4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChannelTokens.cardRadius)),
      constraints: const BoxConstraints(minWidth: 208, maxWidth: 280),
      onSelected: onSelected,
      itemBuilder: (context) => [
            _item(context, 'clear', Icons.delete_sweep_outlined,
                channelText(context, '清空聊天记录', 'Clear chat history'), false),
            _item(
                context,
                'leave',
                owner ? Icons.delete_outline_rounded : Icons.logout_rounded,
                channelText(context, owner ? '解散频道' : '退出',
                    owner ? 'Delete channel' : 'Leave'),
                true),
          ],
      child: child);
  PopupMenuItem<String> _item(BuildContext context, String value, IconData icon,
          String title, bool danger) =>
      PopupMenuItem(
          value: value,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.surfaceContainerHigh
                        : danger
                            ? ChannelTokens.menuDangerFill
                            : ChannelTokens.menuClearFill,
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(icon,
                    size: 20,
                    color: danger
                        ? ChannelTokens.menuDanger
                        : ChannelTokens.action(context))),
            const SizedBox(width: 12),
            Flexible(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: danger ? ChannelTokens.menuDanger : null))),
          ]));
}
