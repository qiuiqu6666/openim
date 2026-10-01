import 'package:flutter/material.dart';

class FolderNameDialog extends StatefulWidget {
  const FolderNameDialog({super.key, this.initialName});

  final String? initialName;

  @override
  State<FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<FolderNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.initialName == null ? '新建分组' : '重命名分组'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(hintText: '分组名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      );
}
