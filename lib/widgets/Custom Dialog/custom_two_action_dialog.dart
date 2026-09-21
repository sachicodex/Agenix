part of 'reusable_dialog.dart';

class CustomTwoActionDialog extends _DialogBase {
  const CustomTwoActionDialog({
    super.key,
    super.title,
    super.content,
    super.description,
    required this.primaryButton,
    required this.secondaryButton,
    this.verticalActions = false,
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
  final SecondaryButton secondaryButton;
  final bool verticalActions;
  @override
  Widget buildActions() {
    if (verticalActions) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [primaryButton, const SizedBox(height: 10), secondaryButton],
      );
    }
    return Row(
      children: [
        Expanded(child: secondaryButton),
        const SizedBox(width: 10),
        Expanded(child: primaryButton),
      ],
    );
  }
}
