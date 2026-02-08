import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';

class DateTimeField extends StatelessWidget {
  final String label;
  final DateTime dateTime;
  final VoidCallback onTap;

  const DateTimeField({
    super.key,
    required this.label,
    required this.dateTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppTextStyles.bodyText1.copyWith(
            color: AppColors.onSurface.withOpacity(0.7),
          ),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        child: Text(
          DateFormat('EEE - h:mm a').format(dateTime.toLocal()),
          style: AppTextStyles.bodyText1,
        ),
      ),
    );
  }
}
