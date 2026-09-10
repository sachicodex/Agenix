import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_popup.dart';

enum DeleteEventChoice { cancel, thisEvent, allEvents }

Future<DeleteEventChoice> showDeleteEventDialog(
  BuildContext context, {
  bool isRecurring = false,
}) async {
  final choice = await showAppDialog<DeleteEventChoice>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 30),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Delete Event',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: AppColors.onBackground,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isRecurring
                    ? 'This is part of a recurring event. What would you like to delete?'
                    : 'Are you sure you want to delete this event?',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: AppColors.onSurface.withValues(alpha: 0.95),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              if (isRecurring) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(DeleteEventChoice.thisEvent),
                    child: const Text('This event'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(DeleteEventChoice.allEvents),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE15A0A),
                    ),
                    child: const Text('All events in the series'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(DeleteEventChoice.cancel),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onSurface,
                      textStyle: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  if (!isRecurring) ...[
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(DeleteEventChoice.thisEvent),
                      style: FilledButton.styleFrom(
                        backgroundColor:  AppColors.error,
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  return choice ?? DeleteEventChoice.cancel;
}
