import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings_draft_store.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

class EditNicknamePage extends StatefulWidget {
  const EditNicknamePage({
    super.key,
    required this.initialNickname,
    required this.service,
    required this.store,
  });

  final String initialNickname;
  final SettingsService service;
  final SettingsDraftStore store;

  @override
  State<EditNicknamePage> createState() => _EditNicknamePageState();
}

class _EditNicknamePageState extends State<EditNicknamePage> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNickname);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final nickname = _controller.text.trim();
    if (nickname.isEmpty) {
      showSettingsMessage(
        context,
        settingsText(context, zh: '昵称不能为空', en: 'Nickname cannot be empty'),
      );
      return;
    }
    if (nickname.length < 2 || nickname.length > 22) {
      showSettingsMessage(
        context,
        settingsText(context, zh: '名字长度为 2-22 个字符', en: 'Name must be 2-22 characters'),
      );
      return;
    }
    if (!widget.service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '修改名字', en: 'Edit name'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.service.updateNickname(nickname);
      if (!mounted) return;
      widget.store.setProfileNickname(nickname);
      Navigator.of(context).pop(nickname);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: settingsText(context, zh: '修改名字', en: 'Edit Name'),
        dismissKeyboardOnOutsideTap: true,
        children: [
          const SizedBox(height: 12),
          SettingsGroup(
            children: [
              SettingsInputCell(
                label: settingsText(context, zh: '名字', en: 'Name'),
                hint: settingsText(context, zh: '请输入名字', en: 'Enter name'),
                controller: _controller,
                inputFormatters: [LengthLimitingTextInputFormatter(22)],
                showDivider: false,
              ),
            ],
          ),
          SettingsSectionText(
            settingsText(
              context,
              zh: '名字长度为 2-22 个字符，可使用文字、数字和常用符号。',
              en: 'Use 2-22 characters: text, numbers, and common symbols.',
            ),
          ),
          SettingsPrimaryButton(
            text: settingsText(context, zh: '保存', en: 'Save'),
            loading: _saving,
            onPressed: _save,
          ),
        ],
      );
}
