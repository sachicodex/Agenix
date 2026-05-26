class BackgroundSyncConfig {
  BackgroundSyncConfig._();

  /// Android foreground sync requires a visible ongoing notification.
  ///
  /// Set this to `false` if you want to disable the foreground-service path
  /// from code. When disabled, Android falls back to WorkManager jobs only.
  static bool enableAndroidForegroundSyncNotification = false;

  static const int backgroundSyncDaysAhead = 15;
  static const int androidForegroundUploadMaxAttempts = 12;
  static const Duration androidOneOffScheduleDebounce = Duration(seconds: 8);

  static const String androidForegroundNotificationTitle = 'Agenix sync';
  static const String androidForegroundNotificationPreparingText =
      'Preparing background sync...';
  static const String androidForegroundNotificationActiveText =
      'Uploading event changes...';
  static const String androidForegroundNotificationFinalizingText =
      'Finalizing background sync...';
  static const String androidForegroundNotificationCompleteText =
      'Background sync complete.';
}
