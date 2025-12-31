# What is the "Calendar" Entry?

## Explanation

The "Calendar" entry that appears in your Google Calendar list is **your primary/default calendar** that Google automatically creates for every Google account.

### Key Points:

1. **Auto-Created by Google**: Every Google account gets a primary calendar automatically when the account is created. This is your main calendar.

2. **Default Name**: If you've never renamed it, it shows up as just "Calendar" (the generic default name).

3. **It's Real, But Confusing**: While it's a real calendar in your Google account, showing it as just "Calendar" is confusing because:
   - You didn't explicitly create it
   - It doesn't have a meaningful name
   - It looks like a placeholder or error

4. **What It's Used For**: This is the calendar where events go by default if you don't specify a calendar. It's essentially your "main" calendar.

### Why We Filter It Out:

We've filtered out calendars with the name "Calendar" because:
- It's confusing to users who didn't create it
- Users typically want to see only calendars they've explicitly created or subscribed to
- If users want to use their primary calendar, they can rename it in Google Calendar to something meaningful (like "My Calendar" or "Personal")

### How to Use Your Primary Calendar:

If you want to use your primary calendar:
1. Go to Google Calendar (web or app)
2. Find the calendar named "Calendar"
3. Click on it and rename it to something meaningful (e.g., "My Calendar", "Personal", "Main Calendar")
4. After renaming, it will appear in the app with its new name

### Technical Details:

- **Calendar ID**: Usually something like `your-email@gmail.com` or `primary`
- **API Behavior**: Google Calendar API returns this calendar in the calendar list
- **Filtering**: We filter it out by checking if the name (case-insensitive) equals "calendar"

## Implementation

The filtering is done in two places:
1. **`GoogleCalendarService.getUserCalendars()`** - Filters at the service level
2. **`CreateEventScreenV2._fetchCalendars()`** - Additional filtering for safety

This ensures the "Calendar" entry doesn't appear anywhere in the app.

