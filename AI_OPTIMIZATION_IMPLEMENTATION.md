# AI-Powered Title & Description Optimization Implementation

## Overview

This document explains the AI-powered optimization feature for Title and Description fields using Google Gemini API in the Flutter app (Windows + Android).

## Architecture

### Components

1. **GeminiService** (`lib/services/gemini_service.dart`)
   - Handles all Gemini API interactions
   - Provides methods for title optimization and description optimization/generation
   - Includes error handling and timeout management

2. **Updated Form Fields** (`lib/widgets/form_fields.dart`)
   - `LargeTextField` - Now supports AI button with loading state
   - `ExpandableDescription` - Now supports AI button with loading state

3. **CreateEventScreenV2** (`lib/screens/create_event_screen_v2.dart`)
   - Integrated AI optimization methods
   - Manages loading states for both fields
   - Handles user interactions

## Features

### Title Field AI Optimization

**Behavior:**
- User enters a title
- Clicks AI icon button (right side of field)
- AI optimizes the title to be:
  - Short and clear (under 60 characters)
  - Professional and event-title friendly
  - Removes unnecessary words
- Replaces the field text with optimized version

**Implementation:**
```dart
Future<void> _optimizeTitle() async {
  final optimizedTitle = await _geminiService.optimizeTitle(currentTitle);
  _titleController.text = optimizedTitle;
}
```

### Description Field AI Optimization/Generation

**Behavior:**
- **If description exists:**
  - User clicks AI icon button
  - AI optimizes description based on Title + Description
  - Makes it Google Calendar-friendly, clear, and well-formatted
  - Replaces existing description

- **If description is empty:**
  - User clicks AI icon button
  - AI generates a description automatically from the Title
  - Creates professional, concise description (2-3 sentences)
  - Fills the description field

**Implementation:**
```dart
Future<void> _optimizeOrGenerateDescription() async {
  if (currentDescription.isEmpty) {
    result = await _geminiService.generateDescription(currentTitle);
  } else {
    result = await _geminiService.optimizeDescription(currentTitle, currentDescription);
  }
  _descController.text = result;
}
```

## UI Components

### AI Icon Button

**Location:** Right side of both Title and Description input fields

**Visual States:**
- **Normal:** Shows AI icon (`assets/img/ai.png`) or fallback icon (`Icons.auto_awesome`)
- **Loading:** Shows circular progress indicator
- **Disabled:** Button disabled during loading

**Styling:**
- Icon size: 24x24 pixels
- Color: Primary theme color
- Tooltip: "Optimize with AI" / "Optimize/Generate with AI"

### Loading States

- `_titleAILoading` - Tracks title optimization progress
- `_descriptionAILoading` - Tracks description optimization/generation progress
- Prevents multiple simultaneous requests
- Shows visual feedback to user

## API Integration

### Gemini API Configuration

**Endpoint:** `https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent`

**API Key:** `AIzaSyC5MK7csZ1p8BDadgWtLEBhnyNgeQcJbCs`

**Request Format:**
```json
{
  "contents": [{
    "parts": [{"text": "prompt"}]
  }],
  "generationConfig": {
    "temperature": 0.7,
    "topK": 40,
    "topP": 0.95,
    "maxOutputTokens": 1024
  }
}
```

### Prompts

**Title Optimization Prompt:**
```
Optimize the following event title to be short, clear, and professional for a Google Calendar event. 
Keep it concise (under 60 characters), remove unnecessary words, and make it event-title friendly.
Only return the optimized title, nothing else.
```

**Description Optimization Prompt:**
```
Optimize the following Google Calendar event description to be clear, professional, and well-formatted.
Use the title as context. Make it concise but informative. Format it properly for Google Calendar.
```

**Description Generation Prompt:**
```
Generate a professional, concise description for a Google Calendar event based on the following title.
Make it informative and well-formatted. Keep it brief (2-3 sentences max).
```

## Error Handling

### Network Errors
- Timeout handling (30 seconds)
- Connection error messages
- User-friendly error dialogs

### API Errors
- Invalid API key detection
- Rate limiting handling
- Safety filter blocking detection
- Empty response handling

### User Feedback
- Error dialogs with clear messages
- Loading indicators during processing
- Field updates only on success

## Code Structure

### Key Files

1. **lib/services/gemini_service.dart**
   - `optimizeTitle(String title)` - Optimizes event title
   - `optimizeDescription(String title, String description)` - Optimizes existing description
   - `generateDescription(String title)` - Generates new description
   - `_callGeminiAPI(String prompt)` - Internal API call method

2. **lib/widgets/form_fields.dart**
   - `LargeTextField` - Added `onAIClick` and `aiLoading` parameters
   - `ExpandableDescription` - Added `onAIClick` and `aiLoading` parameters

3. **lib/screens/create_event_screen_v2.dart**
   - `_optimizeTitle()` - Title optimization handler
   - `_optimizeOrGenerateDescription()` - Description optimization/generation handler
   - Loading state management

## User Experience Flow

### Title Optimization

1. User types title: "meeting with team tomorrow at 3pm"
2. User clicks AI icon
3. Loading indicator appears
4. AI processes: "Team Meeting"
5. Field text replaced with optimized version
6. Cursor positioned at end

### Description Generation

1. User has title: "Team Meeting"
2. Description field is empty
3. User clicks AI icon
4. Loading indicator appears
5. AI generates: "Team meeting to discuss project progress and upcoming milestones."
6. Description field populated

### Description Optimization

1. User has title: "Team Meeting"
2. User has description: "we need to talk about stuff"
3. User clicks AI icon
4. Loading indicator appears
5. AI optimizes: "Team meeting to discuss project updates, address concerns, and plan next steps."
6. Description field updated

## Platform Support

✅ **Windows** - Full support
✅ **Android** - Full support
✅ **iOS** - Ready (code is platform-agnostic)

## Assets

- **AI Icon:** `assets/img/ai.png`
- **Fallback:** Material icon `Icons.auto_awesome` if image not found
- **Asset Registration:** Added to `pubspec.yaml`

## Security Considerations

1. **API Key:** Currently hardcoded (consider moving to environment variables for production)
2. **Error Messages:** User-friendly, don't expose sensitive API details
3. **Timeout:** Prevents hanging requests
4. **Input Validation:** Checks for empty input before API calls

## Testing Checklist

- [ ] Title optimization works correctly
- [ ] Description generation works when field is empty
- [ ] Description optimization works when field has content
- [ ] Loading states display correctly
- [ ] Error handling works for network issues
- [ ] Error handling works for API errors
- [ ] AI icon displays correctly (or fallback)
- [ ] Works on Windows
- [ ] Works on Android
- [ ] Button disabled during loading
- [ ] Text cursor positioned correctly after update

## Future Enhancements

1. Move API key to environment variables
2. Add retry logic for failed requests
3. Cache recent optimizations
4. Add undo functionality
5. Support for multiple languages
6. Custom optimization styles (formal, casual, etc.)

