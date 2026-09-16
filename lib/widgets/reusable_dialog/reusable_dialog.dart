import 'package:flutter/material.dart';

import '../primary_button/primary_button.dart';
import '../secondary_button/secondary_button.dart';
import '../text_only_button/text_only_button.dart';

part 'one_action_dialog.dart';
part 'two_action_dialog.dart';
part 'text_action_dialog.dart';

abstract class _DialogBase extends StatelessWidget {
  const _DialogBase({
    super.key,
    required this.title,
    required this.content,
    this.eyebrow,
    this.dialogWidth = 520,
    this.maxDialogWidth = 720,
    this.cancelAsText = false,
    this.cancelLabel = 'Cancel',
    this.onCancel,
    this.backgroundColor = const Color(0xFF161616),
    this.foregroundColor = const Color(0xFFF4F4F5),
    this.borderColor = const Color(0xFF2A2A2A),
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.contentPadding = const EdgeInsets.fromLTRB(22, 18, 22, 18),
    this.actionsPadding = const EdgeInsets.fromLTRB(22, 0, 22, 18),
    this.titleStyle = const TextStyle(
      fontSize: 25,
      fontWeight: FontWeight.w800,
    ),
    this.centerContent = false,
    this.centerTitle = false,
  });

  final String title;
  final String? eyebrow;
  final Widget content;
  final double dialogWidth;
  final double maxDialogWidth;
  final bool cancelAsText;
  final String cancelLabel;
  final VoidCallback? onCancel;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry actionsPadding;
  final TextStyle titleStyle;
  final bool centerContent;
  final bool centerTitle;

  Widget buildActions();

  Widget primaryButton({
    required String label,
    required VoidCallback? onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
    Widget? icon,
    TextStyle? textStyle,
  }) => PrimaryButton(
    label: label,
    icon: icon,
    onPressed: onPressed,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    textStyle: textStyle,
    width: double.infinity,
  );

  Widget secondaryButton({
    required String label,
    required VoidCallback? onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
    Widget? icon,
    TextStyle? textStyle,
  }) => SecondaryButton(
    label: label,
    icon: icon,
    onPressed: onPressed,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    textStyle: textStyle,
    width: double.infinity,
  );

  Widget textButton({
    required String label,
    required VoidCallback? onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
    Widget? icon,
    TextStyle? textStyle,
  }) => TextOnlyButton(
    label: label,
    icon: icon,
    onPressed: onPressed,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    textStyle: textStyle,
  );

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    final width = dialogWidth
        .clamp(0.0, maxDialogWidth)
        .clamp(0.0, availableWidth);
    final close = onCancel ?? () => Navigator.of(context).pop();

    return Dialog(
      backgroundColor: backgroundColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: borderColor),
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogTitle(
                eyebrow: eyebrow,
                title: title,
                titleStyle: titleStyle,
                foregroundColor: foregroundColor,
                cancelAsText: cancelAsText,
                cancelLabel: cancelLabel,
                onCancel: close,
                centerTitle: centerTitle,
              ),
              const SizedBox(height: 18),
              centerContent
                  ? Center(child: content)
                  : Align(alignment: Alignment.centerLeft, child: content),
              const SizedBox(height: 22),
              Padding(padding: actionsPadding, child: buildActions()),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogTitle extends StatelessWidget {
  const _DialogTitle({
    required this.eyebrow,
    required this.title,
    required this.titleStyle,
    required this.foregroundColor,
    required this.cancelAsText,
    required this.cancelLabel,
    required this.onCancel,
    required this.centerTitle,
  });

  final String? eyebrow;
  final String title;
  final TextStyle titleStyle;
  final Color foregroundColor;
  final bool cancelAsText;
  final String cancelLabel;
  final VoidCallback onCancel;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: centerTitle
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            if (eyebrow != null && eyebrow!.isNotEmpty)
              Text(
                eyebrow!,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            Text(
              title,
              textAlign: centerTitle ? TextAlign.center : TextAlign.start,
              style: titleStyle,
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      cancelAsText
          ? TextOnlyButton(
              label: cancelLabel,
              onPressed: onCancel,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              foregroundColor: foregroundColor,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            )
          : TextOnlyButton(
              icon: Icon(Icons.close, size: 20, color: foregroundColor),
              onPressed: onCancel,
              width: 36,
              height: 36,
              padding: EdgeInsets.zero,
              foregroundColor: foregroundColor,
            ),
    ],
  );
}
