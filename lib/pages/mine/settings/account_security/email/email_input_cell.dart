import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';
import '../../widgets/settings_widgets.dart';

/// Settings-style form row; stacked at large text sizes to keep fields usable.
class EmailInputCell extends StatelessWidget {
  const EmailInputCell({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.enabled = true,
    this.obscureText = false,
    this.showDivider = true,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.autofillHints,
    this.onChanged,
    this.errorText,
    this.trailing,
  });

  final String label, hint;
  final TextEditingController controller;
  final bool enabled, obscureText, showDivider;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final stacked = MediaQuery.textScalerOf(context).scale(16) > 20;
    final title = Text(label,
        style:
            TextStyle(color: AppTokens.textPrimary(dark: dark), fontSize: 16));
    final input = Semantics(
      label: label,
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        autofillHints: autofillHints,
        onChanged: onChanged,
        cursorColor: AppTokens.accent,
        style:
            TextStyle(color: AppTokens.textPrimary(dark: dark), fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          filled: false,
          hintStyle: TextStyle(color: AppTokens.textSecondary(dark: dark)),
        ),
      ),
    );
    return Container(
      constraints: BoxConstraints(
          minHeight: SettingsResponsive.listRowMinHeight(context)),
      padding: SettingsResponsive.listRowPadding(context),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom:
                    BorderSide(color: AppTokens.border(dark: dark), width: 0.7))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stacked) ...[
            title,
            input,
            if (trailing != null)
              Align(alignment: AlignmentDirectional.centerEnd, child: trailing),
          ] else
            Row(children: [
              SizedBox(
                  width: SettingsResponsive.labelWidth(context), child: title),
              Expanded(child: input),
              if (trailing != null) ...[
                const SizedBox(width: AppTokens.s2),
                trailing!,
              ],
            ]),
          if (errorText != null)
            Semantics(
              liveRegion: true,
              child: Text(errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
