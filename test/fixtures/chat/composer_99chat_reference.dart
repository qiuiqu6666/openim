import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Independent rendering reference for the production 99chat mobile composer.
///
/// Source: 99chat revision d7c3c65, Apache-2.0:
/// third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/
/// TIMUIKitTextField/tim_uikit_text_field_layout/narrow.dart
/// (_buildTrailingActionButton, _buildRightActionCluster and tuiBuild).
/// Text metrics come from ui/utils/message_bubble_text_color.dart; colors come
/// from lib/utils/theme.dart and lib/src/ui/app_tokens.dart in that revision.
///
/// This test-only fixture intentionally does not use ChatInputBox, its palette,
/// or ChatComposerTokens. Its plain-text row is transcribed independently so a
/// comparison can expose production regressions rather than share them.
class Composer99ChatReference extends StatelessWidget {
  const Composer99ChatReference({
    super.key,
    required this.dark,
    required this.controller,
    this.fontFamily,
    this.focusNode,
    this.hintText = '',
  });

  final bool dark;
  final TextEditingController controller;

  /// Mobile 99chat uses the system font. Tests can supply the same loaded font
  /// to both implementations to make glyph rasterization deterministic.
  final String? fontFamily;
  final FocusNode? focusNode;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final barColor = dark ? const Color(0xFF101114) : Colors.white;
    final fillColor = dark ? const Color(0xFF1B1D22) : const Color(0xFFF1F3F5);
    final textColor = dark ? const Color(0xFFF4F4F4) : const Color(0xFF1C1C1E);
    final hintColor = dark ? const Color(0xFF9A9CA3) : const Color(0xFF7B8491);
    final dividerColor =
        dark ? const Color(0xFF2A2D33) : const Color(0xFFEAEAEA);
    final textStyle = TextStyle(
      inherit: false,
      fontFamily: fontFamily,
      fontSize: 16,
      height: 1.3,
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
      color: textColor,
    );

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => DecoratedBox(
        key: const ValueKey('reference-composer-surface'),
        decoration: BoxDecoration(
          color: barColor,
          border: Border(
            top: BorderSide(color: dividerColor, width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          minimum: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: const ValueKey('reference-composer-bar'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                constraints: const BoxConstraints(minHeight: 36),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _sizedIcon('voice', textColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ExtendedTextField(
                        key: const ValueKey('reference-composer-input'),
                        style: textStyle,
                        maxLines: 4,
                        minLines: 1,
                        focusNode: focusNode,
                        onChanged: (_) {},
                        onTap: () {},
                        keyboardType: TextInputType.text,
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        enableSuggestions: true,
                        textInputAction: TextInputAction.send,
                        onEditingComplete: () {},
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          hintStyle: textStyle.copyWith(color: hintColor),
                          fillColor: fillColor,
                          filled: true,
                          isDense: true,
                          hintText: hintText,
                        ),
                        controller: controller,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _sizedIcon('face', textColor),
                        const SizedBox(width: 10),
                        if (value.text.isEmpty)
                          _icon('add', textColor)
                        else
                          // Keep both upstream wrappers. The outer 36-pixel
                          // tight constraint overrides the inner height of 30.
                          SizedBox(
                            height: 36,
                            child: SizedBox(
                              height: 30,
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E90FF),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  minimumSize: const Size(0, 30),
                                  shape: const StadiumBorder(),
                                ),
                                child: const Text(
                                  '发送',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 14),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sizedIcon(String asset, Color color) => SizedBox(
        height: 36,
        child: Center(child: _icon(asset, color)),
      );

  Widget _icon(String asset, Color color) => InkWell(
        onTap: () {},
        child: SvgPicture.asset(
          'assets/chat/composer/$asset.svg',
          package: 'openim_common',
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          height: 26,
          width: 26,
        ),
      );
}
