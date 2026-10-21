import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class PendingForwardBar extends StatefulWidget {
  const PendingForwardBar({
    super.key,
    required this.count,
    required this.onCancel,
    this.sending = false,
    this.onOpenOptions,
  });

  final int count;
  final VoidCallback onCancel;
  final bool sending;
  final VoidCallback? onOpenOptions;

  @override
  State<PendingForwardBar> createState() => _PendingForwardBarState();
}

class _PendingForwardBarState extends State<PendingForwardBar> {
  bool _promptOpen = false;

  String _dialogText(String key) {
    // GetX can retain an older translation registry after a hot reload.
    // Read the bundled resource in the resolved UI language for these labels.
    final locale = TranslationService.resolveLocale(
        Get.locale ?? Localizations.localeOf(context));
    final resources = TranslationService().keys;
    return resources[locale.toString()]?[key] ??
        resources[TranslationService.fallbackLocale.toString()]![key]!;
  }

  Future<void> _requestClose() async {
    if (_promptOpen || widget.sending) return;
    _promptOpen = true;
    try {
      final cancel = await showAppAlert<bool>(context,
          title: _dialogText('chatForwardClosePrompt'),
          barrierDismissible: true,
          actions: [
            AppAction(_dialogText('chatOpenForwardOptions'), false),
            AppAction(_dialogText('chatCancelForward'), true,
                destructive: true),
          ]);
      if (!mounted || widget.sending || cancel == null) return;
      if (cancel) {
        widget.onCancel();
      } else {
        widget.onOpenOptions?.call();
      }
    } finally {
      _promptOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
        child: Material(
          color: ChatComposerTokens.surface(
              dark: Theme.of(context).brightness == Brightness.dark),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppTokens.s3),
                child: SvgPicture.asset(
                  'lib/pages/chat/messages/forwarding/assets/forward.svg',
                  width: AppTokens.s7,
                  height: AppTokens.s7,
                  colorFilter:
                      const ColorFilter.mode(AppTokens.accent, BlendMode.srcIn),
                  excludeFromSemantics: true,
                ),
              ),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsetsDirectional.only(start: AppTokens.s2),
                  decoration: const BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(
                          color: AppTokens.accent, width: AppTokens.s2 / 2),
                    ),
                  ),
                  child: Text(
                    'chatPendingForwardCount'
                        .trParams({'count': '${widget.count}'}),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTokens.accent,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('pending-forward-cancel'),
                tooltip: 'chatCancelForward'.tr,
                onPressed: widget.sending ? null : _requestClose,
                color: AppTokens.accent,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      );
}
