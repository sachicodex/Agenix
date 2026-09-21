part of 'reusable_dialog.dart';

class CustomTextActionDialog extends _DialogBase {
  const CustomTextActionDialog({
    super.key,
    super.title,
    super.content,
    super.description,
    required this.textButton,
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
    super.centerContent = true,
    super.centerTitle = true,
  });

  final TextOnlyButton textButton;

  @override
  Widget buildActions() => Center(child: textButton);
}
