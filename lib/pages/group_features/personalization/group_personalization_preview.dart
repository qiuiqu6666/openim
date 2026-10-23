import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'group_personalization.dart';
import '../identity/group_name_label.dart';
import 'group_personalization_style.dart';

class GroupPersonalizationPreview extends StatelessWidget {
  const GroupPersonalizationPreview(
      {super.key,
      required this.name,
      this.avatarUrl,
      required this.appearance,
      required this.scale});
  final String name;
  final String? avatarUrl;
  final GroupPersonalization appearance;
  final double scale;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final avatarSize = 168 * scale;
    final avatar = AvatarView(
        url: avatarUrl,
        text: name,
        isGroup: true,
        isCircle: true,
        width: avatarSize,
        height: avatarSize);
    return ClipRRect(
        borderRadius: BorderRadius.circular(28 * scale),
        child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage(
                    GroupPersonalizationStyle.previewBackground),
                fit: BoxFit.fill,
                colorFilter: dark
                    ? const ColorFilter.mode(
                        GroupPersonalizationStyle.previewDarkOverlay,
                        BlendMode.srcATop)
                    : null,
              ),
            ),
            child: Container(
                constraints: BoxConstraints(minHeight: 314 * scale),
                padding: EdgeInsets.symmetric(
                    horizontal: 46 * scale, vertical: 44 * scale),
                child: Row(children: [
                  Transform.translate(
                      offset: Offset(0, 32 * scale),
                      child: ClipOval(child: avatar)),
                  SizedBox(width: 44 * scale),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 20 * scale, vertical: 9 * scale),
                            decoration: BoxDecoration(
                                color: GroupPersonalizationStyle.blue
                                    .withValues(alpha: .07),
                                borderRadius:
                                    BorderRadius.circular(60 * scale)),
                            child: Text('效果预览',
                                style: TextStyle(
                                    color: GroupPersonalizationStyle.blue,
                                    fontSize: 25 * scale))),
                        SizedBox(height: 18 * scale),
                        Padding(
                            padding:
                                EdgeInsetsDirectional.only(end: 130 * scale),
                            child: GroupNameLabel(
                                name: name,
                                ex: appearance.mergeInto(null),
                                maxLines: largeText ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 46 * scale,
                                    fontWeight: FontWeight.w700,
                                    color: appearance.color == null
                                        ? (dark
                                            ? Colors.white
                                            : GroupPersonalizationStyle.ink)
                                        : Color(appearance.color!)))),
                        SizedBox(height: 18 * scale),
                        Text('保存后，所有群成员都能看到群昵称颜色和图标。',
                            style: TextStyle(
                                fontSize: 25 * scale,
                                color: dark
                                    ? Colors.white70
                                    : const Color(0xFF596680),
                                height: 1.5)),
                      ])),
                ]))));
  }
}
