import 'package:flutter/material.dart';
import 'dart:async';

import '../theme/app_colors.dart';
import 'app_popup.dart';
import 'calendar_color_picker.dart';

class AppSelectOption<T> {
  const AppSelectOption({required this.value, required this.label, this.color});

  final T value;
  final String label;
  final Color? color;
}

/// Dark, searchable selector used throughout Agenix instead of Flutter's
/// platform dropdown menu.
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hint = 'Select an option',
    this.enabled = true,
    this.searchable = true,
    this.onAddPressed,
    this.addTooltip = 'Create calendar',
    this.showAddInField = true,
    this.onDelete,
    this.hasError = false,
    this.onColorChanged,
    this.onNameChanged,
    this.fieldTextStyle = const TextStyle(fontWeight: FontWeight.w400),
    this.listTextStyle = const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppColors.onBackground,
    ),
  });

  final String label;
  final List<AppSelectOption<T>> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final String hint;
  final bool enabled;
  final bool searchable;
  final VoidCallback? onAddPressed;
  final String addTooltip;
  final bool showAddInField;
  final Future<bool> Function(T value)? onDelete;
  final bool hasError;
  final Future<Color?> Function(T value, Color currentColor)? onColorChanged;
  final Future<void> Function(T value, String name)? onNameChanged;
  final TextStyle fieldTextStyle;
  final TextStyle listTextStyle;

  @override
  Widget build(BuildContext context) {
    final selected = options
        .where((option) => option.value == value)
        .firstOrNull;
    final borderSide = hasError
        ? const BorderSide(color: Colors.red, width: 1)
        : const BorderSide(color: AppColors.borderColor);
    return InkWell(
      onTap: !enabled || onChanged == null
          ? null
          : () async {
              final next = await showAppDialog<T>(
                context: context,
                builder: (_) => _AppSelectDialog<T>(
                  label: label,
                  options: options,
                  selected: value,
                  searchable: searchable,
                  onAddPressed: onAddPressed,
                  addTooltip: addTooltip,
                  listTextStyle: listTextStyle,
                  onDelete: onDelete,
                  onColorChanged: onColorChanged,
                  onNameChanged: onNameChanged,
                ),
              );
              if (next != null) onChanged!(next);
            },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        isEmpty: selected == null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppTextStyles.bodyText1.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.7),
          ),
          filled: true,
          fillColor: AppColors.surface,
          suffixIcon: onAddPressed == null || !showAddInField
              ? null
              : IconButton(
                  tooltip: addTooltip,
                  onPressed: enabled ? onAddPressed : null,
                  icon: const Icon(Icons.add),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: borderSide,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: borderSide,
          ),
        ),
        child: _OptionRow(
          option: selected,
          fallback: hint,
          textStyle: fieldTextStyle,
        ),
      ),
    );
  }
}

class _AppSelectDialog<T> extends StatefulWidget {
  const _AppSelectDialog({
    required this.label,
    required this.options,
    required this.selected,
    required this.searchable,
    required this.onAddPressed,
    required this.addTooltip,
    required this.listTextStyle,
    required this.onDelete,
    required this.onColorChanged,
    required this.onNameChanged,
  });

  final String label;
  final List<AppSelectOption<T>> options;
  final T? selected;
  final bool searchable;
  final VoidCallback? onAddPressed;
  final String addTooltip;
  final TextStyle listTextStyle;
  final Future<bool> Function(T value)? onDelete;
  final Future<Color?> Function(T value, Color currentColor)? onColorChanged;
  final Future<void> Function(T value, String name)? onNameChanged;

  @override
  State<_AppSelectDialog<T>> createState() => _AppSelectDialogState<T>();
}

class _AppSelectDialogState<T> extends State<_AppSelectDialog<T>> {
  final _search = TextEditingController();
  final Map<T, Color> _updatedColors = {};
  final Map<T, String> _updatedNames = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final options = widget.options
        .where((option) => option.label.toLowerCase().contains(query))
        .toList();
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: AppColors.surface,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (widget.onAddPressed != null)
                      IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onAddPressed!();
                        },
                        icon: const Icon(
                          Icons.add,
                          color: AppColors.onBackground,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.searchable) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(Icons.search, color: AppColors.onTertiary),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: ClipRect(
                  child: options.isEmpty
                      ? const Center(child: Text('No matching options'))
                      : ListView.separated(
                          clipBehavior: Clip.hardEdge,
                          itemCount: options.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 2),
                          itemBuilder: (context, index) {
                            final option = options[index];
                            final selected = option.value == widget.selected;
                            final displayColor =
                                _updatedColors[option.value] ?? option.color;
                            final displayName =
                                _updatedNames[option.value] ?? option.label;
                            Future<void> editColor() async {
                              if (displayColor == null ||
                                  widget.onColorChanged == null) {
                                return;
                              }
                              final picked =
                                  await showAppDialog<_CalendarEditResult>(
                                    context: context,
                                    builder: (_) => _CalendarColorDialog(
                                      initialName: option.label,
                                      initialColor: displayColor,
                                    ),
                                  );
                              if (picked == null) return;
                              if (picked.name != option.label &&
                                  widget.onNameChanged != null) {
                                await widget.onNameChanged!(
                                  option.value,
                                  picked.name,
                                );
                                if (mounted) {
                                  setState(
                                    () => _updatedNames[option.value] =
                                        picked.name,
                                  );
                                }
                              }
                              final saved = await widget.onColorChanged!(
                                option.value,
                                picked.color,
                              );
                              if (saved != null && mounted) {
                                setState(
                                  () => _updatedColors[option.value] = saved,
                                );
                              }
                            }

                            return _HoldToDelete(
                              onHold: widget.onDelete == null
                                  ? null
                                  : () async {
                                      final confirmed = await showAppDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Delete calendar?'),
                                          content: const Text(
                                            'This calendar will be permanently deleted.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true &&
                                          await widget.onDelete!(
                                            option.value,
                                          )) {
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      }
                                    },
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                selected: false,
                                title: _OptionRow(
                                  option: AppSelectOption(
                                    value: option.value,
                                    label: displayName,
                                    color: option.color,
                                  ),
                                  color: displayColor,
                                  onColorPressed: widget.onColorChanged == null
                                      ? null
                                      : editColor,
                                  textStyle: widget.listTextStyle,
                                  textColor: selected
                                      ? option.color
                                      : AppColors.onBackground.withValues(
                                          alpha: 0.9,
                                        ),
                                ),
                                onTap: () =>
                                    Navigator.pop(context, option.value),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoldToDelete extends StatefulWidget {
  const _HoldToDelete({required this.child, this.onHold});
  final Widget child;
  final Future<void> Function()? onHold;
  @override
  State<_HoldToDelete> createState() => _HoldToDeleteState();
}

class _HoldToDeleteState extends State<_HoldToDelete> {
  Timer? _timer;
  void _start(PointerDownEvent _) {
    _timer = Timer(
      const Duration(milliseconds: 500),
      () => widget.onHold?.call(),
    );
  }

  void _cancel(PointerEvent _) => _timer?.cancel();
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _start,
    onPointerUp: _cancel,
    onPointerCancel: _cancel,
    onPointerMove: _cancel,
    child: widget.child,
  );
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    this.option,
    this.fallback,
    this.textColor,
    this.textStyle,
    this.color,
    this.onColorPressed,
  });

  final AppSelectOption<T>? option;
  final String? fallback;
  final Color? textColor;
  final TextStyle? textStyle;
  final Color? color;
  final VoidCallback? onColorPressed;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          option?.label ?? fallback ?? '',
          overflow: TextOverflow.ellipsis,
          style: textColor == null
              ? textStyle
              : textStyle?.copyWith(color: textColor),
        ),
      ),
      if ((color ?? option?.color) != null) ...[
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onColorPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: color ?? option!.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    ],
  );
}

class _CalendarColorDialog extends StatefulWidget {
  const _CalendarColorDialog({
    required this.initialColor,
    required this.initialName,
  });
  final String initialName;
  final Color initialColor;
  @override
  State<_CalendarColorDialog> createState() => _CalendarColorDialogState();
}

class _CalendarColorDialogState extends State<_CalendarColorDialog> {
  late Color _color = widget.initialColor;
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: 'Calendar name',
              labelStyle: TextStyle(color: AppColors.onSurface),
            ),
          ),
          const SizedBox(height: 20),
          CalendarColorPalette(
            selectedColor: _color,
            onChanged: (color) => setState(() => _color = color),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          if (name.isNotEmpty)
            Navigator.pop(context, _CalendarEditResult(name, _color));
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _CalendarEditResult {
  const _CalendarEditResult(this.name, this.color);
  final String name;
  final Color color;
}
