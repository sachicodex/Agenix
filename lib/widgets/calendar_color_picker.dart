import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:async';

import '../theme/app_colors.dart';
import 'app_popup.dart';

const _baseCalendarColors = <Color>[
  Color(0xFFD65A82),
  Color(0xFFF07A3E),
  Color(0xFFE8BF54),
  Color(0xFF68B98D),
  Color(0xFF5D9ED5),
  Color(0xFF9186D8),
  Color(0xFFAE64C7),
  Color(0xFFD96F68),
  Color(0xFFB7A896),
  Color(0xFFCB5479),
  Color(0xFFF08A42),
  Color(0xFFD5A646),
  Color(0xFF58A67C),
  Color(0xFF508ECA),
  Color(0xFF7D78C8),
  Color(0xFF974EB9),
  Color(0xFFCB6963),
  Color(0xFF8A8A8A),
  Color(0xFFDF877B),
  Color(0xFFE8B550),
  Color(0xFF72C59B),
  Color(0xFF7EABDB),
  Color(0xFFAD9BDF),
  Color(0xFFAF9D8A),
];

final _customCalendarColors = ValueNotifier<List<Color>>(<Color>[]);

class CalendarColorPalette extends StatelessWidget {
  const CalendarColorPalette({
    super.key,
    required this.selectedColor,
    required this.onChanged,
  });

  final Color selectedColor;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<Color>>(
    valueListenable: _customCalendarColors,
    builder: (context, customColors, _) {
      final colors = [..._baseCalendarColors, ...customColors];
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          ...colors.map(
            (color) => _ColorSwatch(
              color: color,
              selected: color.toARGB32() == selectedColor.toARGB32(),
              onTap: () => onChanged(color),
              onHold: customColors.contains(color)
                  ? () async {
                      final confirmed = await showAppDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete custom color?'),
                          content: const Text(
                            'Remove this color from the palette?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        _customCalendarColors.value = _customCalendarColors
                            .value
                            .where(
                              (item) => item.toARGB32() != color.toARGB32(),
                            )
                            .toList();
                      }
                    }
                  : null,
            ),
          ),
          _ColorSwatch(
            icon: Icons.add,
            onTap: () async {
              final color = await showAppDialog<Color>(
                context: context,
                builder: (_) => const _CustomColorDialog(),
              );
              if (color == null) return;
              if (!_customCalendarColors.value.any(
                (item) => item.toARGB32() == color.toARGB32(),
              )) {
                _customCalendarColors.value = [
                  ..._customCalendarColors.value,
                  color,
                ];
              }
              onChanged(color);
            },
          ),
        ],
      );
    },
  );
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    this.color,
    this.selected = false,
    this.icon,
    required this.onTap,
    this.onHold,
  });
  final Color? color;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;
  final Future<void> Function()? onHold;

  @override
  Widget build(BuildContext context) => _HoldAction(
    onHold: onHold,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color ?? AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : AppColors.borderColor,
            width: selected ? 3 : 1,
          ),
        ),
        child: icon != null
            ? Icon(icon, color: AppColors.onBackground, size: 19)
            : selected
            ? const Icon(Icons.check, size: 18, color: Colors.black87)
            : null,
      ),
    ),
  );
}

class _HoldAction extends StatefulWidget {
  const _HoldAction({required this.child, this.onHold});
  final Widget child;
  final Future<void> Function()? onHold;
  @override
  State<_HoldAction> createState() => _HoldActionState();
}

class _HoldActionState extends State<_HoldAction> {
  Timer? _timer;
  void _start(PointerDownEvent _) => _timer = Timer(
    const Duration(milliseconds: 500),
    () => widget.onHold?.call(),
  );
  void _cancel(PointerEvent _) => _timer?.cancel();
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _start,
    onPointerMove: _cancel,
    onPointerUp: _cancel,
    onPointerCancel: _cancel,
    child: widget.child,
  );
}

class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog();
  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  HSVColor _hsv = HSVColor.fromColor(const Color(0xFF5D9ED5));
  late final TextEditingController _hex = TextEditingController(text: '5D9ED5');

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setColor(HSVColor color) {
    setState(() {
      _hsv = color;
      _hex.text = color
          .toColor()
          .toARGB32()
          .toRadixString(16)
          .substring(2)
          .toUpperCase();
    });
  }

  void _setHex(String value) {
    final hex = value.replaceAll('#', '').trim();
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return;
    setState(
      () => _hsv = HSVColor.fromColor(Color(int.parse('FF$hex', radix: 16))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('')),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close, color: AppColors.onSurface),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Directly use flutter_colorpicker's wheel component without
            // its extra slider/labels; this keeps the picker clean.
            SizedBox(
              width: 230,
              height: 230,
              child: ColorPickerArea(_hsv, _setColor, PaletteType.hueWheel),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _hsv.toColor(),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.borderColor),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    onChanged: _setHex,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: 'Hex color',
                      prefixText: '#',
                      counterText: '',
                      labelStyle: TextStyle(
                        color: AppColors.onSurface.withValues(alpha: 0.7),
                      ),
                      floatingLabelStyle: TextStyle(
                        color: AppColors.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _hsv.toColor()),
                child: const Text(
                  'Add color',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
