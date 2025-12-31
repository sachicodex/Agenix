# Default Calendar Selection Implementation

## Overview

This document explains the one-time default calendar selection flow implemented in the Flutter app for both Windows and Android platforms.

## Architecture

### State & Storage Approach

**Storage Service:** `AuthStorageService` (using `flutter_secure_storage`)
- Stores default calendar ID and name securely
- Encrypted storage on both Windows and Android
- Persists across app restarts

**State Management:** `AuthWrapper` widget
- Manages authentication and calendar selection state
- Controls navigation flow based on user state
- Handles transitions between screens

### App Startup Flow

```
App Starts
    ↓
AuthWrapper.initState()
    ↓
_checkAuthStatus()
    ↓
┌─────────────────────────────────────┐
│ Is User Signed In?                  │
└─────────────────────────────────────┘
    │                    │
   NO                   YES
    │                    │
    ↓                    ↓
SignInScreen    ┌──────────────────────┐
    │           │ Has Default Calendar?│
    │           └──────────────────────┘
    │                    │        │
    │                   NO       YES
    │                    │        │
    │                    ↓        ↓
    │         CalendarSelection  CreateEventScreen
    │              Screen
    │                    │
    │                    ↓
    └──────────→ CreateEventScreen
```

## Key Components

### 1. AuthStorageService Extensions

**New Methods:**
- `saveDefaultCalendar(String calendarId, String calendarName)` - Saves selected calendar
- `getDefaultCalendarId()` - Retrieves stored calendar ID
- `getDefaultCalendarName()` - Retrieves stored calendar name
- `hasDefaultCalendar()` - Checks if default calendar is set
- `clearDefaultCalendar()` - Clears stored calendar (on sign out)

**Storage Keys:**
- `default_calendar_id` - Calendar ID
- `default_calendar_name` - Calendar name (for display)

### 2. CalendarSelectionScreen

**Purpose:** One-time screen shown after first login to select default calendar

**Features:**
- Fetches user's calendars from Google Calendar API
- Displays list of calendars with radio buttons
- Saves selection to secure storage
- No back button (prevents skipping)
- Calls `onCalendarSelected` callback when user clicks Continue

**Flow:**
1. Screen loads → Fetches calendars
2. User selects calendar → Radio button updates
3. User clicks Continue → Saves to storage → Navigates to CreateEventScreen

### 3. AuthWrapper Updates

**New State Variables:**
- `_hasDefaultCalendar` - Tracks if default calendar is set

**Updated Methods:**
- `_checkAuthStatus()` - Now also checks for default calendar
- `_onSignInSuccess()` - Checks for default calendar after sign-in
- `_onCalendarSelected()` - Updates state when calendar is selected
- `_onSignOut()` - Clears default calendar on sign out

**Navigation Logic:**
```dart
if (!_isSignedIn) {
  return SignInScreen();
}
if (!_hasDefaultCalendar) {
  return CalendarSelectionScreen();
}
return CreateEventScreenV2();
```

### 4. CreateEventScreenV2 Updates

**New Method:**
- `_loadDefaultCalendar()` - Loads saved default calendar on startup
- Sets `_selectedCalendarId` to the saved default if available

**Behavior:**
- On startup, checks for saved default calendar
- If found and calendar exists in available calendars, selects it automatically
- User can still change calendar selection if needed

### 5. SignInScreen Updates

**Changes:**
- Removed back button (`automaticallyImplyLeading: false`)
- Removed cancel button (no longer needed as full screen)

## User Experience Flow

### First Login

1. **App Starts** → Shows Sign-In screen
2. **User clicks "Sign in with Google"** → Google account picker appears
3. **User selects account** → Authentication completes
4. **Calendar Selection Screen appears** → User sees list of calendars
5. **User selects calendar** → Clicks Continue
6. **Create Event Screen appears** → Default calendar is pre-selected

### Subsequent Logins

1. **App Starts** → Checks authentication
2. **User is signed in** → Checks for default calendar
3. **Default calendar found** → Skips calendar selection
4. **Create Event Screen appears** → Default calendar is pre-selected

### Sign Out

1. **User signs out** → All credentials cleared
2. **Default calendar cleared** → Next login will show calendar selection again

## Code Snippets

### Saving Default Calendar

```dart
// In CalendarSelectionScreen
final storage = GoogleCalendarService.instance.storage;
await storage.saveDefaultCalendar(
  selectedCalendar['id']!,
  selectedCalendar['name'] ?? 'Unknown',
);
```

### Checking Default Calendar on App Launch

```dart
// In AuthWrapper._checkAuthStatus()
if (signedIn) {
  final hasDefault = await GoogleCalendarService.instance.storage.hasDefaultCalendar();
  setState(() {
    _hasDefaultCalendar = hasDefault;
  });
}
```

### Loading Default Calendar in CreateEventScreen

```dart
// In CreateEventScreenV2._loadDefaultCalendar()
final storage = GoogleCalendarService.instance.storage;
final defaultCalendarId = await storage.getDefaultCalendarId();
if (defaultCalendarId != null && calendarExists) {
  setState(() {
    _selectedCalendarId = defaultCalendarId;
  });
}
```

### Conditional Navigation

```dart
// In AuthWrapper.build()
if (!_isSignedIn) {
  return SignInScreen(onSignInSuccess: _onSignInSuccess);
}

if (!_hasDefaultCalendar) {
  return CalendarSelectionScreen(
    onCalendarSelected: _onCalendarSelected,
  );
}

return CreateEventScreenV2(onSignOut: _onSignOut);
```

## Security Considerations

1. **Encrypted Storage:** Default calendar is stored using `flutter_secure_storage`
2. **Platform Support:** Works on both Windows and Android with platform-specific encryption
3. **Data Persistence:** Calendar selection persists across app restarts
4. **Cleanup:** Calendar selection is cleared on sign out for security

## Testing Checklist

- [ ] First login shows calendar selection screen
- [ ] Calendar selection is saved correctly
- [ ] Subsequent logins skip calendar selection
- [ ] Default calendar is pre-selected in CreateEventScreen
- [ ] Sign out clears default calendar
- [ ] Works on both Windows and Android
- [ ] Back button removed from SignInScreen
- [ ] Back button removed from CalendarSelectionScreen

## Benefits

1. **Better UX:** Users set default calendar once, not every time
2. **Faster Workflow:** No need to select calendar for each event
3. **Secure:** Calendar selection stored in encrypted storage
4. **Platform Agnostic:** Works consistently on Windows and Android
5. **Clean State Management:** Clear separation of concerns

