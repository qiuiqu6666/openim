import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// The optional group member count is read from OpenIM, not guessed from history.
class ConversationPeekSubtitle extends StatefulWidget {
  const ConversationPeekSubtitle({
    super.key,
    required this.conversation,
    required this.isActive,
  });
  final ConversationInfo conversation;
  final bool Function() isActive;

  @override
  State<ConversationPeekSubtitle> createState() =>
      _ConversationPeekSubtitleState();
}

class _ConversationPeekSubtitleState extends State<ConversationPeekSubtitle> {
  int? _memberCount;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final groupID = widget.conversation.groupID;
    if (groupID == null || groupID.isEmpty || !widget.isActive()) return;
    try {
      final groups = await OpenIM.iMManager.groupManager
          .getGroupsInfo(groupIDList: [groupID]);
      if (!mounted || !widget.isActive()) return;
      for (final group in groups) {
        if (group.groupID == groupID && group.memberCount != null) {
          setState(() => _memberCount = group.memberCount);
          break;
        }
      }
    } catch (_) {
      // An optional subtitle failure must not block history or menu actions.
    }
  }

  @override
  Widget build(BuildContext context) => _memberCount == null
      ? const SizedBox.shrink()
      : Text(Localizations.localeOf(context).languageCode == 'zh'
          ? '$_memberCount人'
          : '$_memberCount members');
}
