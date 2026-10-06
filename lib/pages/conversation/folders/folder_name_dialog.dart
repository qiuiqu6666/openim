// Adapted from 99chat's conversation.dart _promptFolderName.
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: state-owned controller, keyboard submission and optional validation.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

class FolderNameDialog extends StatefulWidget {
  const FolderNameDialog({
    super.key,
    this.initialName,
    this.validator,
  });

  final String? initialName;

  /// Returns a message to keep the dialog open, or null for a valid name.
  /// Receives the trimmed, non-empty name before the route is dismissed.
  final String? Function(String)? validator;

  @override
  State<FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<FolderNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName ?? '');
  String? _error;
  bool _closing = false;

  void _submit() {
    if (_closing || !mounted) return;
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final error = widget.validator?.call(name)?.trim();
    if (error != null && error.isNotEmpty) {
      setState(() => _error = error);
      return;
    }
    _close(name);
  }

  void _close([String? name]) {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final input = CupertinoTextField(
      controller: _controller,
      autofocus: true,
      maxLength: 16,
      placeholder: chinese ? '分组名称' : 'Folder name',
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
    );
    return CupertinoAlertDialog(
      title: Text(widget.initialName == null
          ? (chinese ? '新建分组' : 'New folder')
          : (chinese ? '重命名分组' : 'Rename folder')),
      content: Padding(
        padding: const EdgeInsets.only(top: AppTokens.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            input,
            if (_error != null) ...[
              const SizedBox(height: AppTokens.s3),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => _close(),
          child: Text(chinese ? '取消' : 'Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _submit,
          child: Text(chinese ? '确定' : 'OK'),
        ),
      ],
    );
  }
}
