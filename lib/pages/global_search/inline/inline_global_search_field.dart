import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../chat/history_search/widgets/chat_history_search_bar.dart';

/// One mounted input for the feed, expansion, search and return transition.
class InlineGlobalSearchField extends StatelessWidget {
  const InlineGlobalSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.progress,
    required this.searching,
    required this.onOpen,
    required this.onCancel,
    required this.onSubmit,
    required this.fieldKey,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double progress;
  final bool searching;
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) => ChatHistorySearchBar(
        fieldKey: fieldKey,
        controller: controller,
        focusNode: focusNode,
        readOnly: !searching,
        onTap: searching ? null : onOpen,
        cancelProgress: progress,
        cancelColor: AppTokens.accent,
        hintText: StrRes.search,
        onChanged: (_) {}, // The active search controller owns input debounce.
        onSubmitted: (_) => onSubmit(),
        onCancel: onCancel,
      );
}
