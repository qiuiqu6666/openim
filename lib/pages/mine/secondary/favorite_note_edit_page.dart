import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/favorite_repository.dart';
import '../../favorites/widgets/favorite_capability_gate.dart';
import '../../favorites/widgets/favorite_conflict_review_dialog.dart';
import '../../favorites/widgets/favorite_note_byte_formatter.dart';
import '../settings/widgets/settings_widgets.dart';

class FavoriteNoteEditPage extends StatefulWidget {
  const FavoriteNoteEditPage(
      {super.key,
      this.initialText = '',
      this.onSave,
      this.repository,
      this.onReviewConflict,
      this.onAcceptConflict});

  final String initialText;
  final Future<void> Function(String text)? onSave;
  final FavoriteRepository? repository;
  final Future<FavoriteItem> Function(FavoriteApiException)? onReviewConflict;
  final void Function(FavoriteItem)? onAcceptConflict;

  @override
  State<FavoriteNoteEditPage> createState() => _FavoriteNoteEditPageState();
}

class _FavoriteNoteEditPageState extends State<FavoriteNoteEditPage> {
  late final TextEditingController _controller;
  late final String? _scope;
  bool _saving = false;
  bool _reviewing = false;
  String? _error;
  String? _notice;
  FavoriteApiException? _conflict;
  bool get _current =>
      widget.repository == null || widget.repository!.isSessionCurrent(_scope!);

  @override
  void initState() {
    super.initState();
    _scope = widget.repository?.sessionScope;
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

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty ||
        _saving ||
        _reviewing ||
        _conflict != null ||
        !_current ||
        !FavoriteNoteByteFormatter.canSave(value)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (widget.onSave == null) {
      Navigator.of(context).pop(value);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.repository?.requireAvailable();
      if (!_current) return;
      await widget.onSave!(value);
      if (mounted && _current) Navigator.of(context).pop(value);
    } catch (error) {
      if (mounted && _current) {
        setState(() {
          if (error is FavoriteApiException &&
              error.isVersionConflict &&
              widget.onAcceptConflict != null) {
            _conflict = error;
          }
          _error = error is FavoriteApiException
              ? error.message
              : settingsErrorMessage(context, error,
                  fallback: settingsText(context,
                      zh: '保存失败，内容已保留，请重试',
                      en: 'Could not save. Your text is kept; please retry.'));
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reviewConflict() async {
    final conflict = _conflict;
    if (conflict == null || _saving || _reviewing || !_current) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _reviewing = true);
    try {
      await widget.repository?.requireAvailable();
      final FavoriteItem? latest = widget.onReviewConflict == null
          ? conflict.currentItem
          : await widget.onReviewConflict!(conflict);
      if (!mounted || !_current) return;
      if (latest == null) {
        throw const FavoriteApiException(
            'LATEST_VERSION_UNAVAILABLE', '无法取得最新版本，请重试');
      }
      final accepted = await showFavoriteConflictReview(context,
          currentItem: latest,
          editedText: _controller.text,
          repository: widget.repository);
      if (!accepted || !mounted || !_current) return;
      if (latest.kind != FavoriteKind.note ||
          latest.content == null ||
          latest.blocks.any((block) => block.type != 'text')) {
        return;
      }
      widget.onAcceptConflict?.call(latest);
      setState(() {
        _conflict = null;
        _error = null;
        _notice = settingsText(context,
            zh: '已保留你的编辑，再次点击“完成”提交',
            en: 'Your edits are kept. Tap Done again to submit.');
      });
    } catch (error) {
      if (mounted && _current) {
        setState(() => _error = error is FavoriteApiException
            ? error.message
            : settingsText(context,
                zh: '最新版本加载失败，编辑内容已保留，请重试',
                en: 'Could not load the latest version. Your edits are kept.'));
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final text = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final fill = AppTokens.surfaceAlt(dark: dark);
    final editor = PopScope(
      canPop: !_saving && !_reviewing,
      child: SettingsScaffold(
        title: settingsText(context, zh: '笔记', en: 'Note'),
        dismissKeyboardOnOutsideTap: true,
        actions: [
          TextButton(
            key: const ValueKey('favorite-note-save'),
            onPressed: _saving ||
                    _reviewing ||
                    _conflict != null ||
                    _controller.text.trim().isEmpty ||
                    !FavoriteNoteByteFormatter.canSave(_controller.text)
                ? null
                : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: AppTokens.s6,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    settingsText(context, zh: '完成', en: 'Done'),
                    style:
                        const TextStyle(fontSize: 16, color: AppTokens.accent),
                  ),
          ),
          const SizedBox(width: 4),
        ],
        children: [
          if (_notice != null)
            Padding(
                padding: const EdgeInsets.all(AppTokens.s5),
                child: Semantics(
                    liveRegion: true,
                    child: Text(_notice!, style: TextStyle(color: secondary)))),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppTokens.s5),
              child: Semantics(
                liveRegion: true,
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
          if (_conflict != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
                child: OutlinedButton.icon(
                    key: const ValueKey('favorite-note-review-conflict'),
                    onPressed: _reviewing ? null : _reviewConflict,
                    icon: const Icon(Icons.compare_arrows),
                    label: Text(settingsText(context,
                        zh: '查看最新版本', en: 'Review latest version')))),
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
                enabled: !_saving && !_reviewing,
                autofocus: true,
                minLines: 9,
                maxLines: 16,
                inputFormatters: const [FavoriteNoteByteFormatter()],
                style: TextStyle(color: text, fontSize: 16, height: 1.5),
                decoration: InputDecoration(
                  hintText: settingsText(context,
                      zh: '写点什么...', en: 'Write something...'),
                  hintStyle: TextStyle(color: secondary, fontSize: 16),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  counterText:
                      '${FavoriteNoteByteFormatter.byteLength(_controller.text)} / ${FavoriteNoteByteFormatter.maxBytes} ${settingsText(context, zh: '字节', en: 'bytes')}',
                  counterStyle: TextStyle(
                      color: FavoriteNoteByteFormatter.canSave(_controller.text)
                          ? secondary
                          : Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return widget.repository == null
        ? editor
        : FavoriteCapabilityGate(
            repository: widget.repository!,
            showScaffold: true,
            title: settingsText(context, zh: '笔记', en: 'Note'),
            child: editor);
  }
}
