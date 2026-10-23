import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'group_personalization.dart';
import 'group_personalization_style.dart';

/// Wraps at large text sizes and retains native selection semantics.
class GroupIconPositionPicker extends StatelessWidget {
  const GroupIconPositionPicker(
      {super.key, required this.value, this.onChanged});

  final GroupIconPosition value;
  final ValueChanged<GroupIconPosition>? onChanged;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(
          spacing: AppTokens.s2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('图标位置', style: Theme.of(context).textTheme.bodyMedium),
            for (final position in GroupIconPosition.values)
              _option(context, position),
          ],
        ),
      );

  Widget _option(BuildContext context, GroupIconPosition position) {
    final selected = value == position;
    final label = position == GroupIconPosition.before ? '昵称前' : '昵称后';
    final theme = Theme.of(context);
    final enabled = onChanged != null;
    final tap = enabled ? () => onChanged!(position) : null;
    return Semantics(
      label: label,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      onTap: tap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: tap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: kMinInteractiveDimension),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: !enabled
                      ? theme.disabledColor
                      : selected
                          ? GroupPersonalizationStyle.blue
                          : theme.colorScheme.outlineVariant,
                ),
                const SizedBox(width: AppTokens.s2),
                Text(label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: !enabled
                          ? theme.disabledColor
                          : selected
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                    )),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
