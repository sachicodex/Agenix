import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_popup.dart';
import '../utils/platform_focus.dart';

class LargeTextField extends StatelessWidget {
  static final ValueNotifier<bool> _unfocused = ValueNotifier<bool>(false);
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? hint;
  final String? label;
  final int minLines;
  final int maxLines;
  final bool requiredField;
  final VoidCallback? onAIClick;
  final bool aiLoading;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  const LargeTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.hint,
    this.label,
    this.minLines = 1,
    this.maxLines = 1,
    this.requiredField = false,
    this.onAIClick,
    this.aiLoading = false,
    this.hasError = false,
    this.onChanged,
  });

  Widget? _buildAiOverlayButton() {
    if (onAIClick == null) return null;

    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Align(
        alignment: Alignment.centerRight,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aiOverlayButton = _buildAiOverlayButton();
    final rightPadding = aiOverlayButton == null ? 16.0 : 56.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: focusNode ?? _unfocused,
            builder: (context, _) => TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus && shouldAutofocusTextInput,
              minLines: minLines,
              maxLines: maxLines,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: focusNode?.hasFocus == true ? null : hint,
                labelText: label,
                labelStyle: AppTextStyles.bodyText1.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.7),
                ),
                hintStyle: AppTextStyles.bodyText1.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: hasError
                      ? const BorderSide(color: Colors.red, width: 1)
                      : const BorderSide(color: AppColors.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: hasError
                      ? const BorderSide(color: Colors.red, width: 1)
                      : const BorderSide(color: AppColors.borderColor),
                ),
                contentPadding: EdgeInsets.fromLTRB(16, 16, rightPadding, 16),
              ),
              style: AppTextStyles.bodyText1,
            ),
          ),
          if (aiOverlayButton != null) Positioned.fill(child: aiOverlayButton),
        ],
      ),
    );
  }
}

class ExpandableDescription extends StatefulWidget {
  final TextEditingController? controller;
  final String? hint;
  final int minLines;
  final int maxLines;
  final VoidCallback? onAIClick;
  final bool aiLoading;

  const ExpandableDescription({
    super.key,
    this.controller,
    this.hint,
    this.minLines = 1,
    this.maxLines = 5,
    this.onAIClick,
    this.aiLoading = false,
  });

  @override
  State<ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<ExpandableDescription> {
  bool _showExpandAction = false;
  double _lastMeasuredWidth = 0;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant ExpandableDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleTextChanged);
      widget.controller?.addListener(_handleTextChanged);
      _scheduleOverflowCheck();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleTextChanged);
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() => setState(() {});

  void _handleTextChanged() {
    _scheduleOverflowCheck();
  }

  void _scheduleOverflowCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastMeasuredWidth <= 0) return;
      _updateOverflowState(_lastMeasuredWidth);
    });
  }

  void _updateOverflowState(double width) {
    final controller = widget.controller;
    if (controller == null) {
      if (_showExpandAction) {
        setState(() => _showExpandAction = false);
      }
      return;
    }

    final actionWidth = widget.onAIClick != null ? 52.0 : 0.0;
    final availableTextWidth = width - 32 - actionWidth;
    if (availableTextWidth <= 0) return;

    final textPainter = TextPainter(
      text: TextSpan(
        text: controller.text.isEmpty ? (widget.hint ?? '') : controller.text,
        style: AppTextStyles.bodyText1,
      ),
      textDirection: Directionality.of(context),
      maxLines: widget.maxLines,
    )..layout(maxWidth: availableTextWidth);

    final exceedsMaxLines = textPainter.didExceedMaxLines;
    if (exceedsMaxLines != _showExpandAction) {
      setState(() => _showExpandAction = exceedsMaxLines);
    }
  }

  Future<void> _openExpandedEditor() async {
    final controller = widget.controller;
    if (controller == null) return;

    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: AppColors.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: shouldAutofocusTextInput,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      style: AppTextStyles.bodyText1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget? _buildExpandButton() {
    if (!_showExpandAction) return null;

    return SizedBox(
      width: 48,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, right: 12),
          child: IconButton(
            icon: const Icon(Icons.fullscreen, size: 18),
            onPressed: _openExpandedEditor,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            splashRadius: 14,
          ),
        ),
      ),
    );
  }

  Widget? _buildAiSuffixIcon() {
    if (widget.onAIClick == null) return null;

    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          icon: widget.aiLoading
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
          onPressed: widget.aiLoading ? null : widget.onAIClick,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if ((_lastMeasuredWidth - constraints.maxWidth).abs() > 1) {
            _lastMeasuredWidth = constraints.maxWidth;
            _scheduleOverflowCheck();
          }

          final expandButton = _buildExpandButton();
          final rightPadding = widget.onAIClick == null ? 16.0 : 56.0;

          return Stack(
            alignment: Alignment.topRight,
            children: [
              TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                autofocus: shouldAutofocusTextInput,
                minLines: widget.minLines,
                maxLines: widget.maxLines,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  // The floating label already identifies a focused field.
                  // Hiding the duplicate inner hint keeps every form field
                  // visually clean while the user types.
                  hintText: _focusNode.hasFocus ? null : widget.hint,
                  labelText: widget.hint,
                  labelStyle: AppTextStyles.bodyText1.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.7),
                  ),
                  hintStyle: AppTextStyles.bodyText1.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.fromLTRB(16, 16, rightPadding, 16),
                ),
                style: AppTextStyles.bodyText1,
              ),
              if (widget.onAIClick != null)
                Positioned.fill(child: _buildAiSuffixIcon()!),
              if (expandButton != null)
                Positioned(top: 0, right: 0, child: expandButton),
            ],
          );
        },
      ),
    );
  }
}
