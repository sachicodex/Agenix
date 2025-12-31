import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  static const routeName = '/settings';
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String defaultReminder = '10 minutes';
  String themeMode = 'Dark';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: AppTextStyles.headline2)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(Icons.person, color: AppColors.onPrimary),
                backgroundColor: AppColors.primary,
              ),
              title: Text('Google Account', style: AppTextStyles.bodyText1),
              subtitle: Text(
                'Not connected',
                style: AppTextStyles.bodyText1.copyWith(
                  color: AppColors.onSurface.withOpacity(0.6),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () {},
                    child: Text('Connect', style: AppTextStyles.button),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: Text('Default Reminder', style: AppTextStyles.bodyText1),
              trailing: DropdownButton<String>(
                value: defaultReminder,
                items: ['None', '10 minutes', '30 minutes', '1 hour']
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e, style: AppTextStyles.bodyText1),
                      ),
                    )
                    .toList(),
                onChanged: (v) =>
                    setState(() => defaultReminder = v ?? defaultReminder),
                style: AppTextStyles.bodyText1,
                dropdownColor: AppColors.surface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: Text('Theme', style: AppTextStyles.bodyText1),
              subtitle: Text(
                themeMode,
                style: AppTextStyles.bodyText1.copyWith(
                  color: AppColors.onSurface.withOpacity(0.6),
                ),
              ),
              trailing: TextButton(
                onPressed: () {},
                child: Text('Change', style: AppTextStyles.button),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: Text('About', style: AppTextStyles.bodyText1),
              subtitle: Text('NUVEX Flow • v1.0.0'),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }
}
