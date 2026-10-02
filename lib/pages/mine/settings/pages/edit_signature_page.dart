import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_draft_store.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

class EditSignaturePage extends StatefulWidget {
  const EditSignaturePage({
    super.key,
    required this.store,
    required this.service,
  });

  final SettingsDraftStore store;
  final SettingsService service;

  @override
  State<EditSignaturePage> createState() => _EditSignaturePageState();
}

class _EditSignaturePageState extends State<EditSignaturePage> {
  static const int _maxLength = 100;
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.store.profileSignature)
      ..addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final value = _controller.text.trim();
    if (!widget.service.isProfileBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '个性签名', en: 'Bio'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.service.updateSignature(value);
      if (!mounted) return;
      widget.store.setProfileSignature(value);
      Navigator.of(context).pop(value);
    } catch (_) {
      if (mounted) {
        showSettingsMessage(
            context,
            settingsText(context,
                zh: '保存失败，请稍后重试', en: 'Failed to save. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final fill = AppTokens.surface(dark: dark);
    final text = AppTokens.textPrimary(dark: dark);
    final hint = AppTokens.textSecondary(dark: dark);
    final changed = _controller.text.trim() != widget.store.profileSignature;

    return SettingsScaffold(
      title: settingsText(context, zh: '个性签名', en: 'Bio'),
      dismissKeyboardOnOutsideTap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _controller,
              enabled: !_saving,
              autofocus: true,
              minLines: 5,
              maxLines: 7,
              maxLength: _maxLength,
              inputFormatters: [LengthLimitingTextInputFormatter(_maxLength)],
              style: TextStyle(color: text, fontSize: 16, height: 1.45),
              decoration: InputDecoration(
                hintText: settingsText(context, zh: '填写个性签名', en: 'Enter bio'),
                hintStyle: TextStyle(color: hint, fontSize: 16),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                counterText:
                    '${_controller.text.characters.length}/$_maxLength',
                counterStyle: TextStyle(color: hint, fontSize: 12),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: SizedBox(
            height: SettingsResponsive.controlHeight(context),
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving || !changed ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTokens.accent,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                disabledBackgroundColor:
                    AppTokens.accent.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _saving
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Text(
                      settingsText(context, zh: '完成', en: 'Done'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
