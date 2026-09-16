part of 'reusable_dialog.dart';

class OneActionDialog extends _DialogBase {
  const OneActionDialog({
    super.key,
    required super.title,
    required super.content,
    required this.actionLabel,
    required this.onAction,
    super.eyebrow,
    this.actionBackgroundColor,
    this.actionForegroundColor,
    this.actionIcon,
    this.actionTextStyle,
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

  final String actionLabel;
  final VoidCallback? onAction;
  final Color? actionBackgroundColor;
  final Color? actionForegroundColor;
  final Widget? actionIcon;
  final TextStyle? actionTextStyle;

  @override
  Widget buildActions() => primaryButton(
    label: actionLabel,
    onPressed: onAction,
    backgroundColor: actionBackgroundColor,
    foregroundColor: actionForegroundColor,
    icon: actionIcon,
    textStyle: actionTextStyle,
  );
}
