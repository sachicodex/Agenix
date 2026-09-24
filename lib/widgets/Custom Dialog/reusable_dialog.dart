import 'package:agenix/widgets/Custom%20Text/custom_text.dart';
import 'package:agenix/widgets/Primary%20Button/primary_button.dart';
import 'package:flutter/material.dart';

import '../Secondary Button/secondary_button.dart';
import '../Text Only Button/text_only_button.dart';
import '../Glass Card/glass_carrd.dart';

part 'custom_one_action_dialog.dart';
part 'custom_two_action_dialog.dart';
part 'custom_text_action_dialog.dart';

abstract class _DialogBase extends StatelessWidget {
  const _DialogBase({
    super.key,
    this.title,
    this.content,
    this.description,
    this.eyebrow,
    this.dialogWidth = 520,
    this.maxDialogWidth = 720,
    this.cancelAsText = false,
    this.cancelLabel = 'Cancel',
    this.cancelTextColor,
    this.showCancelButton = true,
    this.onCancel,
    this.backgroundColor = const Color(0xFF161616),
    this.foregroundColor = const Color(0xFFF4F4F5),
    this.borderColor = const Color(0xFF2A2A2A),
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.contentPadding = const EdgeInsets.fromLTRB(22, 18, 22, 18),
    this.actionsPadding = const EdgeInsets.fromLTRB(0, 0, 0, 18),
    this.titleStyle = const TextStyle(
      fontSize: 25,
      fontWeight: FontWeight.w800,
    ),
    this.centerContent = false,
    this.centerTitle = false,
    this.contentAboveDescription = false,
    this.titleDescriptionSpacing = 0,
    this.showCloseButton = true,
    this.descriptionStyle,
    this.useGlassCard = true,
  });

  final String? title;
  final String? description;
  final String? eyebrow;
  final Widget? content;
  final double dialogWidth;
  final double maxDialogWidth;
  final bool cancelAsText;
  final String cancelLabel;
  final Color? cancelTextColor;
  final bool showCancelButton;
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
  final bool contentAboveDescription;
  final double titleDescriptionSpacing;
  final bool showCloseButton;
  final TextStyle? descriptionStyle;
  final bool useGlassCard;

  Widget buildActions();

  bool get cancelAtBottom => false;

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    final width = dialogWidth
        .clamp(0.0, maxDialogWidth)
        .clamp(0.0, availableWidth);
    final close = onCancel ?? () => Navigator.of(context).pop();

    final dialogContent = Padding(
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
            showCloseButton:
                showCloseButton &&
                showCancelButton &&
                !(cancelAsText && cancelAtBottom),
          ),
          if ((title != null && title!.trim().isNotEmpty) ||
              (eyebrow != null && eyebrow!.trim().isNotEmpty))
            SizedBox(height: titleDescriptionSpacing),
          if (contentAboveDescription && content != null)
            centerContent
                ? Center(child: content)
                : Align(alignment: Alignment.centerLeft, child: content),
          if (contentAboveDescription && content != null)
            const SizedBox(height: 12),
          if (description != null && description!.trim().isNotEmpty)
            centerContent
                ? SizedBox(
                    width: double.infinity,
                    child: CustomTextDescription(
                      description!,
                      textAlign: TextAlign.center,
                      style: descriptionStyle,
                    ),
                  )
                : CustomTextDescription(description!, style: descriptionStyle),
          if (!contentAboveDescription &&
              description != null &&
              description!.trim().isNotEmpty &&
              content != null)
            const SizedBox(height: 12),
          if (!contentAboveDescription && content != null)
            centerContent
                ? Center(child: content)
                : Align(alignment: Alignment.centerLeft, child: content),
          if ((description != null && description!.trim().isNotEmpty) ||
              content != null)
            const SizedBox(height: 22),
          Padding(padding: actionsPadding, child: buildActions()),
        ],
      ),
    );
    final surface = useGlassCard
        ? GlassCard(
            width: width,
            padding: EdgeInsets.zero,
            borderRadius: borderRadius is BorderRadius
                ? borderRadius as BorderRadius
                : BorderRadius.circular(18),
            tintColor: Colors.white,
            tintOpacity: 0.075,
            borderColor: Colors.white,
            borderOpacity: 0.16,
            blurSigma: 22,
            child: dialogContent,
          )
        : Container(
            width: width,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: borderRadius,
              border: Border.all(color: borderColor),
            ),
            child: dialogContent,
          );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: surface,
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
    required this.showCloseButton,
  });

  final String? eyebrow;
  final String? title;
  final TextStyle titleStyle;
  final Color foregroundColor;
  final bool cancelAsText;
  final String cancelLabel;
  final VoidCallback onCancel;
  final bool centerTitle;
  final bool showCloseButton;

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
              CustomTextMuted(
                eyebrow!,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            if (title != null && title!.trim().isNotEmpty)
              CustomTextHeading(
                title!,
                textAlign: centerTitle ? TextAlign.center : TextAlign.start,
                style: titleStyle,
              ),
          ],
        ),
      ),
      if (showCloseButton) ...[
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
                label: null,
                icon: Icon(Icons.close, size: 20, color: foregroundColor),
                onPressed: onCancel,
                width: 36,
                height: 36,
                padding: EdgeInsets.zero,
                foregroundColor: foregroundColor,
              ),
      ],
    ],
  );
}
