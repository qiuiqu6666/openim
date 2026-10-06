import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'presence_store.dart';

class PresenceLabel extends StatelessWidget {
  const PresenceLabel({super.key, required this.presence, this.textStyle});
  final UserPresence presence;
  final TextStyle? textStyle;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: FriendDisplayPreferences.changes,
      builder: (context, _) => !FriendDisplayPreferences.showOnlineStatus
          ? const SizedBox.shrink()
          : Text(presence.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle ?? Styles.ts_8E9AB0_12sp));
}
