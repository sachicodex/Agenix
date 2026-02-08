import 'dart:io' show Platform, HttpServer, InternetAddress;
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../google_oauth_config.dart';
import 'auth_storage_service.dart';

/// Lightweight service to sign in and insert events into Google Calendar.
///
/// Notes:
/// - Android: uses `google_sign_in` to obtain an access token and then calls the
///   Calendar API with that token (no refresh token in this simple flow).
/// - Windows/Desktop: uses `clientViaUserConsent` (loopback) to perform an
///   OAuth2 consent flow and receive an authenticated client.
///
/// For production you should persist refresh credentials securely (e.g., in
/// flutter_secure_storage) and handle token refresh logic.
class GoogleCalendarService {
  String? _desktopUserEmail;
  String? _desktopUserPhotoUrl;

  /// Returns a map with email and photoUrl if available, else nulls.
  Future<Map<String, String?>> getAccountDetails() async {
    if (Platform.isAndroid || Platform.isIOS) {
      _googleSignIn ??= GoogleSignIn(
        scopes: [calendar.CalendarApi.calendarScope],
      );
      final acc =
          await _googleSignIn!.signInSilently() ??
          await _googleSignIn!.signIn();
      return {'email': acc?.email, 'photoUrl': acc?.photoUrl};
    }
    // For desktop, return stored info if available
    if (_signedIn) {
      return {'email': _desktopUserEmail, 'photoUrl': _desktopUserPhotoUrl};
    }
    return {'email': null, 'photoUrl': null};
  }

  /// Returns a list of the user's calendars as maps with 'id', 'name', and 'color'.
  /// Filters out the default "Calendar" entry which is Google's auto-created primary calendar
  /// that users haven't explicitly created or renamed.
  /// Also includes 'primary' calendar even if it's named "Calendar".
  Future<List<Map<String, dynamic>>> getUserCalendars() async {
    final client = await _getAuthenticatedClient();
    final calApi = calendar.CalendarApi(client);
    final list = await calApi.calendarList.list();
    final items = list.items ?? [];
    
    return items
        .map((c) {
          // Get calendar color - Google Calendar API provides backgroundColor
          int calendarColor = 0xFF039BE5; // Default blue
          if (c.backgroundColor != null) {
            // Google Calendar API returns color as hex string like "#a4bdfc"
            final hexColor = c.backgroundColor!.replaceAll('#', '');
            if (hexColor.length == 6) {
              calendarColor = int.parse('FF$hexColor', radix: 16);
            }
          } else if (c.colorId != null) {
            // Fallback to colorId if backgroundColor not available
            final colorMap = {
              '1': 0xFF7986CB, // lavender
              '2': 0xFF33B679, // green
              '3': 0xFF8E24AA, // purple
              '4': 0xFFE67C73, // red
              '5': 0xFFF6BF26, // yellow
              '6': 0xFFF4511E, // orange
              '7': 0xFF039BE5, // blue
              '8': 0xFF0097A7, // teal
              '9': 0xFFAD1457, // pink
              '10': 0xFF616161, // grey
              '11': 0xFF795548, // brown
            };
            calendarColor = colorMap[c.colorId] ?? 0xFF039BE5;
          }
          
          return {
            'id': c.id ?? '',
            'name': c.summary ?? c.id ?? '',
            'color': calendarColor,
            'backgroundColor': c.backgroundColor,
            'colorId': c.colorId,
            'selected': c.selected ?? true, // Whether calendar is selected/visible
          };
        })
        .where((c) {
          // Filter out empty IDs
          final id = c['id'] as String?;
          if (id == null || id.isEmpty) return false;
          // Include primary calendar even if named "Calendar"
          if (id == 'primary') return true;
          // Filter out calendars with the generic name "Calendar"
          final name = (c['name'] as String?) ?? '';
          return name.isNotEmpty && name.toLowerCase() != 'calendar';
        })
        .toList();
  }

  GoogleCalendarService._privateConstructor();
  static final GoogleCalendarService instance =
      GoogleCalendarService._privateConstructor();

  GoogleSignIn? _googleSignIn;
  http.Client? _authClient;
  bool _signedIn = false;
  bool _initialized = false;
  final AuthStorageService _storage = AuthStorageService();
  auth_io.AccessCredentials? _storedCredentials;
  String?
  _currentAccessTokenString; // Store access token string for persistence

  /// Get the storage service instance (for calendar selection)
  AuthStorageService get storage => _storage;

  /// Initialize the service and restore authentication state from storage.
  /// Should be called at app startup.
  Future<void> initialize() async {
    if (_initialized) return;

    if (Platform.isAndroid || Platform.isIOS) {
      // For Android/iOS, google_sign_in handles persistence automatically
      _googleSignIn ??= GoogleSignIn(
        scopes: [calendar.CalendarApi.calendarScope],
      );
      // Try silent sign-in to restore session
      try {
        await _googleSignIn!.signInSilently();
      } catch (_) {
        // Silent sign-in failed, user needs to sign in again
      }
      _initialized = true;
      return;
    }

    // For desktop, restore from secure storage
    try {
      final hasStored = await _storage.hasStoredCredentials();
      if (hasStored) {
        await _restoreDesktopAuthFromStorage();
      }
    } catch (e) {
      debugPrint('Error initializing auth: $e');
      // If restoration fails, clear storage and require re-login
      await _storage.clearCredentials();
    }

    _initialized = true;
  }

  /// Restore desktop authentication from stored credentials
  Future<void> _restoreDesktopAuthFromStorage() async {
    try {
      final refreshToken = await _storage.getRefreshToken();
      final accessToken = await _storage.getAccessToken();
      final tokenExpiry = await _storage.getTokenExpiry();
      final scopes = await _storage.getScopes();
      final userEmail = await _storage.getUserEmail();
      final userPhotoUrl = await _storage.getUserPhotoUrl();

      if (refreshToken == null || refreshToken.isEmpty) {
        return;
      }

      // Check if access token is still valid
      bool needsRefresh = true;
      if (accessToken != null &&
          tokenExpiry != null &&
          tokenExpiry.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
        needsRefresh = false;
      }

      if (needsRefresh) {
        // Refresh the access token using refresh token
        await _refreshAccessToken(refreshToken, scopes);
      } else {
        // Use stored access token
        if (tokenExpiry == null) {
          // Token expiry missing, refresh the token
          await _refreshAccessToken(refreshToken, scopes);
          return;
        }
        final token = auth_io.AccessToken('Bearer', accessToken!, tokenExpiry);
        _storedCredentials = auth_io.AccessCredentials(
          token,
          refreshToken,
          scopes.isNotEmpty ? scopes : [calendar.CalendarApi.calendarScope],
        );
        _authClient = auth_io.authenticatedClient(
          http.Client(),
          _storedCredentials!,
        );
        _currentAccessTokenString = accessToken; // Store for later use
      }

      _desktopUserEmail = userEmail;
      _desktopUserPhotoUrl = userPhotoUrl;
      _signedIn = true;
      debugPrint('Desktop auth restored from storage');
    } catch (e) {
      debugPrint('Failed to restore desktop auth: $e');
      await _storage.clearCredentials();
      _signedIn = false;
      _authClient = null;
      _storedCredentials = null;
    }
  }

  /// Refresh access token using refresh token
  Future<void> _refreshAccessToken(
    String refreshToken,
    List<String> scopes,
  ) async {
    try {
      final clientId = kDesktopClientId.trim();
      final clientSecret = kDesktopClientSecret.trim();
      final basicAuth =
          'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}';

      final tokenResp = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': basicAuth,
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': clientId,
          'client_secret': clientSecret,
        },
      );

      if (tokenResp.statusCode != 200) {
        throw Exception('Token refresh failed: ${tokenResp.body}');
      }

      final tokenJson = jsonDecode(tokenResp.body) as Map<String, dynamic>;
      final newAccessToken = tokenJson['access_token'] as String?;
      final expiresIn = tokenJson['expires_in'] as int? ?? 3600;
      final newRefreshToken =
          tokenJson['refresh_token'] as String? ?? refreshToken;

      if (newAccessToken == null) {
        throw Exception('No access token in refresh response');
      }

      final token = auth_io.AccessToken(
        'Bearer',
        newAccessToken,
        DateTime.now().add(Duration(seconds: expiresIn)).toUtc(),
      );

      _storedCredentials = auth_io.AccessCredentials(
        token,
        newRefreshToken,
        scopes.isNotEmpty ? scopes : [calendar.CalendarApi.calendarScope],
      );

      _authClient = auth_io.authenticatedClient(
        http.Client(),
        _storedCredentials!,
      );

      // Store access token string for persistence
      _currentAccessTokenString = newAccessToken;

      // Save updated tokens
      await _storage.saveCredentials(
        refreshToken: newRefreshToken,
        accessToken: newAccessToken,
        tokenExpiry: token.expiry,
        scopes: _storedCredentials!.scopes,
        userEmail: _desktopUserEmail,
        userPhotoUrl: _desktopUserPhotoUrl,
      );

      debugPrint('Access token refreshed successfully');
    } catch (e) {
      debugPrint('Error refreshing token: $e');
      await _storage.clearCredentials();
      throw Exception('Failed to refresh access token: $e');
    }
  }

  /// Attempts silent sign-in for Android/iOS. Returns true if successful.
  /// This should be called before showing any sign-in UI to avoid bad UX.
  Future<bool> trySilentSignIn() async {
    if (Platform.isAndroid || Platform.isIOS) {
      _googleSignIn ??= GoogleSignIn(
        scopes: [calendar.CalendarApi.calendarScope],
      );
      try {
        final account = await _googleSignIn!.signInSilently();
        if (account != null) {
          _signedIn = true;
          return true;
        }
      } catch (e) {
        debugPrint('Silent sign-in failed: $e');
      }
      return false;
    }
    // For desktop, just check if already signed in
    return await isSignedIn();
  }

  /// Returns whether we have a usable signed-in session.
  Future<bool> isSignedIn() async {
    // Ensure initialization
    if (!_initialized) {
      await initialize();
    }

    if (Platform.isAndroid || Platform.isIOS) {
      _googleSignIn ??= GoogleSignIn(
        scopes: [calendar.CalendarApi.calendarScope],
      );
      return await _googleSignIn!.isSignedIn();
    }

    // For desktop, check both in-memory state and storage
    if (_signedIn && _authClient != null) {
      return true;
    }

    // If not signed in but have stored credentials, try to restore
    final hasStored = await _storage.hasStoredCredentials();
    if (hasStored && !_signedIn) {
      try {
        await _restoreDesktopAuthFromStorage();
        return _signedIn && _authClient != null;
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  /// Ensure the user is signed in. On desktop, this may show the browser
  /// consent screen; `context` is required to show error dialogs if the loopback
  /// handler fails.
  Future<void> ensureSignedIn(BuildContext context) async {
    if (await isSignedIn()) return;

    if (Platform.isAndroid || Platform.isIOS) {
      _googleSignIn ??= GoogleSignIn(
        scopes: [calendar.CalendarApi.calendarScope],
      );
      final account = await _googleSignIn!.signIn();
      if (account == null) throw Exception('Sign in aborted by user');
      _signedIn = true;
      return;
    }

    // Desktop flow: use clientViaUserConsent with loopback. Provide error
    // instructions if the local callback fails (common cause: browser blocking or
    // an external factor that leads to a 500 on localhost).
    if (kDesktopClientId.startsWith('YOUR_') ||
        kDesktopClientId.isEmpty ||
        kDesktopClientSecret.startsWith('YOUR_') ||
        kDesktopClientSecret.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('OAuth client not configured'),
          content: SingleChildScrollView(
            child: ListBody(
              children: const [
                Text(
                  'The Desktop OAuth Client ID or Client Secret is not set.',
                ),
                SizedBox(height: 8),
                Text(
                  'Create a "Desktop" OAuth Client (APIs & Services → Credentials) and set both `kDesktopClientId` and `kDesktopClientSecret` in `lib/google_oauth_config.dart`.',
                ),
                SizedBox(height: 8),
                Text(
                  'Note: Keep the client secret private and avoid committing it to public repositories.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      throw Exception('Desktop OAuth Client ID/Secret not configured');
    }

    final scopes = [
      calendar.CalendarApi.calendarScope,
      'email',
      'profile',
      'https://www.googleapis.com/auth/userinfo.email',
      'https://www.googleapis.com/auth/userinfo.profile',
      'openid',
    ];

    try {
      final client = await _obtainDesktopAuthClient(context, scopes);
      _authClient = client;
      _signedIn = true;

      // Fetch user info from Google People API
      try {
        final peopleResp = await client.get(
          Uri.parse(
            'https://people.googleapis.com/v1/people/me?personFields=names,emailAddresses,photos',
          ),
        );
        if (peopleResp.statusCode == 200) {
          final data = jsonDecode(peopleResp.body);
          _desktopUserEmail =
              (data['emailAddresses'] != null &&
                  data['emailAddresses'].isNotEmpty)
              ? data['emailAddresses'][0]['value']
              : null;
          _desktopUserPhotoUrl =
              (data['photos'] != null && data['photos'].isNotEmpty)
              ? data['photos'][0]['url']
              : null;
        }
      } catch (_) {
        _desktopUserEmail = null;
        _desktopUserPhotoUrl = null;
      }

      // Save credentials to secure storage for persistence
      if (_storedCredentials != null && _currentAccessTokenString != null) {
        await _storage.saveCredentials(
          refreshToken: _storedCredentials!.refreshToken,
          accessToken: _currentAccessTokenString!,
          tokenExpiry: _storedCredentials!.accessToken.expiry,
          scopes: _storedCredentials!.scopes,
          userEmail: _desktopUserEmail,
          userPhotoUrl: _desktopUserPhotoUrl,
        );
        debugPrint('Credentials saved to secure storage');
      }
    } catch (err) {
      final errStr = err.toString();
      if (errStr.contains('invalid_client')) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('OAuth client error'),
            content: SingleChildScrollView(
              child: ListBody(
                children: const [
                  Text('The OAuth client was not found (invalid_client).'),
                  SizedBox(height: 8),
                  Text(
                    'Ensure you created a "Desktop" OAuth client in the Google Cloud Console (APIs & Services → Credentials) '
                    'and pasted its client ID into `lib/google_oauth_config.dart` as `kDesktopClientId`.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        rethrow;
      }

      // Show a helpful dialog with the actual error and actionable steps.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign-in failed'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                const Text('Sign-in did not complete.'),
                const SizedBox(height: 8),
                Text('Reason: ${err.toString()}'),
                const SizedBox(height: 8),
                const Text('Try one of the following:'),
                const SizedBox(height: 6),
                const Text(
                  '• Allow loopback redirects and try again using a different browser.',
                ),
                const Text(
                  '• Ensure the Desktop OAuth client ID exists in the Cloud Console.',
                ),
                const Text(
                  '• If the problem persists, use the manual copy/paste fallback when prompted.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                showDialog<void>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: const Text('Error details'),
                    content: SingleChildScrollView(child: Text(err.toString())),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dCtx).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Show details'),
            ),
          ],
        ),
      );

      rethrow;
    }
  }

  /// Gets an authenticated http client (throws if sign-in not done). The caller
  /// should not close the returned client in Android/iOS (google_sign_in token
  /// wrapper used), but for desktop clients we return the _authClient which is
  /// closed by callers when appropriate.
  Future<http.Client> _getAuthenticatedClient() async {
    if (Platform.isAndroid || Platform.isIOS) {
      _googleSignIn ??= GoogleSignIn(
        scopes: [calendar.CalendarApi.calendarScope],
      );

      final account =
          await _googleSignIn!.signInSilently() ??
          await _googleSignIn!.signIn();
      if (account == null) throw Exception('Sign in aborted by user');

      final auth = await account.authentication;
      final accessToken = auth.accessToken;
      if (accessToken == null) throw Exception('Missing access token');

      return _SimpleAuthClient(accessToken);
    }

    if (_authClient != null) return _authClient!;

    throw Exception('Not signed in (desktop).');
  }

  /// Inserts a calendar event into the primary calendar.
  Future<calendar.Event> insertEvent({
    required String summary,
    String? description,
    required DateTime start,
    required DateTime end,
    String calendarId = 'primary',
    List<Map<String, dynamic>>? reminders,
  }) async {
    final client = await _getAuthenticatedClient();

    final cal = calendar.CalendarApi(client);

    // Ensure we send timestamps with a valid timezone to Google Calendar.
    // Using UTC prevents invalid time zone definitions from causing API 400 errors.
    debugPrint(
      'Creating event: start=${start.toIso8601String()}, end=${end.toIso8601String()}, start.timeZone=${start.timeZoneName}, end.timeZone=${end.timeZoneName}',
    );

    final event = calendar.Event()
      ..summary = summary
      ..description = description
      ..start = calendar.EventDateTime(dateTime: start.toUtc(), timeZone: 'UTC')
      ..end = calendar.EventDateTime(dateTime: end.toUtc(), timeZone: 'UTC');

    if (reminders != null && reminders.isNotEmpty) {
      event.reminders = calendar.EventReminders(
        useDefault: false,
        overrides: reminders
            .map(
              (r) => calendar.EventReminder(
                method: r['method'],
                minutes: r['minutes'],
              ),
            )
            .toList(),
      );
    }

    final created = await cal.events.insert(event, calendarId);

    // If the desktop auth flow was used, the _authClient should stay open during
    // the app's session. We don't close it here.
    return created;
  }

  /// Fetches events from Google Calendar for a given date range with incremental sync support.
  /// Returns events list and syncToken for incremental sync.
  /// Uses user's local timezone consistently.
  /// CRITICAL: Handles pagination to get ALL events, not just the first page.
  /// calendarColor: Optional color of the calendar (for event coloring)
  Future<Map<String, dynamic>> getEventsWithSync({
    required DateTime start,
    required DateTime end,
    String calendarId = 'primary',
    String? syncToken,
    int? calendarColor,
  }) async {
    final client = await _getAuthenticatedClient();
    final cal = calendar.CalendarApi(client);

    // Get local timezone for proper date range calculation
    final localTimeZone = DateTime.now().timeZoneName;
    
    // Use UTC for API calls, but ensure we include the full day range
    // Add buffer to account for timezone differences
    final timeMin = DateTime(start.year, start.month, start.day, 0, 0, 0).toUtc();
    // End should be start of next day in UTC to include all events of the selected day
    final timeMax = DateTime(end.year, end.month, end.day, 23, 59, 59).toUtc();

    debugPrint('Fetching events: timeMin=$timeMin (${start.toLocal()}), timeMax=$timeMax (${end.toLocal()}), timezone=$localTimeZone');

    try {
      final allParsedEvents = <Map<String, dynamic>>[];
      String? currentPageToken;
      String? finalSyncToken;

      do {
        calendar.Events events;
        if (syncToken != null && syncToken.isNotEmpty && currentPageToken == null) {
          // Incremental sync (only on first page)
          events = await cal.events.list(
            calendarId,
            syncToken: syncToken,
            pageToken: currentPageToken,
          );
        } else {
          // Full sync or pagination
          events = await cal.events.list(
            calendarId,
            timeMin: timeMin,
            timeMax: timeMax,
            singleEvents: true,
            orderBy: 'startTime',
            pageToken: currentPageToken,
            timeZone: localTimeZone, // Specify timezone for proper filtering
          );
        }

        final items = events.items ?? [];
        debugPrint('Page returned ${items.length} events (pageToken: ${currentPageToken ?? 'none'})');
        
        // Parse all events from this page
        final parsedEvents = items
            .map((event) => _parseEvent(event, calendarId, calendarColor: calendarColor))
            .where((e) => e != null)
            .cast<Map<String, dynamic>>()
            .toList();
        
        allParsedEvents.addAll(parsedEvents);
        
        // Save syncToken from first page
        if (finalSyncToken == null) {
          finalSyncToken = events.nextSyncToken;
        }
        
        // Check if there are more pages
        currentPageToken = events.nextPageToken;
        
        if (currentPageToken != null) {
          debugPrint('More pages available, fetching next page...');
        }
      } while (currentPageToken != null);

      debugPrint('Total events fetched after pagination: ${allParsedEvents.length}');

      return {
        'events': allParsedEvents,
        'syncToken': finalSyncToken,
        'nextPageToken': null, // All pages fetched
      };
    } catch (e) {
      // Handle 410 GONE - syncToken expired
      if (e.toString().contains('410') || e.toString().contains('GONE')) {
        debugPrint('SyncToken expired, performing full sync');
        // Retry with full sync (with pagination)
        final allParsedEvents = <Map<String, dynamic>>[];
        String? currentPageToken;
        
        do {
          final events = await cal.events.list(
            calendarId,
            timeMin: timeMin,
            timeMax: timeMax,
            singleEvents: true,
            orderBy: 'startTime',
            pageToken: currentPageToken,
            timeZone: localTimeZone,
          );
          
          final items = events.items ?? [];
          final parsedEvents = items
              .map((event) => _parseEvent(event, calendarId, calendarColor: calendarColor))
              .where((e) => e != null)
              .cast<Map<String, dynamic>>()
              .toList();
          
          allParsedEvents.addAll(parsedEvents);
          currentPageToken = events.nextPageToken;
        } while (currentPageToken != null);
        
        return {
          'events': allParsedEvents,
          'syncToken': null, // Will be set on next successful sync
          'nextPageToken': null,
        };
      }
      rethrow;
    }
  }

  /// Fetches events from Google Calendar for a given date range.
  /// Returns a list of events as maps with: id, title, startDateTime, endDateTime, allDay, color, description
  Future<List<Map<String, dynamic>>> getEvents({
    required DateTime start,
    required DateTime end,
    String calendarId = 'primary',
  }) async {
    final result = await getEventsWithSync(
      start: start,
      end: end,
      calendarId: calendarId,
    );
    return result['events'] as List<Map<String, dynamic>>;
  }

  /// Fetches events from ALL calendars for a given date range.
  /// Returns a list of events with their calendar colors.
  /// CRITICAL: This fetches from ALL calendars directly from API, not filtered list
  Future<List<Map<String, dynamic>>> getEventsFromAllCalendars({
    required DateTime start,
    required DateTime end,
  }) async {
    // CRITICAL FIX: Get ALL calendars directly from API, don't use filtered getUserCalendars()
    // This ensures we get events from ALL calendars, not just filtered ones
    final client = await _getAuthenticatedClient();
    final calApi = calendar.CalendarApi(client);
    final list = await calApi.calendarList.list();
    final items = list.items ?? [];
    
    // Process all calendars (no filtering)
    final calendars = items.map((c) {
      // Get calendar color
      int calendarColor = 0xFF039BE5; // Default blue
      if (c.backgroundColor != null) {
        final hexColor = c.backgroundColor!.replaceAll('#', '');
        if (hexColor.length == 6) {
          calendarColor = int.parse('FF$hexColor', radix: 16);
        }
      } else if (c.colorId != null) {
        final colorMap = {
          '1': 0xFF7986CB, '2': 0xFF33B679, '3': 0xFF8E24AA, '4': 0xFFE67C73,
          '5': 0xFFF6BF26, '6': 0xFFF4511E, '7': 0xFF039BE5, '8': 0xFF0097A7,
          '9': 0xFFAD1457, '10': 0xFF616161, '11': 0xFF795548,
        };
        calendarColor = colorMap[c.colorId] ?? 0xFF039BE5;
      }
      
      return {
        'id': c.id ?? '',
        'name': c.summary ?? c.id ?? '',
        'color': calendarColor,
        'selected': c.selected ?? true,
      };
    }).where((c) {
      // Only filter out calendars with empty IDs
      final id = c['id'] as String?;
      return id != null && id.isNotEmpty;
    }).toList();
    
    final allEvents = <Map<String, dynamic>>[];

    debugPrint('=== FETCHING EVENTS FROM ALL CALENDARS ===');
    debugPrint('Total calendars found: ${calendars.length}');
    for (final cal in calendars) {
      debugPrint('  - ${cal['name']} (ID: ${cal['id']}, selected: ${cal['selected']})');
    }

    // Fetch events from each calendar
    // CRITICAL: Fetch from ALL calendars, regardless of selected/visible status
    // This ensures all calendar events are shown, not just default calendar
    int calendarsProcessed = 0;
    int calendarsWithEvents = 0;
    
    for (final cal in calendars) {
      final calendarId = cal['id'] as String;
      final calendarColor = cal['color'] as int;
      final calendarName = cal['name'] as String;

      // CRITICAL FIX: Don't skip calendars - show ALL calendars
      // The user wants to see events from all calendars, not just selected ones
      calendarsProcessed++;

      try {
        debugPrint('[Calendar $calendarsProcessed/${calendars.length}] Fetching from: $calendarName (ID: $calendarId)');
        final result = await getEventsWithSync(
          start: start,
          end: end,
          calendarId: calendarId,
          calendarColor: calendarColor,
        );
        
        final events = result['events'] as List<Map<String, dynamic>>;
        
        if (events.isNotEmpty) {
          calendarsWithEvents++;
        }
        
        // Update each event with the calendar's color
        for (final event in events) {
          event['color'] = calendarColor; // Use calendar color, not event color
          event['calendarId'] = calendarId;
          event['calendarName'] = calendarName;
        }
        
        allEvents.addAll(events);
        debugPrint('  ✓ Found ${events.length} events in "$calendarName"');
      } catch (e) {
        debugPrint('  ✗ ERROR fetching from "$calendarName": $e');
        // Continue with other calendars even if one fails
      }
    }

    debugPrint('=== SUMMARY ===');
    debugPrint('Calendars processed: $calendarsProcessed');
    debugPrint('Calendars with events: $calendarsWithEvents');
    debugPrint('Total events from all calendars: ${allEvents.length}');
    debugPrint('================');
    return allEvents;
  }

  /// Parses a Google Calendar event to our format
  /// CRITICAL: This must handle all event types including those created in Google Calendar app
  /// calendarColor: The color of the calendar this event belongs to (from calendarList)
  Map<String, dynamic>? _parseEvent(calendar.Event event, String calendarId, {int? calendarColor}) {
    // Skip cancelled/deleted events
    if (event.status == 'cancelled') {
      debugPrint('Skipping cancelled event: ${event.id}');
      return null;
    }

    final startDateTime = event.start?.dateTime ?? event.start?.date;
    final endDateTime = event.end?.dateTime ?? event.end?.date;
    final isAllDay = event.start?.date != null;

    DateTime? start;
    DateTime? end;
    
    if (isAllDay && startDateTime != null) {
      // All-day events use date only - keep in local timezone
      final dateStr = event.start!.date!.toIso8601String();
      start = DateTime.parse(dateStr);
      end = event.end?.date != null
          ? DateTime.parse(event.end!.date!.toIso8601String())
          : start.add(const Duration(days: 1));
    } else if (startDateTime != null && endDateTime != null) {
      // Convert UTC to local timezone
      // CRITICAL: Events from Google Calendar API are in UTC, convert to local
      start = startDateTime.toLocal();
      end = endDateTime.toLocal();
    } else {
      debugPrint('Skipping event with invalid date/time: ${event.id}, start=$startDateTime, end=$endDateTime');
      return null; // Skip invalid events
    }

    // Get color - prioritize calendar color, then event colorId, then default
    int eventColorValue = 0xFF039BE5; // Default blue
    
    // First, use the calendar's color (this is what Google Calendar does)
    if (calendarColor != null) {
      eventColorValue = calendarColor;
    } else if (event.colorId != null) {
      // Fallback to event-specific colorId if calendar color not provided
      final colorMap = {
        '1': 0xFF7986CB, // lavender
        '2': 0xFF33B679, // green
        '3': 0xFF8E24AA, // purple
        '4': 0xFFE67C73, // red
        '5': 0xFFF6BF26, // yellow
        '6': 0xFFF4511E, // orange
        '7': 0xFF039BE5, // blue
        '8': 0xFF0097A7, // teal
        '9': 0xFFAD1457, // pink
        '10': 0xFF616161, // grey
        '11': 0xFF795548, // brown
      };
      eventColorValue = colorMap[event.colorId] ?? 0xFF039BE5;
    }

    // CRITICAL: Handle events with no title (they should still be shown)
    final title = event.summary?.trim();
    if (title == null || title.isEmpty) {
      debugPrint('Event has no title, using default: ${event.id}');
    }

    return {
      'id': event.id ?? '',
      'title': title ?? '(No Title)',
      'startDateTime': start,
      'endDateTime': end,
      'allDay': isAllDay,
      'color': eventColorValue,
      'description': event.description ?? '',
      'reminders': event.reminders?.overrides?.map((r) => r.minutes ?? 0).toList() ?? [],
      'googleCalendarId': event.id,
      'calendarId': calendarId,
      'recurringEventId': event.recurringEventId,
      'recurrence': event.recurrence,
    };
  }

  /// Creates a watch channel for push notifications
  /// Returns channel info that should be stored
  Future<Map<String, dynamic>> watchCalendar({
    required String calendarId,
    required String channelId,
    required String address, // Webhook URL or app-specific identifier
    int expirationMinutes = 43200, // 30 days default
  }) async {
    final client = await _getAuthenticatedClient();
    final cal = calendar.CalendarApi(client);

    final expirationMs = DateTime.now().add(Duration(minutes: expirationMinutes)).millisecondsSinceEpoch;
    final channel = calendar.Channel()
      ..id = channelId
      ..type = 'web_hook'
      ..address = address
      ..expiration = expirationMs.toString();

    final result = await cal.events.watch(channel, calendarId);
    
    return {
      'channelId': result.id,
      'resourceId': result.resourceId,
      'expiration': result.expiration,
    };
  }

  /// Stops a watch channel
  Future<void> stopWatch({
    required String channelId,
    required String resourceId,
  }) async {
    final client = await _getAuthenticatedClient();
    final cal = calendar.CalendarApi(client);

    final channel = calendar.Channel()
      ..id = channelId
      ..resourceId = resourceId;

    await cal.channels.stop(channel);
  }

  /// Updates an existing event
  Future<calendar.Event> updateEvent({
    required String eventId,
    required String summary,
    String? description,
    required DateTime start,
    required DateTime end,
    String calendarId = 'primary',
    List<Map<String, dynamic>>? reminders,
    Color? color,
  }) async {
    final client = await _getAuthenticatedClient();
    final cal = calendar.CalendarApi(client);

    // Get existing event first
    final existingEvent = await cal.events.get(calendarId, eventId);

    // Update fields
    existingEvent.summary = summary;
    existingEvent.description = description;
    existingEvent.start = calendar.EventDateTime(
      dateTime: start.toUtc(),
      timeZone: 'UTC',
    );
    existingEvent.end = calendar.EventDateTime(
      dateTime: end.toUtc(),
      timeZone: 'UTC',
    );

    if (reminders != null && reminders.isNotEmpty) {
      existingEvent.reminders = calendar.EventReminders(
        useDefault: false,
        overrides: reminders
            .map(
              (r) => calendar.EventReminder(
                method: r['method'],
                minutes: r['minutes'],
              ),
            )
            .toList(),
      );
    }

    if (color != null) {
      // Map color to Google Calendar colorId (simplified)
      existingEvent.colorId = _colorToColorId(color);
    }

    return await cal.events.update(existingEvent, calendarId, eventId);
  }

  /// Deletes an event
  Future<void> deleteEvent({
    required String eventId,
    String calendarId = 'primary',
  }) async {
    final client = await _getAuthenticatedClient();
    final cal = calendar.CalendarApi(client);

    await cal.events.delete(calendarId, eventId);
  }

  /// Maps Flutter Color to Google Calendar colorId
  String? _colorToColorId(Color color) {
    final colorValue = color.value;
    // Map common colors to Google Calendar color IDs
    if (colorValue == 0xFF7986CB) return '1';
    if (colorValue == 0xFF33B679) return '2';
    if (colorValue == 0xFF8E24AA) return '3';
    if (colorValue == 0xFFE67C73) return '4';
    if (colorValue == 0xFFF6BF26) return '5';
    if (colorValue == 0xFFF4511E) return '6';
    if (colorValue == 0xFF039BE5 || colorValue == 0xFF2196F3) return '7';
    if (colorValue == 0xFF0097A7) return '8';
    if (colorValue == 0xFFAD1457) return '9';
    if (colorValue == 0xFF616161) return '10';
    if (colorValue == 0xFF795548) return '11';
    return '7'; // Default to blue
  }

  /// Signs out and clears all stored authentication data.
  Future<void> signOut() async {
    if (_googleSignIn != null) {
      await _googleSignIn!.signOut();
    }

    _authClient?.close();
    _authClient = null;
    _signedIn = false;
    _storedCredentials = null;
    _currentAccessTokenString = null;
    _desktopUserEmail = null;
    _desktopUserPhotoUrl = null;

    // Clear stored credentials and default calendar from secure storage
    await _storage.clearCredentials();
    await _storage.clearDefaultCalendar();
    debugPrint(
      'Signed out and cleared stored credentials and default calendar',
    );
  }

  /// Return a human-readable account label when available (displayName or email).
  Future<String?> getAccountDisplayName() async {
    if (Platform.isAndroid || Platform.isIOS) {
      _googleSignIn ??= GoogleSignIn(
        scopes: [calendar.CalendarApi.calendarScope],
      );
      final acc = await _googleSignIn!.signInSilently();
      return acc?.displayName ?? acc?.email;
    }

    if (_signedIn) return 'Signed in (Desktop)';
    return null;
  }

  /// Attempts a PKCE + loopback flow. Binds to IPv4 (prefer 127.0.0.1) and falls
  /// back to IPv6 binding. If the browser cannot connect back, offers a manual
  /// code paste fallback.
  Future<http.Client> _obtainDesktopAuthClient(
    BuildContext context,
    List<String> scopes,
  ) async {
    final verifier = _createCodeVerifier();
    final challenge = _createCodeChallenge(verifier);

    HttpServer server;
    try {
      // Prefer IPv4 loopback to avoid localhost => ::1 IPv6 mismatches.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } catch (_) {
      // Fall back to IPv6 (allow both v6 and v4 mapped if supported).
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv6,
        0,
        v6Only: false,
      );
    }

    final port = server.port;
    debugPrint('Loopback server listening on port $port');
    final redirectUri = 'http://127.0.0.1:$port/';

    // Use trimmed client id to avoid accidental whitespace copying issues.
    final clientId = kDesktopClientId.trim();
    final clientSecret = kDesktopClientSecret.trim();
    debugPrint('Using Desktop client id: $clientId');
    debugPrint(
      'Desktop client secret length: ${clientSecret.length} (not printing secret)',
    );

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': scopes.join(' '),
      'access_type': 'offline',
      'prompt': 'consent',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });

    // Open system browser to authorize.
    debugPrint('Opening browser to ${authUrl.toString()}');
    await launchUrlString(
      authUrl.toString(),
      mode: LaunchMode.externalApplication,
    );

    // Robust listener: use a shared completer so either the server handler or
    // the manual dialog can supply the authorization code. This lets us handle
    // timeouts, late arrivals (race), and programmatically close the manual
    // dialog if the server later receives the callback.
    final resultCompleter = Completer<String>();
    var manualDialogOpen = false;

    server.listen(
      (request) async {
        try {
          final params = request.uri.queryParameters;
          debugPrint('Loopback request received: ${request.uri}');
          if (params.containsKey('error')) {
            final err = params['error']!;
            request.response.statusCode = 200;
            request.response.headers.set(
              'Content-Type',
              'text/html; charset=utf-8',
            );
            final html = _buildBrandedHtmlPage(
              title: 'Authentication Failed',
              message: err,
              isError: true,
            );
            request.response.write(html);
            await request.response.close();

            if (!resultCompleter.isCompleted) {
              resultCompleter.completeError(Exception('OAuth error: $err'));
            }
            return;
          }

          final nextCode = params['code'];
          if (nextCode != null) {
            // respond to browser immediately
            request.response.statusCode = 200;
            request.response.headers.set(
              'Content-Type',
              'text/html; charset=utf-8',
            );
            final html = _buildBrandedHtmlPage(
              title: 'Authentication Successful',
              message: 'You can close this window.',
              isError: false,
            );
            request.response.write(html);
            await request.response.close();

            if (!resultCompleter.isCompleted) {
              resultCompleter.complete(nextCode);
              // close manual dialog if open
              if (manualDialogOpen) {
                try {
                  Navigator.of(context, rootNavigator: true).pop();
                } catch (_) {}
              }
            }
            return;
          }

          // No recognizable params - return a simple page
          request.response.statusCode = 400;
          request.response.headers.set(
            'Content-Type',
            'text/html; charset=utf-8',
          );
          final html = _buildBrandedHtmlPage(
            title: 'Invalid Request',
            message: 'The authentication request was invalid.',
            isError: true,
          );
          request.response.write(html);
          await request.response.close();
        } catch (e) {
          // If the server handler itself throws, surface it.
          if (!resultCompleter.isCompleted)
            resultCompleter.completeError(Exception('Server error: $e'));
          try {
            await request.response.close();
          } catch (_) {}
        }
      },
      onError: (e) {
        if (!resultCompleter.isCompleted) resultCompleter.completeError(e);
      },
    );

    // Wait a short period for automatic callback. If nothing arrives, show
    // the manual-copy dialog and wait for either to complete.
    String code;
    try {
      try {
        // Wait briefly for automatic callback from browser.
        final auto = await resultCompleter.future.timeout(
          const Duration(seconds: 20),
        );
        code = auto;
      } on TimeoutException {
        // No automatic callback soon - prompt the user for manual copy/paste, but
        // keep listening for a late automatic callback.
        manualDialogOpen = true;
        debugPrint('Showing manual copy/paste dialog for auth URL');
        _showManualCodeInputDialog(context, authUrl.toString()).then((manual) {
          debugPrint(
            'Manual dialog closed, manual code: ${manual != null ? 'provided' : 'cancelled'}',
          );
          manualDialogOpen = false;
          if (!resultCompleter.isCompleted) {
            if (manual == null) {
              resultCompleter.completeError(Exception('Sign in aborted'));
            } else {
              resultCompleter.complete(manual);
            }
          }
        });

        // Wait longer for either the server callback or manual input.
        code = await resultCompleter.future.timeout(const Duration(minutes: 3));
      }
    } catch (err) {
      // bubble up with informative message
      throw Exception(
        'Automatic localhost callback failed or sign-in aborted: ${err.toString()}',
      );
    } finally {
      // ensure server closed
      await server.close(force: true);
    }

    // Use the already-trimmed clientId/clientSecret and add HTTP Basic auth header.
    final basicAuth =
        'Basic ${base64Encode(utf8.encode('${clientId}:${clientSecret}'))}';

    final tokenResp = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': basicAuth,
      },
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': clientId,
        'client_secret': clientSecret,
        'code_verifier': verifier,
      },
    );

    // Debug: log token response for troubleshooting (remove/guard in prod).
    debugPrint('OAuth token exchange status: ${tokenResp.statusCode}');
    debugPrint('OAuth token exchange body: ${tokenResp.body}');

    if (tokenResp.statusCode == 401 || tokenResp.statusCode == 400) {
      final body = tokenResp.body.toLowerCase();
      if (body.contains('invalid_client') || body.contains('client_secret')) {
        throw Exception(
          'Token exchange returned invalid_client / client_secret error. Check Desktop client ID/secret, exact copy, and that the client is type "Desktop" in Cloud Console. Response: ${tokenResp.body}',
        );
      }
    }

    if (tokenResp.statusCode != 200) {
      throw Exception('Token exchange failed: ${tokenResp.body}');
    }

    final tokenJson = jsonDecode(tokenResp.body) as Map<String, dynamic>;

    // Show presence of tokens (but not the tokens themselves) to help debugging.
    final hasAccess =
        tokenJson.containsKey('access_token') &&
        (tokenJson['access_token'] as String).isNotEmpty;
    final hasRefresh =
        tokenJson.containsKey('refresh_token') &&
        (tokenJson['refresh_token'] as String).isNotEmpty;
    debugPrint(
      'OAuth tokens present - access_token: $hasAccess, refresh_token: $hasRefresh',
    );
    final accessToken = tokenJson['access_token'] as String?;
    final refreshToken = tokenJson['refresh_token'] as String?;
    final expiresIn = tokenJson['expires_in'] as int? ?? 3600;

    final tokenExpiry = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .toUtc();
    final token = auth_io.AccessToken('Bearer', accessToken!, tokenExpiry);

    final credentials = auth_io.AccessCredentials(token, refreshToken, scopes);

    // Store credentials and access token string for later persistence
    _storedCredentials = credentials;
    _currentAccessTokenString = accessToken;

    final client = auth_io.authenticatedClient(http.Client(), credentials);
    return client;
  }

  String _createCodeVerifier() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _createCodeChallenge(String verifier) {
    final bytes = sha256.convert(utf8.encode(verifier)).bytes;
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<String?> _showManualCodeInputDialog(
    BuildContext context,
    String authUrl,
  ) {
    final controller = TextEditingController();

    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete sign-in manually'),
        content: SingleChildScrollView(
          child: ListBody(
            children: [
              const Text('The browser could not reach the app at localhost.'),
              const SizedBox(height: 8),
              const Text(
                'Click the link below, complete sign-in, then copy the "code" parameter from the URL and paste it below.',
              ),
              const SizedBox(height: 6),
              SelectableText(authUrl),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Paste code here'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData('text/plain');
              if (data?.text != null) {
                controller.text = data!.text!;
              }
            },
            child: const Text('Paste from clipboard'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(
              controller.text.trim().isEmpty ? null : controller.text.trim(),
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  /// Builds a branded HTML page for OAuth redirect
  String _buildBrandedHtmlPage({
    required String title,
    required String message,
    required bool isError,
  }) {
    final color = isError ? '#D32F2F' : '#D99A00'; // Error red or primary gold
    final iconBg = isError
        ? 'rgba(211, 47, 47, 0.2)'
        : 'rgba(217, 154, 0, 0.2)';
    final iconSymbol = isError ? '✕' : '✓';

    // Escape HTML special characters in title and message
    final escapedTitle = _escapeHtml(title);
    final escapedMessage = _escapeHtml(message);

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$escapedTitle - Agenix</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&display=swap');
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    body {
      font-family: 'Montserrat', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: linear-gradient(135deg, #030303 0%, #161616 100%);
      color: #F5F5F5;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      padding: 20px;
    }
    .container {
      background: #161616;
      border-radius: 16px;
      padding: 48px 32px;
      text-align: center;
      max-width: 500px;
      width: 100%;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
      border: 1px solid rgba(217, 154, 0, 0.2);
    }
    .logo {
      font-size: 32px;
      font-weight: 700;
      color: #D99A00;
      margin-bottom: 8px;
      letter-spacing: -0.5px;
    }
    .subtitle {
      font-size: 14px;
      color: #D1D5DB;
      margin-bottom: 32px;
      font-weight: 400;
      opacity: 0.8;
    }
    .icon {
      width: 64px;
      height: 64px;
      margin: 0 auto 24px;
      border-radius: 50%;
      background: $iconBg;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 32px;
    }
    h1 {
      font-size: 24px;
      font-weight: 600;
      color: $color;
      margin-bottom: 16px;
    }
    p {
      font-size: 16px;
      color: #D1D5DB;
      line-height: 1.6;
      font-weight: 400;
    }
    .divider {
      height: 1px;
      background: rgba(217, 154, 0, 0.2);
      margin: 32px 0;
    }
    .footer {
      font-size: 12px;
      color: #9CA3AF;
      margin-top: 24px;
      opacity: 0.6;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="logo">AGENIX</div>
    <div class="subtitle">Streamline your calendar management</div>
    <div class="icon">$iconSymbol</div>
    <h1>$escapedTitle</h1>
    <p>$escapedMessage</p>
    <div class="divider"></div>
    <div class="footer">You can safely close this window.</div>
  </div>
</body>
</html>
''';
  }

  /// Escapes HTML special characters to prevent XSS and parsing errors
  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}

/// Very small auth-wrapping HTTP client that attaches an Authorization header.
/// Used for simple GoogleSignIn-based calls where only a short-lived access
/// token is available.
class _SimpleAuthClient extends http.BaseClient {
  final String _accessToken;
  final http.Client _inner = http.Client();

  _SimpleAuthClient(this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }
}
