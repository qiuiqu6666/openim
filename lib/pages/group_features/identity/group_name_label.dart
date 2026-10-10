import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../data/group_feature_store.dart';
import '../models/group_game_type.dart';

/// Public group type affects the name only, never member names or permissions.
Color? groupNameColor(BuildContext context, GroupGameType type) {
  if (type != GroupGameType.sangong && type != GroupGameType.markSix) {
    return null;
  }
  return Theme.of(context).brightness == Brightness.dark
      ? AppTokens.paymentErrorDark
      : AppTokens.danger;
}

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
    if (store == null) return _name(context, GroupGameType.fromEx(ex));
    return ListenableBuilder(
      listenable: store!,
      builder: (context, _) => _name(context, store!.gameType(groupID ?? '')),
    );
  }

  Widget _name(BuildContext context, GroupGameType type) {
    final color = groupNameColor(context, type);
    return Text(name,
        maxLines: maxLines,
        overflow: overflow,
        style: color == null
            ? style
            : (style ?? const TextStyle()).copyWith(color: color));
  }
}
