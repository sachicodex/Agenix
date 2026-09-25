import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../theme/app_colors.dart';
import '../utils/platform_focus.dart';
import 'app_popup.dart';
import 'Custom Dialog/reusable_dialog.dart';
import 'Primary Button/primary_button.dart' as dialog_buttons;
import 'Secondary Button/secondary_button.dart';

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

class _IgnoreEditorShortcutIntent extends Intent {
  const _IgnoreEditorShortcutIntent();
}

class _AddLinkIntent extends Intent {
  const _AddLinkIntent();
}

class _IncreaseFontSizeIntent extends Intent {
  const _IncreaseFontSizeIntent();
}

class _DecreaseFontSizeIntent extends Intent {
  const _DecreaseFontSizeIntent();
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
  final VoidCallback? onSubmitted;
  final Color backgroundColor;

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
    this.onSubmitted,
    this.backgroundColor = Colors.transparent,
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

    Widget textField = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus && shouldAutofocusTextInput,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      textInputAction: onSubmitted == null ? null : TextInputAction.done,
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
        fillColor: backgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: hasError
              ? const BorderSide(color: AppColors.error, width: 1)
              : const BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: hasError
              ? const BorderSide(color: AppColors.error, width: 1)
              : const BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.glassBorderFocus,
            width: 1.2,
          ),
        ),
        contentPadding: EdgeInsets.fromLTRB(16, 16, rightPadding, 16),
      ),
      style: AppTextStyles.bodyText1,
    );

    if (onSubmitted != null) {
      textField = Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.enter):
              const _SubmitLargeTextFieldIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _SubmitLargeTextFieldIntent: CallbackAction<Intent>(
              onInvoke: (_) {
                onSubmitted!();
                return null;
              },
            ),
          },
          child: textField,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: focusNode ?? _unfocused,
            builder: (context, _) => textField,
          ),
          if (aiOverlayButton != null) Positioned.fill(child: aiOverlayButton),
        ],
      ),
    );
  }
}

class _SubmitLargeTextFieldIntent extends Intent {
  const _SubmitLargeTextFieldIntent();
}

class ExpandableDescription extends StatefulWidget {
  final TextEditingController? controller;
  final String? hint;
  final int minLines;
  final int maxLines;
  final VoidCallback? onAIClick;
  final bool aiLoading;
  final ValueChanged<bool>? onExpansionChanged;
  final Color backgroundColor;
  final bool initiallyExpanded;
  final double editorHeight;

  const ExpandableDescription({
    super.key,
    this.controller,
    this.hint,
    this.minLines = 1,
    this.maxLines = 5,
    this.onAIClick,
    this.aiLoading = false,
    this.onExpansionChanged,
    this.backgroundColor = Colors.transparent,
    this.initiallyExpanded = false,
    this.editorHeight = 180,
  });

  @override
  State<ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<ExpandableDescription> {
  late bool _isExpanded;
  final _focusNode = FocusNode();
  late final QuillController _quillController;
  bool _syncingExternalText = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _quillController = QuillController(
      document: _documentFromStoredText(widget.controller?.text ?? ''),
      selection: const TextSelection.collapsed(offset: 0),
      keepStyleOnNewLine: true,
      // ignore: experimental_member_use
      config: const QuillControllerConfig(
        // ignore: experimental_member_use
        clipboardConfig: QuillClipboardConfig(
          // The Windows native HTML clipboard bridge can return a null
          // pointer for ordinary text clipboard data. Let Quill use its
          // internal Delta clipboard and plain-text fallback instead.
          // ignore: experimental_member_use
          enableExternalRichPaste: false,
        ),
      ),
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
    if (attribute == Attribute.ul || attribute == Attribute.ol) {
      _formatList(attribute);
      return;
    }

    final currentAttribute = _quillController
        .getSelectionStyle()
        .attributes[attribute.key];
    final isActive = currentAttribute != null;

    _quillController.formatSelection(
      isActive ? Attribute.clone(attribute, null) : attribute,
    );
    _focusNode.requestFocus();
  }

  void _formatList(Attribute listAttribute) {
    final selection = _quillController.selection;
    if (!selection.isValid) return;

    final lineStart = _lineStart(selection.start);
    final line = _lineAt(lineStart);
    if (line == null) {
      // An empty Quill document can briefly report no line while focus is
      // moving. Applying the list attribute to the selection is safe and
      // lets Quill create its default paragraph/list line.
      _quillController.formatSelection(listAttribute);
      _focusNode.requestFocus();
      return;
    }

    final currentList = line.style.attributes[Attribute.list.key]?.value;
    final currentLevel = _lineIndent(line);
    final isSameList = currentList == listAttribute.value;

    if (isSameList && _isEmptyLine(lineStart)) {
      _removeCurrentListLevel(lineStart, line);
      _focusNode.requestFocus();
      return;
    }

    if (isSameList) {
      _formatLineAttribute(
        lineStart,
        line,
        Attribute.clone(Attribute.list, null),
      );
      _formatLineAttribute(
        lineStart,
        line,
        Attribute.clone(Attribute.indent, null),
      );
      _focusNode.requestFocus();
      return;
    }

    // Changing list type inside a list creates a child list. Quill carries
    // the line attributes to the next line, so this also makes Enter continue
    // the newly selected nested list naturally.
    if (currentList != null && !isSameList) {
      _formatLineAttribute(
        lineStart,
        line,
        Attribute.getIndentLevel(currentLevel + 1),
      );
      _formatLineAttribute(lineStart, line, listAttribute);
    } else {
      _insertListSpacerIfNeeded();
      _quillController.formatSelection(listAttribute);
    }
    _focusNode.requestFocus();
  }

  int _lineStart(int offset) {
    final text = _quillController.document.toPlainText();
    final cursor = offset.clamp(0, text.length);
    if (cursor == 0) return 0;
    return text.lastIndexOf('\n', cursor - 1) + 1;
  }

  Line? _lineAt(int lineStart) {
    Line? result;
    for (final line in _documentLines()) {
      if (line.documentOffset == lineStart) {
        result = line;
        break;
      }
    }
    return result;
  }

  List<Line> _documentLines() {
    final lines = <Line>[];
    void visit(Node node) {
      if (node is Line) {
        lines.add(node);
      } else if (node is Block) {
        for (final child in node.children) {
          visit(child);
        }
      }
    }

    for (final node in _quillController.document.root.children) {
      visit(node);
    }
    return lines;
  }

  int _lineEnd(int lineStart) {
    final text = _quillController.document.toPlainText();
    final end = text.indexOf('\n', lineStart);
    return end == -1 ? text.length : end;
  }

  int _lineIndent(Line line) {
    final value = line.style.attributes[Attribute.indent.key]?.value;
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  bool _isEmptyLine(int lineStart) => _quillController.document
      .toPlainText()
      .substring(lineStart, _lineEnd(lineStart))
      .trim()
      .isEmpty;

  void _formatLineAttribute(int lineStart, Line line, Attribute attribute) {
    final length = _lineEnd(lineStart) - lineStart + 1;
    _quillController.formatText(lineStart, length, attribute);
  }

  Line? _parentListLine(Line line, int level) {
    final lines = _documentLines();
    final currentIndex = lines.indexOf(line);
    var previous = currentIndex > 0 ? lines[currentIndex - 1] : null;
    while (previous != null) {
      final previousList = previous.style.attributes[Attribute.list.key];
      if (previousList != null && _lineIndent(previous) < level) {
        return previous;
      }
      final index = lines.indexOf(previous);
      previous = index > 0 ? lines[index - 1] : null;
    }
    return null;
  }

  void _removeCurrentListLevel(int lineStart, Line line) {
    final currentLevel = _lineIndent(line);
    final currentList = line.style.attributes[Attribute.list.key]?.value;
    final parent = currentLevel > 0
        ? _parentListLine(line, currentLevel)
        : _implicitParentNumberedLine(line);
    final parentList = parent?.style.attributes[Attribute.list.key];

    _logListDebug(
      'remove-start cursor=${_quillController.selection.start} '
      'lineStart=$lineStart lineText="${line.toPlainText().replaceAll('\n', r'\n')}" '
      'list=$currentList level=$currentLevel '
      'parentList=${parentList?.value} '
      'parentText="${parent?.toPlainText().replaceAll('\n', r'\n')}"',
    );

    // Quill may omit the indent attribute on an empty nested bullet. If its
    // nearest list parent is numbered, treat Backspace as returning to that
    // numbered list rather than removing list formatting entirely.
    if (currentLevel == 0 &&
        currentList == Attribute.ul.value &&
        parent != null &&
        parentList?.value == Attribute.ol.value) {
      _formatLineAttribute(lineStart, line, Attribute.ol);
      _quillController.updateSelection(
        TextSelection.collapsed(offset: lineStart),
        ChangeSource.local,
      );
      _logListDebug('branch=implicit-parent-numbered cursor=$lineStart');
      return;
    }

    if (currentLevel == 0 && currentList != null && _isEmptyLine(lineStart)) {
      // Keep a blank paragraph between the last root-list item and the new
      // normal paragraph. This makes the end of the list visually distinct
      // while keeping the caret on the following line.
      _quillController.replaceText(
        lineStart,
        0,
        '\n',
        TextSelection.collapsed(offset: lineStart + 1),
      );
      final nextLineStart = lineStart + 1;
      // Format the terminators directly instead of looking up the shifted
      // Line node; Quill may rebuild that node during replaceText.
      for (final start in <int>[lineStart, nextLineStart]) {
        _quillController.formatText(
          start,
          1,
          Attribute.clone(Attribute.list, null),
        );
        _quillController.formatText(
          start,
          1,
          Attribute.clone(Attribute.indent, null),
        );
      }
      _quillController.updateSelection(
        TextSelection.collapsed(offset: nextLineStart),
        ChangeSource.local,
      );
      _logListDebug(
        'branch=root-empty-exit blankStart=$lineStart '
        'cursor=$nextLineStart delta=${_quillController.document.toDelta().toJson()}',
      );
      return;
    }

    if (currentLevel > 0) {
      // Convert the current line in place. Do not insert a temporary spacer:
      // Quill may rebuild its block tree immediately, making the old offset
      // point at no line and leaving the caret on the wrong paragraph.
      final targetStart = lineStart;
      _formatLineAttribute(
        targetStart,
        line,
        parentList ?? line.style.attributes[Attribute.list.key]!,
      );
      _formatLineAttribute(
        targetStart,
        line,
        currentLevel == 1
            ? Attribute.clone(Attribute.indent, null)
            : Attribute.getIndentLevel(currentLevel - 1),
      );
      // Formatting the line can leave the selection on the temporary spacer
      // inserted above it. Put the caret at the start of the converted parent
      // item so Quill renders it immediately after the new list marker.
      if (currentLevel == 1 && parent != null) {
        _quillController.updateSelection(
          TextSelection.collapsed(offset: targetStart),
          ChangeSource.local,
        );
      }
      _logListDebug(
        'branch=nested-exit targetStart=$targetStart '
        'cursor=${_quillController.selection.start} '
        'delta=${_quillController.document.toDelta().toJson()}',
      );
      return;
    }

    _formatLineAttribute(
      lineStart,
      line,
      Attribute.clone(Attribute.list, null),
    );
    _formatLineAttribute(
      lineStart,
      line,
      Attribute.clone(Attribute.indent, null),
    );
    _logListDebug(
      'branch=root-nonempty-exit cursor=${_quillController.selection.start} '
      'delta=${_quillController.document.toDelta().toJson()}',
    );
  }

  void _logListDebug(String message) {
    debugPrint('[DescriptionEditor][List] $message');
  }

  Line? _implicitParentNumberedLine(Line line) {
    final lines = _documentLines();
    final currentIndex = lines.indexOf(line);
    var previous = currentIndex > 0 ? lines[currentIndex - 1] : null;
    while (previous != null) {
      final list = previous.style.attributes[Attribute.list.key]?.value;
      if (list == Attribute.ol.value) return previous;
      if (list == null) return null;
      final index = lines.indexOf(previous);
      previous = index > 0 ? lines[index - 1] : null;
    }
    return null;
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
    // Quill can group lines in Block nodes. A line's previous sibling is not
    // guaranteed to be another Line, so never cast it directly.
    final previousSibling = line.previous;
    final previousLine = _lastLineIn(previousSibling);
    if (previousLine != null) return previousLine;

    final parent = line.parent;
    return _lastLineIn(parent?.previous);
  }

  Line? _lastLineIn(Node? node) {
    if (node is Line) return node;
    if (node is Block && node.isNotEmpty) {
      final last = node.last;
      return _lastLineIn(last);
    }
    return null;
  }

  Future<void> _addLink() async {
    final selection = _quillController.selection;
    final selectedText = selection.isValid && !selection.isCollapsed
        ? _quillController.document.toPlainText().substring(
            selection.start,
            selection.end,
          )
        : '';
    final link = await showAppDialog<(String text, String url)>(
      context: context,
      builder: (context) {
        final textController = TextEditingController(text: selectedText);
        final urlController = TextEditingController();
        return CustomTwoActionDialog(
          showCloseButton: false,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                autofocus: selectedText.isEmpty,
                decoration: const InputDecoration(hintText: 'Text to show'),
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
          secondaryButton: SecondaryButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context),
            backgroundColor: Colors.transparent,
            borderSide: const BorderSide(color: Colors.white24),
          ),
          primaryButton: dialog_buttons.PrimaryButton(
            label: 'Apply',
            onPressed: () => Navigator.pop(context, (
              textController.text.trim(),
              urlController.text.trim(),
            )),
          ),
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

  int _orderedListIndex(Line line, int level) {
    var index = 1;
    var previous = _previousLine(line);
    while (previous != null) {
      final previousLevel = _lineIndent(previous);
      final previousList = previous.style.attributes[Attribute.list.key]?.value;
      if (previousLevel < level) break;
      if (previousLevel == level && previousList == Attribute.ol.value) {
        index++;
      }
      previous = _previousLine(previous);
    }
    return index;
  }

  String _formatOrderedMarker(int index, int level) {
    if (level % 3 == 1) {
      final result = StringBuffer();
      var value = index;
      while (value > 0) {
        value--;
        result.write(String.fromCharCode((value % 26) + 97));
        value ~/= 26;
      }
      return result.toString().split('').reversed.join();
    }
    if (level % 3 == 2) {
      const values = <int, String>{
        1000: 'm',
        900: 'cm',
        500: 'd',
        400: 'cd',
        100: 'c',
        90: 'xc',
        50: 'l',
        40: 'xl',
        10: 'x',
        9: 'ix',
        5: 'v',
        4: 'iv',
        1: 'i',
      };
      var value = index;
      final result = StringBuffer();
      for (final entry in values.entries) {
        while (value >= entry.key) {
          result.write(entry.value);
          value -= entry.key;
        }
      }
      return result.toString();
    }
    return '$index';
  }

  QuillEditorConfig _editorConfig() {
    final defaultStyles = DefaultStyles.getInstance(context);
    final paragraphStyle = defaultStyles.paragraph?.copyWith(
      style: defaultStyles.paragraph!.style.copyWith(height: 1.25),
    );
    return QuillEditorConfig(
      autoFocus: false,
      padding: const EdgeInsets.all(16),
      scrollable: true,
      scrollPhysics: const ClampingScrollPhysics(),
      placeholder: null,
      customStyles: defaultStyles.merge(
        DefaultStyles(
          paragraph: paragraphStyle,
          link: defaultStyles.link?.copyWith(decoration: TextDecoration.none),
        ),
      ),
      // Quill styles ordered-list markers from the line style, while bold is
      // usually an inline style on the text. Mirror an all-bold list item on
      // its marker so the number visually belongs to the formatted text.
      // ignore: experimental_member_use
      customLeadingBlockBuilder: (node, config) {
        if (config.attribute != Attribute.ol || node is! Line) return null;

        final level = _lineIndent(node);
        final orderedIndex = _orderedListIndex(node, level);
        final marker = _formatOrderedMarker(orderedIndex, level);

        final textChildren = node.children
            .where((child) => child.toPlainText().isNotEmpty)
            .toList();
        final isEntireLineBold =
            textChildren.isNotEmpty &&
            textChildren.every(
              (child) => child.style.containsKey(Attribute.bold.key),
            );
        return QuillNumberPoint(
          index: marker,
          indentLevelCounts: config.indentLevelCounts,
          count: config.count,
          style: isEntireLineBold
              ? config.style!.copyWith(fontWeight: FontWeight.bold)
              : config.style!,
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
        const SingleActivator(LogicalKeyboardKey.keyL, control: true):
            const _AddLinkIntent(),
        const SingleActivator(
          LogicalKeyboardKey.equal,
          control: true,
          shift: true,
        ): const _IncreaseFontSizeIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
            const _IncreaseFontSizeIntent(),
        const SingleActivator(LogicalKeyboardKey.minus, control: true):
            const _DecreaseFontSizeIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
            const _DecreaseFontSizeIntent(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const _IgnoreEditorShortcutIntent(),
        const SingleActivator(
          LogicalKeyboardKey.keyL,
          control: true,
          shift: true,
        ): const _IgnoreEditorShortcutIntent(),
      },
      customActions: {
        _IgnoreEditorShortcutIntent:
            CallbackAction<_IgnoreEditorShortcutIntent>(onInvoke: (_) => null),
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
        _IncreaseFontSizeIntent: CallbackAction<_IncreaseFontSizeIntent>(
          onInvoke: (_) {
            _changeFontSize(2);
            return null;
          },
        ),
        _DecreaseFontSizeIntent: CallbackAction<_DecreaseFontSizeIntent>(
          onInvoke: (_) {
            _changeFontSize(-2);
            return null;
          },
        ),
      },
      // Quill exposes this hook for precise keyboard behavior in list blocks.
      // ignore: experimental_member_use
      onKeyPressed: (event, _) {
        final selection = _quillController.selection;
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            selection.isCollapsed) {
          final lineStart = _lineStart(selection.start);
          final line = _lineAt(lineStart);
          if (line != null &&
              line.style.attributes.containsKey(Attribute.list.key) &&
              _isEmptyLine(lineStart)) {
            _removeCurrentListLevel(lineStart, line);
            _focusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            selection.isCollapsed) {
          final plainText = _quillController.document.toPlainText();
          final cursor = selection.start.clamp(0, plainText.length);
          final lineStart = _lineStart(cursor);
          final line = _lineAt(lineStart);
          _logListDebug(
            'backspace cursor=${selection.start} clamped=$cursor '
            'lineStart=$lineStart lineFound=${line != null} '
            'lineText="${line?.toPlainText().replaceAll('\n', r'\n')}" '
            'attrs=${line?.style.attributes}',
          );
          if (line == null ||
              !line.style.attributes.containsKey(Attribute.list.key)) {
            _logListDebug('backspace branch=not-list-or-line-missing');
            return null;
          }

          // Let Quill delete normal characters. At a list boundary, however,
          // remove one list level first so Backspace never eats the previous
          // item's content unexpectedly.
          if (cursor == lineStart) {
            _logListDebug('backspace branch=list-boundary');
            _removeCurrentListLevel(lineStart, line);
            _focusNode.requestFocus();
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

  void _changeFontSize(double delta) {
    final value = _quillController
        .getSelectionStyle()
        .attributes[Attribute.size.key]
        ?.value;
    final currentSize = switch (value) {
      'small' => 14.0,
      'large' => 18.0,
      'huge' => 24.0,
      num size => size.toDouble(),
      String size => double.tryParse(size) ?? 16.0,
      _ => 16.0,
    };
    final nextSize = (currentSize + delta).clamp(10.0, 48.0).toDouble();
    final attribute = Attribute.fromKeyValue(
      Attribute.size.key,
      nextSize.toString(),
    );
    if (attribute == null) return;
    _quillController.formatSelection(attribute);
    _focusNode.requestFocus();
  }

  Widget _formattingToolbar() {
    final selectionStyle = _quillController.getSelectionStyle();
    final attributes = selectionStyle.attributes;
    bool isActive(Attribute attribute) => attributes[attribute.key] != null;
    final activeList = attributes[Attribute.list.key]?.value;
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    final toolbar = Row(
      mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
      children: [
        _formatButton(Icons.text_increase_rounded, () => _changeFontSize(2)),
        _formatButton(Icons.text_decrease_rounded, () => _changeFontSize(-2)),
        const SizedBox(width: 4),
        Container(width: 1, height: 22, color: AppColors.glassBorder),
        const SizedBox(width: 4),
        _formatButton(
          Icons.format_bold,
          () => _format(Attribute.bold),
          isActive: isActive(Attribute.bold),
        ),
        _formatButton(
          Icons.format_italic,
          () => _format(Attribute.italic),
          isActive: isActive(Attribute.italic),
        ),
        _formatButton(
          Icons.format_underlined,
          () => _format(Attribute.underline),
          isActive: isActive(Attribute.underline),
        ),
        const SizedBox(width: 4),
        Container(width: 1, height: 22, color: AppColors.glassBorder),
        const SizedBox(width: 4),
        _formatButton(
          Icons.format_list_numbered,
          () => _format(Attribute.ol),
          isActive: activeList == Attribute.ol.value,
        ),
        _formatButton(
          Icons.format_list_bulleted,
          () => _format(Attribute.ul),
          isActive: activeList == Attribute.ul.value,
        ),
        const SizedBox(width: 4),
        Container(width: 1, height: 22, color: AppColors.glassBorder),
        const SizedBox(width: 4),
        _formatButton(Icons.link, _addLink),
        if (!isMobile) const Spacer(),
        if (widget.onAIClick != null)
          IconButton(
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
    );

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
      ),
      child: isMobile
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: toolbar,
            )
          : toolbar,
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
                    color: widget.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.glassBorder),
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
                color: widget.backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _formattingToolbar(),
                  SizedBox(
                    height: widget.editorHeight,
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
