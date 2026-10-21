import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../select_contacts/contact_card/contact_card_picker_tokens.dart';

/// The count belongs to the current tab or search result, not group members.
class GroupCountFooter extends StatelessWidget {
  const GroupCountFooter(
      {super.key, required this.count, this.channels = false});
  final bool channels;

  final int count;

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.s5, AppTokens.s5, AppTokens.s5, AppTokens.s7),
        child: Center(
          child: Text(
            channels
                ? (chinese
                    ? AppCopy.format('共 {#0} 个频道', [count])
                    : '$count channels')
                : chinese
                    ? AppCopy.format('共 {#0} 个群聊', [count])
                    : '$count group ${count == 1 ? 'chat' : 'chats'}',
            textAlign: TextAlign.center,
            style: ContactCardPickerTokens.subtitleStyle(context),
          ),
        ),
      ),
    );
  }
}
