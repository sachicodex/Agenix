import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Hour grid lines for the day timeline — single [CustomPaint] repaint per zoom.
class TimelineVirtualHourGrid extends StatelessWidget {
  const TimelineVirtualHourGrid({
    super.key,
    required this.hourHeight,
  });

  final double hourHeight;

  static const int hourCount = 24;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _HourGridPainter(hourHeight: hourHeight),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _HourGridPainter extends CustomPainter {
  _HourGridPainter({required this.hourHeight});

  final double hourHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.dividerColor
      ..strokeWidth = 1;

    for (var hour = 0; hour <= hourCount; hour++) {
      final y = hour * hourHeight;
      if (y > size.height) break;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  static const int hourCount = TimelineVirtualHourGrid.hourCount;

  @override
  bool shouldRepaint(covariant _HourGridPainter oldDelegate) {
    return oldDelegate.hourHeight != hourHeight;
  }
}
