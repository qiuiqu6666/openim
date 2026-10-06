import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../presence/contact_presence_policy.dart';
import '../../presence_label.dart';
import '../../presence_store.dart';
import 'contact_card_picker_tokens.dart';
import '../../../official_account/widgets/official_account_name_label.dart';

class ContactCardFriendRow extends StatelessWidget {
  const ContactCardFriendRow({
    super.key,
    required this.friend,
    required this.onTap,
    this.presence,
    this.starred = false,
  });

  final ISUserInfo friend;
  final VoidCallback? onTap;
  final UserPresence? presence;
  final bool starred;

  @override
  Widget build(BuildContext context) {
    final showPresence = FriendDisplayPreferences.showOnlineStatus;
    final displayPresence = ContactPresencePolicy.resolve(
      userID: friend.userID,
      ex: friend.ex,
      presence: presence,
    );
    return Material(
      color: ContactCardPickerTokens.rowBackground(context),
      child: InkWell(
        key: ValueKey('contact-card-friend-${friend.userID}'),
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Font metrics can round above the reference's calculated height.
          // Keep its minimum while allowing the real text block to grow.
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: ContactCardPickerTokens.rowHeight(context) -
                  ContactCardPickerTokens.dividerThickness,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ContactCardPickerTokens.horizontalPadding,
                vertical: ContactCardPickerTokens.verticalPadding,
              ),
              child: Row(children: [
                Stack(clipBehavior: Clip.none, children: [
                  AvatarView(
                    width: ContactCardPickerTokens.avatarSize,
                    height: ContactCardPickerTokens.avatarSize,
                    isCircle: true,
                    url: friend.faceURL,
                    text: friend.showName,
                  ),
                  if (showPresence && displayPresence?.displayOnline == true)
                    Positioned(
                      right: ContactCardPickerTokens.onlineDotOffset,
                      bottom: ContactCardPickerTokens.onlineDotOffset,
                      child: Container(
                        key: ValueKey('contact-card-online-${friend.userID}'),
                        width: ContactCardPickerTokens.onlineDotSize,
                        height: ContactCardPickerTokens.onlineDotSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ContactCardPickerTokens.onlineColor,
                          border: Border.all(
                            color: AppTokens.onAccent,
                            width: ContactCardPickerTokens.onlineDotBorder,
                          ),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(width: ContactCardPickerTokens.avatarTextGap),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OfficialAccountNameLabel(
                          name: friend.showName,
                          userID: friend.userID,
                          ex: friend.ex,
                          style: ContactCardPickerTokens.titleStyle(context)),
                      if (showPresence) ...[
                        const SizedBox(height: ContactCardPickerTokens.textGap),
                        if (displayPresence != null)
                          PresenceLabel(
                            key: ValueKey(
                                'contact-card-presence-${friend.userID}'),
                            presence: displayPresence,
                            textStyle:
                                ContactCardPickerTokens.subtitleStyle(context),
                          )
                        else
                          SizedBox(
                            height: MediaQuery.textScalerOf(context).scale(
                                    ContactCardPickerTokens.subtitleSize) *
                                ContactCardPickerTokens.lineHeight,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                key: ValueKey(
                                    'contact-card-presence-loading-${friend.userID}'),
                                width: ContactCardPickerTokens
                                    .presenceSkeletonWidth,
                                height: ContactCardPickerTokens
                                    .presenceSkeletonHeight,
                                decoration: BoxDecoration(
                                  color:
                                      ContactCardPickerTokens.secondary(context)
                                          .withValues(
                                              alpha: ContactCardPickerTokens
                                                  .presenceSkeletonOpacity),
                                  borderRadius: BorderRadius.circular(
                                      ContactCardPickerTokens
                                          .presenceSkeletonRadius),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                if (starred)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: ContactCardPickerTokens.starGap),
                    child: Tooltip(
                      message: 'starredFriend'.tr,
                      child: const Icon(Icons.star,
                          size: ContactCardPickerTokens.starSize,
                          color: ContactCardPickerTokens.starColor),
                    ),
                  ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
                left: ContactCardPickerTokens.horizontalPadding +
                    ContactCardPickerTokens.avatarSize +
                    ContactCardPickerTokens.avatarTextGap),
            child: SizedBox(
              height: ContactCardPickerTokens.dividerThickness,
              child: ColoredBox(
                  color: ContactCardPickerTokens.divider(context),
                  child: const SizedBox(width: double.infinity)),
            ),
          ),
        ]),
      ),
    );
  }
}
