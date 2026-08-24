# Agenix

<p align="center">
  <img src="assets/logo/agenix-windows.png" alt="Agenix Logo" width="140" />
</p>

<p align="center">
  An AI-powered Google Calendar planner with local-first sync, smart reminders, and fast day-view scheduling for Android and Windows.
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
| Windows | EXE | [Latest Release](https://github.com/sachicodex/Agenix/releases/latest) | Recommended Windows install; uses the Inno Setup installer. |
| Linux / macOS / iOS | Build from source | [Run From Source](#run-from-source) | Desktop and mobile code paths exist, but Android and Windows are the configured release targets. |
| Web | Not supported | - | The app uses native platform APIs and does not support web builds. |

## About

Agenix is a Google Calendar planner focused on fast scheduling and reliable syncing:
- Sign in with Google and work directly with your calendars.
- Create, edit, drag, move, and resize events in an interactive day-view timeline.
- Save events locally first, then push changes back to Google Calendar.
- Use AI tools to improve event titles and descriptions with a Groq API key.
- Configure daily agenda notifications, event reminders, startup behavior, and account settings from one settings screen.

## Preview

<p align="center">
  <img src="assets/img/ai.png" alt="Agenix AI Tools Preview" width="560" />
</p>

<p align="center">
  <img src="assets/img/verify.png" alt="Agenix Verification Preview" width="320" />
</p>

## Features

| Icon | Feature | What you get |
|---|---|---|
| &#127760; | Google Calendar integration | Google sign-in, calendar listing, default calendar selection, event management, reminders, and sync-token refresh. |
| &#128197; | Interactive day view | Timeline scheduling with date navigation, an all-day row, event creation, drag-and-drop movement, and resize interactions. |
| &#128190; | Local-first storage | SQLite event, calendar, and profile caches with pending-change tracking and sync retries. |
| &#128276; | Notifications | Daily agenda alerts, configurable event reminders, Android scheduled notifications, and Windows-friendly notification support. |
| &#10024; | AI writing tools | Event title optimization and description generation or editing powered by Groq. |
| &#128295; | Platform utilities | Windows startup and system tray controls, Android background sync, and synchronized settings. |

## Mobile Gestures (Day View)

| Gesture | Action |
|---|---|
| Swipe left/right on the timeline | Change day. |
| Long-press empty timeline, then drag | Create a new event range. |
| Long-press an event, then drag | Move an event. |
| Long-press the event resize handle, then drag | Resize event duration. |
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
5. Open `Settings` to manage your account, AI tools, notifications, calendar, and startup behavior.
6. Tap the sync button whenever you want a manual sync.

## How to Get a Groq API Key

1. Go to [Groq Console](https://console.groq.com/).
2. Create an API key.
3. Open `Settings` -> `AI Tools`.
4. Paste the key and validate it.

If no key is configured, AI actions inside the create and edit event forms guide you back to Settings.

## Run From Source

### Prerequisites

- Flutter SDK with Dart `3.10.3+`
- Google Cloud project with the Google Calendar API enabled
- Google OAuth credentials for desktop and mobile flows
- Cloudflare Worker setup for desktop OAuth token exchange
- Optional: Groq API key for AI features
- Optional: Firebase project and `google-services.json` for Android messaging and cloud-backed settings sync

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

In [Google Cloud Console](https://console.cloud.google.com/):
1. Enable the `Google Calendar API`.
2. Create an OAuth client for a desktop application.
3. Create an OAuth client for a web application.
4. Keep the desktop client ID and secret, plus the web client ID.

### 2. Configure Flutter OAuth values

Update `lib/google_oauth_config.dart`:

```dart
const String kDesktopClientId = 'YOUR_DESKTOP_CLIENT_ID.apps.googleusercontent.com';
const String kGoogleOauthProxyTokenUrl = 'https://YOUR_WORKER_SUBDOMAIN.workers.dev/oauth/token';
```

Update `web/index.html` with the web client ID:

```html
<meta name="google-signin-client_id" content="YOUR_WEB_CLIENT_ID.apps.googleusercontent.com">
```

### 3. Configure the Cloudflare Worker OAuth proxy

From the repository root:

```bash
cd oauth-proxy
npm install
```

Set `GOOGLE_CLIENT_ID` in `oauth-proxy/wrangler.jsonc`, then add the desktop client secret:

```bash
wrangler secret put GOOGLE_CLIENT_SECRET
```

Deploy the worker:

```bash
npm run deploy
```

The Flutter desktop client ID and worker `GOOGLE_CLIENT_ID` must match. Never place the desktop client secret in Flutter source files.

### 4. Configure Firebase (optional)

In [Firebase Console](https://console.firebase.google.com/):
1. Create or reuse a project.
2. Add your Android app.
3. Download `google-services.json`.
4. Place it in `android/app/google-services.json`.
5. Enable Firebase Messaging if Android notifications are required.

For desktop Firebase settings sync, configure `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_PROJECT_ID`, and `FIREBASE_MESSAGING_SENDER_ID` in `.env`.

### 5. Test the sign-in flow

1. Run Agenix on Windows or Android.
2. Tap `Sign in with Google`.
3. Complete browser consent.
4. Let Agenix exchange the authorization code through the worker.
5. Return to the app and verify that calendars load correctly.

## Build Release Packages

```bash
# Android APK
flutter build apk --release

# Windows release
flutter build windows --release
```

The Android build currently uses the debug signing key unless release signing is configured separately. Configure production signing before distributing an APK publicly.

## Windows Installer (Inno Setup)

Agenix uses a normal Inno Setup EXE installer for Windows distribution.

Prerequisites:
- Install the Flutter Windows desktop tooling.
- Build the Windows release first with `flutter build windows --release`.

The installer script is saved at:

```text
installer\Agenix.iss
```

To compile from VS Code:

1. Press `Ctrl + Shift + B`.
2. Choose `Release: Build Windows Installer`.
3. VS Code runs the Flutter Windows release build, then compiles `installer\Agenix.iss`.
4. The setup EXE is created at `installer\Output\Agenix-Setup.exe`.

To compile from Inno Setup:

1. Open `installer\Agenix.iss` in Inno Setup Compiler.
2. Click **Compile**.
3. The setup EXE is created at `installer\Output\Agenix-Setup.exe`.

Script Wizard settings used for Agenix:

| Wizard page | Value |
|---|---|
| Application name | `Agenix` |
| Application version | `4.3.17` |
| Publisher | `Sachicodex` |
| Destination base folder | `(Custom)` |
| Custom destination folder | `{localappdata}\Programs` |
| Application folder name | `Agenix` |
| Main executable | `build\windows\x64\runner\Release\Agenix.exe` |
| Other application files | Add the full `build\windows\x64\runner\Release` folder |
| File association | Disabled |
| Start Menu shortcut | Enabled |
| Desktop shortcut option | Enabled |
| Documentation files | Blank |
| Install mode | Non administrative install mode, current user only |
| Registry import file | Blank |
| Project root folder | installer |
| Installer subfolder | Output |
| Compiler output folder | Output |
| Output base file name | `Agenix-Setup` |
| Setup password | Blank |
| Preprocessor directives | Enabled |
| ISS file location | installer |

This installs to:

```text
%LOCALAPPDATA%\Programs\Agenix
```

That keeps installation user-friendly and avoids requiring admin rights.



## Notifications

- Daily agenda notifications can be enabled and scheduled from Settings.
- Event reminders support `Off`, 5, 10, 15, 30, and 60 minute options.
- Android uses local notifications, WorkManager, and optional foreground sync helpers.
- Windows works best with an Inno Setup install for closed-app notification behavior.

## Sync Behavior

- Local edits are written first, then synced to Google Calendar.
- Manual sync is available from the main calendar screen.
- Background sync can run without animating the manual sync button.
- Android can schedule additional upload work when the app moves to the background.

## Settings Overview

The Settings screen includes:
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
  screens/        Auth, calendar, settings, and create/edit flows
  services/       Google auth, sync, AI, startup, tray, and background services
  theme/          App colors and theme
  widgets/        Shared UI widgets
oauth-proxy/
  src/            Cloudflare Worker OAuth token exchange
assets/
  fonts/          Montserrat font family
  img/            AI and verification artwork
  logo/           Agenix application logos and icons
```

## Tech Stack

| Area | Tech |
|---|---|
| App | Flutter |
| State management | Riverpod |
| Local database | `sqflite`, `sqflite_common_ffi` |
| Calendar API | `googleapis`, `google_sign_in`, `googleapis_auth` |
| AI | Groq API |
| Notifications | `flutter_local_notifications`, `firebase_messaging`, `workmanager`, `flutter_foreground_task` |
| Desktop utilities | `window_manager`, `tray_manager` |
| Windows packaging | Inno Setup |
| Cloud sync | Firebase Auth + Cloud Firestore |
| OAuth proxy | Cloudflare Workers |

## Publisher

| Field | Value |
|---|---|
| Display name | Agenix |
| Publisher | Sachicodex |
| Package ID | `com.sachicodex.agenix` |
| Version | `6.3.25+5` |

## Support

- Issues: [GitHub Issues](https://github.com/sachicodex/Agenix/issues)
- Releases: [GitHub Releases](https://github.com/sachicodex/Agenix/releases)
- Repository: [github.com/sachicodex/Agenix](https://github.com/sachicodex/Agenix)
