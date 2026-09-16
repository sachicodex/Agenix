part of 'reusable_dialog.dart';

class TextActionDialog extends _DialogBase {
  const TextActionDialog({
    super.key,
    required super.title,
    required super.content,
    required this.actionLabel,
    required this.onAction,
    this.actionBackgroundColor,
    this.actionForegroundColor,
    this.actionIcon,
    this.actionTextStyle,
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
  }) : super(centerContent: true, centerTitle: true);

  final String actionLabel;
  final VoidCallback? onAction;
  final Color? actionBackgroundColor;
  final Color? actionForegroundColor;
  final Widget? actionIcon;
  final TextStyle? actionTextStyle;

  @override
  Widget buildActions() => Center(
    child: textButton(
      label: actionLabel,
      onPressed: onAction,
      backgroundColor: actionBackgroundColor,
      foregroundColor: actionForegroundColor,
      icon: actionIcon,
      textStyle: actionTextStyle,
    ),
  );
}
