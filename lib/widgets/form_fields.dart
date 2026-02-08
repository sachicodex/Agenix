import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class LargeTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? hint;
  final String? label;
  final bool requiredField;
  final VoidCallback? onAIClick;
  final bool aiLoading;

  const LargeTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.hint,
    this.label,
    this.requiredField = false,
    this.onAIClick,
    this.aiLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
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
          suffixIcon: onAIClick != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: IconButton(
                    icon: aiLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                            ),
                          )
                        : Image.asset(
                            'assets/img/ai.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.auto_awesome,
                                color: AppColors.primary,
                                size: 24,
                              );
                            },
                          ),
                    onPressed: aiLoading ? null : onAIClick,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                )
              : null,
        ),
        style: AppTextStyles.bodyText1,
      ),
    );
  }
}

class ExpandableDescription extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final VoidCallback? onAIClick;
  final bool aiLoading;

  const ExpandableDescription({
    super.key,
    this.controller,
    this.hint,
    this.onAIClick,
    this.aiLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: 3,
        textInputAction: TextInputAction.newline,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          hintText: hint,
          labelText: hint,
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 16.0,
          ),
          suffixIcon: onAIClick != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: IconButton(
                    icon: aiLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                            ),
                          )
                        : Image.asset(
                            'assets/img/ai.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.auto_awesome,
                                color: AppColors.primary,
                                size: 24,
                              );
                            },
                          ),
                    onPressed: aiLoading ? null : onAIClick,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                )
              : null,
        ),
        style: AppTextStyles.bodyText1,
      ),
    );
  }
}
