import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

class ChannelSettingsRow extends StatelessWidget {
  const ChannelSettingsRow(
      {super.key,
      required this.title,
      this.value,
      this.onTap,
      this.danger = false});
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Expanded(
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 16,
                            color: danger
                                ? Theme.of(context).colorScheme.error
                                : null))),
                if (value != null)
                  Expanded(
                      child: Text(value!,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              color: AppTokens.textSecondary(
                                  dark: Theme.of(context).brightness ==
                                      Brightness.dark)))),
                if (onTap != null && !danger) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.keyboard_arrow_right,
                      color: AppTokens.textSecondary(
                          dark:
                              Theme.of(context).brightness == Brightness.dark)),
                ],
              ]))));
}

class ChannelCaption extends StatelessWidget {
  const ChannelCaption(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s8, vertical: AppTokens.s3),
      child: Text(text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTokens.textSecondary(
                  dark: Theme.of(context).brightness == Brightness.dark))));
}
