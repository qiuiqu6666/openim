import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'chat_emoji_panel.dart';
import 'chat_composer_palette.dart';
import 'chat_composer_context_preview.dart';
import 'toolbox/chat_composer_toolbox_slot.dart';
import '../../res/chat_voice_tokens.dart';

const double kInputBoxMinHeight =
    ChatComposerTokens.inputHeight + ChatComposerTokens.verticalPadding * 2;

class ChatInputBox extends StatefulWidget {
  const ChatInputBox({
    super.key,
    required this.toolbox,
    required this.voiceRecordBar,
    this.controller,
    this.focusNode,
    this.style,
    this.atStyle,
    this.enabled = true,
    this.isNotInGroup = false,
    this.hintText,
    this.forceCloseToolboxSub,
    this.quoteContent,
    this.onClearQuote,
    this.onSend,
    this.onTapVoice,
    this.directionalText,
    this.onCloseDirectional,
    this.stickerPanel,
    this.builtinStickerPanel,
    this.builtinStickerIcon,
  });
  final FocusNode? focusNode;
  final TextEditingController? controller;
  final TextStyle? style;
  final TextStyle? atStyle;
  final bool enabled;
  final bool isNotInGroup;
  final String? hintText;
  final Widget toolbox;
  final Widget voiceRecordBar;
  final Stream? forceCloseToolboxSub;
  final String? quoteContent;
  final Function()? onClearQuote;
  final ValueChanged<String>? onSend;
  final VoidCallback? onTapVoice;
  final TextSpan? directionalText;
  final VoidCallback? onCloseDirectional;
  final Widget? stickerPanel;
  final Widget? builtinStickerPanel;
  final Widget? builtinStickerIcon;

  @override
  State<ChatInputBox> createState() => _ChatInputBoxState();
}

class _ChatInputBoxState
    extends State<ChatInputBox> /*with TickerProviderStateMixin */ {
  StreamSubscription? _toolSubscription;
  void _focusChanged() {
    if (mounted && widget.focusNode?.hasFocus == true) {
      setState(() {
        _toolsVisible = false;
        _emojiVisible = false;
        _leftKeyboardButton = false;
      });
    }
  }

  bool _toolsVisible = false;
  bool _emojiVisible = false;
  bool _leftKeyboardButton = false;
  bool _sendButtonVisible = false;

  bool get _inputBlocked => !widget.enabled || widget.isNotInGroup;

  bool get _showQuoteView => IMUtils.isNotNullEmptyStr(widget.quoteContent);

  bool get _showDirectionalView => widget.directionalText != null;

  @override
  void initState() {
    _sendButtonVisible = widget.controller?.text.isNotEmpty ?? false;
    widget.focusNode?.addListener(_focusChanged);

    _toolSubscription = widget.forceCloseToolboxSub?.listen((value) {
      if (!mounted) return;
      setState(() {
        _toolsVisible = false;
        _emojiVisible = false;
        _leftKeyboardButton = false;
      });
    });

    widget.controller?.addListener(_syncSendButton);

    super.initState();
  }

  @override
  void didUpdateWidget(covariant ChatInputBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_inputBlocked) {
      _toolsVisible = false;
      _emojiVisible = false;
      _leftKeyboardButton = false;
      widget.focusNode?.unfocus();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_focusChanged);
      widget.focusNode?.addListener(_focusChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_syncSendButton);
      widget.controller?.addListener(_syncSendButton);
      _sendButtonVisible = widget.controller?.text.isNotEmpty ?? false;
    }
  }

  void _syncSendButton() {
    final visible = widget.controller?.text.isNotEmpty ?? false;
    if (mounted && visible != _sendButtonVisible) {
      setState(() => _sendButtonVisible = visible);
    }
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_focusChanged);
    _toolSubscription?.cancel();
    widget.controller?.removeListener(_syncSendButton);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final alternatePanelVisible = _emojiVisible || _leftKeyboardButton;
    final content = _inputBlocked
        ? ChatDisableInputBox(
            message: widget.isNotInGroup
                ? StrRes.notSendMessageNotInGroup
                : widget.hintText ?? StrRes.youMuted,
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: const ValueKey('chat-composer-bar'),
                constraints: const BoxConstraints(
                    minHeight: ChatComposerTokens.inputHeight),
                padding: const EdgeInsets.symmetric(
                  horizontal: ChatComposerTokens.horizontalPadding,
                  vertical: ChatComposerTokens.verticalPadding,
                ),
                child: Row(
                  children: [
                    if (widget.onTapVoice != null)
                      _buildIconAction(
                        tooltip: StrRes.voiceCapture,
                        onPressed: widget.enabled
                            ? () {
                                setState(() {
                                  _emojiVisible = false;
                                  _toolsVisible = false;
                                  _leftKeyboardButton = !_leftKeyboardButton;
                                });
                                if (_leftKeyboardButton) {
                                  unfocus();
                                } else {
                                  focus();
                                }
                              }
                            : null,
                        asset: _leftKeyboardButton ? 'keyboard' : 'voice',
                      ),
                    if (widget.onTapVoice != null)
                      const SizedBox(width: ChatComposerTokens.actionGap),
                    Expanded(
                      child: Stack(
                        children: [
                          Offstage(
                            offstage: _leftKeyboardButton,
                            child: _textFiled,
                          ),
                          Offstage(
                            offstage: !_leftKeyboardButton,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.enabled
                                  ? () {
                                      setState(
                                          () => _leftKeyboardButton = false);
                                      focus();
                                    }
                                  : null,
                              child: Container(
                                key: const ValueKey(
                                    'chat-voice-input-placeholder'),
                                height: ChatComposerTokens.inputHeight,
                                decoration: BoxDecoration(
                                  color: chatComposerInputFill(context),
                                  borderRadius: BorderRadius.circular(
                                      ChatComposerTokens.radius),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: ChatComposerTokens.actionGap),
                    _buildIconAction(
                      tooltip: _emojiVisible
                          ? 'sdkSwitchKeyboard'.tr
                          : 'sdkEmojiPanel'.tr,
                      onPressed: widget.enabled ? toggleEmojiPanel : null,
                      asset: _emojiVisible ? 'keyboard' : 'face',
                    ),
                    const SizedBox(width: ChatComposerTokens.actionGap),
                    if (_sendButtonVisible)
                      SizedBox(
                        height: ChatComposerTokens.inputHeight,
                        child: SizedBox(
                          height: ChatComposerTokens.sendHeight,
                          child: ElevatedButton(
                            onPressed: widget.enabled ? send : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTokens.accent,
                              foregroundColor: AppTokens.onAccent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal:
                                      ChatComposerTokens.sendHorizontalPadding),
                              minimumSize:
                                  const Size(0, ChatComposerTokens.sendHeight),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(StrRes.send,
                                style: const TextStyle(
                                  color: AppTokens.onAccent,
                                  fontSize: ChatComposerTokens.sendFontSize,
                                )),
                          ),
                        ),
                      )
                    else
                      _buildIconAction(
                        tooltip: StrRes.add,
                        onPressed: widget.enabled ? toggleToolbox : null,
                        asset: 'add',
                      ),
                  ],
                ),
              ),
              if (_showQuoteView)
                ChatComposerContextPreview(
                    content: widget.quoteContent, onClose: widget.onClearQuote),
              if (_showDirectionalView)
                ChatComposerContextPreview(
                  textSpan: widget.directionalText,
                  onClose: () {
                    widget.onCloseDirectional?.call();
                  },
                ),
              ChatComposerToolboxSlot(
                visible: _toolsVisible,
                safeBottom: safeBottom,
                collapsedHeight: alternatePanelVisible ? 0 : safeBottom,
                animate: !alternatePanelVisible,
                child: widget.toolbox,
              ),
              if (_emojiVisible)
                Padding(
                  padding: EdgeInsets.only(bottom: safeBottom),
                  child: _emojiPanel,
                ),
              if (_leftKeyboardButton)
                AnimatedContainer(
                  key: const ValueKey('chat-voice-panel-slot'),
                  duration: ChatVoiceTokens.panelAnimationDuration,
                  curve: Curves.easeOutCubic,
                  height: ChatVoiceTokens.panelHeight +
                      MediaQuery.paddingOf(context).bottom,
                  alignment: Alignment.topCenter,
                  child: widget.voiceRecordBar,
                ),
            ],
          );
    final bottomColor = _inputBlocked
        ? chatComposerSurface(context)
        : _toolsVisible
            ? ChatToolboxTokens.panelBackground(context)
            : !_leftKeyboardButton &&
                    !_emojiVisible &&
                    (_showQuoteView || _showDirectionalView)
                ? Styles.c_F0F2F6
                : chatComposerSurface(context);
    return AppSystemBars(
      background: bottomColor,
      child: ColoredBox(
        color: bottomColor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
                top: BorderSide(
              color: chatComposerDivider(context),
              width: ChatComposerTokens.dividerWidth,
            )),
          ),
          child: SafeArea(
              top: false,
              left: false,
              right: false,
              bottom: _inputBlocked,
              child: content),
        ),
      ),
    );
  }

  Widget _buildIconAction({
    required String tooltip,
    required String asset,
    required VoidCallback? onPressed,
  }) =>
      SizedBox(
        height: ChatComposerTokens.inputHeight,
        child: Center(
            child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onPressed,
            child: SvgPicture.asset(
              'assets/chat/composer/$asset.svg',
              package: 'openim_common',
              width: ChatComposerTokens.iconSize,
              height: ChatComposerTokens.iconSize,
              colorFilter: ColorFilter.mode(
                  chatComposerForeground(context)
                      .withValues(alpha: widget.enabled ? 1 : .38),
                  BlendMode.srcIn),
            ),
          ),
        )),
      );

  Widget get _emojiPanel => ChatEmojiPanel(
        onEmojiSelected: _insertEmoji,
        onBackspace: _deleteEmoji,
        onSend: send,
        canSend: _sendButtonVisible && widget.enabled,
        stickerPanel: widget.stickerPanel,
        builtinStickerPanel: widget.builtinStickerPanel,
        builtinStickerIcon: widget.builtinStickerIcon,
      );

  void _insertEmoji(String emoji) {
    if (_inputBlocked) return;
    final controller = widget.controller;
    if (controller == null) return;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _deleteEmoji() {
    if (_inputBlocked) return;
    final controller = widget.controller;
    if (controller == null || controller.text.isEmpty) return;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    if (start != end) {
      controller.value = TextEditingValue(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
      return;
    }
    if (start == 0) return;
    final before = text.substring(0, start);
    final removed = before.characters.last.length;
    controller.value = TextEditingValue(
      text: text.replaceRange(start - removed, start, ''),
      selection: TextSelection.collapsed(offset: start - removed),
    );
  }

  Widget get _textFiled => TextSelectionTheme(
        data: TextSelectionThemeData(
          cursorColor: ChatComposerTokens.cursor(
              dark: Theme.of(context).brightness == Brightness.dark),
          selectionColor: AppTokens.accent
              .withValues(alpha: ChatComposerTokens.selectionOpacity),
          selectionHandleColor: ChatComposerTokens.cursor(
              dark: Theme.of(context).brightness == Brightness.dark),
        ),
        child: ChatTextField(
          key: const ValueKey('chat-composer-input-fill'),
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ChatComposerTokens.radius),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ChatComposerTokens.radius),
              borderSide: BorderSide.none,
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ChatComposerTokens.radius),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: chatComposerInputFill(context),
            isDense: true,
            hintText: widget.hintText ?? '',
            hintStyle: chatComposerTextStyle(context, hint: true),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: ChatComposerTokens.textHorizontalPadding,
              vertical: ChatComposerTokens.textVerticalPadding,
            ),
          ),
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.send,
          onEditingComplete: send,
          autocorrect: false,
          controller: widget.controller,
          focusNode: widget.focusNode,
          style: widget.style ?? chatComposerTextStyle(context),
          atStyle: widget.atStyle ??
              TextStyle(
                  fontSize: ChatComposerTokens.fontSize,
                  color: AppTokens.accent),
          enabled: widget.enabled,
          hintText: widget.hintText,
          textAlign: widget.enabled ? TextAlign.start : TextAlign.center,
        ),
      );

  void send() {
    if (_inputBlocked) return;
    if (null != widget.onSend && null != widget.controller) {
      final text = widget.controller!.text.trim();
      if (text.isNotEmpty) widget.onSend!(text);
    }
  }

  void toggleToolbox() {
    if (_inputBlocked) return;
    setState(() {
      _toolsVisible = !_toolsVisible;
      _emojiVisible = false;
      _leftKeyboardButton = false;
      if (_toolsVisible) {
        unfocus();
      } else {
        focus();
      }
    });
  }

  void toggleEmojiPanel() {
    if (_inputBlocked) return;
    if (_emojiVisible) {
      setState(() => _emojiVisible = false);
      focus();
    } else {
      setState(() {
        _emojiVisible = true;
        _toolsVisible = false;
        _leftKeyboardButton = false;
      });
      unfocus();
    }
  }

  void onTapLeftKeyboard() {
    if (_inputBlocked) return;
    setState(() {
      _leftKeyboardButton = false;
      _toolsVisible = false;
      focus();
    });
  }

  void onTapRightKeyboard() {
    if (_inputBlocked) return;
    setState(() {
      _toolsVisible = false;
      focus();
    });
  }

  void focus() {
    if (!_inputBlocked) FocusScope.of(context).requestFocus(widget.focusNode);
  }

  void unfocus() => FocusScope.of(context).unfocus();
}
