import 'package:flutter/material.dart';

import '../../../contacts/select_contacts/selection/contact_single_selection.dart';
import '../support/sangong_ui.dart';
import '../support/settings_exports.dart';

class SangongConfigSelection {
  const SangongConfigSelection({required this.id, required this.name});
  final String id, name;
}

/// Keeps manual IDs editable while offering a directory shortcut and showing
/// the selected name only while the input still matches that directory entry.
class SangongConfigSelectionCell extends StatelessWidget {
  const SangongConfigSelectionCell({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.kind,
    this.selection,
    this.onSelect,
    this.readOnly = false,
  });

  final String label, hint;
  final TextEditingController controller;
  final ContactSingleSelectionKind kind;
  final SangongConfigSelection? selection;
  final VoidCallback? onSelect;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, value, _) {
          final name =
              value.text.trim() == selection?.id ? selection?.name : null;
          final groups = kind == ContactSingleSelectionKind.groups;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsInputCell(
                  label: label,
                  hint: hint,
                  controller: controller,
                  readOnly: readOnly,
                  showDivider: name == null,
                  trailing: onSelect == null
                      ? null
                      : IconButton(
                          tooltip: settingsText(context,
                              zh: groups ? '从群聊列表选择$label' : '从通讯录选择$label',
                              en: groups
                                  ? 'Select $label from groups'
                                  : 'Select $label from contacts'),
                          onPressed: readOnly ? null : onSelect,
                          color: AppTokens.accent,
                          icon: Icon(groups
                              ? Icons.groups_outlined
                              : Icons.person_search_outlined),
                        ),
                ),
                if (name != null)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: AppTokens.s5,
                        right: AppTokens.s5,
                        bottom: AppTokens.s4),
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: settingsSecondaryTextColor(context))),
                  ),
              ]);
        },
      );
}
