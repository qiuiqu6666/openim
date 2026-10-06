import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class SearchBox extends StatefulWidget {
  const SearchBox({
    super.key,
    this.controller,
    this.focusNode,
    this.textStyle,
    this.hintStyle,
    this.hintText,
    this.searchIconColor,
    this.searchIcon,
    this.clearIcon,
    this.backgroundColor,
    this.searchIconHeight,
    this.searchIconWidth,
    this.margin,
    this.padding,
    this.enabled = false,
    this.autofocus = false,
    this.height,
    this.borderRadius,
    this.onSubmitted,
    this.onCleared,
    this.onChanged,
  });
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextStyle? hintStyle;
  final TextStyle? textStyle;
  final String? hintText;
  final Color? searchIconColor;

  /// Override bitmap artwork when a surface needs fully theme-colored icons.
  final Widget? searchIcon;
  final Widget? clearIcon;
  final Color? backgroundColor;
  final double? searchIconWidth;
  final double? searchIconHeight;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final bool enabled;
  final bool autofocus;
  final double? height;
  final BorderRadiusGeometry? borderRadius;
  final Function(String)? onSubmitted;
  final Function()? onCleared;
  final ValueChanged<String>? onChanged;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  bool _showClearBtn = false;

  @override
  void initState() {
    super.initState();
    _showClearBtn = widget.controller?.text.isNotEmpty ?? false;
    widget.controller?.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant SearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleControllerChanged);
      widget.controller?.addListener(_handleControllerChanged);
      _showClearBtn = widget.controller?.text.isNotEmpty ?? false;
    }
  }

  void _handleControllerChanged() {
    final showClear = widget.controller?.text.isNotEmpty ?? false;
    if (showClear != _showClearBtn) {
      setState(() => _showClearBtn = showClear);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height ?? 36.h,
      margin: widget.margin,
      padding: widget.padding ?? EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? Styles.c_8E9AB0_opacity15,
        borderRadius: widget.borderRadius ?? BorderRadius.circular(6.r),
      ),
      child: Row(
        children: [
          widget.searchIcon ??
              (ImageRes.searchGrey.toImage
                ..color = widget.searchIconColor
                ..width = widget.searchIconWidth ?? 18.w
                ..height = widget.searchIconHeight ?? 18.h),
          8.horizontalSpace,
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              style: widget.textStyle ?? Styles.ts_0C1C33_17sp,
              autofocus: widget.autofocus,
              enabled: widget.enabled,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.hintText ?? StrRes.search,
                hintStyle: widget.hintStyle ?? Styles.ts_8E9AB0_17sp,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
              onSubmitted: widget.onSubmitted,
              onChanged: widget.onChanged,
            ),
          ),
          if (_showClearBtn) _clearBtn,
        ],
      ),
    );
  }

  Widget get _clearBtn => Visibility(
        visible: _showClearBtn,
        child: GestureDetector(
          onTap: () {
            widget.controller?.clear();
            widget.onCleared?.call();
          },
          behavior: HitTestBehavior.translucent,
          child: widget.clearIcon ??
              (ImageRes.clearText.toImage
                ..width = widget.searchIconWidth ?? 24.w
                ..height = widget.searchIconHeight ?? 24.h
                ..color = widget.searchIconColor),
        ),
      );
}
