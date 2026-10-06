import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'favorite_detail_tokens.dart';

/// Detail actions share one thumb-friendly footer, with room for large text.
class FavoriteDetailFooter extends StatelessWidget {
  const FavoriteDetailFooter({
    super.key,
    required this.actions,
    this.pendingAction,
  });

  final List<Widget> actions;
  final Widget? pendingAction;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty && pendingAction == null) {
      return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.rMd));
    return ColoredBox(
      color: AppTokens.surface(dark: dark),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s5, vertical: AppTokens.s4),
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: FavoriteDetailTokens.contentMaxWidth),
              child: FilledButtonTheme(
                data: FilledButtonThemeData(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.accent,
                    foregroundColor: AppTokens.onAccent,
                    minimumSize:
                        const Size(0, FavoriteDetailTokens.actionHeight),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.s5, vertical: AppTokens.s4),
                    shape: shape,
                    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: AppTokens.secondaryFontSize,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                child: OutlinedButtonTheme(
                  data: OutlinedButtonThemeData(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTokens.accent,
                      minimumSize:
                          const Size(0, FavoriteDetailTokens.actionHeight),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.s5, vertical: AppTokens.s4),
                      side: BorderSide(color: AppTokens.border(dark: dark)),
                      shape: shape,
                    ),
                  ),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final stack = actions.length > 1 &&
                        (constraints.maxWidth <
                                FavoriteDetailTokens.stackedActionsWidth ||
                            MediaQuery.textScalerOf(context).scale(1) >
                                FavoriteDetailTokens.stackedTextScale);
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      if (pendingAction != null) pendingAction!,
                      if (stack)
                        Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var index = 0;
                                  index < actions.length;
                                  index++)
                                Padding(
                                    padding: EdgeInsets.only(
                                        top: index == 0 ? 0 : AppTokens.s3),
                                    child: actions[index]),
                            ])
                      else
                        Row(children: [
                          for (var index = 0;
                              index < actions.length;
                              index++) ...[
                            if (index > 0) const SizedBox(width: AppTokens.s4),
                            Expanded(child: actions[index]),
                          ],
                        ]),
                    ]);
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
