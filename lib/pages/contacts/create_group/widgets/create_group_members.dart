import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../create_group_strings.dart';
import '../create_group_tokens.dart';

/// Selected SDK members and the existing member-picker and terms entry points.
/// The page owns the surrounding card and the selection state.
class CreateGroupMembers extends StatelessWidget {
  const CreateGroupMembers({
    super.key,
    required this.members,
    required this.onAddMembers,
    required this.onOpenTerms,
  });

  final List<UserInfo> members;
  final VoidCallback onAddMembers;
  final VoidCallback onOpenTerms;

  @override
  Widget build(BuildContext context) {
    final colors = CreateGroupTokens.of(context);
    final strings = CreateGroupStrings.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: CreateGroupTokens.memberGap,
              runSpacing: CreateGroupTokens.memberNameGap,
              children: [
                Text(strings.members(members.length),
                    style: TextStyle(
                        color: colors.title,
                        fontSize: CreateGroupTokens.sectionTitleSize,
                        fontWeight: FontWeight.w600)),
                TextButton.icon(
                  key: const ValueKey('create-group-add-members'),
                  onPressed: onAddMembers,
                  icon: const Icon(Icons.person_add_alt_1_outlined,
                      size: CreateGroupTokens.addIconSize),
                  label: Text(strings.addMembers),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.accent,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(
                        kMinInteractiveDimension, kMinInteractiveDimension),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTokens.s3),
        Wrap(
          spacing: CreateGroupTokens.memberGap,
          runSpacing: CreateGroupTokens.memberRunGap,
          children: [
            for (final member in members) _memberTile(member, colors.secondary),
            Semantics(
              button: true,
              label: strings.addMembers,
              onTap: onAddMembers,
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('create-group-add-member-tile'),
                onTap: onAddMembers,
                borderRadius: BorderRadius.circular(
                    CreateGroupTokens.memberItemWidth / 2),
                child: SizedBox(
                  width: CreateGroupTokens.memberItemWidth,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        minHeight: kMinInteractiveDimension),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: CreateGroupTokens.memberAvatarSize,
                          height: CreateGroupTokens.memberAvatarSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.addBorder),
                          ),
                          child: Icon(Icons.add_rounded, color: colors.accent),
                        ),
                        const SizedBox(height: CreateGroupTokens.memberNameGap),
                        Text(strings.addMemberTile,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: colors.secondary,
                                fontSize: CreateGroupTokens.memberNameSize)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: CreateGroupTokens.noticeGap),
        Semantics(
          button: true,
          label: strings.declaration,
          onTap: onOpenTerms,
          excludeSemantics: true,
          child: Material(
            color: colors.inset,
            borderRadius: BorderRadius.circular(CreateGroupTokens.insetRadius),
            child: InkWell(
              key: const ValueKey('create-group-terms'),
              onTap: onOpenTerms,
              borderRadius:
                  BorderRadius.circular(CreateGroupTokens.insetRadius),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: kMinInteractiveDimension),
                child: Padding(
                  padding:
                      const EdgeInsets.all(CreateGroupTokens.policyPadding),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined,
                          color: colors.accent,
                          size: CreateGroupTokens.policyIconSize),
                      const SizedBox(width: CreateGroupTokens.memberGap),
                      Expanded(
                        child: Text(strings.declaration,
                            style: TextStyle(
                                color: colors.secondary,
                                fontSize: CreateGroupTokens.policyTextSize,
                                height: 1.4)),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: colors.secondary,
                          size: CreateGroupTokens.chevronSize),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _memberTile(UserInfo member, Color textColor) {
    final name = member.nickname?.trim().isNotEmpty == true
        ? member.nickname!
        : member.userID ?? '';
    return SizedBox(
      width: CreateGroupTokens.memberItemWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: AvatarView(
              width: CreateGroupTokens.memberAvatarSize,
              height: CreateGroupTokens.memberAvatarSize,
              isCircle: true,
              url: member.faceURL,
              text: name,
            ),
          ),
          const SizedBox(height: CreateGroupTokens.memberNameGap),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: textColor,
                  fontSize: CreateGroupTokens.memberNameSize)),
        ],
      ),
    );
  }
}
