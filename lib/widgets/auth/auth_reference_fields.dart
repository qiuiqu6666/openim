import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_copy.dart';
import 'auth_reference_field_frame.dart';
import 'auth_reference_input_decoration.dart';
import 'auth_reference_tokens.dart';

/// Scroll padding so focused fields stay above the keyboard in auth scroll views.
EdgeInsets authFieldScrollPadding(BuildContext context) {
  final bottom = MediaQuery.viewInsetsOf(context).bottom;
  return EdgeInsets.fromLTRB(20, 20, 20, bottom + 120);
}

/// The auth theme supplies the platform's font; field sizes share one token.
TextStyle authFieldInputStyle(
  BuildContext context, {
  Color color = AuthReferenceTokens.ink800,
}) {
  return TextStyle(
    fontSize: AuthReferenceTokens.inputFontSize,
    fontWeight: FontWeight.w500,
    color: color,
    height: 1.2,
  );
}

TextStyle authFieldHintStyle(BuildContext context) {
  return authFieldInputStyle(context).copyWith(
    color: AuthReferenceTokens.hint,
    fontWeight: FontWeight.w400,
  );
}

class AuthTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final String? label;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final Widget? suffix;
  final Widget? prefix;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool showClearButton;
  final String? errorText;
  final bool reserveErrorSpace;
  final bool showErrorMessage;
  final ValueChanged<bool>? onFocusChanged;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.keyboardType,
    this.autofillHints,
    this.obscureText = false,
    this.suffix,
    this.prefix,
    this.enabled = true,
    this.inputFormatters,
    this.maxLength,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.showClearButton = true,
    this.errorText,
    this.reserveErrorSpace = false,
    this.showErrorMessage = true,
    this.onFocusChanged,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode.addListener(_focusChanged);
    widget.controller.addListener(_refreshClearButton);
  }

  @override
  void didUpdateWidget(covariant AuthTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refreshClearButton);
      widget.controller.addListener(_refreshClearButton);
      _refreshClearButton();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _focusNode).removeListener(_focusChanged);
      if (_ownsFocusNode) {
        _focusNode.dispose();
        _ownsFocusNode = false;
      }
      if (widget.focusNode != null) {
        _focusNode = widget.focusNode!;
        _ownsFocusNode = false;
      } else if (!_ownsFocusNode) {
        _focusNode = FocusNode();
        _ownsFocusNode = true;
      }
      _focusNode.addListener(_focusChanged);
      _refreshClearButton();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_focusChanged);
    widget.controller.removeListener(_refreshClearButton);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _refreshClearButton() {
    if (mounted) {
      setState(() {});
    }
  }

  void _focusChanged() {
    if (!mounted) return;
    widget.onFocusChanged?.call(_focusNode.hasFocus);
    _refreshClearButton();
  }

  bool get _showClear =>
      widget.showClearButton &&
      widget.enabled &&
      _focusNode.hasFocus &&
      widget.controller.text.isNotEmpty;

  void _clearText() {
    widget.controller.clear();
    widget.onChanged?.call('');
    _focusNode.requestFocus();
  }

  Widget? _buildSuffixIcon() {
    final clear = _showClear
        ? IconButton(
            onPressed: _clearText,
            tooltip: authText('清空输入', 'Clear input'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
                minWidth: AuthReferenceTokens.tapTarget,
                minHeight: AuthReferenceTokens.tapTarget),
            icon: const Icon(
              Icons.cancel,
              size: 18,
              color: AuthReferenceTokens.ink300,
            ),
          )
        : null;
    if (clear == null) {
      return widget.suffix;
    }
    if (widget.suffix == null) {
      return clear;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          clear,
          widget.suffix!,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inputStyle = authFieldInputStyle(context);
    final suffix = _buildSuffixIcon();
    final scrollPadding = authFieldScrollPadding(context);
    return AuthFieldFrame(
      focused: _focusNode.hasFocus,
      enabled: widget.enabled,
      errorText: widget.errorText,
      reserveErrorSpace: widget.reserveErrorSpace,
      showErrorMessage: widget.showErrorMessage,
      showBorder: widget.label == null,
      showFill: widget.label == null,
      child: TextField(
        controller: widget.controller,
        autofillHints: widget.autofillHints,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        keyboardType: widget.obscureText
            ? (widget.keyboardType ?? TextInputType.visiblePassword)
            : widget.keyboardType,
        obscureText: widget.obscureText,
        autocorrect: !widget.obscureText,
        enableSuggestions: !widget.obscureText,
        enabled: widget.enabled,
        inputFormatters: widget.inputFormatters,
        maxLength: widget.maxLength,
        onChanged: widget.onChanged,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onFieldSubmitted,
        scrollPadding: scrollPadding,
        style: inputStyle,
        cursorColor: AuthReferenceTokens.brand500,
        decoration: authReferenceInputDecoration(
          label: widget.label,
          hint: widget.hint,
          hintStyle: authFieldHintStyle(context),
          focused: _focusNode.hasFocus,
          enabled: widget.enabled,
          errorText: widget.errorText,
          contentPadding: AuthReferenceTokens.fieldContentPadding,
          prefix: widget.prefix,
          suffix: suffix,
        ),
      ),
    );
  }
}

class AuthCompoundField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final String? label;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final bool enabled;
  final Widget? leading;
  final Widget? trailing;
  final double? leadingWidth;
  final double? trailingWidth;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool showClearButton;
  final String? errorText;
  final bool reserveErrorSpace;
  final bool showErrorMessage;
  final ValueChanged<bool>? onFocusChanged;
  final TextStyle? inputStyle;
  final TextStyle? hintStyle;
  final bool showBorder;

  const AuthCompoundField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.keyboardType,
    this.autofillHints,
    this.obscureText = false,
    this.enabled = true,
    this.leading,
    this.trailing,
    this.leadingWidth,
    this.trailingWidth,
    this.inputFormatters,
    this.maxLength,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.showClearButton = true,
    this.errorText,
    this.reserveErrorSpace = false,
    this.showErrorMessage = true,
    this.onFocusChanged,
    this.inputStyle,
    this.hintStyle,
    this.showBorder = true,
  });

  @override
  State<AuthCompoundField> createState() => _AuthCompoundFieldState();
}

class _AuthCompoundFieldState extends State<AuthCompoundField> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode.addListener(_focusChanged);
    widget.controller.addListener(_refreshClearButton);
  }

  @override
  void didUpdateWidget(covariant AuthCompoundField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refreshClearButton);
      widget.controller.addListener(_refreshClearButton);
      _refreshClearButton();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _focusNode).removeListener(_focusChanged);
      if (_ownsFocusNode) {
        _focusNode.dispose();
        _ownsFocusNode = false;
      }
      if (widget.focusNode != null) {
        _focusNode = widget.focusNode!;
        _ownsFocusNode = false;
      } else if (!_ownsFocusNode) {
        _focusNode = FocusNode();
        _ownsFocusNode = true;
      }
      _focusNode.addListener(_focusChanged);
      _refreshClearButton();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_focusChanged);
    widget.controller.removeListener(_refreshClearButton);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _refreshClearButton() {
    if (mounted) {
      setState(() {});
    }
  }

  void _focusChanged() {
    if (!mounted) return;
    widget.onFocusChanged?.call(_focusNode.hasFocus);
    _refreshClearButton();
  }

  bool get _showClear =>
      widget.showClearButton &&
      widget.enabled &&
      _focusNode.hasFocus &&
      widget.controller.text.isNotEmpty;

  void _clearText() {
    widget.controller.clear();
    widget.onChanged?.call('');
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final inputStyle = widget.inputStyle ?? authFieldInputStyle(context);
    final scrollPadding = authFieldScrollPadding(context);
    return AuthFieldFrame(
      focused: _focusNode.hasFocus,
      enabled: widget.enabled,
      errorText: widget.errorText,
      reserveErrorSpace: widget.reserveErrorSpace,
      showErrorMessage: widget.showErrorMessage,
      showBorder: widget.showBorder && widget.label == null,
      showFill: widget.label == null,
      inputFontSize: inputStyle.fontSize ?? AuthReferenceTokens.inputFontSize,
      child: TextField(
        controller: widget.controller,
        autofillHints: widget.autofillHints,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        keyboardType: widget.obscureText
            ? (widget.keyboardType ?? TextInputType.visiblePassword)
            : widget.keyboardType,
        obscureText: widget.obscureText,
        enabled: widget.enabled,
        autocorrect: !widget.obscureText,
        enableSuggestions: !widget.obscureText,
        inputFormatters: widget.inputFormatters,
        maxLength: widget.maxLength,
        onChanged: widget.onChanged,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onFieldSubmitted,
        scrollPadding: scrollPadding,
        style: inputStyle,
        cursorColor: AuthReferenceTokens.brand500,
        decoration: authReferenceInputDecoration(
          label: widget.label,
          hint: widget.hint,
          hintStyle: widget.hintStyle ?? authFieldHintStyle(context),
          focused: _focusNode.hasFocus,
          enabled: widget.enabled,
          errorText: widget.errorText,
          showBorder: widget.showBorder,
          contentPadding: AuthReferenceTokens.compoundFieldContentPadding,
          prefix: widget.leading == null
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: widget.leadingWidth ?? 120,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: widget.leading,
                    ),
                  ),
                  _divider(),
                  const SizedBox(width: 12),
                ]),
          suffix: !_showClear && widget.trailing == null
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_showClear)
                    IconButton(
                      onPressed: _clearText,
                      tooltip: authText('清空输入', 'Clear input'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: AuthReferenceTokens.tapTarget,
                        minHeight: AuthReferenceTokens.tapTarget,
                      ),
                      icon: const Icon(Icons.cancel,
                          size: 18, color: AuthReferenceTokens.ink300),
                    ),
                  if (widget.trailing != null) ...[
                    _divider(),
                    SizedBox(
                      width: widget.trailingWidth ?? 120,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: widget.trailing,
                      ),
                    ),
                  ],
                ]),
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 22,
        color: AuthReferenceTokens.ink150,
      );
}
