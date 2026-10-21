import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../data/group_feature_store.dart';
import '../personalization/group_personalization.dart';
import '../personalization/group_personalization_artwork.dart';

/// Reuses account-scoped metadata. Rendering a name never starts a request.
class GroupNameLabel extends StatelessWidget {
  const GroupNameLabel({
    super.key,
    required this.name,
    this.groupID,
    this.ex,
    this.store,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String name;
  final String? groupID, ex;
  final GroupFeatureStore? store;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    if (store == null) return _name(context, ex);
    return ListenableBuilder(
      listenable: store!,
      builder: (context, _) =>
          _name(context, store!.cachedGroupInfo(groupID ?? '')?.ex ?? ex),
    );
  }

  Widget _name(BuildContext context, String? metadata) {
    final appearance = GroupPersonalization.fromEx(metadata);
    final color = appearance.color == null ? null : Color(appearance.color!);
    final text = Text(name,
        maxLines: maxLines,
        overflow: overflow,
        style: color == null
            ? style
            : (style ?? const TextStyle()).copyWith(color: color));
    if (appearance.iconUrl == null && appearance.iconKey == null) return text;
    final size =
        (style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 16);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ExcludeSemantics(
          child: appearance.iconKey != null
              ? GroupPersonalizationArtwork(
                  iconKey: appearance.iconKey!, size: size)
              : Image.network(appearance.iconUrl!,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      SizedBox.square(dimension: size))),
      const SizedBox(width: AppTokens.s2),
      Flexible(child: text),
    ]);
  }
}
