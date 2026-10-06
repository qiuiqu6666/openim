import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../mine/settings/widgets/settings_widgets.dart';
import '../chat_setup_tokens.dart';

/// Member actions keep the same profile and preselected create-group routes.
class ChatSetupMembersCard extends StatelessWidget {
  const ChatSetupMembersCard({
    super.key,
    required this.conversation,
    required this.onViewProfile,
    required this.onAddMember,
  });

  final ConversationInfo conversation;
  final VoidCallback onViewProfile;
  final VoidCallback onAddMember;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final name = conversation.showName ?? '';
    return SettingsGroup(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.s5, AppTokens.s2, AppTokens.s5, AppTokens.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onViewProfile,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    minHeight: ChatSetupTokens.memberHeaderHeight),
                child: Row(children: [
                  Expanded(
                    child: Text('chatMembersTitle'.tr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTokens.textPrimary(dark: dark),
                            fontSize: ChatSetupTokens.memberTitleFontSize)),
                  ),
                  const SizedBox(width: AppTokens.s3),
                  Text('oneChatMember'.tr,
                      style: TextStyle(
                          color: AppTokens.textSecondary(dark: dark),
                          fontSize: AppTokens.captionFontSize)),
                  const SizedBox(width: AppTokens.s2),
                  Icon(Icons.chevron_right_rounded,
                      size: ChatSetupTokens.memberChevronSize,
                      color: AppTokens.textSecondary(dark: dark)),
                ]),
              ),
            ),
            const SizedBox(height: AppTokens.s2),
            Wrap(
              spacing: AppTokens.s4,
              runSpacing: AppTokens.s4,
              children: [
                _MemberAction(
                  key: const ValueKey('chat-setup-member-profile'),
                  label: name,
                  onTap: onViewProfile,
                  child: AvatarView(
                    width: ChatSetupTokens.memberAvatarSize,
                    height: ChatSetupTokens.memberAvatarSize,
                    text: name,
                    url: conversation.faceURL,
                  ),
                ),
                _MemberAction(
                  key: const ValueKey('chat-setup-add-member'),
                  label: 'addChatMember'.tr,
                  onTap: onAddMember,
                  child: Container(
                    width: ChatSetupTokens.memberAvatarSize,
                    height: ChatSetupTokens.memberAvatarSize,
                    decoration: BoxDecoration(
                      color: AppTokens.background(dark: dark),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTokens.border(dark: dark)),
                    ),
                    child: Icon(Icons.add_rounded,
                        color: AppTokens.textSecondary(dark: dark),
                        size: ChatSetupTokens.addIconSize),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ]);
  }
}

class _MemberAction extends StatelessWidget {
  const _MemberAction({
    super.key,
    required this.label,
    required this.child,
    required this.onTap,
  });

  final String label;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTokens.rMd),
            child: SizedBox(
              width: MediaQuery.textScalerOf(context).scale(1) >
                      ChatSetupTokens.largeTextThreshold
                  ? ChatSetupTokens.largeTextMemberWidth
                  : ChatSetupTokens.memberWidth,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ExcludeSemantics(child: child),
                const SizedBox(height: AppTokens.s3),
                ExcludeSemantics(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      maxLines: MediaQuery.textScalerOf(context).scale(1) >
                              ChatSetupTokens.largeTextThreshold
                          ? 2
                          : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTokens.textSecondary(
                            dark: settingsIsDark(context)),
                        fontSize: AppTokens.captionFontSize,
                        height: ChatSetupTokens.memberLabelHeight,
                      )),
                ),
              ]),
            ),
          ),
        ),
      );
}
