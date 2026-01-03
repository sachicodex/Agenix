Agenix — UI Prototype (Flutter)

What this includes:
- App theme tokens: `lib/theme/app_theme.dart` (colors, radii, motion)
- Screens (UI-only): `CreateEventScreen`, `SyncFeedbackScreen`, `SettingsScreen`
- Shared widgets: `RoundedCard`, basic form fields
- Routes wired in `lib/main.dart`

Notes:
- This is UI-only: no Google Calendar logic, no auth, no storage.
- Fonts: `pubspec.yaml` references Inter fonts under `assets/fonts/`. Please add the actual font files (Inter-Regular.ttf, Inter-Medium.ttf, Inter-SemiBold.ttf, Inter-Bold.ttf) to `assets/fonts/` to enable the custom font.
- Assets: placeholder icons are in `assets/icons/` (SVG placeholders). You can replace them with your production assets.

How to run:
1. Add Inter font files (optional) and run `flutter pub get`.
2. Run `flutter run -d windows` or `-d emulator` for Android.

Next steps if you want:
- Add Google Calendar integration logic and token storage
- Add account management flows
- Polish animations and add SVG assets
