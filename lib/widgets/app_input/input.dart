import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';

/// Reusable text input with configurable icons and dark app defaults.
class AppInput extends StatelessWidget {
  const AppInput({
    super.key,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.hintText,
    this.labelText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.showPrefixIcon = true,
    this.showSuffixIcon = true,
    this.backgroundColor = Colors.transparent,
    this.borderColor = AppColors.glassBorder,
    this.focusedBorderColor = AppColors.glassBorderFocus,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.borderWidth = 1,
    this.focusedBorderWidth = 1.2,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 14,
    ),
    this.textStyle,
    this.hintStyle,
    this.labelStyle,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.minLines,
    this.maxLines = 1,
    this.readOnly = false,
    this.inputFormatters,
    this.validator,
  }) : assert(
         controller == null || initialValue == null,
         'Use controller or initialValue, not both.',
       );

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? hintText;
  final String? labelText;
  final String? helperText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool showPrefixIcon;
  final bool showSuffixIcon;
  final Color backgroundColor;
  final Color? borderColor;
  final Color? focusedBorderColor;
  final BorderRadius borderRadius;
  final double borderWidth;
  final double focusedBorderWidth;
  final EdgeInsetsGeometry contentPadding;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;
  final TextStyle? labelStyle;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? minLines;
  final int? maxLines;
  final bool readOnly;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  InputBorder _border(Color? color, double width) => OutlineInputBorder(
    borderRadius: borderRadius,
    borderSide: color == null
        ? BorderSide.none
        : BorderSide(color: color, width: width),
  );

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      hintText: hintText,
      labelText: labelText,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: showPrefixIcon ? prefixIcon : null,
      suffixIcon: showSuffixIcon ? suffixIcon : null,
      filled: true,
      fillColor: backgroundColor,
      contentPadding: contentPadding,
      hintStyle: hintStyle,
      labelStyle: labelStyle,
      border: _border(borderColor, borderWidth),
      enabledBorder: _border(borderColor, borderWidth),
      focusedBorder: _border(
        focusedBorderColor ?? borderColor,
        focusedBorderWidth,
      ),
      errorBorder: _border(Colors.red, borderWidth),
      focusedErrorBorder: _border(Colors.red, focusedBorderWidth),
    );
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      initialValue: initialValue,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      decoration: decoration,
      style: textStyle,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      minLines: minLines,
      maxLines: obscureText ? 1 : maxLines,
      readOnly: readOnly,
      inputFormatters: inputFormatters,
      validator: validator,
    );
  }
}
