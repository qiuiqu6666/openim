import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'auth_copy.dart';
import 'auth_reference.dart';

/// Shared phone/email choice for registration, recovery and code login.
class AuthIdentitySelector extends StatelessWidget {
  const AuthIdentitySelector({
    super.key,
    required this.email,
    this.action = '',
    this.account = false,
    this.showAccount = false,
    this.onAccountSelected,
    required this.onChanged,
  });
  final bool account;
  final bool showAccount;
  final VoidCallback? onAccountSelected;
  final String action;
  final bool email;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AuthReferenceTokens.fieldGap),
        child: Row(
          children: [
            for (final value in [
              0,
              1,
              if (showAccount || onAccountSelected != null || account) 2
            ])
              Expanded(
                  child: Semantics(
                selected: value ==
                    (account
                        ? 2
                        : email
                            ? 1
                            : 0),
                child: TextButton(
                  key: ValueKey(
                      'auth-identity-${value == 2 ? "account" : value == 1 ? "email" : "phone"}'),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    overlayColor: Colors.transparent,
                    splashFactory: NoSplash.splashFactory,
                    shape: const RoundedRectangleBorder(),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    visualDensity: VisualDensity.standard,
                    minimumSize: const Size(
                        kMinInteractiveDimension, kMinInteractiveDimension),
                    foregroundColor: value ==
                            (account
                                ? 2
                                : email
                                    ? 1
                                    : 0)
                        ? AuthReferenceTokens.brand500
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: value == 2
                      ? onAccountSelected
                      : onChanged == null
                          ? null
                          : () => onChanged!(value == 1),
                  child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                          border: value ==
                                  (account
                                      ? 2
                                      : email
                                          ? 1
                                          : 0)
                              ? Border(
                                  bottom: BorderSide(
                                      color: AuthReferenceTokens.brand500))
                              : null),
                      child: Text(
                          '${value == 2 ? authText("用户ID", "User ID") : value == 1 ? authText(AppCopy.text('邮箱'), "Email") : authText(AppCopy.text('手机'), "Phone")}$action',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: AuthReferenceTokens.tabSize))),
                ),
              )),
          ],
        ),
      );
}
