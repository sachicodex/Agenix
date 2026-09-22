import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:async';

import '../theme/app_colors.dart';
import '../services/calendar_palette_sync_service.dart';
import 'app_popup.dart';
import '../utils/platform_focus.dart';
import 'Glass Card/glass_carrd.dart';
import 'Custom Dialog/reusable_dialog.dart';
import 'Primary Button/primary_button.dart';
import 'Secondary Button/secondary_button.dart';

const _baseCalendarColors = AppColors.calendarPalette;

final _customCalendarColors = ValueNotifier<List<Color>>(<Color>[]);
final _calendarPaletteSync = CalendarPaletteSyncService();
String? _loadedPaletteUserId;
Future<void>? _paletteLoadInFlight;
StreamSubscription<CalendarPaletteData>? _paletteSubscription;
List<int>? _pendingPaletteUpload;

class CalendarColorPalette extends StatefulWidget {
  const CalendarColorPalette({
    super.key,
    required this.selectedColor,
    required this.onChanged,
  });

  final Color selectedColor;
  final ValueChanged<Color> onChanged;

  @override
  State<CalendarColorPalette> createState() => _CalendarColorPaletteState();
}

class _CalendarColorPaletteState extends State<CalendarColorPalette> {
  @override
  void initState() {
    super.initState();
    unawaited(_loadCustomColors());
  }

  Future<void> _loadCustomColors() {
    return _paletteLoadInFlight ??= () async {
      try {
        final cachedColors = await _calendarPaletteSync.loadCached();
        if (cachedColors.isNotEmpty) {
          _customCalendarColors.value = cachedColors.map(Color.new).toList();
        }
        final data = await _calendarPaletteSync.loadForCurrentUser();
        if (data == null) return;
        final subscribedUserId = _loadedPaletteUserId;
        // Never discard a locally-created palette when this device comes
        // online before it has had a chance to upload it.
        final cloudColors = data.colors;
        if (cloudColors.isEmpty && cachedColors.isNotEmpty) {
          _pendingPaletteUpload = cachedColors;
          unawaited(_calendarPaletteSync.saveForCurrentUser(cachedColors));
        } else {
          _applyCloudPalette(data);
        }
        if (subscribedUserId == data.userId && _paletteSubscription != null) {
          return;
        }
        await _paletteSubscription?.cancel();
        _loadedPaletteUserId = data.userId;
        _paletteSubscription = _calendarPaletteSync
            .watchForUser(data.userId)
            .listen(
              (data) {
                final pending = _pendingPaletteUpload;
                if (pending != null) {
                  if (_sameColorValues(pending, data.colors)) {
                    _pendingPaletteUpload = null;
                  } else if (data.colors.isEmpty && pending.isNotEmpty) {
                    // Ignore Firestore's initial empty snapshot while a local
                    // offline palette is being uploaded.
                    return;
                  }
                }
                _applyCloudPalette(data);
              },
              onError: (_, _) {
                // Keep the current local palette visible when offline.
              },
            );
      } finally {
        _paletteLoadInFlight = null;
      }
    }();
  }

  Future<void> _saveCustomColors(List<Color> colors) async {
    final values = colors.map((color) => color.toARGB32()).toList();
    _pendingPaletteUpload = values;
    await _calendarPaletteSync.saveForCurrentUser(values);
  }

  void _applyCloudPalette(CalendarPaletteData data) {
    _loadedPaletteUserId = data.userId;
    final nextColors = data.colors.map(Color.new).toList();
    if (_sameColors(_customCalendarColors.value, nextColors)) return;
    _customCalendarColors.value = nextColors;
  }

  bool _sameColors(List<Color> first, List<Color> second) {
    return _sameColorValues(
      first.map((color) => color.toARGB32()).toList(),
      second.map((color) => color.toARGB32()).toList(),
    );
  }

  bool _sameColorValues(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

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
              selected: color.toARGB32() == widget.selectedColor.toARGB32(),
              onTap: () => widget.onChanged(color),
              onHold: customColors.contains(color)
                  ? () async {
                      final confirmed = await showAppDialog<bool>(
                        context: context,
                        builder: (context) => CustomTwoActionDialog(
                          title: 'Delete custom color?',
                          description: 'Remove this color from the palette?',
                          centerTitle: true,
                          centerContent: true,
                          titleDescriptionSpacing: 12,
                          showCloseButton: false,
                          secondaryButton: SecondaryButton(
                            label: 'Cancel',
                            onPressed: () => Navigator.of(context).pop(false),
                            backgroundColor: Colors.transparent,
                            borderSide: const BorderSide(
                              color: AppColors.glassBorder,
                            ),
                          ),
                          primaryButton: PrimaryButton(
                            label: 'Yes, Delete',
                            onPressed: () => Navigator.of(context).pop(true),
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      );
                      if (confirmed == true) {
                        final nextColors = _customCalendarColors.value
                            .where(
                              (item) => item.toARGB32() != color.toARGB32(),
                            )
                            .toList();
                        _customCalendarColors.value = nextColors;
                        unawaited(_saveCustomColors(nextColors));
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
                final nextColors = [..._customCalendarColors.value, color];
                _customCalendarColors.value = nextColors;
                unawaited(_saveCustomColors(nextColors));
              }
              widget.onChanged(color);
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
  HSVColor _hsv = HSVColor.fromColor(AppColors.royalBlue);
  late final TextEditingController _hex = TextEditingController(text: '2563EB');

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
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: appPopupInsetPadding(context),
      child: GlassCard(
        width: appPopupWidth(context, 360),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, color: AppColors.onSurface),
              ),
            ),
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
                    autofocus: shouldAutofocusTextInput,
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
