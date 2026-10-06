import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../contact_card/contact_card_picker_tokens.dart';

/// Contact selection keeps the shared navigation surface and back behavior.
class SelectContactsAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const SelectContactsAppBar({super.key, required String this.title})
      : search = null;

  const SelectContactsAppBar.search({super.key, required Widget this.search})
      : title = null;

  final String? title;
  final Widget? search;

  @override
  Size get preferredSize =>
      Size.fromHeight(NavigationGlassTokens.toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GlassAppBar(
      toolbarHeight: NavigationGlassTokens.toolbarHeight,
      backgroundColor: AppTokens.surface(dark: dark),
      centerTitle: search == null,
      leadingWidth: AppIconTokens.androidTouchTarget + AppTokens.s3,
      titleSpacing: search == null ? null : 0,
      leading: Center(
        child: SizedBox.square(
          dimension: AppIconTokens.androidTouchTarget,
          child: IconButton(
            key: const ValueKey('select-contacts-back'),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: AppIconTokens.large, color: AppTokens.accent),
          ),
        ),
      ),
      title: search ??
          Text(title!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ContactCardPickerTokens.headingStyle(context)),
      actions: search == null
          ? const [
              SizedBox(width: AppIconTokens.androidTouchTarget + AppTokens.s3),
            ]
          : const [
              SizedBox(width: ContactCardPickerTokens.horizontalPadding),
            ],
    );
  }
}
