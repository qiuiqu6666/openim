import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../res/app_tokens.dart';
import '../../res/strings.dart';
import '../../utils/permissions.dart';

import 'toolbox/chat_toolbox_grid.dart';
import 'toolbox/chat_toolbox_icon.dart';
import 'toolbox/chat_toolbox_tile.dart';
import 'toolbox/chat_toolbox_tokens.dart';

export 'toolbox/chat_toolbox_tokens.dart';

class ChatToolBox extends StatefulWidget {
  const ChatToolBox({
    super.key,
    this.onTapAlbum,
    this.onTapCall,
    this.onTapCard,
    this.onTapAudio,
    this.onTapFile,
    this.onTapCamera,
    this.onTapRecord,
    this.onTapLocation,
    this.onTapEmoji,
    this.onTapFormattedText,
    this.onTapRedPacket,
    this.onTapTransfer,
    this.onTapFavorites,
    this.isGroupChat = false,
    this.extraItems = const [],
  });
  final Function()? onTapAlbum;
  final Function()? onTapCall;
  final VoidCallback? onTapCard;
  final VoidCallback? onTapAudio;
  final VoidCallback? onTapFile;
  final VoidCallback? onTapCamera;
  final VoidCallback? onTapRecord;
  final VoidCallback? onTapLocation;
  final VoidCallback? onTapEmoji;
  final VoidCallback? onTapFormattedText;
  final VoidCallback? onTapRedPacket;
  final VoidCallback? onTapTransfer;
  final VoidCallback? onTapFavorites;
  final bool isGroupChat;
  final List<ToolboxItemInfo> extraItems;

  @override
  State<ChatToolBox> createState() => _ChatToolBoxState();
}

class _ChatToolBoxState extends State<ChatToolBox> {
  var _pageController = PageController();
  int _page = 0;

  List<_ToolboxAction> _actions(ChatToolBox toolbox) {
    final album = toolbox.onTapAlbum;
    final camera = toolbox.onTapCamera;
    final call = toolbox.onTapCall;
    return [
      _ToolboxAction(
          'album',
          ToolboxItemInfo(
            text: StrRes.toolboxAlbum,
            icon: '',
            onTap: album == null ? null : () => Permissions.photos(album),
          )),
      if (camera != null)
        _ToolboxAction(
            'camera',
            ToolboxItemInfo(
              text: StrRes.toolboxCamera,
              icon: '',
              onTap: () => Permissions.cameraAndMicrophone(camera),
            )),
      if (toolbox.onTapFavorites != null)
        _ToolboxAction(
            'favorites',
            ToolboxItemInfo(
              text: StrRes.favoriteCollection,
              icon: '',
              onTap: toolbox.onTapFavorites,
            )),
      if (!toolbox.isGroupChat && call != null)
        _ToolboxAction(
            'call',
            ToolboxItemInfo(
              text: StrRes.toolboxCall,
              icon: '',
              onTap: () => Permissions.cameraAndMicrophone(call),
            )),
      if (toolbox.onTapCard != null)
        _ToolboxAction(
            'card',
            ToolboxItemInfo(
              text: StrRes.toolboxCard,
              icon: '',
              onTap: toolbox.onTapCard,
            )),
      if (toolbox.onTapFile != null)
        _ToolboxAction(
            'file',
            ToolboxItemInfo(
              text: StrRes.file,
              icon: '',
              onTap: toolbox.onTapFile,
            )),
      if (toolbox.onTapRedPacket != null)
        _ToolboxAction(
            'red-packet',
            ToolboxItemInfo(
              text: StrRes.fundPacket,
              icon: '',
              onTap: toolbox.onTapRedPacket,
            )),
      if (toolbox.onTapTransfer != null)
        _ToolboxAction(
            'transfer',
            ToolboxItemInfo(
              text: toolbox.isGroupChat
                  ? StrRes.fundGroupTransfer
                  : StrRes.fundTransfer,
              icon: '',
              onTap: toolbox.onTapTransfer,
            )),
      for (var index = 0; index < toolbox.extraItems.length; index++)
        _ToolboxAction(toolbox.extraItems[index].id ?? 'extra-$index',
            toolbox.extraItems[index]),
      if (toolbox.onTapRecord != null)
        _ToolboxAction(
            'record',
            ToolboxItemInfo(
              text: StrRes.voiceCapture,
              icon: '',
              symbol: Icons.mic_none,
              onTap: toolbox.onTapRecord,
            )),
      if (toolbox.onTapAudio != null)
        _ToolboxAction(
            'audio',
            ToolboxItemInfo(
              text: StrRes.voice,
              icon: '',
              symbol: Icons.audio_file_outlined,
              onTap: toolbox.onTapAudio,
            )),
      if (toolbox.onTapLocation != null)
        _ToolboxAction(
            'location',
            ToolboxItemInfo(
              text: StrRes.location,
              icon: '',
              symbol: Icons.location_on_outlined,
              onTap: toolbox.onTapLocation,
            )),
      if (toolbox.onTapFormattedText != null)
        _ToolboxAction(
            'formatted-text',
            ToolboxItemInfo(
              text: 'sdkRichText'.tr,
              icon: '',
              symbol: Icons.text_fields,
              onTap: toolbox.onTapFormattedText,
            )),
      if (toolbox.onTapEmoji != null)
        _ToolboxAction(
            'emoji',
            ToolboxItemInfo(
              text: StrRes.emoji,
              icon: '',
              symbol: Icons.emoji_emotions_outlined,
              onTap: toolbox.onTapEmoji,
            )),
    ];
  }

  @override
  void didUpdateWidget(covariant ChatToolBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count =
        (_actions(widget).length / ChatToolboxTokens.itemsPerPage).ceil();
    if (_page >= count) {
      // A permission update may remove the page currently being viewed.
      _page = 0;
      final previous = _pageController;
      _pageController = PageController();
      previous.dispose();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(widget);
    final pageCount = (actions.length / ChatToolboxTokens.itemsPerPage).ceil();
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      key: const ValueKey('chat-toolbox-panel'),
      height: ChatToolboxTokens.panelHeight + safeBottom,
      decoration: BoxDecoration(
        color: ChatToolboxTokens.panelBackground(context),
        border: Border(
            top: BorderSide(
          width: ChatToolboxTokens.dividerWidth,
          color: ChatToolboxTokens.dividerColor(context),
        )),
      ),
      padding: EdgeInsets.only(
        top: ChatToolboxTokens.panelPadding,
        left: ChatToolboxTokens.panelPadding,
        right: ChatToolboxTokens.panelPadding,
        bottom: safeBottom,
      ),
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: pageCount > 1
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: pageCount,
              onPageChanged: (page) {
                if (mounted && _page != page) setState(() => _page = page);
              },
              itemBuilder: (context, page) {
                final start = page * ChatToolboxTokens.itemsPerPage;
                final items = actions
                    .skip(start)
                    .take(ChatToolboxTokens.itemsPerPage)
                    .toList(growable: false);
                return ChatToolboxGrid(
                  page: page,
                  labels: items.map((action) => action.item.text).toList(),
                  items: [
                    for (final action in items)
                      (width, height) => ChatToolboxTile(
                            id: action.id,
                            text: action.item.text,
                            width: width,
                            height: height,
                            onTap: action.item.onTap == null
                                ? null
                                : () => action.item.onTap!(),
                            icon: ChatToolboxIcon(
                              id: action.id,
                              asset: action.item.icon,
                              symbol: action.item.symbol,
                              enabled: action.item.onTap != null,
                            ),
                          ),
                  ],
                );
              },
            ),
          ),
          if (pageCount > 1)
            Padding(
              padding: const EdgeInsets.only(
                  bottom: ChatToolboxTokens.indicatorBottom),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < pageCount; index++)
                    Container(
                      key: ValueKey('chat-toolbox-indicator-$index'),
                      width: ChatToolboxTokens.indicatorSize,
                      height: ChatToolboxTokens.indicatorSize,
                      margin: const EdgeInsets.symmetric(
                          horizontal: ChatToolboxTokens.indicatorGap),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index == _page
                            ? AppTokens.accent
                            : ChatToolboxTokens.labelColor(context).withValues(
                                alpha:
                                    ChatToolboxTokens.inactiveIndicatorOpacity),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolboxAction {
  const _ToolboxAction(this.id, this.item);
  final String id;
  final ToolboxItemInfo item;
}

class ToolboxItemInfo {
  String text;
  String icon;
  IconData? symbol;
  Function()? onTap;
  String? id;

  ToolboxItemInfo(
      {required this.text,
      required this.icon,
      this.onTap,
      this.symbol,
      this.id});
}
