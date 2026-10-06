import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

class LiveWatchingBottomBar extends StatelessWidget {
  const LiveWatchingBottomBar(
      {super.key,
      required this.roomName,
      required this.description,
      required this.anchorID,
      this.anchorFaceURL = '',
      this.onFullscreen,
      this.fullscreen = false});
  final String roomName, description, anchorID, anchorFaceURL;
  final VoidCallback? onFullscreen;
  final bool fullscreen;
  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox.square(
            dimension: 44,
            child: ClipOval(
                child: AvatarView(
                    width: 44,
                    height: 44,
                    url: anchorFaceURL,
                    text: anchorID))),
        const SizedBox(width: 8),
        Expanded(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(roomName.isEmpty ? '群直播' : roomName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      shadows: [
                        Shadow(color: Color(0x66000000), blurRadius: 4)
                      ])),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFE8E8E8),
                        fontSize: 12,
                        height: 1.2,
                        shadows: [
                          Shadow(color: Color(0x66000000), blurRadius: 4)
                        ]))
              ],
            ])),
        const SizedBox(width: 8),
        ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .4),
            child: Material(
                color: Colors.transparent,
                shape: const StadiumBorder(
                    side: BorderSide(color: Colors.white, width: 1)),
                child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: onFullscreen,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                              child: Text(fullscreen ? '退出全屏' : '全屏观看',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600))),
                          const SizedBox(width: 2),
                          const Icon(Icons.north_east,
                              size: 14, color: Colors.white),
                        ]))))),
      ]);
}
