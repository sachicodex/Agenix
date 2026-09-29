import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
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
      if (!isRecurring) {
        return CustomOneActionDialog(
          title: 'Delete event?',
          description: 'Are you sure you want to delete this event?',
          centerTitle: true,
          centerContent: true,
          primaryButton: dialog_buttons.PrimaryButton(
            label: 'Delete',
            isDeleteButton: true,
            onPressed: () =>
                Navigator.of(context).pop(DeleteEventChoice.thisEvent),
          ),
        );
      }

      return CustomTwoActionDialog(
        title: 'Delete Event?',
        description: 'Delete only this event or the entire series?',
        centerTitle: true,
        centerContent: true,
        titleDescriptionSpacing: 5,
        secondaryButton: SecondaryButton(
          label: 'This event ',
          onPressed: () =>
              Navigator.of(context).pop(DeleteEventChoice.thisEvent),
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete03, size: 18),
          backgroundColor: const Color(0x1AEF4444),
          foregroundColor: const Color(0xFFEF4444),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        primaryButton: dialog_buttons.PrimaryButton(
          label: 'All events',
          backgroundColor: Colors.transparent,
          foregroundColor: const Color(0xFFF4F4F5),
          borderSide: const BorderSide(color: AppColors.glassBorder),
          onPressed: () =>
              Navigator.of(context).pop(DeleteEventChoice.allEvents),
        ),
        primaryButtonFirst: true,
      );
    },
  );

  return choice ?? DeleteEventChoice.cancel;
}
