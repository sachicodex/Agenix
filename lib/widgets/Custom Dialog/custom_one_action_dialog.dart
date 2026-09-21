part of 'reusable_dialog.dart';

class CustomOneActionDialog extends _DialogBase {
  const CustomOneActionDialog({
    super.key,
    super.title,
    super.content,
    super.description,
    required this.primaryButton,
    super.eyebrow,
    super.dialogWidth,
    super.maxDialogWidth,
    super.cancelAsText,
    super.cancelLabel,
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

  final PrimaryButton primaryButton;

  @override
  Widget buildActions() => primaryButton;
}
