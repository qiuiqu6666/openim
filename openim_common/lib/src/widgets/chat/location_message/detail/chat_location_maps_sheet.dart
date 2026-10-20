import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:map_launcher/map_launcher.dart';
import '../../../../res/app_tokens.dart';
import 'chat_location_detail_chrome.dart';
import 'chat_location_detail_labels.dart';
import 'chat_location_detail_tokens.dart';

/// Only installed, supported applications are supplied by the launcher.
class ChatLocationMapsSheet extends StatelessWidget {
  const ChatLocationMapsSheet({super.key, required this.maps});
  final List<AvailableMap> maps;

  @override
  Widget build(BuildContext context) {
    final labels = ChatLocationDetailLabels.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s3),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ChatLocationDetailTokens.maxCardWidth,
            maxHeight: MediaQuery.sizeOf(context).height * .7,
          ),
          child: ChatLocationDetailSurface(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.s5),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  ChatLocationDetailControl(
                    label: MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: Icons.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: AppTokens.s3),
                  Expanded(
                    child: Text(
                      labels.text(
                          '使用其它应用打开…', '使用其他 App 開啟…', 'Open in another app…'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: ChatLocationDetailTokens.controlSize),
                ]),
                const SizedBox(height: AppTokens.s8),
                if (maps.isNotEmpty)
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppTokens.s5,
                    runSpacing: AppTokens.s5,
                    children: [
                      for (var i = 0; i < maps.length; i++)
                        SizedBox(
                          width: ChatLocationDetailTokens.mapAppWidth,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context, i),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ExcludeSemantics(
                                    child: SvgPicture.asset(
                                      maps[i].icon,
                                      width:
                                          ChatLocationDetailTokens.mapAppIcon,
                                      height:
                                          ChatLocationDetailTokens.mapAppIcon,
                                    ),
                                  ),
                                  const SizedBox(height: AppTokens.s3),
                                  Text(maps[i].mapName,
                                      textAlign: TextAlign.center),
                                ]),
                          ),
                        ),
                    ],
                  )
                else ...[
                  Text(labels.text('未检测到可用的地图应用', '未偵測到可用的地圖 App',
                      'No supported map apps found')),
                  const SizedBox(height: AppTokens.s3),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context, -1),
                    icon: const Icon(Icons.open_in_browser),
                    label: Text(labels.browser),
                  ),
                ],
                const SizedBox(height: AppTokens.s8),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
