import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';
import '../../../../../widgets/text_input/caret_selection_controls.dart';
import '../../../../../widgets/text_input/sensitive_caret_region.dart';

class NameEditorInput extends StatefulWidget {
  const NameEditorInput({
    super.key,
    required this.controller,
    required this.maxLength,
    required this.onSave,
    this.hintText,
    this.showClearButton = false,
    this.remarkLayout = false,
    this.saving = false,
    this.saveEnabled = true,
    this.keyboardType,
    this.inputStatus,
  });

  final TextEditingController controller;
  final int maxLength;
  final VoidCallback onSave;
  final String? hintText;
  final bool showClearButton;
  final bool remarkLayout;
  final bool saving;
  final bool saveEnabled;
  final TextInputType? keyboardType;
  final Widget? inputStatus;

  @override
  State<NameEditorInput> createState() => _NameEditorInputState();
}

class _NameEditorInputState extends State<NameEditorInput> {
  bool _startedEditing = false;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (_startedEditing) return;
    _startedEditing = true;
    final controller = widget.controller;
    final text =
        controller.text.isEmpty ? widget.hintText ?? '' : controller.text;
    controller.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final maxLength = widget.maxLength;
    final onSave = widget.onSave;
    final hintText = widget.hintText;
    final showClearButton = widget.showClearButton;
    final saving = widget.saving;
    final saveEnabled = widget.saveEnabled;
    final keyboardType = widget.keyboardType;
    final inputStatus = widget.inputStatus;
    final input = SensitiveCaretRegion(
      focusNode: saving ? null : _focusNode,
      onDragStart: _startEditing,
      child: TextField(
        focusNode: _focusNode,
        controller: controller,
        selectionControls: caretSelectionControls(context),
        onTap: _startEditing,
        enabled: !saving,
        maxLength: maxLength,
        keyboardType: keyboardType,
        maxLines: 1,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          if (!saving && saveEnabled) onSave();
        },
        style: TextStyle(color: Styles.c_0C1C33, fontSize: 16.sp),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Styles.c_8E9AB0, fontSize: 16.sp),
          filled: true,
          fillColor: widget.remarkLayout ? Styles.c_F4F5F7 : Styles.c_FFFFFF,
          border: _border(),
          enabledBorder: _border(),
          focusedBorder: _border(),
          counterText: '',
          suffixIcon: widget.remarkLayout
              ? null
              : ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (_, value, __) => Padding(
                    padding: EdgeInsets.only(left: 8.w, right: 18.w),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showClearButton && value.text.isNotEmpty)
                            IconButton(
                              key: const ValueKey('name-editor-clear'),
                              onPressed: saving
                                  ? null
                                  : () {
                                      _startedEditing = true;
                                      controller.clear();
                                    },
                              tooltip: StrRes.clearAll,
                              constraints: const BoxConstraints(
                                minWidth: kMinInteractiveDimension,
                                minHeight: kMinInteractiveDimension,
                              ),
                              visualDensity: VisualDensity.standard,
                              color: Styles.c_8E9AB0,
                              icon:
                                  const Icon(Icons.cancel, size: AppTokens.s5),
                            ),
                          if (inputStatus != null) ...[
                            inputStatus,
                            const SizedBox(width: AppTokens.s3),
                          ],
                          Text('${value.text.characters.length}/$maxLength',
                              style: Styles.ts_8E9AB0_13sp),
                        ],
                      ),
                    ),
                  ),
                ),
          contentPadding: widget.remarkLayout
              ? const EdgeInsets.fromLTRB(
                  AppTokens.s3, AppTokens.s2, AppTokens.s3, AppTokens.s4)
              : EdgeInsets.symmetric(horizontal: 18.w, vertical: 13.h),
        ),
      ),
    );
    if (!widget.remarkLayout) return input;
    return Container(
      decoration: BoxDecoration(
        color: Styles.c_F4F5F7,
        borderRadius: BorderRadius.circular(AppTokens.s2.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          input,
          Padding(
            padding: const EdgeInsets.only(
                right: AppTokens.s4, bottom: AppTokens.s2),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, __) => Text(
                '${(maxLength - value.text.characters.length).clamp(0, maxLength)}',
                textAlign: TextAlign.right,
                style: Styles.ts_8E9AB0_13sp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _border() => OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(widget.remarkLayout ? AppTokens.s2.r : 10.r),
        borderSide: BorderSide.none,
      );
}
