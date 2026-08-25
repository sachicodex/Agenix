import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_popup.dart';

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
  final TextStyle fieldTextStyle;
  final TextStyle listTextStyle;

  @override
  Widget build(BuildContext context) {
    final selected = options
        .where((option) => option.value == value)
        .firstOrNull;
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
            borderSide: BorderSide.none,
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
  });

  final String label;
  final List<AppSelectOption<T>> options;
  final T? selected;
  final bool searchable;
  final VoidCallback? onAddPressed;
  final String addTooltip;
  final TextStyle listTextStyle;

  @override
  State<_AppSelectDialog<T>> createState() => _AppSelectDialogState<T>();
}

class _AppSelectDialogState<T> extends State<_AppSelectDialog<T>> {
  final _search = TextEditingController();

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
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              selected: false,
                              title: _OptionRow(
                                option: option,
                                textStyle: widget.listTextStyle,
                                textColor: selected
                                    ? option.color
                                    : AppColors.onBackground.withValues(
                                        alpha: 0.9,
                                      ),
                              ),
                              onTap: () => Navigator.pop(context, option.value),
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

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    this.option,
    this.fallback,
    this.textColor,
    this.textStyle,
  });

  final AppSelectOption<T>? option;
  final String? fallback;
  final Color? textColor;
  final TextStyle? textStyle;

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
      if (option?.color != null) ...[
        const SizedBox(width: 12),
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: option!.color,
            shape: BoxShape.circle,
          ),
        ),
      ],
    ],
  );
}
