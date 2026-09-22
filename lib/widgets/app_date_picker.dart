import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import 'Glass Card/glass_carrd.dart';
import 'app_popup.dart';

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showAppDialog<DateTime>(
    context: context,
    builder: (_) => _AppDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showAppDialog<TimeOfDay>(
    context: context,
    builder: (_) => _AppTimePickerDialog(initialTime: initialTime),
  );
}

class _AppDatePickerDialog extends StatefulWidget {
  const _AppDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_AppDatePickerDialog> createState() => _AppDatePickerDialogState();
}

class _AppDatePickerDialogState extends State<_AppDatePickerDialog> {
  late DateTime _selectedDate;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _selectedDate = _clampDate(widget.initialDate);
    _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _clampDate(DateTime date) {
    final normalized = _dateOnly(date);
    final first = _dateOnly(widget.firstDate);
    final last = _dateOnly(widget.lastDate);
    if (normalized.isBefore(first)) return first;
    if (normalized.isAfter(last)) return last;
    return normalized;
  }

  bool _isAllowed(DateTime date) {
    final normalized = _dateOnly(date);
    return !normalized.isBefore(_dateOnly(widget.firstDate)) &&
        !normalized.isAfter(_dateOnly(widget.lastDate));
  }

  bool get _canGoPrevious {
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    return _visibleMonth.isAfter(firstMonth);
  }

  bool get _canGoNext {
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    return _visibleMonth.isBefore(lastMonth);
  }

  void _changeMonth(int amount) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + amount);
    if (amount < 0 && !_canGoPrevious || amount > 0 && !_canGoNext) return;
    setState(() => _visibleMonth = next);
  }

  List<DateTime> _monthDays() {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final leadingDays = first.weekday % 7;
    final gridStart = first.subtract(Duration(days: leadingDays));
    return List.generate(42, (index) => gridStart.add(Duration(days: index)));
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_visibleMonth);
    final days = _monthDays();
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final dialogHeight = isCompact ? 440.0 : 470.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: GlassCard(
        width: appPopupWidth(context, 620),
        height: dialogHeight,
        padding: EdgeInsets.all(isCompact ? 16 : 20),
        borderRadius: BorderRadius.circular(26),
        tintOpacity: 0.075,
        borderOpacity: 0.16,
        blurSigma: 22,
        child: Column(
          children: [
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        monthLabel,
                        style: const TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _canGoPrevious ? () => _changeMonth(-1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      onPressed: _canGoNext ? () => _changeMonth(1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                      .map(
                        (label) => Expanded(
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: AppColors.timeTextColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: isCompact ? 240 : 264,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: days.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisExtent: 40,
                        ),
                    itemBuilder: (context, index) {
                      final day = days[index];
                      final allowed = _isAllowed(day);
                      final selected = _dateOnly(day) == _selectedDate;
                      final today = _dateOnly(day) == _dateOnly(DateTime.now());
                      final inMonth = day.month == _visibleMonth.month;
                      return InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: allowed
                            ? () =>
                                  setState(() => _selectedDate = _dateOnly(day))
                            : null,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primary
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                              border: today && !selected
                                  ? Border.all(color: AppColors.primary)
                                  : null,
                            ),
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                color: !allowed
                                    ? AppColors.onTertiary.withValues(
                                        alpha: 0.35,
                                      )
                                    : selected
                                    ? AppColors.onPrimary
                                    : inMonth
                                    ? AppColors.onSurface
                                    : AppColors.onTertiary,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.onSurface,
                        side: const BorderSide(color: AppColors.glassBorder),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_selectedDate),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                      ),
                      child: const Text('Select'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AppTimePickerDialog extends StatefulWidget {
  const _AppTimePickerDialog({required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<_AppTimePickerDialog> createState() => _AppTimePickerDialogState();
}

class _AppTimePickerDialogState extends State<_AppTimePickerDialog> {
  late int _hour;
  late int _minute;
  late bool _isPm;
  bool _selectingMinute = false;
  int? _lastClockValue;

  @override
  void initState() {
    super.initState();
    final time = widget.initialTime;
    _hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    _minute = (time.minute / 5).round() * 5;
    if (_minute == 60) {
      _minute = 55;
    }
    _isPm = time.period == DayPeriod.pm;
  }

  TimeOfDay get _selectedTime {
    var hour = _hour % 12;
    if (_isPm) hour += 12;
    return TimeOfDay(hour: hour, minute: _minute);
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onPressed(),
      selectedColor: AppColors.primary.withValues(alpha: 0.18),
      backgroundColor: Colors.transparent,
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.glassBorder,
      ),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.onSurface,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  void _selectClockValue(int value) {
    if (_lastClockValue == value) return;
    _lastClockValue = value;
    setState(() {
      if (_selectingMinute) {
        _minute = value * 5;
      } else {
        _hour = value == 0 ? 12 : value;
        _selectingMinute = true;
        _lastClockValue = null;
      }
    });
  }

  Widget _buildClockDialog(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: GlassCard(
        width: appPopupWidth(context, 430),
        height: compact ? 520 : 550,
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 24,
          20,
          compact ? 16 : 24,
          18,
        ),
        borderRadius: BorderRadius.circular(26),
        tintOpacity: 0.075,
        borderOpacity: 0.16,
        blurSigma: 22,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => setState(() {
                    _lastClockValue = null;
                    _selectingMinute = false;
                  }),
                  child: Text(
                    _hour.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: _selectingMinute
                          ? AppColors.timeTextColor
                          : AppColors.primary,
                      fontSize: compact ? 34 : 40,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  ':',
                  style: TextStyle(
                    color: AppColors.onSurface,
                    fontSize: compact ? 34 : 40,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    _lastClockValue = null;
                    _selectingMinute = true;
                  }),
                  child: Text(
                    _minute.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: _selectingMinute
                          ? AppColors.primary
                          : AppColors.timeTextColor,
                      fontSize: compact ? 34 : 40,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _choice(
                  label: 'AM',
                  selected: !_isPm,
                  onPressed: () => setState(() => _isPm = false),
                ),
                const SizedBox(width: 8),
                _choice(
                  label: 'PM',
                  selected: _isPm,
                  onPressed: () => setState(() => _isPm = true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: _ClockFace(
                  selectingMinute: _selectingMinute,
                  hour: _hour,
                  minute: _minute,
                  onValueSelected: _selectClockValue,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.onSurface,
                        side: const BorderSide(color: AppColors.glassBorder),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_selectedTime),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                      ),
                      child: const Text('Select'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 0) {
      return _buildClockDialog(context);
    }
    final formatted = _selectedTime.format(context);
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: GlassCard(
        width: appPopupWidth(context, 440),
        padding: EdgeInsets.fromLTRB(
          isCompact ? 16 : 24,
          20,
          isCompact ? 16 : 24,
          18,
        ),
        borderRadius: BorderRadius.circular(26),
        tintOpacity: 0.075,
        borderOpacity: 0.16,
        blurSigma: 22,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Select time', style: AppTextStyles.headline3),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppColors.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              formatted,
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: isCompact ? 32 : 40,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Hour',
                style: TextStyle(
                  color: AppColors.timeTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                12,
                (index) => _choice(
                  label: '${index + 1}',
                  selected: _hour == index + 1,
                  onPressed: () => setState(() => _hour = index + 1),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Minutes',
                  style: TextStyle(
                    color: AppColors.timeTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(
                    12,
                    (index) => _choice(
                      label: index == 0 ? '00' : '${index * 5}',
                      selected: _minute == index * 5,
                      onPressed: () => setState(() => _minute = index * 5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                _choice(
                  label: 'AM',
                  selected: !_isPm,
                  onPressed: () => setState(() => _isPm = false),
                ),
                const SizedBox(width: 8),
                _choice(
                  label: 'PM',
                  selected: _isPm,
                  onPressed: () => setState(() => _isPm = true),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_selectedTime),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                  ),
                  child: const Text('Select'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClockFace extends StatefulWidget {
  const _ClockFace({
    required this.selectingMinute,
    required this.hour,
    required this.minute,
    required this.onValueSelected,
  });

  final bool selectingMinute;
  final int hour;
  final int minute;
  final ValueChanged<int> onValueSelected;

  @override
  State<_ClockFace> createState() => _ClockFaceState();
}

class _ClockFaceState extends State<_ClockFace> {
  bool _lockDragAfterHour = false;

  void _handleTap(BuildContext context, Offset localPosition, double size) {
    final center = Offset(size / 2, size / 2);
    final delta = localPosition - center;
    if (delta.distance < size * 0.22) return;
    var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    final index = (angle / (math.pi * 2 / 12)).round() % 12;
    widget.onValueSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final size = math.min(MediaQuery.sizeOf(context).width - 48, 300.0);
    return GestureDetector(
      onTapUp: (details) => _handleTap(context, details.localPosition, size),
      onPanStart: (_) => _lockDragAfterHour = false,
      onPanUpdate: (details) {
        if (_lockDragAfterHour) return;
        _handleTap(context, details.localPosition, size);
        if (!widget.selectingMinute) {
          _lockDragAfterHour = true;
        }
      },
      onPanEnd: (_) => _lockDragAfterHour = false,
      onPanCancel: () => _lockDragAfterHour = false,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: CustomPaint(
          key: ValueKey(widget.selectingMinute),
          size: Size.square(size),
          painter: _ClockFacePainter(
            selectingMinute: widget.selectingMinute,
            hour: widget.hour,
            minute: widget.minute,
          ),
        ),
      ),
    );
  }
}

class _ClockFacePainter extends CustomPainter {
  const _ClockFacePainter({
    required this.selectingMinute,
    required this.hour,
    required this.minute,
  });

  final bool selectingMinute;
  final int hour;
  final int minute;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final selectedIndex = selectingMinute ? minute ~/ 5 : hour % 12;
    final selectedAngle = selectedIndex * (math.pi * 2 / 12) - math.pi / 2;
    final selectedPoint = Offset(
      center.dx + math.cos(selectedAngle) * radius * 0.58,
      center.dy + math.sin(selectedAngle) * radius * 0.58,
    );

    final backgroundPaint = Paint()
      ..color = AppColors.background.withValues(alpha: 0.82)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.84, backgroundPaint);

    final borderPaint = Paint()
      ..color = AppColors.glassBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius * 0.84, borderPaint);

    final tickPaint = Paint()
      ..color = AppColors.onSurface.withValues(alpha: 0.55)
      ..strokeCap = StrokeCap.round;
    for (var tick = 0; tick < 60; tick++) {
      final angle = tick * (math.pi * 2 / 60) - math.pi / 2;
      final isMajor = tick % 5 == 0;
      final outerRadius = radius * 0.79;
      final innerRadius = isMajor ? radius * 0.70 : radius * 0.74;
      tickPaint.strokeWidth = isMajor ? 2 : 1;
      canvas.drawLine(
        Offset(
          center.dx + math.cos(angle) * innerRadius,
          center.dy + math.sin(angle) * innerRadius,
        ),
        Offset(
          center.dx + math.cos(angle) * outerRadius,
          center.dy + math.sin(angle) * outerRadius,
        ),
        tickPaint,
      );
    }

    final handPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, selectedPoint, handPaint);
    canvas.drawCircle(center, 4, handPaint);
    canvas.drawCircle(selectedPoint, 18, handPaint);

    for (var index = 0; index < 12; index++) {
      final angle = index * (math.pi * 2 / 12) - math.pi / 2;
      final labelRadius = index == selectedIndex
          ? radius * 0.58
          : radius * 0.64;
      final point = Offset(
        center.dx + math.cos(angle) * labelRadius,
        center.dy + math.sin(angle) * labelRadius,
      );
      final label = selectingMinute
          ? (index * 5).toString().padLeft(2, '0')
          : (index == 0 ? '12' : '$index');
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: index == selectedIndex
                ? AppColors.onPrimary
                : AppColors.onSurface,
            fontSize: selectingMinute ? 13 : 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        point - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ClockFacePainter oldDelegate) {
    return oldDelegate.selectingMinute != selectingMinute ||
        oldDelegate.hour != hour ||
        oldDelegate.minute != minute;
  }
}
