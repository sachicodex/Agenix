import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_popup.dart';
import 'Custom Dialog/reusable_dialog.dart';
import 'Primary Button/primary_button.dart' as dialog_buttons;
import 'Secondary Button/secondary_button.dart';

enum DeleteEventChoice { cancel, thisEvent, allEvents }

Future<DeleteEventChoice> showDeleteEventDialog(
  BuildContext context, {
  bool isRecurring = false,
}) async {
  final choice = await showAppDialog<DeleteEventChoice>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return CustomTwoActionDialog(
        title: 'Delete Event?',
        description: isRecurring
            ? 'This is part of a recurring event. What would you like to delete?'
            : 'Are you sure you want to delete this event?',
        centerTitle: true,
        centerContent: true,
        showCloseButton: false,
        titleDescriptionSpacing: 5,
        content: isRecurring
            ? SecondaryButton(
                width: double.infinity,
                label: 'This event only',
                onPressed: () =>
                    Navigator.of(context).pop(DeleteEventChoice.thisEvent),
                backgroundColor: Colors.transparent,
                borderSide: const BorderSide(color: AppColors.glassBorder),
              )
            : null,
        secondaryButton: SecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(DeleteEventChoice.cancel),
          backgroundColor: Colors.transparent,
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        primaryButton: dialog_buttons.PrimaryButton(
          label: isRecurring ? 'All events' : 'Delete',
          isDeleteButton: true,
          onPressed: () => Navigator.of(context).pop(
            isRecurring
                ? DeleteEventChoice.allEvents
                : DeleteEventChoice.thisEvent,
          ),
        ),
      );
    },
  );

  return choice ?? DeleteEventChoice.cancel;
}
