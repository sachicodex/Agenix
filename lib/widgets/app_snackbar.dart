import 'package:flutter/material.dart';

enum AppSnackBarType { info, success, error, offline }

AppSnackBarType inferSnackBarType(String message) {
  final text = message.toLowerCase();
  if (text.contains('no internet') ||
      text.contains('offline') ||
      text.contains('failed host lookup') ||
      text.contains('socketexception') ||
      text.contains('network is unreachable')) {
    return AppSnackBarType.offline;
  }
  if (text.contains('error') || text.contains('failed')) {
    return AppSnackBarType.error;
  }
  return AppSnackBarType.info;
}

SnackBar buildAppSnackBar(
  BuildContext context,
  String message, {
  AppSnackBarType? type,
  Duration? duration,
  EdgeInsetsGeometry? padding,
}) {
  final resolvedType = type ?? inferSnackBarType(message);
  final icon = switch (resolvedType) {
    AppSnackBarType.offline => Icons.wifi_off_rounded,
    AppSnackBarType.error => Icons.error_outline_rounded,
    AppSnackBarType.success => Icons.check_circle_outline_rounded,
    AppSnackBarType.info => Icons.info_outline_rounded,
  };

  final theme = Theme.of(context);
  final snackTheme = theme.snackBarTheme;
  final barWidth = MediaQuery.sizeOf(context).width * 0.97;

  return SnackBar(
    duration: duration ?? const Duration(seconds: 4),
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    content: Center(
      child: Container(
        width: barWidth,
        padding: padding ?? const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: snackTheme.backgroundColor ?? theme.colorScheme.surface,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: barWidth - 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: snackTheme.contentTextStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void showAppSnackBar(
  BuildContext context,
  String message, {
  AppSnackBarType? type,
  Duration? duration,
  EdgeInsetsGeometry? padding,
  bool hideCurrent = true,
}) {
  final messenger = ScaffoldMessenger.of(context);
  if (hideCurrent) {
    messenger.hideCurrentSnackBar();
  }
  messenger.showSnackBar(
    buildAppSnackBar(
      context,
      message,
      type: type,
      duration: duration,
      padding: padding,
    ),
  );
}
