part of 'reusable_dialog.dart';

class TwoActionDialog extends _DialogBase {
  const TwoActionDialog({
    super.key,
    required super.title,
    required super.content,
    required this.primaryLabel,
    required this.onPrimaryPressed,
    required this.secondaryLabel,
    required this.onSecondaryPressed,
    this.verticalActions = false,
    this.primaryBackgroundColor,
    this.primaryForegroundColor,
    this.primaryIcon,
    this.primaryTextStyle,
    this.secondaryBackgroundColor,
    this.secondaryForegroundColor,
    this.secondaryIcon,
    this.secondaryTextStyle,
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
  });

  final String primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final String secondaryLabel;
  final VoidCallback? onSecondaryPressed;
  final bool verticalActions;
  final Color? primaryBackgroundColor;
  final Color? primaryForegroundColor;
  final Widget? primaryIcon;
  final TextStyle? primaryTextStyle;
  final Color? secondaryBackgroundColor;
  final Color? secondaryForegroundColor;
  final Widget? secondaryIcon;
  final TextStyle? secondaryTextStyle;

  @override
  Widget buildActions() {
    final primary = primaryButton(
      label: primaryLabel,
      onPressed: onPrimaryPressed,
      backgroundColor: primaryBackgroundColor,
      foregroundColor: primaryForegroundColor,
      icon: primaryIcon,
      textStyle: primaryTextStyle,
    );
    final secondary = secondaryButton(
      label: secondaryLabel,
      onPressed: onSecondaryPressed,
      backgroundColor: secondaryBackgroundColor,
      foregroundColor: secondaryForegroundColor,
      icon: secondaryIcon,
      textStyle: secondaryTextStyle,
    );
    if (verticalActions) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [primary, const SizedBox(height: 10), secondary],
      );
    }
    return Row(
      children: [
        Expanded(child: secondary),
        const SizedBox(width: 10),
        Expanded(child: primary),
      ],
    );
  }
}
