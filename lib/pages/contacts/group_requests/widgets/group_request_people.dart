import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../request_history/presentation/request_history_labels.dart';
import '../../request_history/presentation/request_history_style.dart';

/// Inline profile links preserve the original single-line notice layout.
class GroupRequestPeople extends StatefulWidget {
  const GroupRequestPeople(
      {super.key,
      required this.applicant,
      required this.groupName,
      this.inviter,
      this.onApplicant,
      this.onInviter});
  final String applicant, groupName;
  final String? inviter;
  final VoidCallback? onApplicant, onInviter;

  @override
  State<GroupRequestPeople> createState() => _GroupRequestPeopleState();
}

class _GroupRequestPeopleState extends State<GroupRequestPeople> {
  final _applicantTap = TapGestureRecognizer();
  final _inviterTap = TapGestureRecognizer();

  @override
  void dispose() {
    _applicantTap.dispose();
    _inviterTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _applicantTap.onTap = widget.onApplicant;
    _inviterTap.onTap = widget.onInviter;
    final template = RequestHistoryLabels.groupContent(
        '{applicant}', '{group}', widget.inviter == null ? null : '{inviter}');
    final spans = <InlineSpan>[];
    for (final match in RegExp(r'\{applicant\}|\{inviter\}|\{group\}|[^{}]+')
        .allMatches(template)) {
      final token = match.group(0)!;
      final name = switch (token) {
        '{applicant}' => widget.applicant,
        '{inviter}' => widget.inviter ?? '',
        '{group}' => widget.groupName,
        _ => token,
      };
      final recognizer = switch (token) {
        '{applicant}' when widget.onApplicant != null => _applicantTap,
        '{inviter}' when widget.onInviter != null => _inviterTap,
        _ => null,
      };
      spans.add(TextSpan(
          text: name,
          recognizer: recognizer,
          style: recognizer == null
              ? null
              : const TextStyle(color: AppTokens.accent)));
    }
    return Text.rich(TextSpan(children: spans),
        style: RequestHistoryStyle.subtitle(context),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis);
  }
}
