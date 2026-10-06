import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// A bundled dice entry alongside the user's personal image stickers.
class ChatDiceTile extends StatelessWidget {
  const ChatDiceTile({
    super.key,
    required this.onSend,
    this.sending = false,
    this.enabled = true,
  });

  final VoidCallback onSend;
  final bool sending, enabled;

  @override
  Widget build(BuildContext context) {
    final label = Localizations.localeOf(context).languageCode == 'zh'
        ? '掷骰子'
        : 'Roll dice';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTokens.rSm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('dice-sticker-tile'),
            onTap: enabled && !sending ? onSend : null,
            child: Stack(fit: StackFit.expand, children: [
              const ExcludeSemantics(
                child: ChatDiceSticker(
                    value: 1, animate: false, tightPreview: true),
              ),
              if (sending)
                Center(
                  child: SizedBox.square(
                    dimension: AppTokens.s5,
                    child: const CircularProgressIndicator(),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
