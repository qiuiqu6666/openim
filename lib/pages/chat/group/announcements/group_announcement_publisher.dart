import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/localization.dart';

/// Resolves the recorded publisher once per announcement sheet.
class GroupAnnouncementPublisher extends StatefulWidget {
  const GroupAnnouncementPublisher({super.key, required this.userID});
  final String userID;

  @override
  State<GroupAnnouncementPublisher> createState() => _PublisherState();
}

class _PublisherState extends State<GroupAnnouncementPublisher> {
  String? _name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final account = OpenIM.iMManager.userID;
      final users = await OpenIM.iMManager.userManager
          .getUsersInfo(userIDList: [widget.userID]);
      if (!mounted || OpenIM.iMManager.userID != account) return;
      for (final user in users) {
        if (user.userID == widget.userID &&
            user.nickname?.trim().isNotEmpty == true) {
          setState(() => _name = user.nickname!.trim());
          break;
        }
      }
    } catch (_) {
      // The recorded ID remains available offline or after account deletion.
    }
  }

  @override
  Widget build(BuildContext context) => Text(
        '${AppCopy.text('发布人')}：${_name ?? widget.userID}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}
