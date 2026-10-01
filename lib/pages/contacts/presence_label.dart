import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'presence_store.dart';

class PresenceLabel extends StatelessWidget {
  const PresenceLabel({super.key, required this.presence});
  final UserPresence presence;
  @override
  Widget build(BuildContext context) => Text(presence.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Styles.ts_8E9AB0_12sp);
}
