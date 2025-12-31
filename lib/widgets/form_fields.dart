import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class LargeTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final String? label;
  final bool requiredField;

  const LargeTextField({
    super.key,
    this.controller,
    this.hint,
    this.label,
    this.requiredField = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          labelText: label,
          labelStyle: AppTextStyles.bodyText1.copyWith(
            color: AppColors.onSurface.withOpacity(0.7),
          ),
          hintStyle: AppTextStyles.bodyText1.copyWith(
            color: AppColors.onSurface.withOpacity(0.5),
          ),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        style: AppTextStyles.bodyText1,
      ),
    );
  }
}

class ExpandableDescription extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;

  const ExpandableDescription({super.key, this.controller, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64, maxHeight: 220),
        child: TextField(
          controller: controller,
          maxLines: null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.bodyText1.copyWith(
              color: AppColors.onSurface.withOpacity(0.5),
            ),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          style: AppTextStyles.bodyText1,
        ),
      ),
    );
  }
}
