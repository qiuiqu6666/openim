import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Protects a route's local edits; business saves and their results stay owned
/// by the editor. Toolbar back actions must use Navigator.maybePop.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.dirty,
    required this.busy,
    required this.child,
  });

  final bool dirty;
  final bool busy;
  final Widget child;

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  bool _allowPop = false;
  bool _confirming = false;

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Future<void> _requestLeave() async {
    if (_confirming || ModalRoute.of(context)?.isCurrent != true) return;
    _confirming = true;
    try {
      if (widget.busy) {
        IMViews.showToast(_text(AppCopy.text('请等待操作完成，当前内容会保留。'),
            'Please wait for the result. Your content is kept.'));
        return;
      }
      final discard = await showAppConfirm(context,
          title: _text(AppCopy.text('放弃未保存的内容？'), 'Discard unsaved changes?'),
          message: _text(AppCopy.text('离开后，本次未提交的修改将丢失。'),
              'Your unsubmitted changes will be lost if you leave.'),
          cancelText: _text(AppCopy.text('继续编辑'), 'Keep editing'),
          confirmText: _text(AppCopy.text('放弃修改'), 'Discard changes'),
          destructive: true);
      if (!mounted || !discard || widget.busy) return;
      setState(() => _allowPop = true);
      // Let PopScope publish the new disposition before retrying this pop once.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).maybePop();
        }
      });
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _allowPop || (!widget.dirty && !widget.busy),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestLeave();
        },
        child: widget.child,
      );
}
