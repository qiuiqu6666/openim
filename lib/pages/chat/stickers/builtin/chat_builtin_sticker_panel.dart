import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart'
    show AppTokens, ChatComposerTokens;

import 'chat_builtin_sticker.dart';

/// The bundled 99CHAT pack sends directly and has no collection or management.
class ChatBuiltinStickerPanel extends StatefulWidget {
  const ChatBuiltinStickerPanel({super.key, required this.onSend});

  final Future<void> Function(ChatBuiltinSticker sticker) onSend;

  @override
  State<ChatBuiltinStickerPanel> createState() =>
      _ChatBuiltinStickerPanelState();
}

class _ChatBuiltinStickerPanelState extends State<ChatBuiltinStickerPanel> {
  String? _sendingID;

  Future<void> _send(ChatBuiltinSticker sticker) async {
    if (_sendingID != null) return;
    setState(() => _sendingID = sticker.id);
    try {
      await widget.onSend(sticker);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('发送失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _sendingID = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _sendingID == null;
    return ColoredBox(
      color:
          ChatComposerTokens.surface(dark: theme.brightness == Brightness.dark),
      child: GridView.builder(
        key: const ValueKey('chat-builtin-sticker-grid'),
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(AppTokens.s3),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: AppTokens.s3,
          mainAxisSpacing: AppTokens.s3,
        ),
        itemCount: ChatBuiltinStickerCatalog.stickers.length,
        itemBuilder: (context, index) {
          final sticker = ChatBuiltinStickerCatalog.stickers[index];
          final send = enabled ? () => _send(sticker) : null;
          return Semantics(
            key: ValueKey('builtin-sticker-${sticker.id}'),
            button: true,
            enabled: enabled,
            label: '发送${sticker.label}',
            onTap: send,
            excludeSemantics: true,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppTokens.rSm),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: send,
                excludeFromSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.s3),
                  child: Stack(fit: StackFit.expand, children: [
                    Image.asset(sticker.assetPath,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.broken_image_outlined,
                            color: theme.colorScheme.onSurfaceVariant)),
                    if (_sendingID == sticker.id)
                      const Center(
                        child: SizedBox.square(
                          dimension: AppTokens.s7,
                          child: CircularProgressIndicator(),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
