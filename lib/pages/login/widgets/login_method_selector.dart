import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../widgets/auth/auth_tokens.dart';
import '../login_logic.dart';

/// Three login identities presented as a single segmented control.
class LoginMethodSelector extends StatelessWidget {
  const LoginMethodSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final LoginType selected;
  final ValueChanged<LoginType>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showIcons = MediaQuery.textScalerOf(context).scale(14) < 20;
    return Material(
      color: AuthTokens.welcomeSurface(context),
      borderRadius: BorderRadius.circular(AuthTokens.touchTarget),
      child: Row(
        children: LoginType.values.map((type) {
          final active = type == selected;
          final foreground =
              active ? AuthTokens.link(context) : colors.onSurfaceVariant;
          return Expanded(
            child: Semantics(
              selected: active,
              button: true,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AuthTokens.touchTarget),
                child: InkWell(
                  key: ValueKey('login-method-${type.name}'),
                  borderRadius: BorderRadius.circular(AuthTokens.touchTarget),
                  onTap: onSelected == null
                      ? null
                      : () {
                          if (!active) onSelected!(type);
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.s2),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: active ? colors.surface : Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(AuthTokens.touchTarget),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            minHeight: AuthTokens.touchTarget - AppTokens.s3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.s3, vertical: AppTokens.s3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (showIcons) ...[
                                ExcludeSemantics(
                                  child: Icon(_icon(type),
                                      size: AppTokens.s6, color: foreground),
                                ),
                                const SizedBox(width: AppTokens.s3),
                              ],
                              Flexible(
                                child: Text(type.name,
                                    textAlign: TextAlign.center,
                                    style: AuthTokens.body(context).copyWith(
                                        color: foreground,
                                        height: 1.3,
                                        fontWeight: active
                                            ? FontWeight.w600
                                            : FontWeight.w400)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static IconData _icon(LoginType type) => switch (type) {
        LoginType.phone => Icons.phone_iphone_rounded,
        LoginType.email => Icons.mail_outline_rounded,
        LoginType.account => Icons.person_outline_rounded,
      };
}
