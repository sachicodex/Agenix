import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../theme/app_colors.dart';
import '../utils/platform_focus.dart';

/// Returns readable text from a rich description or a legacy plain value.
String plainDescriptionText(String value) {
  if (!value.startsWith('quill:')) return value;
  try {
    return Document.fromJson(
      jsonDecode(value.substring(6)) as List,
    ).toPlainText().trim();
  } catch (_) {
    return value;
  }
}

class _ToggleBulletListIntent extends Intent {
  const _ToggleBulletListIntent();
}

class _ToggleNumberListIntent extends Intent {
  const _ToggleNumberListIntent();
}

class _ToggleBoldIntent extends Intent {
  const _ToggleBoldIntent();
}

class _AddLinkIntent extends Intent {
  const _AddLinkIntent();
}

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
  final ValueChanged<bool>? onExpansionChanged;

  const ExpandableDescription({
    super.key,
    this.controller,
    this.hint,
    this.minLines = 1,
    this.maxLines = 5,
    this.onAIClick,
    this.aiLoading = false,
    this.onExpansionChanged,
  });

  @override
  State<ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<ExpandableDescription> {
  bool _isExpanded = false;
  final _focusNode = FocusNode();
  late final QuillController _quillController;
  bool _syncingExternalText = false;

  @override
  void initState() {
    super.initState();
    _quillController = QuillController(
      document: _documentFromStoredText(widget.controller?.text ?? ''),
      selection: const TextSelection.collapsed(offset: 0),
      keepStyleOnNewLine: true,
    )..addListener(_handleQuillChanged);
    widget.controller?.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant ExpandableDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleTextChanged);
      widget.controller?.addListener(_handleTextChanged);
      _replaceDocumentFromExternalText(widget.controller?.text ?? '');
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleTextChanged);
    _quillController
      ..removeListener(_handleQuillChanged)
      ..dispose();
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() => setState(() {});

  void _handleTextChanged() {
    if (_syncingExternalText) return;
    _replaceDocumentFromExternalText(widget.controller?.text ?? '');
    if (mounted) setState(() {});
  }

  void _handleQuillChanged() {
    if (_syncingExternalText) return;
    if (widget.controller != null) {
      final encoded =
          'quill:${jsonEncode(_quillController.document.toDelta().toJson())}';
      if (widget.controller!.text != encoded) {
        _syncingExternalText = true;
        widget.controller!.value = TextEditingValue(text: encoded);
        _syncingExternalText = false;
      }
    }
    if (mounted) setState(() {});
  }

  Document _documentFromStoredText(String value) {
    if (value.startsWith('quill:')) {
      try {
        return Document.fromJson(jsonDecode(value.substring(6)) as List);
      } catch (_) {
        // Fall through to a plain-text document for older/corrupt values.
      }
    }
    final document = Document();
    if (value.isNotEmpty) document.insert(0, value);
    return document;
  }

  void _replaceDocumentFromExternalText(String value) {
    final current =
        'quill:${jsonEncode(_quillController.document.toDelta().toJson())}';
    if (value == current) return;
    _syncingExternalText = true;
    _quillController.document = _documentFromStoredText(value);
    _quillController.moveCursorToEnd();
    _syncingExternalText = false;
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
    widget.onExpansionChanged?.call(_isExpanded);
    if (_isExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && shouldAutofocusTextInput) _focusNode.requestFocus();
      });
    }
  }

  void _format(Attribute attribute) {
    final currentAttribute = _quillController
        .getSelectionStyle()
        .attributes[attribute.key];
    final isActive = attribute == Attribute.ul || attribute == Attribute.ol
        ? currentAttribute?.value == attribute.value
        : currentAttribute != null;

    if (!isActive && (attribute == Attribute.ul || attribute == Attribute.ol)) {
      _insertListSpacerIfNeeded();
    }

    if (isActive &&
        (attribute == Attribute.ul || attribute == Attribute.ol) &&
        _exitEmptyListItemIfNeeded()) {
      _focusNode.requestFocus();
      return;
    }

    _quillController.formatSelection(
      isActive ? Attribute.clone(attribute, null) : attribute,
    );
    _focusNode.requestFocus();
  }

  bool _exitEmptyListItemIfNeeded() {
    final selection = _quillController.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;

    final plainText = _quillController.document.toPlainText();
    final cursor = selection.start.clamp(0, plainText.length);
    final lineStart = plainText.lastIndexOf('\n', cursor - 1) + 1;
    final lineEnd = plainText.indexOf('\n', cursor);
    final lineText = plainText.substring(
      lineStart,
      lineEnd == -1 ? plainText.length : lineEnd,
    );
    if (lineText.trim().isNotEmpty) return false;

    final node = _quillController.document.queryChild(lineStart).node;
    if (node is! Line ||
        !node.style.attributes.containsKey(Attribute.list.key)) {
      return false;
    }

    _quillController.formatText(
      selection.start,
      1,
      Attribute.clone(Attribute.list, null),
    );
    _quillController.replaceText(
      selection.start,
      0,
      '\n',
      TextSelection.collapsed(offset: selection.start + 1),
    );
    return true;
  }

  void _insertListSpacerIfNeeded() {
    final selection = _quillController.selection;
    if (!selection.isValid || !selection.isCollapsed) return;

    final current = _quillController.document.queryChild(selection.start).node;
    if (current is! Line || current.toPlainText().trim().isNotEmpty) return;

    final previous = _previousLine(current);
    final previousList = previous?.style.attributes[Attribute.list.key];
    final currentList = current.style.attributes[Attribute.list.key];
    if (previousList == null || currentList != null) return;

    // When a list is exited and the user immediately starts another list,
    // keep one empty paragraph between the two list blocks. This gives the
    // new list visual breathing room without increasing spacing between its
    // individual items.
    final cursor = selection.start;
    _quillController.replaceText(
      cursor,
      0,
      '\n',
      TextSelection.collapsed(offset: cursor + 1),
    );
  }

  Line? _previousLine(Line line) {
    if (!line.isFirst) return line.previous as Line?;
    final parent = line.parent;
    final previousBlock = parent is Block ? parent.previous : null;
    if (previousBlock is Block) return previousBlock.last as Line?;
    return previousBlock is Line ? previousBlock : null;
  }

  void _clearFormatting() {
    for (final Attribute attribute in <Attribute>[
      Attribute.bold,
      Attribute.italic,
      Attribute.underline,
      Attribute.strikeThrough,
      Attribute.link,
      Attribute.color,
      Attribute.background,
    ]) {
      _quillController.formatSelection(Attribute.clone(attribute, null));
    }
    _focusNode.requestFocus();
  }

  Future<void> _addLink() async {
    final selection = _quillController.selection;
    final selectedText = selection.isValid && !selection.isCollapsed
        ? _quillController.document.toPlainText().substring(
            selection.start,
            selection.end,
          )
        : '';
    final link = await showDialog<(String text, String url)>(
      context: context,
      builder: (context) {
        final textController = TextEditingController(text: selectedText);
        final urlController = TextEditingController();
        return AlertDialog(
          title: const Text('Add link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                autofocus: selectedText.isEmpty,
                decoration: const InputDecoration(labelText: 'Text to show'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                autofocus: selectedText.isNotEmpty,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(hintText: 'https://'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                textController.text.trim(),
                urlController.text.trim(),
              )),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    if (link == null || link.$1.isEmpty || link.$2.isEmpty) return;
    final start = selection.isValid
        ? selection.start
        : _quillController.selection.start;
    final length = selection.isValid ? selection.end - selection.start : 0;
    _quillController.replaceText(
      start,
      length,
      link.$1,
      TextSelection.collapsed(offset: start + link.$1.length),
    );
    _quillController.formatText(start, link.$1.length, LinkAttribute(link.$2));
    _focusNode.requestFocus();
  }

  QuillEditorConfig _editorConfig() {
    return QuillEditorConfig(
      autoFocus: false,
      padding: const EdgeInsets.all(16),
      scrollable: true,
      scrollPhysics: const ClampingScrollPhysics(),
      placeholder: null,
      // Quill styles ordered-list markers from the line style, while bold is
      // usually an inline style on the text. Mirror an all-bold list item on
      // its marker so the number visually belongs to the formatted text.
      // ignore: experimental_member_use
      customLeadingBlockBuilder: (node, config) {
        if (config.attribute != Attribute.ol || node is! Line) return null;

        final textChildren = node.children
            .where((child) => child.toPlainText().isNotEmpty)
            .toList();
        final isEntireLineBold =
            textChildren.isNotEmpty &&
            textChildren.every(
              (child) => child.style.containsKey(Attribute.bold.key),
            );
        if (!isEntireLineBold) return null;

        return QuillNumberPoint(
          index: config.getIndexNumberByIndent!,
          indentLevelCounts: config.indentLevelCounts,
          count: config.count,
          style: config.style!.copyWith(fontWeight: FontWeight.bold),
          attrs: config.attrs,
          width: config.width!,
          padding: config.padding!,
        );
      },
      customShortcuts: {
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            const _ToggleBoldIntent(),
        const SingleActivator(
          LogicalKeyboardKey.keyU,
          control: true,
          shift: true,
        ): const _ToggleBulletListIntent(),
        const SingleActivator(
          LogicalKeyboardKey.keyO,
          control: true,
          shift: true,
        ): const _ToggleNumberListIntent(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const _AddLinkIntent(),
      },
      customActions: {
        _ToggleBoldIntent: CallbackAction<_ToggleBoldIntent>(
          onInvoke: (_) {
            _format(Attribute.bold);
            return null;
          },
        ),
        _ToggleBulletListIntent: CallbackAction<_ToggleBulletListIntent>(
          onInvoke: (_) {
            _format(Attribute.ul);
            return null;
          },
        ),
        _ToggleNumberListIntent: CallbackAction<_ToggleNumberListIntent>(
          onInvoke: (_) {
            _format(Attribute.ol);
            return null;
          },
        ),
        _AddLinkIntent: CallbackAction<_AddLinkIntent>(
          onInvoke: (_) {
            _addLink();
            return null;
          },
        ),
      },
      // Quill exposes this hook for precise keyboard behavior in list blocks.
      // ignore: experimental_member_use
      onKeyPressed: (event, _) {
        final selection = _quillController.selection;
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            selection.isCollapsed) {
          final plainText = _quillController.document.toPlainText();
          final cursor = selection.start.clamp(0, plainText.length);
          final lineStart = plainText.lastIndexOf('\n', cursor - 1) + 1;
          final lineEnd = plainText.indexOf('\n', cursor);
          final lineText = plainText.substring(
            lineStart,
            lineEnd == -1 ? plainText.length : lineEnd,
          );
          final node = _quillController.document.queryChild(lineStart).node;
          final isListLine =
              node is Line &&
              node.style.attributes.containsKey(Attribute.list.key);
          final characterBeforeCaret =
              cursor > 0 && plainText[cursor - 1] != '\n'
              ? plainText[cursor - 1]
              : null;

          debugPrint(
            '[DescriptionEditor] Backspace: cursor=$cursor '
            'lineStart=$lineStart line="${lineText.replaceAll('\n', r'\n')}" '
            'charBefore=$characterBeforeCaret isList=$isListLine',
          );

          if (!isListLine) return null;

          // Handle character deletion ourselves for list lines. This prevents
          // Quill from interpreting deletion of the final character as an
          // empty-list exit in the same key event.
          if (characterBeforeCaret != null) {
            _quillController.replaceText(
              cursor - 1,
              1,
              '',
              TextSelection.collapsed(offset: cursor - 1),
            );
            debugPrint(
              '[DescriptionEditor] Deleted list character '
              '"$characterBeforeCaret"; list remains active',
            );
            return KeyEventResult.handled;
          }

          if (_exitEmptyListItemIfNeeded()) {
            debugPrint(
              '[DescriptionEditor] Empty list item exited; '
              'inserted spaced normal line',
            );
            return KeyEventResult.handled;
          }
        }
        return null;
      },
    );
  }

  Widget _formatButton(
    IconData icon,
    VoidCallback onPressed, {
    String? tooltip,
    bool isActive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: isActive
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.55))
            : null,
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: isActive
            ? AppColors.primary
            : AppColors.onSurface.withValues(alpha: 0.78),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        splashRadius: 17,
      ),
    );
  }

  Widget _formattingToolbar() {
    final selectionStyle = _quillController.getSelectionStyle();
    final attributes = selectionStyle.attributes;
    bool isActive(Attribute attribute) => attributes[attribute.key] != null;
    final activeList = attributes[Attribute.list.key]?.value;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderColor.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: Row(
        children: [
          _formatButton(
            Icons.format_bold,
            () => _format(Attribute.bold),
            isActive: isActive(Attribute.bold),
            tooltip: 'Bold (Ctrl+B)',
          ),
          _formatButton(
            Icons.format_italic,
            () => _format(Attribute.italic),
            isActive: isActive(Attribute.italic),
            tooltip: 'Italic (Ctrl+I)',
          ),
          _formatButton(
            Icons.format_underlined,
            () => _format(Attribute.underline),
            isActive: isActive(Attribute.underline),
            tooltip: 'Underline (Ctrl+U)',
          ),
          const SizedBox(width: 4),
          Container(width: 1, height: 22, color: AppColors.borderColor),
          const SizedBox(width: 4),
          _formatButton(
            Icons.format_list_numbered,
            () => _format(Attribute.ol),
            isActive: activeList == Attribute.ol.value,
            tooltip: 'Numbered list (Ctrl+Shift+O)',
          ),
          _formatButton(
            Icons.format_list_bulleted,
            () => _format(Attribute.ul),
            isActive: activeList == Attribute.ul.value,
            tooltip: 'Bulleted list (Ctrl+Shift+U)',
          ),
          const SizedBox(width: 4),
          Container(width: 1, height: 22, color: AppColors.borderColor),
          const SizedBox(width: 4),
          _formatButton(Icons.link, _addLink, tooltip: 'Add link (Ctrl+K)'),
          _formatButton(
            Icons.format_clear,
            _clearFormatting,
            tooltip: 'Clear formatting',
          ),
          const Spacer(),
          _formatButton(Icons.keyboard_arrow_up, _toggleExpanded),
          if (widget.onAIClick != null)
            IconButton(
              tooltip: 'Improve with AI',
              onPressed: widget.aiLoading ? null : widget.onAIClick,
              icon: widget.aiLoading
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Image.asset(
                      'assets/img/ai.png',
                      width: 20,
                      height: 20,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.auto_awesome, size: 19),
                    ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasText = plainDescriptionText(
      widget.controller?.text ?? '',
    ).isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          if (!_isExpanded)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggleExpanded,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notes_outlined,
                        size: 19,
                        color: AppColors.onSurface.withValues(alpha: 0.62),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          hasText ? 'Description added' : 'Add description',
                          style: AppTextStyles.bodyText1.copyWith(
                            color: AppColors.onSurface.withValues(
                              alpha: hasText ? 0.9 : 0.62,
                            ),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: AppColors.onSurface.withValues(alpha: 0.72),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isExpanded) ...[
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderColor),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _formattingToolbar(),
                  SizedBox(
                    height: 180,
                    child: QuillEditor.basic(
                      controller: _quillController,
                      focusNode: _focusNode,
                      config: _editorConfig(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
