import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

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

  @override
  State<ChatToolBox> createState() => _ChatToolBoxState();
}

class _ChatToolBoxState extends State<ChatToolBox> {
  int _page = 0;
  static const _itemsPerPage = 8;

  @override
  Widget build(BuildContext context) {
    final onTapAlbum = widget.onTapAlbum;
    final onTapCall = widget.onTapCall;
    final onTapCard = widget.onTapCard;
    final onTapAudio = widget.onTapAudio;
    final onTapFile = widget.onTapFile;
    final onTapCamera = widget.onTapCamera;
    final onTapRecord = widget.onTapRecord;
    final onTapLocation = widget.onTapLocation;
    final onTapEmoji = widget.onTapEmoji;
    final onTapFormattedText = widget.onTapFormattedText;
    final items = [
      if (onTapFormattedText != null)
        ToolboxItemInfo(
            text: 'sdkRichText'.tr,
            icon: '',
            symbol: Icons.text_fields,
            onTap: onTapFormattedText),
      if (onTapLocation != null)
        ToolboxItemInfo(
            text: StrRes.location,
            icon: '',
            symbol: Icons.location_on_outlined,
            onTap: onTapLocation),
      if (onTapEmoji != null)
        ToolboxItemInfo(
            text: StrRes.emoji,
            icon: '',
            symbol: Icons.emoji_emotions_outlined,
            onTap: onTapEmoji),
      if (onTapCamera != null)
        ToolboxItemInfo(
            text: StrRes.toolboxCamera,
            icon: '',
            symbol: Icons.camera_alt_outlined,
            onTap: () => Permissions.cameraAndMicrophone(onTapCamera)),
      if (onTapRecord != null)
        ToolboxItemInfo(
            text: StrRes.voiceCapture,
            icon: '',
            symbol: Icons.mic_none,
            onTap: onTapRecord),
      if (onTapAudio != null)
        ToolboxItemInfo(
            text: StrRes.voice,
            icon: '',
            symbol: Icons.audio_file_outlined,
            onTap: onTapAudio),
      if (onTapFile != null)
        ToolboxItemInfo(
            text: StrRes.file,
            icon: '',
            symbol: Icons.insert_drive_file_outlined,
            onTap: onTapFile),
      ToolboxItemInfo(
        text: StrRes.toolboxAlbum,
        icon: ImageRes.toolboxAlbum,
        onTap: () => Permissions.photos(onTapAlbum),
      ),
      if (onTapCall != null)
        ToolboxItemInfo(
          text: StrRes.toolboxCall,
          icon: ImageRes.toolboxCall,
          onTap: () => Permissions.cameraAndMicrophone(onTapCall),
        ),
      if (onTapCard != null)
        ToolboxItemInfo(
          text: StrRes.toolboxCard,
          icon: ImageRes.toolboxCard,
          onTap: onTapCard,
        ),
    ];

    final pageCount = (items.length / _itemsPerPage).ceil();
    return Container(
      color: Styles.c_F0F2F6,
      height: 224.h,
      child: Column(children: [
        Expanded(
            child: PageView.builder(
                itemCount: pageCount,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (_, page) => LayoutBuilder(
                    builder: (_, constraints) => GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          primary: false,
                          itemCount: (items.length - page * _itemsPerPage)
                              .clamp(0, _itemsPerPage),
                          padding: EdgeInsets.only(
                            left: 16.w,
                            right: 16.w,
                            top: 6.h,
                            bottom: 6.h,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisExtent:
                                (constraints.maxHeight - 12.h - 2.h) / 2,
                            crossAxisSpacing: 10.w,
                            mainAxisSpacing: 2.h,
                          ),
                          itemBuilder: (_, index) {
                            final item =
                                items.elementAt(page * _itemsPerPage + index);
                            return _buildItemView(
                              icon: item.icon,
                              symbol: item.symbol,
                              text: item.text,
                              onTap: item.onTap,
                            );
                          },
                        )))),
        SizedBox(
            height: 20.h,
            child: pageCount > 1
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var index = 0; index < pageCount; index++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index == _page
                                ? Styles.c_0089FF
                                : Styles.c_8E9AB0.withValues(alpha: .35)),
                      ),
                  ])
                : null),
      ]),
    );
  }

  Widget _buildItemView({
    required String text,
    required String icon,
    IconData? symbol,
    Function()? onTap,
  }) =>
      Column(
        children: [
          if (symbol != null)
            SizedBox(
                width: 58.w,
                height: 58.h,
                child: IconButton.filledTonal(
                    onPressed: onTap,
                    icon: Icon(symbol, color: Styles.c_0C1C33),
                    tooltip: text))
          else
            icon.toImage
              ..width = 58.w
              ..height = 58.h
              ..onTap = onTap,
          10.verticalSpace,
          text.toText
            ..style = Styles.ts_0C1C33_12sp
            ..maxLines = 1
            ..overflow = TextOverflow.ellipsis,
        ],
      );
}

class ToolboxItemInfo {
  String text;
  String icon;
  IconData? symbol;
  Function()? onTap;

  ToolboxItemInfo(
      {required this.text, required this.icon, this.onTap, this.symbol});
}
