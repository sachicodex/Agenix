import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ReminderOptions {
  static const List<String> values = [
    '10 minutes',
    '30 minutes',
    '1 hour',
    '1 day',
  ];
}

class ReminderField extends StatelessWidget {
  final bool reminderOn;
  final String reminderValue;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onTimeSelected;

  const ReminderField({
    super.key,
    required this.reminderOn,
    required this.reminderValue,
    required this.onToggle,
    required this.onTimeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Switch(
                value: reminderOn,
                onChanged: onToggle,
                activeColor: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text('Reminder', style: AppTextStyles.bodyText1),
            ],
          ),
          if (reminderOn)
            Theme(
              data: Theme.of(context).copyWith(
                highlightColor: AppColors.primary.withOpacity(0.15),
                splashColor: AppColors.primary.withOpacity(0.1),
                listTileTheme: ListTileThemeData(
                  selectedColor: AppColors.primary,
                  selectedTileColor: AppColors.primary.withOpacity(0.15),
                ),
              ),
              child: PopupMenuButton<String>(
                tooltip: "",
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        reminderValue,
                        style: AppTextStyles.bodyText1.copyWith(
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        color: AppColors.onSurface,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                itemBuilder: (BuildContext context) {
                  return ReminderOptions.values
                      .map(
                        (e) => PopupMenuItem(
                          value: e,
                          child: Text(
                            e,
                            style: AppTextStyles.bodyText1.copyWith(
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      )
                      .toList();
                },
                onSelected: onTimeSelected,
              ),
            ),
        ],
      ),
    );
  }
}
