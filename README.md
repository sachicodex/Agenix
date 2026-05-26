# Agenix

<p align="center">
  <img src="assets/logo/agenix-windows.png" alt="Agenix Logo" width="140" />
</p>

<p align="center">
  AI-powered Google Calendar planner with local-first sync, smart reminders, and fast day-view scheduling on Android and Windows.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" alt="Flutter Badge" />
  <img src="https://img.shields.io/badge/Dart-3.10+-0175C2?logo=dart" alt="Dart Badge" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20Desktop-2ea44f" alt="Platform Badge" />
  <img src="https://img.shields.io/badge/Calendar-Google%20Calendar-EA4335?logo=googlecalendar" alt="Google Calendar Badge" />
</p>

## Download

| Platform | Package | Link | Notes |
|---|---|---|---|
| Android | APK | [Latest Release](https://github.com/sachicodex/Agenix/releases/latest) | Install the release APK on your Android device. |
| Windows | MSIX | [Latest Release](https://github.com/sachicodex/Agenix/releases/latest) | MSIX is recommended for the best Windows notification/startup experience. |
| Linux / macOS / iOS | Build from source | [Run From Source](#run-from-source) | Source builds are possible with Flutter tooling, but Android and Windows are the main polished targets in this repo. |

## About

Agenix is a Google Calendar planner focused on fast scheduling and reliable syncing:
- Sign in with Google and work directly with your calendars.
- Create, edit, drag, move, and resize events in a day-view timeline.
- Save events locally first, then push changes back to Google Calendar.
- Use AI tools to improve event titles and descriptions with a Groq API key.
- Configure daily agenda notifications, event reminders, startup behavior, and account settings from one settings screen.

## Preview

<p align="center">
  <img src="assets/img/preview-desktop.png" alt="Agenix Desktop Preview" width="560" />
</p>

<p align="center">
  <img src="assets/img/preview-mobile.png" alt="Agenix Mobile Preview" width="320" />
</p>

## Features

| Icon | Feature | What you get |
|---|---|---|
| &#127760; | Google Calendar integration | Google sign-in, calendar listing, create/update/delete support, and sync token based refresh. |
| &#128197; | Interactive day view | Timeline scheduling with drag, resize, double-tap edit, all-day row, and multi-day support on desktop. |
| &#128190; | Local-first storage | Local event database, cached profile data, sync retry behavior, and offline-friendly edits. |
| &#128276; | Notifications | Daily agenda alerts, per-event reminders, Android background notification support, and Windows-friendly packaging support. |
| &#10024; | AI writing tools | Title optimization and description generation/editing powered by Groq API. |
| &#128295; | Platform utilities | Windows startup toggle, system tray behavior, Android background/foreground sync helpers, and synced settings. |

## Mobile Gestures (Day View)

| Gesture | Action |
|---|---|
| Swipe left/right on the timeline | Change day. |
| Long-press empty timeline, then drag | Create a new event range. |
| Long-press an event, then drag | Move an event. |
| Long-press event resize handle, then drag | Resize event duration. |
| Double-tap an event | Open the edit modal. |
| Tap the top-bar sync icon | Run a manual sync and animate the sync icon until it finishes. |

## Desktop Keyboard Shortcuts

| Key | Action |
|---|---|
| `C` | Create event |
| `T` | Jump to today |
| `Enter` | Edit selected event |
| `Delete` / `Backspace` | Delete selected event |
| `Esc` | Cancel the current interaction |
| `Arrow Up` / `Arrow Left` | Move selected event `-15` minutes |
| `Arrow Down` / `Arrow Right` | Move selected event `+15` minutes |

## How to Use

1. Launch Agenix and sign in with your Google account.
2. Choose a default calendar in `Settings`.
3. Create or edit events from the day view.
4. Use drag-and-drop or resize gestures to adjust timing quickly.
5. Open `Settings` to manage:
   - Account
   - AI tools
   - Notifications
   - Default calendar
   - Startup / background behavior
6. Tap the sync button any time you want a manual sync.

## How to Get Groq API Key

1. Go to [Groq Console](https://console.groq.com/).
2. Create an API key.
3. Open `Settings` -> `AI Tools`.
4. Paste the key.
5. Tap the check icon to validate and save it.

If no key is configured, AI actions inside the create/edit event forms will guide the user back to Settings.

## Run From Source

### Prerequisites

- Flutter SDK with Dart `3.10+`
- Google Cloud project with Google Calendar API enabled
- Google OAuth credentials for desktop and mobile/web flows
- Cloudflare Worker setup for desktop OAuth token exchange
- Optional: Groq API key for AI features
- Optional: Firebase project for Android messaging and cloud-backed settings sync

### Setup

```bash
git clone https://github.com/sachicodex/Agenix.git
cd Agenix
flutter pub get
flutter run
```

### Common run targets

```bash
flutter run -d android
flutter run -d windows
flutter run -d linux
flutter run -d macos
```

## Setup A-Z (Google Login + Cloudflare + Firebase)

### 1. Create Google OAuth credentials

In Google Cloud Console:
1. Enable `Google Calendar API`.
2. Create an OAuth client for `Desktop app`.
3. Create an OAuth client for `Web application`.
4. Keep the desktop client ID and client secret.
5. Keep the web client ID.

### 2. Configure Flutter OAuth values

Update `lib/google_oauth_config.dart`:

```dart
const String kDesktopClientId = 'YOUR_DESKTOP_CLIENT_ID.apps.googleusercontent.com';
const String kGoogleOauthProxyTokenUrl = 'https://YOUR_WORKER_SUBDOMAIN.workers.dev/oauth/token';
```

Update `web/index.html`:

```html
<meta name="google-signin-client_id" content="YOUR_WEB_CLIENT_ID.apps.googleusercontent.com">
```

### 3. Configure the Cloudflare Worker OAuth proxy

From repo root:

```bash
cd oauth-proxy
```

Set `GOOGLE_CLIENT_ID` in `oauth-proxy/wrangler.jsonc`:

```jsonc
"vars": {
  "GOOGLE_CLIENT_ID": "YOUR_DESKTOP_CLIENT_ID.apps.googleusercontent.com"
}
```

Add the desktop client secret:

```bash
wrangler secret put GOOGLE_CLIENT_SECRET
```

Deploy:

```bash
npm run deploy
```

Important:
- The Flutter desktop client ID and worker `GOOGLE_CLIENT_ID` must match.
- Never place the desktop client secret inside Flutter source files.

### 4. Configure Firebase (optional but recommended for Android)

In Firebase Console:
1. Create or reuse a project.
2. Add your Android app.
3. Download `google-services.json`.
4. Place it in `android/app/google-services.json`.
5. Ensure the project is configured for Firebase Messaging if you need it.

Desktop Firebase values can be loaded from `.env` through the app bootstrap path.

### 5. Test the sign-in flow

1. Run the app on Windows or Android.
2. Tap `Sign in with Google`.
3. Complete browser consent.
4. Let Agenix exchange the auth code through the worker.
5. Return to the app and verify calendars load correctly.

If desktop sign-in fails with OAuth-related errors:
- Recheck the desktop client ID.
- Recheck the worker secret and deployment.
- Recheck the redirect/token proxy URL in `google_oauth_config.dart`.

## Build

### Android APK

```bash
flutter build apk
```

### Windows EXE

```bash
flutter build windows
```

### Windows MSIX package

```bash
dart run msix:create
```

Notes:
- The repo now uses a valid four-part MSIX version format in `pubspec.yaml`.
- If you previously used `flutter pub run msix:create`, that still works in older flows, but `dart run msix:create` is the modern command.

## Notifications

- Daily agenda notifications can be enabled and timed from Settings.
- Event reminders are configured from a single selector, including an `Off` state.
- Android uses local notifications, WorkManager, and optional foreground sync helpers.
- Windows works best with an MSIX install if you want the most reliable closed-app notification behavior.

## Sync Behavior

- Local edits are written first, then synced to Google Calendar.
- Manual sync is available from the main calendar screen.
- Background sync can still run without animating the manual sync button.
- Android can schedule additional upload work when the app moves to the background.

## Settings Overview

The current settings screen is organized as:
- Account
- AI Tools
- Notifications
- Calendar
- Startup / Background
- About
- Logout

## Project Structure

```text
lib/
  controllers/    Timeline zoom and interaction controllers
  data/           Local database and remote calendar data sources
  models/         Core app models such as calendar events
  navigation/     Route observer helpers
  notifications/  Reminder scheduling, local notifications, Firebase messaging
  providers/      Riverpod providers
  repositories/   Event repository and sync orchestration
  screens/        Auth, calendar, settings, create/edit flows
  services/       Google auth, sync, AI, startup, tray, background services
  theme/          App colors and theme
  widgets/        Shared UI widgets
```

## Tech Stack

| Area | Tech |
|---|---|
| App | Flutter |
| State management | Riverpod |
| Local DB | `sqflite`, `sqflite_common_ffi` |
| Calendar API | `googleapis`, `google_sign_in`, `googleapis_auth` |
| AI | Groq API |
| Notifications | `flutter_local_notifications`, `firebase_messaging`, `workmanager`, `flutter_foreground_task` |
| Desktop utilities | `window_manager`, `tray_manager`, `msix` |
| Cloud sync | Firebase Auth + Cloud Firestore |

## Support

- Issues: [GitHub Issues](https://github.com/sachicodex/Agenix/issues)
- Releases: [GitHub Releases](https://github.com/sachicodex/Agenix/releases)
