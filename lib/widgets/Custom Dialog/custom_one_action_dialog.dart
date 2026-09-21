part of 'reusable_dialog.dart';

class CustomOneActionDialog extends _DialogBase {
  const CustomOneActionDialog({
    super.key,
    super.title,
    super.content,
    super.description,
    this.primaryButton,
    super.eyebrow,
    super.dialogWidth,
    super.maxDialogWidth,
    super.cancelAsText,
    super.cancelLabel,
    super.cancelTextColor,
    super.showCancelButton,
    super.onCancel,
    super.backgroundColor,
    super.foregroundColor,
    super.borderColor,
    super.borderRadius,
    super.contentPadding,
    super.actionsPadding,
    super.titleStyle,
    super.titleDescriptionSpacing,
    super.showCloseButton,
    super.descriptionStyle,
    super.centerContent = false,
    super.centerTitle = false,
  });

  final PrimaryButton? primaryButton;

  @override
  bool get cancelAtBottom => true;

  @override
  Widget buildActions() {
    if (!cancelAsText || !showCancelButton) {
      return primaryButton ?? const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (primaryButton != null) primaryButton!,
          if (primaryButton != null) const SizedBox(height: 10),
          Builder(
            builder: (context) => TextOnlyButton(
              label: cancelLabel,
              onPressed: onCancel ?? () => Navigator.of(context).pop(),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              foregroundColor: cancelTextColor ?? foregroundColor,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
