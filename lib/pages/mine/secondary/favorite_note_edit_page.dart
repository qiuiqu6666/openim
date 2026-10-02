import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../settings/widgets/settings_widgets.dart';

class FavoriteNoteEditPage extends StatefulWidget {
  const FavoriteNoteEditPage({super.key, this.initialText = ''});

  final String initialText;

  @override
  State<FavoriteNoteEditPage> createState() => _FavoriteNoteEditPageState();
}

class _FavoriteNoteEditPageState extends State<FavoriteNoteEditPage> {
  static const _maxLength = 2000;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText)
      ..addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final text = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final fill = dark ? const Color(0xFF23262D) : const Color(0xFFF1F2F4);
    return SettingsScaffold(
      title: settingsText(context, zh: '笔记', en: 'Note'),
      dismissKeyboardOnOutsideTap: true,
      actions: [
        TextButton(
          onPressed: _controller.text.trim().isEmpty ? null : _save,
          child: Text(
            settingsText(context, zh: '完成', en: 'Done'),
            style: const TextStyle(fontSize: 16, color: AppTokens.accent),
          ),
        ),
        const SizedBox(width: 4),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Container(
            constraints: const BoxConstraints(minHeight: 220),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _controller,
              autofocus: true,
              minLines: 9,
              maxLines: 16,
              maxLength: _maxLength,
              inputFormatters: [LengthLimitingTextInputFormatter(_maxLength)],
              style: TextStyle(color: text, fontSize: 16, height: 1.5),
              decoration: InputDecoration(
                hintText: settingsText(context, zh: '写点什么...', en: 'Write something...'),
                hintStyle: TextStyle(color: secondary, fontSize: 16),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
