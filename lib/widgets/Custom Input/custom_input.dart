import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

class CustomInput extends StatelessWidget {
  const CustomInput({
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
    this.width = double.infinity,
    this.backgroundColor = Colors.transparent,
    this.borderColor = const Color(0x24F4F4F5),
    this.focusedBorderColor = const Color(0x52F4F4F5),
    this.errorColor = const Color(0xFFEF4444),
    this.iconColor = const Color(0xFFD4D4D8),
    this.iconSize = 20,
    this.iconStrokeWidth = 2,
    this.cursorColor = const Color(0xFFC8F902),
    this.selectionColor = const Color(0x4DC8F902),
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.borderWidth = 1,
    this.focusedBorderWidth = 1.2,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 14,
    ),
    this.textStyle = const TextStyle(
      fontFamily: 'GoogleSans',
      color: Color(0xFFF4F4F5),
    ),
    this.hintStyle = const TextStyle(
      fontFamily: 'GoogleSans',
      color: Color(0xFFa1a1aa),
    ),
    this.labelStyle = const TextStyle(fontFamily: 'GoogleSans'),
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
  final double width;
  final Color backgroundColor;
  final Color? borderColor;
  final Color? focusedBorderColor;
  final Color errorColor;
  final Color iconColor;
  final double iconSize;
  final double iconStrokeWidth;
  final Color cursorColor;
  final Color selectionColor;
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

  Widget? _icon(Widget? icon) {
    if (icon == null) return null;
    if (icon is HugeIcon) {
      return SizedBox(
        width: 48,
        child: Center(
          child: HugeIcon(
            icon: icon.icon,
            color: icon.color ?? iconColor,
            secondaryColor: icon.secondaryColor,
            disableSecondaryOpacity: icon.disableSecondaryOpacity,
            size: icon.size == 24.0 ? iconSize : icon.size,
            strokeWidth: icon.strokeWidth ?? iconStrokeWidth,
          ),
        ),
      );
    }
    return SizedBox(
      width: 48,
      child: Center(
        child: IconTheme(
          data: IconThemeData(color: iconColor, size: iconSize),
          child: icon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      hintText: hintText,
      labelText: labelText,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: showPrefixIcon ? _icon(prefixIcon) : null,
      suffixIcon: showSuffixIcon ? _icon(suffixIcon) : null,
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
      errorBorder: _border(errorColor, borderWidth),
      focusedErrorBorder: _border(errorColor, focusedBorderWidth),
    );
    return SizedBox(
      width: width,
      child: DefaultSelectionStyle.merge(
        cursorColor: cursorColor,
        selectionColor: selectionColor,
        child: TextFormField(
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
          cursorColor: cursorColor,
        ),
      ),
    );
  }
}
