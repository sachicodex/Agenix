import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/calendar_event.dart';

/// Event title/time layout that scales with block height to avoid overflow when zoomed out.
class TimelineEventBlockContent extends StatelessWidget {
  const TimelineEventBlockContent({
    super.key,
    required this.event,
    required this.visualHeight,
    this.textColor = const Color(0xFF141614),
  });

  final CalendarEvent event;
  final double visualHeight;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final padding = paddingForHeight(visualHeight);
    final innerHeight = (visualHeight - padding.vertical).clamp(
      0.0,
      visualHeight,
    );

    if (innerHeight < 10) {
      return Padding(padding: padding, child: const SizedBox.shrink());
    }

    if (innerHeight < 16) {
      return Padding(
        padding: padding,
        child: _fittedTitle(innerHeight, fontSize: 8),
      );
    }

    if (innerHeight < 24) {
      return Padding(
        padding: padding,
        child: _singleLineTitle(
          innerHeight,
          fontSize: (innerHeight * 0.75).clamp(8.0, 10.0),
        ),
      );
    }

    if (innerHeight < 34) {
      return Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _singleLineTitle(
              innerHeight,
              fontSize: (innerHeight * 0.42).clamp(9.0, 11.0),
            ),
            const Spacer(),
            Text(
              _formatTimeRange(compact: false),
              style: _timeStyle(8.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    final titleSize = (innerHeight * 0.42).clamp(10.0, 13.0);
    final timeSize = (innerHeight * 0.32).clamp(8.0, 11.0);
    final showTime = innerHeight >= 28;
    final titleMaxLines = innerHeight >= 64 ? 2 : 1;
    final titleBottomGap = innerHeight >= 56 ? 4.0 : 2.0;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Text(
            event.title,
            style: _titleStyle(titleSize),
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
          if (showTime) ...[
            SizedBox(height: titleBottomGap),
            const Spacer(),
            Text(
              _formatTimeRange(compact: false),
              style: _timeStyle(timeSize),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _fittedTitle(double innerHeight, {required double fontSize}) {
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          event.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _titleStyle(fontSize),
        ),
      ),
    );
  }

  Widget _singleLineTitle(double innerHeight, {required double fontSize}) {
    return Text(
      event.title,
      style: _titleStyle(fontSize),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  TextStyle _titleStyle(double fontSize) {
    return TextStyle(
      fontFamily: 'Montserrat',
      color: textColor,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: 1.1,
    );
  }

  TextStyle _timeStyle(double fontSize) {
    return TextStyle(
      fontFamily: 'Montserrat',
      color: textColor,
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: 1.1,
    );
  }

  String _formatTimeRange({required bool compact}) {
    if (compact) {
      return '${DateFormat('h:mma').format(event.startDateTime).toLowerCase()} - ${DateFormat('h:mma').format(event.endDateTime).toLowerCase()}';
    }
    return '${DateFormat('h:mm').format(event.startDateTime)} - ${DateFormat('h:mm').format(event.endDateTime)}';
  }

  /// Padding to apply on the parent [Container] for consistent spacing.
  static EdgeInsets paddingForHeight(double visualHeight) {
    if (visualHeight < 20) {
      return const EdgeInsets.symmetric(horizontal: 4, vertical: 1);
    }
    if (visualHeight < 32) {
      return const EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    }
    return const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
  }
}
