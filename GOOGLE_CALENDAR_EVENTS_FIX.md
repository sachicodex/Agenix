# Why Google Calendar Events Weren't Showing - Root Cause Analysis & Fix

## 🔍 **The Problem**

Events created in the Google Calendar app were **not appearing** in your Flutter app's timeline, but events created through your app **were showing**. This created a confusing user experience.

## 🐛 **Root Causes Identified**

### 1. **CRITICAL: Missing Pagination Handling** ⚠️
**The Main Issue:**

Google Calendar API returns events in **pages** (typically 250 events per page). If you have more than 250 events, you need to make **multiple API calls** using the `nextPageToken`.

**What Was Happening:**
- Your code only fetched the **first page** of results
- Events created in Google Calendar app that appeared on page 2, 3, etc. were **never fetched**
- Only events on the first page (often the most recent or first created) were showing

**Code Before:**
```dart
events = await cal.events.list(
  calendarId,
  timeMin: timeMin,
  timeMax: timeMax,
  singleEvents: true,
  orderBy: 'startTime',
);
// ❌ Only gets first page - ignores nextPageToken!
```

**Code After:**
```dart
do {
  events = await cal.events.list(
    calendarId,
    timeMin: timeMin,
    timeMax: timeMax,
    singleEvents: true,
    orderBy: 'startTime',
    pageToken: currentPageToken, // ✅ Handles pagination
    timeZone: localTimeZone,
  );
  // Process events...
  currentPageToken = events.nextPageToken;
} while (currentPageToken != null); // ✅ Fetches ALL pages
```

### 2. **Date Range Timezone Issues**

**The Problem:**
- When converting local time to UTC for the API call, timezone differences could cause events to be excluded
- The date range calculation didn't account for full day coverage

**Fix:**
- Added explicit timezone parameter to API calls
- Improved date range to cover full day (00:00:00 to 23:59:59)

### 3. **Missing Timezone Parameter**

**The Problem:**
- Google Calendar API needs to know the timezone to properly filter events
- Without it, events might be filtered incorrectly

**Fix:**
- Added `timeZone: localTimeZone` parameter to API calls

### 4. **Event Filtering Issues**

**The Problem:**
- Cancelled events were being processed
- Events with no title might be skipped incorrectly

**Fix:**
- Skip cancelled events explicitly
- Handle events with no title gracefully

## ✅ **The Fix**

### Changes Made:

1. **Added Pagination Loop** (`lib/services/google_calendar_service.dart`)
   - Now fetches ALL pages of events, not just the first page
   - Uses `do-while` loop to continue fetching until `nextPageToken` is null

2. **Improved Date Range Calculation**
   - Uses full day range (00:00:00 to 23:59:59)
   - Better timezone handling

3. **Added Timezone Parameter**
   - Explicitly passes local timezone to API calls
   - Ensures proper event filtering

4. **Better Event Parsing**
   - Skips cancelled events
   - Handles events with no title
   - Better error logging

5. **Enhanced Debugging**
   - Added detailed logging to track event fetching
   - Shows how many events per page
   - Logs pagination progress

## 📊 **How to Verify the Fix**

1. **Create an event in Google Calendar app** (not your Flutter app)
2. **Open your Flutter app** and navigate to the calendar view
3. **Check the debug console** - you should see:
   ```
   Fetching events: timeMin=..., timeMax=...
   Page returned X events (pageToken: none)
   Total events fetched after pagination: X
   Successfully loaded X events from Google Calendar
   ```
4. **The event should now appear** in your timeline

## 🔧 **Technical Details**

### Why Pagination Matters:

Google Calendar API has a **default page size of 250 events**. If you have:
- 100 events created in your app (on page 1)
- 200 events created in Google Calendar app (on page 2)

**Before Fix:** Only page 1 fetched → Only your app's events showed
**After Fix:** All pages fetched → All events show

### API Response Structure:

```json
{
  "items": [...],           // Events on this page
  "nextPageToken": "...",   // Token to get next page (null if last page)
  "nextSyncToken": "..."    // Token for incremental sync
}
```

## 🎯 **Summary**

**The main issue was pagination** - your code only fetched the first page of results from Google Calendar API. Events created in Google Calendar app that appeared on subsequent pages were never fetched, so they never appeared in your timeline.

**The fix ensures ALL pages are fetched**, so all events (regardless of where they were created) now appear correctly in your timeline.

---

**Files Modified:**
- `lib/services/google_calendar_service.dart` - Added pagination handling
- `lib/screens/calendar_day_view_screen.dart` - Improved date range and debugging

**Testing:**
After this fix, events created in Google Calendar app should now appear in your Flutter app's timeline.

