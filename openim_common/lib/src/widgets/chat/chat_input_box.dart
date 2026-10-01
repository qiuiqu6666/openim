import 'dart:async';
import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'chat_emoji_panel.dart';
import 'chat_composer_palette.dart';

double kInputBoxMinHeight = 52.h;

class ChatInputBox extends StatefulWidget {
  const ChatInputBox({
    Key? key,
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
  }) : super(key: key);
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

  bool get _showQuoteView => IMUtils.isNotNullEmptyStr(widget.quoteContent);

  bool get _showDirectionalView => widget.directionalText != null;

  @override
  void initState() {
    _sendButtonVisible = widget.controller?.text.trim().isNotEmpty ?? false;
    widget.focusNode?.addListener(_focusChanged);

    _toolSubscription = widget.forceCloseToolboxSub?.listen((value) {
      if (!mounted) return;
      setState(() {
        _toolsVisible = false;
        _emojiVisible = false;
      });
    });

    widget.controller?.addListener(_syncSendButton);

    super.initState();
  }

  @override
  void didUpdateWidget(covariant ChatInputBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_focusChanged);
      widget.focusNode?.addListener(_focusChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_syncSendButton);
      widget.controller?.addListener(_syncSendButton);
      _sendButtonVisible = widget.controller?.text.trim().isNotEmpty ?? false;
    }
  }

  void _syncSendButton() {
    final visible = widget.controller?.text.trim().isNotEmpty ?? false;
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
    final colors = Theme.of(context).colorScheme;
    return widget.isNotInGroup
        ? const ChatDisableInputBox()
        : Column(
            children: [
              Container(
                constraints: BoxConstraints(minHeight: kInputBoxMinHeight),
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                color: chatComposerSurface(context),
                child: Row(
                  children: [
                    if (widget.onTapVoice != null)
                      IconButton(
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
                        icon: Icon(
                            _leftKeyboardButton
                                ? Icons.keyboard_alt_outlined
                                : Icons.mic_none_rounded,
                            color: colors.onSurface,
                            size: 24.w),
                      )
                    else
                      8.horizontalSpace,
                    Expanded(
                      child: Stack(
                        children: [
                          Offstage(
                            offstage: _leftKeyboardButton,
                            child: _textFiled,
                          ),
                          Offstage(
                            offstage: !_leftKeyboardButton,
                            child: widget.voiceRecordBar,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _emojiVisible
                          ? 'sdkSwitchKeyboard'.tr
                          : 'sdkEmojiPanel'.tr,
                      onPressed: widget.enabled ? toggleEmojiPanel : null,
                      icon: Icon(
                          _emojiVisible
                              ? Icons.keyboard_alt_outlined
                              : Icons.sentiment_satisfied_alt_outlined,
                          color: colors.onSurface,
                          size: 24.w),
                    ),
                    IconButton(
                      tooltip: _sendButtonVisible && !_leftKeyboardButton
                          ? StrRes.send
                          : StrRes.add,
                      onPressed: widget.enabled
                          ? (_sendButtonVisible && !_leftKeyboardButton
                              ? send
                              : toggleToolbox)
                          : null,
                      icon: Icon(
                        _sendButtonVisible && !_leftKeyboardButton
                            ? Icons.send_rounded
                            : Icons.add_circle_outline_rounded,
                        size: 28.w,
                        color: _sendButtonVisible && !_leftKeyboardButton
                            ? colors.primary
                            : colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (_showQuoteView)
                _SubView(
                    content: widget.quoteContent, onClose: widget.onClearQuote),
              if (_showDirectionalView)
                _SubView(
                  textSpan: widget.directionalText,
                  onClose: () {
                    widget.onCloseDirectional?.call();
                  },
                ),
              Visibility(
                visible: _toolsVisible,
                child: FadeInUp(
                  duration: const Duration(milliseconds: 200),
                  child: widget.toolbox,
                ),
              ),
              if (_emojiVisible) _emojiPanel,
            ],
          );
  }

  Widget get _emojiPanel => ChatEmojiPanel(
        onEmojiSelected: _insertEmoji,
        onBackspace: _deleteEmoji,
        onSend: send,
        canSend: _sendButtonVisible && widget.enabled,
        stickerPanel: widget.stickerPanel,
      );

  void _insertEmoji(String emoji) {
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

  Widget get _textFiled => Container(
        constraints: BoxConstraints(minHeight: 40.h),
        margin: EdgeInsets.only(top: 6.h, bottom: _showQuoteView ? 4.h : 6.h),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
        ),
        child: ChatTextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          style: widget.style ??
              TextStyle(
                  fontSize: 16.sp,
                  color: Theme.of(context).colorScheme.onSurface),
          atStyle: widget.atStyle ??
              TextStyle(
                  fontSize: 16.sp,
                  color: Theme.of(context).colorScheme.primary),
          enabled: widget.enabled,
          hintText: widget.hintText,
          textAlign: widget.enabled ? TextAlign.start : TextAlign.center,
        ),
      );

  void send() {
    if (!widget.enabled) return;
    if (null != widget.onSend && null != widget.controller) {
      widget.onSend!(widget.controller!.text.toString().trim());
    }
  }

  void toggleToolbox() {
    if (!widget.enabled) return;
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
    if (!widget.enabled) return;
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
    if (!widget.enabled) return;
    setState(() {
      _leftKeyboardButton = false;
      _toolsVisible = false;
      focus();
    });
  }

  void onTapRightKeyboard() {
    if (!widget.enabled) return;
    setState(() {
      _toolsVisible = false;
      focus();
    });
  }

  focus() => FocusScope.of(context).requestFocus(widget.focusNode);

  unfocus() => FocusScope.of(context).unfocus();
}

class _SubView extends StatelessWidget {
  const _SubView({
    this.onClose,
    this.content,
    this.textSpan,
  }) : assert(content != null || textSpan != null,
            'Either content or textSpan must be provided.');
  final VoidCallback? onClose;
  final String? content;
  final InlineSpan? textSpan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
      color: Styles.c_F0F2F6,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onClose,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 1.h, horizontal: 4.w),
          decoration: BoxDecoration(
            color: Styles.c_FFFFFF,
            borderRadius: BorderRadius.circular(4.r),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  children: [
                    if (content != null)
                      Expanded(
                          child: Text(
                        content!,
                        style: Styles.ts_8E9AB0_14sp,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      )),
                    if (textSpan != null)
                      Expanded(
                        child: RichText(
                          text: textSpan!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              ImageRes.delQuote.toImage
                ..width = 14.w
                ..height = 14.h,
            ],
          ),
        ),
      ),
    );
  }
}
