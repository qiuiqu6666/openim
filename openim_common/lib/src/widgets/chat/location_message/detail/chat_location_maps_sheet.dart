import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:map_launcher/map_launcher.dart';
import '../../../../res/app_tokens.dart';
import 'chat_location_detail_labels.dart';
import 'chat_location_detail_tokens.dart';

/// Only installed, supported applications are supplied by the launcher.
class ChatLocationMapsSheet extends StatelessWidget {
  const ChatLocationMapsSheet({super.key, required this.maps});
  final List<AvailableMap> maps;

  @override
  Widget build(BuildContext context) {
    final labels = ChatLocationDetailLabels.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .7,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: AppTokens.surface(
              dark: Theme.of(context).brightness == Brightness.dark),
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ChatLocationDetailTokens.cardRadius)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.s5),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: const Icon(Icons.close),
                    constraints: const BoxConstraints.tightFor(
                        width: ChatLocationDetailTokens.controlSize,
                        height: ChatLocationDetailTokens.controlSize),
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
                  LayoutBuilder(builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth -
                            AppTokens.s3 *
                                (ChatLocationDetailTokens.mapAppColumns - 1)) /
                        ChatLocationDetailTokens.mapAppColumns;
                    return Wrap(
                      alignment: WrapAlignment.start,
                      spacing: AppTokens.s3,
                      runSpacing: AppTokens.s5,
                      children: [
                        for (var i = 0; i < maps.length; i++)
                          SizedBox(
                            width: itemWidth,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppTokens.s2,
                                      vertical: AppTokens.s3)),
                              onPressed: () => Navigator.pop(context, i),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ExcludeSemantics(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            AppTokens.rLg),
                                        child: SvgPicture.asset(
                                          maps[i].icon,
                                          width: ChatLocationDetailTokens
                                              .mapAppIcon,
                                          height: ChatLocationDetailTokens
                                              .mapAppIcon,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: AppTokens.s3),
                                    Text(maps[i].mapName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center),
                                  ]),
                            ),
                          ),
                      ],
                    );
                  })
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
