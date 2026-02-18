# Agenix

<p align="center">
  <img src="assets/logo/agenix-windows.png" alt="Agenix Logo" width="140" />
</p>

<p align="center">
  AI-powered Google Calendar planner with fast event creation, smart reminders, and smooth day-view interactions.
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
| Android | APK | [Latest Release](https://github.com/sachicodex/Agenix/releases/latest) | Install from release assets on your device. |
| Windows | MSIX | [Latest Release](https://github.com/sachicodex/Agenix/releases/latest) | Recommended for best notification behavior when app is closed. |
| Linux / macOS / iOS | Build from source | [Run From Source](#run-from-source) | Use Flutter build commands for your target platform. |

## About

Agenix helps you manage Google Calendar faster:
- Sign in with Google and choose a default calendar.
- Create and edit events with fast day-view interactions.
- Use AI assistance (Groq API) to improve titles/descriptions.
- Keep data local-first, then sync to Google Calendar.
- Get local reminder notifications and daily agenda alerts.

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
| &#127760; | Google Calendar integration | Sign in, read calendars, create/update/delete events, and sync. |
| &#128198; | Day-view planner | Drag, resize, and create events directly on the timeline. |
| &#128190; | Offline-first behavior | Events are saved locally first, then synced in background. |
| &#128100; | Account + defaults | Keep your default calendar and account profile in settings. |
| &#128276; | Smart reminders | Daily agenda (6:00 AM) + event reminder scheduling. |
| &#10024; | AI writing help | Optimize event title/description using Groq API key in Settings. |

## Mobile Gestures (Day View)

| Gesture | Action |
|---|---|
| Swipe left/right on timeline | Change day (left = next day, right = previous day). |
| Long-press empty time grid, then drag | Create a new event time range (minimum 15 minutes). |
| Long-press an event, then drag | Move event time (snaps by 15-minute steps). |
| Long-press event bottom edge/handle, then drag | Resize event duration. |
| Double-tap an event | Open edit event modal quickly. |
| Tap sync icon on top bar | Trigger manual sync now. |

## Desktop Keyboard Shortcuts

| Key | Action |
|---|---|
| `C` | Create event |
| `T` | Jump to today |
| `Enter` | Edit selected/focused event |
| `Delete` / `Backspace` | Delete selected/focused event |
| `Esc` | Cancel current keyboard interaction |
| `Arrow Up` / `Arrow Left` | Move selected event by `-15` minutes |
| `Arrow Down` / `Arrow Right` | Move selected event by `+15` minutes |

## How to Use

1. Open app and sign in with your Google account.
2. Select your default calendar.
3. Use `+` button (or `C`) to create an event.
4. Optionally use AI buttons in Title/Description fields.
5. Save event and let sync run.
6. Open Settings from profile icon to manage:
   - AI API key
   - Default calendar
   - Notification settings
7. In day view, move/resize/edit events directly.

## How to Get Groq API Key

1. Go to [Groq Console](https://console.groq.com/).
2. Sign in and open API keys section.
3. Create a new key and copy it.
4. In Agenix, open `Settings` -> `AI API Key`.
5. Paste your key and press the check icon to validate/save.

If AI is not configured, Agenix will show a setup prompt when you tap AI actions.

## Run From Source

### Prerequisites

- Flutter SDK (Dart 3.10+)
- Google Cloud project with Google Calendar API + OAuth clients
- Cloudflare account (free) for OAuth token proxy
- Optional: Groq API key for AI features
- Firebase project for Android push notifications

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

## Setup A-Z (Google Login + Cloudflare + Firebase Push)

### 1. Create Google OAuth credentials

In Google Cloud Console:
1. Enable `Google Calendar API`.
2. Create OAuth Client: `Desktop app`.
3. Create OAuth Client: `Web application` (for Flutter web sign-in meta).
4. Keep the desktop `Client ID` and `Client Secret`.
5. Keep the web `Client ID`.

### 2. Configure Flutter app OAuth values

Set desktop client ID in `lib/google_oauth_config.dart`:

```dart
const String kDesktopClientId = 'YOUR_DESKTOP_CLIENT_ID.apps.googleusercontent.com';
const String kGoogleOauthProxyTokenUrl = 'https://YOUR_WORKER_SUBDOMAIN.workers.dev/oauth/token';
```

Set web client ID in `web/index.html`:

```html
<meta name="google-signin-client_id" content="YOUR_WEB_CLIENT_ID.apps.googleusercontent.com">
```

### 3. Configure Cloudflare Worker OAuth proxy (required for desktop secret safety)

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

Upload desktop client secret to Cloudflare Worker secret store:

```bash
wrangler secret put GOOGLE_CLIENT_SECRET
```

Deploy:

```bash
npm run deploy
```

Verify:

```bash
wrangler secret list
```

Expected secret name:
- `GOOGLE_CLIENT_SECRET`

Important:
- `kDesktopClientId` in Flutter and `GOOGLE_CLIENT_ID` in Worker must match the same Google OAuth desktop client.
- Never store desktop client secret in Flutter/Dart files.

### 4. Configure Firebase push notifications (Android)

In Firebase Console:
1. Create project (or reuse existing).
2. Add Android app with your package name.
3. Download `google-services.json`.
4. Place it at `android/app/google-services.json`.
5. Ensure Firebase Messaging is enabled in project settings.

Build/run Android:

```bash
flutter run -d android
```

### 5. Login flow test (end-to-end)

1. Run app (`flutter run -d windows` or Android).
2. Tap `Sign in with Google`.
3. Browser opens for consent.
4. After allowing access, app receives callback and exchanges code through Cloudflare Worker.
5. App stores tokens locally and proceeds to calendar screen.
6. Choose default calendar and continue.

If sign-in fails with `401`:
- Recheck that desktop client ID in app and Worker are identical.
- Re-upload `GOOGLE_CLIENT_SECRET` and redeploy Worker.

## Notifications

- Local notifications:
  - Daily agenda summary at `6:00 AM` (configurable on/off)
  - Event reminders (default reminder configurable)
- Push notifications:
  - Firebase Messaging is configured for Android using `android/app/google-services.json`.
  - Device token generation depends on valid Firebase project setup.
- Windows note:
  - Background notifications when app is closed work best with MSIX install.

## Project Structure

```text
lib/
  screens/         UI screens (day view, settings, create event, auth)
  services/        Google Calendar auth/sync, Groq API, storage services
  notifications/   Reminder scheduling, local notification orchestration
  data/            Local/remote data sources
  repositories/    Event repository layer
  providers/       Riverpod providers
  theme/           App colors and theme
  widgets/         Shared UI widgets
```

## Tech Stack

| Area | Tech |
|---|---|
| App | Flutter |
| State management | Riverpod |
| Local DB | Sqflite |
| Calendar API | Google Calendar API (`googleapis`, `google_sign_in`) |
| AI | Groq API |
| Notifications | `flutter_local_notifications`, Firebase Messaging (Android) |

## Support

- Issues: [GitHub Issues](https://github.com/sachicodex/Agenix/issues)
- Releases: [GitHub Releases](https://github.com/sachicodex/Agenix/releases)
