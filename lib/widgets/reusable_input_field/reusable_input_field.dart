import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A reusable, configurable text input field.
///
/// Prefix and suffix properties accept any widget, including Flutter [Icon],
/// `HugeIcon`, SVG, or a custom widget. Pass [decoration] to replace the
/// default decoration completely.
class ReusableInputField extends StatelessWidget {
  const ReusableInputField({
    super.key,
    this.controller,
    this.initialValue,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.onSaved,
    this.validator,
    this.onEditingComplete,
    this.inputFormatters,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.textColor = const Color(0xFFF4F4F5),
    this.hintColor = const Color(0xFFA1A1AA),
    this.fillColor = const Color(0xFF161616),
    this.borderColor = const Color(0xFF2A2A2A),
    this.focusedBorderColor = const Color(0xFF3A3A3A),
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 13,
    ),
    this.decoration,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.expands = false,
    this.enabledBorder,
    this.focusedBorder,
    this.keyboardAppearance,
    this.cursorColor,
    this.autovalidateMode,
    this.scrollPadding = const EdgeInsets.all(20),
  }) : assert(
         controller == null || initialValue == null,
         'Use controller or initialValue, not both.',
       );

  final TextEditingController? controller;
  final String? initialValue;
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final String? helperText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final Widget? prefix;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldSetter<String>? onSaved;
  final FormFieldValidator<String>? validator;
  final VoidCallback? onEditingComplete;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final Color? textColor;
  final Color? hintColor;
  final Color? fillColor;
  final Color? borderColor;
  final Color? focusedBorderColor;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry contentPadding;
  final InputDecoration? decoration;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool expands;
  final InputBorder? enabledBorder;
  final InputBorder? focusedBorder;
  final Brightness? keyboardAppearance;
  final Color? cursorColor;
  final AutovalidateMode? autovalidateMode;
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context) {
    final inputDecoration =
        decoration ??
        InputDecoration(
          hintText: hintText,
          labelText: labelText,
          helperText: helperText,
          errorText: errorText,
          hintStyle: TextStyle(color: hintColor),
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          prefix: prefix,
          suffix: suffix,
          filled: true,
          fillColor: fillColor,
          contentPadding: contentPadding,
          border: OutlineInputBorder(
            borderRadius: borderRadius,
            borderSide: BorderSide(color: borderColor ?? Colors.transparent),
          ),
          enabledBorder:
              enabledBorder ??
              OutlineInputBorder(
                borderRadius: borderRadius,
                borderSide: BorderSide(
                  color: borderColor ?? Colors.transparent,
                ),
              ),
          focusedBorder:
              focusedBorder ??
              OutlineInputBorder(
                borderRadius: borderRadius,
                borderSide: BorderSide(
                  color: focusedBorderColor ?? Colors.transparent,
                ),
              ),
        );

    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      focusNode: focusNode,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      onSaved: onSaved,
      validator: validator,
      onEditingComplete: onEditingComplete,
      inputFormatters: inputFormatters,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      style: style ?? TextStyle(color: textColor),
      decoration: inputDecoration,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      obscureText: obscureText,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      expands: expands,
      keyboardAppearance: keyboardAppearance,
      cursorColor: cursorColor,
      autovalidateMode: autovalidateMode,
      scrollPadding: scrollPadding,
    );
  }
}
