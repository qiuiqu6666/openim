import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class NameEditorInput extends StatelessWidget {
  const NameEditorInput({
    super.key,
    required this.controller,
    required this.maxLength,
    required this.onSave,
    this.hintText,
    this.showClearButton = false,
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
  final bool saving;
  final bool saveEnabled;
  final TextInputType? keyboardType;
  final Widget? inputStatus;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
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
          fillColor: Styles.c_FFFFFF,
          border: _border(),
          enabledBorder: _border(),
          focusedBorder: _border(),
          counterText: '',
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
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
                        onPressed: saving ? null : controller.clear,
                        tooltip: StrRes.clearAll,
                        constraints: const BoxConstraints(
                          minWidth: kMinInteractiveDimension,
                          minHeight: kMinInteractiveDimension,
                        ),
                        visualDensity: VisualDensity.standard,
                        color: Styles.c_8E9AB0,
                        icon: const Icon(Icons.cancel, size: AppTokens.s5),
                      ),
                    if (inputStatus != null) ...[
                      inputStatus!,
                      const SizedBox(width: AppTokens.s3),
                    ],
                    Text('${value.text.characters.length}/$maxLength',
                        style: Styles.ts_8E9AB0_13sp),
                  ],
                ),
              ),
            ),
          ),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 18.w, vertical: 13.h),
        ),
      );

  OutlineInputBorder _border() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: BorderSide.none,
      );
}
