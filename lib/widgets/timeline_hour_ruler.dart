import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'timeline_virtual_hour_grid.dart';

/// Zoom-dependent timeline scale: subdivision interval and label visibility.
class TimelineScale {
  TimelineScale._();

  /// Minutes between minor grid lines (60 = hour lines only).
  static int subdivisionMinutes(double hourHeight) {
    if (hourHeight >= 150) return 5;
    if (hourHeight >= 100) return 15;
    if (hourHeight >= 56) return 30;
    return 60;
  }

  /// Sub-minute labels (e.g. :15, :30) — hour labels are always shown.
  static bool showSubdivisionLabels(double hourHeight) {
    return hourHeight >= 72;
  }

  /// Minimum vertical space (px) between minor grid lines to draw a sub-label.
  static double minSlotHeightForSubLabel(double hourHeight) {
    if (subdivisionMinutes(hourHeight) <= 5) return 12;
    if (subdivisionMinutes(hourHeight) <= 15) return 14;
    return 16;
  }

  static double subdivisionLineHeight(double hourHeight) {
    final minutes = subdivisionMinutes(hourHeight);
    if (minutes >= 60) return 1;
    if (minutes <= 15) return 0.5;
    return 0.75;
  }

  static Color subdivisionLineColor(double hourHeight) {
    if (subdivisionMinutes(hourHeight) >= 60) {
      return AppColors.dividerColor;
    }
    return AppColors.dividerColor.withValues(alpha: 0.55);
  }

  static String formatHourLabel(int hour) {
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final period = hour < 12 ? 'AM' : 'PM';
    return '$h$period';
  }

  static String formatSubdivisionLabel(int hour, int minute) {
    return minute.toString().padLeft(2, '0');
  }

  static bool shouldShowSubdivisionLabel(double hourHeight, int minute) {
    if (!showSubdivisionLabels(hourHeight) || minute == 0) {
      return false;
    }

    final subdivision = subdivisionMinutes(hourHeight);
    if (subdivision <= 5) {
      return minute % 15 == 0;
    }
    return true;
  }
}

/// Hour + zoom-aware minute grid with compact stacked labels.
class TimelineHourRuler extends StatelessWidget {
  const TimelineHourRuler({
    super.key,
    required this.hourHeight,
    required this.labelAreaWidth,
  });

  final double hourHeight;
  final double labelAreaWidth;

  static const int hourCount = TimelineVirtualHourGrid.hourCount;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _TimelineHourRulerPainter(
          hourHeight: hourHeight,
          labelAreaWidth: labelAreaWidth,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TimelineHourRulerPainter extends CustomPainter {
  _TimelineHourRulerPainter({
    required this.hourHeight,
    required this.labelAreaWidth,
  });

  final double hourHeight;
  final double labelAreaWidth;

  static const double _hourLabelLeftPadding = 10;
  static const double _subLabelLeftPadding = 28;
  static const double _labelRightPadding = 8;

  TextStyle _hourLabelStyle() {
    final fontSize = (hourHeight * 0.13).clamp(11.0, 13.0);
    return TextStyle(
      fontFamily: 'Montserrat',
      fontSize: fontSize,
      color: AppColors.timeTextColor,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: -0.1,
    );
  }

  TextStyle _subLabelStyle() {
    final fontSize = (hourHeight * 0.1).clamp(9.0, 11.0);
    return TextStyle(
      fontFamily: 'Montserrat',
      fontSize: fontSize,
      color: AppColors.timeTextSecondaryColor,
      fontWeight: FontWeight.w400,
      height: 1,
      letterSpacing: 0,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final columnBackgroundPaint = Paint()
      ..color = AppColors.surface.withValues(alpha: 0.72);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, labelAreaWidth, size.height),
      columnBackgroundPaint,
    );

    final borderPaint = Paint()
      ..color = AppColors.dividerColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(labelAreaWidth, 0),
      Offset(labelAreaWidth, size.height),
      borderPaint,
    );

    final subdivisionMinutes = TimelineScale.subdivisionMinutes(hourHeight);
    final showSubLabels = TimelineScale.showSubdivisionLabels(hourHeight);
    final slotHeight = hourHeight * (subdivisionMinutes / 60);
    final minSubSlot = TimelineScale.minSlotHeightForSubLabel(hourHeight);

    final hourLinePaint = Paint()
      ..color = AppColors.dividerColor
      ..strokeWidth = 1;

    final subLinePaint = Paint()
      ..color = TimelineScale.subdivisionLineColor(hourHeight)
      ..strokeWidth = TimelineScale.subdivisionLineHeight(hourHeight);

    final hourStyle = _hourLabelStyle();
    final subStyle = _subLabelStyle();
    final maxLabelWidth =
        labelAreaWidth - _hourLabelLeftPadding - _labelRightPadding;

    final totalMinutes = hourCount * 60;
    for (
      var minuteOfDay = 0;
      minuteOfDay <= totalMinutes;
      minuteOfDay += subdivisionMinutes
    ) {
      if (minuteOfDay > totalMinutes) break;
      final y = (minuteOfDay / 60) * hourHeight;
      if (y > size.height + 1) break;

      final isHourLine = minuteOfDay % 60 == 0;
      final hour = (minuteOfDay ~/ 60) % 24;
      final minute = minuteOfDay % 60;

      final lineStartX = labelAreaWidth;
      final paint = isHourLine ? hourLinePaint : subLinePaint;
      canvas.drawLine(Offset(lineStartX, y), Offset(size.width, y), paint);

      if (isHourLine) {
        _paintHourLabel(
          canvas,
          size,
          text: TimelineScale.formatHourLabel(hour),
          style: hourStyle,
          y: y,
          maxWidth: maxLabelWidth,
        );
        continue;
      }

      if (!showSubLabels ||
          slotHeight < minSubSlot ||
          !TimelineScale.shouldShowSubdivisionLabel(hourHeight, minute)) {
        continue;
      }

      _paintSubdivisionLabel(
        canvas,
        size,
        text: TimelineScale.formatSubdivisionLabel(hour, minute),
        style: subStyle,
        y: y,
        maxWidth: maxLabelWidth,
      );
    }
  }

  void _paintHourLabel(
    Canvas canvas,
    Size size, {
    required String text,
    required TextStyle style,
    required double y,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);

    final textY = (y - painter.height / 2).clamp(
      0.0,
      size.height - painter.height,
    );
    final textX = _hourLabelLeftPadding;

    painter.paint(canvas, Offset(textX, textY));
  }

  void _paintSubdivisionLabel(
    Canvas canvas,
    Size size, {
    required String text,
    required TextStyle style,
    required double y,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textAlign: TextAlign.right,
    )..layout(maxWidth: maxWidth);

    final textY = (y - painter.height / 2).clamp(
      0.0,
      size.height - painter.height,
    );
    final textX = _subLabelLeftPadding.clamp(
      _hourLabelLeftPadding,
      labelAreaWidth - painter.width - _labelRightPadding,
    );

    painter.paint(canvas, Offset(textX, textY));
  }

  static const int hourCount = TimelineVirtualHourGrid.hourCount;

  @override
  bool shouldRepaint(covariant _TimelineHourRulerPainter oldDelegate) {
    return oldDelegate.hourHeight != hourHeight ||
        oldDelegate.labelAreaWidth != labelAreaWidth;
  }
}
