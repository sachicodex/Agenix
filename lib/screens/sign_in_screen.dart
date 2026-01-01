import 'package:flutter/material.dart';
import '../services/google_calendar_service.dart';
import '../theme/app_colors.dart';

class SignInScreen extends StatefulWidget {
  final VoidCallback? onSignInSuccess;

  const SignInScreen({super.key, this.onSignInSuccess});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _loading = false;

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
    });

    try {
      // Only trigger sign-in when user clicks the button
      // This will show the Google account picker
      await GoogleCalendarService.instance.ensureSignedIn(context);
      if (!mounted) return;

      // Call success callback if provided
      widget.onSignInSuccess?.call();
    } catch (err) {
      if (mounted) {
        _showErrorDialog(err.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo/text-logo.png', width: 250),
              SizedBox(height: 48),
              Text(
                'You must sign in with Google to save events to your calendar.',
                style: AppTextStyles.bodyText1,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _loading ? null : _signIn,
                icon: const Icon(Icons.login),
                label: _loading
                    ? Text('Signing in…', style: AppTextStyles.button)
                    : Text('Sign in with Google', style: AppTextStyles.button),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
