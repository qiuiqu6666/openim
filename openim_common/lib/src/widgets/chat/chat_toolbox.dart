import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class ChatToolBox extends StatelessWidget {
  const ChatToolBox({
    super.key,
    this.onTapAlbum,
    this.onTapCall,
    this.onTapCard,
    this.onTapAudio,
    this.onTapFile,
    this.onTapCamera,
    this.onTapRecord,
  });
  final Function()? onTapAlbum;
  final Function()? onTapCall;
  final VoidCallback? onTapCard;
  final VoidCallback? onTapAudio;
  final VoidCallback? onTapFile;
  final VoidCallback? onTapCamera;
  final VoidCallback? onTapRecord;

  @override
  Widget build(BuildContext context) {
    final items = [
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

    return Container(
      color: Styles.c_F0F2F6,
      height: 224.h,
      child: GridView.builder(
        itemCount: items.length,
        padding: EdgeInsets.only(
          left: 16.w,
          right: 16.w,
          top: 6.h,
          bottom: 6.h,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 78.w / 105.h,
          crossAxisSpacing: 10.w,
          mainAxisSpacing: 2.h,
        ),
        itemBuilder: (_, index) {
          final item = items.elementAt(index);
          return _buildItemView(
            icon: item.icon,
            symbol: item.symbol,
            text: item.text,
            onTap: item.onTap,
          );
        },
      ),
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
          text.toText..style = Styles.ts_0C1C33_12sp,
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
