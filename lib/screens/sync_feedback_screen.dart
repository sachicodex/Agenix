import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SyncFeedbackScreen extends StatefulWidget {
  static const routeName = '/sync';
  final String initialState; // 'syncing' | 'success' | 'error'

  const SyncFeedbackScreen({super.key, this.initialState = 'syncing'});

  @override
  State<SyncFeedbackScreen> createState() => _SyncFeedbackScreenState();
}

class _SyncFeedbackScreenState extends State<SyncFeedbackScreen>
    with SingleTickerProviderStateMixin {
  String state = 'syncing';

  @override
  void didUpdateWidget(covariant SyncFeedbackScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeShowErrorDialog();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeShowErrorDialog();
  }

  void _maybeShowErrorDialog() {
    if (state == 'error') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sync Failed'),
            content: const Text('Failed to sync: network error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();
    state = widget.initialState;

    // Demo transitions: after 1s go to success for 'syncing'
    if (state == 'syncing') {
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        setState(() => state = 'success');
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (!mounted) return;
          Navigator.pop(context); // auto-return
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (state == 'syncing') {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.secondary),
          SizedBox(height: 12),
          Text(
            'Syncing with Google Calendar...',
            style: AppTextStyles.bodyText1,
          ),
        ],
      );
    } else if (state == 'success') {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: AppColors.primary, size: 72),
          SizedBox(height: 12),
          Text('Event added successfully', style: AppTextStyles.bodyText1),
        ],
      );
    } else {
      // Error state: show only retry button, error dialog is handled separately
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: () => setState(() => state = 'syncing'),
            child: Text('Retry', style: AppTextStyles.button),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Material(
          color: AppColors.surface,
          elevation: 8,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(padding: EdgeInsets.all(24), child: body),
        ),
      ),
    );
  }
}
