import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../models/calendar_event.dart';
import '../services/google_calendar_service.dart';
import '../providers/event_providers.dart';
import '../repositories/event_repository.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import 'widgets/event_creation_modal.dart';
import 'create_event_screen.dart';
import 'settings_screen.dart';
import '../widgets/context_menu.dart';
import '../navigation/app_route_observer.dart';
import '../widgets/app_animations.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/modern_splash_screen.dart';

class CalendarDayViewScreen extends ConsumerStatefulWidget {
  final VoidCallback? onSignOut;
  final VoidCallback? onInitialReady;

  const CalendarDayViewScreen({super.key, this.onSignOut, this.onInitialReady});

  @override
  ConsumerState<CalendarDayViewScreen> createState() =>
      _CalendarDayViewScreenState();
}

class _CalendarDayViewScreenState extends ConsumerState<CalendarDayViewScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin, RouteAware {
  static const Color _eventBlockTextColor = Color(0xFF141614);
  static const double _pastEventOpacity = 0.55;
  static const double _desktopTimeColumnWidth = 72.0;
  static const double _mobileTimeColumnWidth = 56.0;
  static const Duration _touchLongPressDuration = Duration(milliseconds: 320);
  static const double _touchCancelDistance = 10.0;
  static const Duration _mobileDoubleTapWindow = Duration(milliseconds: 280);
  static const double _mobileDoubleTapDistance = 28.0;
  static const Duration _desktopDoubleClickWindow = Duration(milliseconds: 260);
  static const double _desktopDoubleClickDistance = 18.0;
  static const double _mobileMinEventInteractionHeight = 52.0;
  static const double _horizontalSwipeMinDistance = 56.0;
  static const double _horizontalSwipeDominanceRatio = 1.2;
  static const int _horizontalSwipeMaxDurationMs = 700;
  static const Duration _optimisticEventOverrideTtl = Duration(seconds: 6);
  static const Duration _daySwitchMinLoader = Duration(milliseconds: 600);

  DateTime _currentDate = DateTime.now();
  late DateTime _selectedRangeStartDate;
  late DateTime _selectedRangeEndDate;
  late DateTime _miniCalendarVisibleMonth;
  late final EventRepository _repository;
  late final SyncService _syncService;
  StreamSubscription<List<CalendarEvent>>? _eventsSubscription;
  late final ProviderSubscription<AsyncValue<SyncStatus>> _syncStatusSub;
  late final AnimationController _syncRotationController;
  late final FocusNode _keyboardListenerFocusNode;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Use Map to prevent duplicates - key is event ID
  final Map<String, CalendarEvent> _eventsMap = {};
  final Map<String, CalendarEvent> _optimisticEventOverrides = {};
  final Map<String, DateTime> _optimisticEventOverrideExpiresAt = {};
  List<CalendarEvent> _allDayEvents = [];
  List<CalendarEvent> _timedEvents = [];

  bool _keyboardShortcutsEnabled = true;
  bool _isLoading = true;
  bool _hasLoadedEventsOnce = false;
  bool _isSyncing = false;
  DateTime? _loadingStartedAt;
  bool _didReportInitialReady = false;
  String? _selectedCalendarId;
  String? _userEmail;
  String? _userDisplayName;
  String? _userPhotoUrl;
  Map<String, int> _calendarColors = {}; // Map of calendarId -> color

  // Drag state
  String? _draggedEventId;
  DateTime? _dragStartTime;
  Offset? _dragStartGlobalPosition;
  CalendarEvent? _draggedEventOriginal;
  bool _isDraggingEvent = false;

  // Resize state
  String? _resizingEventId;
  bool? _resizingFromTop;
  CalendarEvent? _resizingEventOriginal;
  String? _resizeHoverEventId;
  bool? _resizeHoverFromTop;
  double? _resizeStartGlobalY;
  DateTime? _resizeAnchorStart;
  DateTime? _resizeAnchorEnd;

  // Scroll controller for unified timeline scrolling
  final ScrollController _dayGridScrollController = ScrollController();

  // Interaction state (Google Calendar-like)
  final Map<String, FocusNode> _eventFocusNodes = {};
  String? _keyboardActiveEventId;
  String? _eventActionsPopoverEventId;
  String? _pendingPointerEventId;
  Offset? _pointerDownGlobalPosition;
  bool _dragThresholdExceeded = false;
  CalendarEvent? _dragPreviewEvent;
  bool _isPointerDownOnEvent = false;
  double? _dayGridWidth;

  // Drag-to-create state
  bool _isDraggingToCreate = false;
  bool _isPointerDownOnGrid = false;
  Offset? _gridPointerDownPosition;
  DateTime? _pendingCreateStartTime;
  DateTime? _pendingCreateEndTime;

  // Context menu
  Offset? _contextMenuPosition;
  CalendarEvent? _contextMenuEvent;

  // Touch support
  bool _didInitialNowScroll = false;
  int _initialNowScrollAttempts = 0;
  bool _isSwipeNavigating = false;
  Offset? _swipeStartGlobalPosition;
  DateTime? _swipeStartTime;
  Timer? _eventLongPressTimer;
  bool _eventLongPressArmed = false;
  String? _touchPendingEventId;
  String? _lastMobileTapEventId;
  DateTime? _lastMobileTapTime;
  Offset? _lastMobileTapPosition;
  String? _lastDesktopClickEventId;
  DateTime? _lastDesktopClickTime;
  Offset? _lastDesktopClickPosition;
  Timer? _resizeLongPressTimer;
  String? _touchPendingResizeEventId;
  Offset? _resizeTouchDownGlobalPosition;
  Timer? _gridLongPressTimer;
  bool _gridLongPressArmed = false;
  Offset? _lastGridPointerPosition;
  bool _isRouteVisible = false;
  bool _syncLoopActive = false;
  bool _screenInitialized = false;
  ModalRoute<dynamic>? _subscribedRoute;
  bool _isOfflineSnackBarVisible = false;

  // Mini calendar range-selection state
  bool _isMiniCalendarRangeSelecting = false;
  DateTime? _miniCalendarPreviewStartDate;
  DateTime? _miniCalendarPreviewEndDate;
  DateTime? _miniCalendarDragAnchorDate;
  final GlobalKey _miniCalendarGridKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final today = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    _selectedRangeStartDate = today;
    _selectedRangeEndDate = today;
    _miniCalendarVisibleMonth = DateTime(_currentDate.year, _currentDate.month);
    WidgetsBinding.instance.addObserver(this);
    _repository = ref.read(eventRepositoryProvider);
    _syncService = ref.read(syncServiceProvider);
    _syncRotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _keyboardListenerFocusNode = FocusNode();

    _initialize();
    _syncStatusSub = ref.listenManual<AsyncValue<SyncStatus>>(
      syncStatusProvider,
      (previous, next) {
        _handleSyncStatusChanged(next);
        _updateSyncRotation(next);
        final status = next.valueOrNull;
        if (status != null && mounted) {
          _handleSyncStatusSnackBar(status);
        }
      },
    );
    _handleSyncStatusChanged(ref.read(syncStatusProvider));
    _updateSyncRotation(ref.read(syncStatusProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keyboardListenerFocusNode.requestFocus();
    });
  }

  Future<void> _initialize() async {
    await _loadCalendarId();
    _subscribeToEvents();
    _screenInitialized = true;
    unawaited(_resumeSyncLoopIfNeeded());
    unawaited(_loadCalendarColors());
    unawaited(_refreshUserInfo());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && _subscribedRoute != route) {
      if (_subscribedRoute is PageRoute) {
        appRouteObserver.unsubscribe(this);
      }
      _subscribedRoute = route;
      appRouteObserver.subscribe(this, route);
      _isRouteVisible = route.isCurrent;
      unawaited(
        _isRouteVisible ? _resumeSyncLoopIfNeeded() : _pauseSyncLoopIfNeeded(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventsSubscription?.cancel();
    _syncStatusSub.close();
    _syncRotationController.dispose();
    _keyboardListenerFocusNode.dispose();
    if (_subscribedRoute is PageRoute) {
      appRouteObserver.unsubscribe(this);
    }
    unawaited(_pauseSyncLoopIfNeeded());
    _dayGridScrollController.dispose();
    for (final node in _eventFocusNodes.values) {
      node.dispose();
    }
    _eventLongPressTimer?.cancel();
    _resizeLongPressTimer?.cancel();
    _gridLongPressTimer?.cancel();
    super.dispose();
  }

  Future<void> _resumeSyncLoopIfNeeded() async {
    if (!_screenInitialized || !_isRouteVisible || _syncLoopActive) return;
    await _syncService.start(
      range: _currentRange,
      calendarId: _selectedCalendarId ?? 'primary',
    );
    _syncLoopActive = true;
  }

  Future<void> _pauseSyncLoopIfNeeded() async {
    if (!_syncLoopActive) return;
    await _syncService.stop();
    _syncLoopActive = false;
  }

  void _updateSyncRotation(AsyncValue<SyncStatus> syncState) {
    final isSyncing = syncState.maybeWhen(
      data: (status) => status.state == SyncState.syncing,
      loading: () => true,
      orElse: () => false,
    );

    if (isSyncing) {
      if (!_syncRotationController.isAnimating) {
        _syncRotationController.repeat();
      }
      return;
    }

    if (_syncRotationController.isAnimating) {
      _syncRotationController.stop();
    }
    _syncRotationController.value = 0;
  }

  void _showCompactSnackBar(
    String message, {
    Duration? duration,
    AppSnackBarType? type,
  }) {
    if (!mounted) return;
    final scaffoldContext = _scaffoldKey.currentContext;
    if (scaffoldContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showCompactSnackBar(message, duration: duration, type: type);
      });
      return;
    }
    showAppSnackBar(scaffoldContext, message, duration: duration, type: type);
  }

  bool _isLikelyOfflineError(String message) {
    final text = message.toLowerCase();
    return text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('network is unreachable') ||
        text.contains('name or service not known') ||
        text.contains('no address associated with hostname') ||
        text.contains('nodename nor servname provided');
  }

  void _handleSyncStatusSnackBar(SyncStatus status) {
    if (status.state == SyncState.error) {
      final message = status.error ?? 'Sync error';
      if (_isLikelyOfflineError(message)) {
        if (_isOfflineSnackBarVisible) return;
        _isOfflineSnackBarVisible = true;
        _showCompactSnackBar(
          'No internet connection',
          type: AppSnackBarType.offline,
          duration: const Duration(days: 1),
        );
        return;
      }
      _isOfflineSnackBarVisible = false;
      _showCompactSnackBar(message, type: AppSnackBarType.error);
      return;
    }

    if (_isOfflineSnackBarVisible) {
      _isOfflineSnackBarVisible = false;
      _showCompactSnackBar(
        'Back online',
        type: AppSnackBarType.success,
        duration: const Duration(seconds: 2),
      );
    }
  }

  bool _syncingFromState(AsyncValue<SyncStatus> syncState) {
    return syncState.maybeWhen(
      data: (status) => status.state == SyncState.syncing,
      loading: () => true,
      orElse: () => false,
    );
  }

  void _handleSyncStatusChanged(AsyncValue<SyncStatus> syncState) {
    final nextSyncing = _syncingFromState(syncState);
    if (!mounted || _isSyncing == nextSyncing) return;
    setState(() {
      _isSyncing = nextSyncing;
    });
  }

  bool _isMobileLayout(BuildContext context) {
    return MediaQuery.of(context).size.width < 700;
  }

  double _timeColumnWidthFor(BuildContext context) {
    return _isMobileLayout(context)
        ? _mobileTimeColumnWidth
        : _desktopTimeColumnWidth;
  }

  DateTimeRange get _currentRange {
    final dayStart = DateTime(
      _selectedRangeStartDate.year,
      _selectedRangeStartDate.month,
      _selectedRangeStartDate.day,
    );
    final dayEnd = DateTime(
      _selectedRangeEndDate.year,
      _selectedRangeEndDate.month,
      _selectedRangeEndDate.day,
    ).add(const Duration(days: 1));
    return DateTimeRange(start: dayStart, end: dayEnd);
  }

  int get _selectedRangeDayCount {
    return _selectedRangeEndDate.difference(_selectedRangeStartDate).inDays + 1;
  }

  List<DateTime> get _selectedRangeDays {
    return List<DateTime>.generate(_selectedRangeDayCount, (index) {
      return _selectedRangeStartDate.add(Duration(days: index));
    });
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  ({DateTime start, DateTime end}) _normalizedRangeForSelection(
    DateTime start,
    DateTime end,
  ) {
    final normalizedStart = _normalizeDate(start);
    final normalizedEnd = _normalizeDate(end);
    var rangeStart = normalizedStart.isBefore(normalizedEnd)
        ? normalizedStart
        : normalizedEnd;
    var rangeEnd = normalizedStart.isBefore(normalizedEnd)
        ? normalizedEnd
        : normalizedStart;

    const maxDays = 7;
    if (rangeEnd.difference(rangeStart).inDays + 1 > maxDays) {
      rangeEnd = rangeStart.add(const Duration(days: maxDays - 1));
    }
    return (start: rangeStart, end: rangeEnd);
  }

  Future<void> _handleDateRangeChange(DateTime start, DateTime end) async {
    final normalized = _normalizedRangeForSelection(start, end);
    final rangeStart = normalized.start;
    final rangeEnd = normalized.end;

    final currentStart = _normalizeDate(_selectedRangeStartDate);
    final currentEnd = _normalizeDate(_selectedRangeEndDate);
    if (rangeStart == currentStart && rangeEnd == currentEnd) return;

    setState(() {
      _currentDate = rangeStart;
      _selectedRangeStartDate = rangeStart;
      _selectedRangeEndDate = rangeEnd;
      _miniCalendarVisibleMonth = DateTime(rangeStart.year, rangeStart.month);
      _isLoading = true;
      _loadingStartedAt = DateTime.now();
      _optimisticEventOverrides.clear();
      _optimisticEventOverrideExpiresAt.clear();
      _didInitialNowScroll = false;
      _initialNowScrollAttempts = 0;
    });
    _subscribeToEvents();
    unawaited(
      _syncService.updateRange(_currentRange).catchError((e) {
        debugPrint('Error updating range after date change: $e');
      }),
    );
  }

  void _subscribeToEvents() {
    _eventsSubscription?.cancel();
    final startedAt = DateTime.now();
    if (_isLoading) {
      _loadingStartedAt ??= startedAt;
    } else {
      setState(() {
        _isLoading = true;
        _loadingStartedAt = startedAt;
      });
    }

    _eventsSubscription = _repository.watchEvents(_currentRange).listen((
      events,
    ) async {
      final resolvedEvents = _resolveOptimisticEvents(events);
      _eventsMap
        ..clear()
        ..addEntries(resolvedEvents.map((e) => MapEntry(e.id, e)));

      final startedAt = _loadingStartedAt;
      if (_hasLoadedEventsOnce && startedAt != null) {
        final elapsed = DateTime.now().difference(startedAt);
        final remaining = _daySwitchMinLoader - elapsed;
        if (remaining > Duration.zero) {
          await Future.delayed(remaining);
        }
      }
      if (!mounted) return;

      setState(() {
        _updateEventLists();
        _isLoading = false;
        _hasLoadedEventsOnce = true;
      });
      if (!_didReportInitialReady) {
        _didReportInitialReady = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onInitialReady?.call();
        });
      }
      _scrollToNowOnInitialOpen();
    });
  }

  List<CalendarEvent> _resolveOptimisticEvents(List<CalendarEvent> incoming) {
    if (_optimisticEventOverrides.isEmpty) return incoming;

    final now = DateTime.now();
    final mergedById = <String, CalendarEvent>{
      for (final event in incoming) event.id: event,
    };

    final expiredIds = <String>[];
    for (final entry in _optimisticEventOverrideExpiresAt.entries) {
      if (now.isAfter(entry.value)) {
        expiredIds.add(entry.key);
      }
    }
    for (final id in expiredIds) {
      _optimisticEventOverrideExpiresAt.remove(id);
      _optimisticEventOverrides.remove(id);
    }

    final resolvedOverrideIds = <String>[];
    for (final entry in _optimisticEventOverrides.entries) {
      final id = entry.key;
      final optimistic = entry.value;
      final incomingEvent = mergedById[id];

      if (incomingEvent != null &&
          _eventTimingMatches(optimistic, incomingEvent)) {
        resolvedOverrideIds.add(id);
        continue;
      }

      mergedById[id] = optimistic;
    }
    for (final id in resolvedOverrideIds) {
      _optimisticEventOverrides.remove(id);
      _optimisticEventOverrideExpiresAt.remove(id);
    }

    return mergedById.values.toList();
  }

  bool _eventTimingMatches(CalendarEvent a, CalendarEvent b) {
    return a.startDateTime == b.startDateTime &&
        a.endDateTime == b.endDateTime &&
        a.allDay == b.allDay;
  }

  void _pinOptimisticEventOverride(CalendarEvent event) {
    _optimisticEventOverrides[event.id] = event;
    _optimisticEventOverrideExpiresAt[event.id] = DateTime.now().add(
      _optimisticEventOverrideTtl,
    );
  }

  void _clearOptimisticEventOverride(String eventId) {
    _optimisticEventOverrides.remove(eventId);
    _optimisticEventOverrideExpiresAt.remove(eventId);
  }

  void _scrollToNowOnInitialOpen() {
    if (_didInitialNowScroll) return;
    final now = DateTime.now();
    final viewedDay = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    if (!viewedDay.isAtSameMomentAs(today)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didInitialNowScroll) return;
      if (!_dayGridScrollController.hasClients) {
        if (_initialNowScrollAttempts < 8) {
          _initialNowScrollAttempts++;
          _scrollToNowOnInitialOpen();
        }
        return;
      }

      const hourHeight = 60.0;
      final nowPosition = ((now.hour * 60 + now.minute) / 60) * hourHeight;
      final viewport = _dayGridScrollController.position.viewportDimension;
      final targetOffset = (nowPosition - (viewport / 2)).clamp(
        0.0,
        _dayGridScrollController.position.maxScrollExtent,
      );

      _dayGridScrollController.jumpTo(targetOffset);
      _didInitialNowScroll = true;
    });
  }

  Future<void> _handleDateChange(DateTime newDate) async {
    await _handleDateRangeChange(newDate, newDate);
  }

  void _handleSwipePointerDown(PointerDownEvent event) {
    if (!_isMobileLayout(context)) return;
    _swipeStartGlobalPosition = event.position;
    _swipeStartTime = DateTime.now();
  }

  void _resetSwipeTracking() {
    _swipeStartGlobalPosition = null;
    _swipeStartTime = null;
  }

  void _handleGlobalPointerUp(PointerUpEvent event) {
    if (_isPointerDownOnGrid) {
      _handleGridPointerUp(event);
      return;
    }

    if (_resizingEventId != null) {
      _isPointerDownOnEvent = false;
      _finalizeEventResize();
      return;
    }

    if (_isDraggingEvent && _draggedEventId != null) {
      _isPointerDownOnEvent = false;
      _pendingPointerEventId = null;
      _pointerDownGlobalPosition = null;
      _eventLongPressTimer?.cancel();
      _clearEventTouchPressState();
      _finalizeEventDrag();
      return;
    }

    if (_isPointerDownOnEvent || _pendingPointerEventId != null) {
      setState(() {
        _isPointerDownOnEvent = false;
        _pendingPointerEventId = null;
        _pointerDownGlobalPosition = null;
        _dragThresholdExceeded = false;
        _dragStartGlobalPosition = null;
        _dragStartTime = null;
        _draggedEventOriginal = null;
      });
      _clearEventTouchPressState();
    }
  }

  void _handleGlobalPointerCancel() {
    if (_isPointerDownOnGrid) {
      _handleGridPointerCancel();
    }

    if (_resizingEventId != null) {
      final original = _resizingEventOriginal;
      if (original != null) {
        _eventsMap[original.id] = original;
        _updateEventLists();
      }
      setState(() {
        _resizingEventId = null;
        _resizingFromTop = null;
        _resizingEventOriginal = null;
        _resizeHoverEventId = null;
        _resizeHoverFromTop = null;
        _resizeStartGlobalY = null;
        _resizeAnchorStart = null;
        _resizeAnchorEnd = null;
        _isPointerDownOnEvent = false;
      });
      return;
    }

    if (_isDraggingEvent ||
        _pendingPointerEventId != null ||
        _isPointerDownOnEvent) {
      setState(() {
        _clearDragState();
        _pendingPointerEventId = null;
        _pointerDownGlobalPosition = null;
        _dragThresholdExceeded = false;
        _isPointerDownOnEvent = false;
      });
    }
    _clearEventTouchPressState();
  }

  Future<void> _handleSwipePointerUp(PointerUpEvent event) async {
    try {
      if (!_isMobileLayout(context)) return;
      if (_isDraggingEvent ||
          _isDraggingToCreate ||
          _resizingEventId != null ||
          _isSwipeNavigating) {
        return;
      }
      if (_swipeStartGlobalPosition == null || _swipeStartTime == null) return;

      final swipeDurationMs = DateTime.now()
          .difference(_swipeStartTime!)
          .inMilliseconds;
      final delta = event.position - _swipeStartGlobalPosition!;
      final absDx = delta.dx.abs();
      final absDy = delta.dy.abs();

      final isHorizontalEnough = absDx >= _horizontalSwipeMinDistance;
      final isMostlyHorizontal =
          absDx >= (absDy * _horizontalSwipeDominanceRatio);
      final isQuickEnough = swipeDurationMs <= _horizontalSwipeMaxDurationMs;

      if (!isHorizontalEnough || !isMostlyHorizontal || !isQuickEnough) return;

      final currentDay = DateTime(
        _currentDate.year,
        _currentDate.month,
        _currentDate.day,
      );
      // Requested mapping: swipe left => +1 day, swipe right => -1 day.
      final dayDelta = delta.dx < 0 ? 1 : -1;
      _isSwipeNavigating = true;
      await _handleDateChange(currentDay.add(Duration(days: dayDelta)));
      _isSwipeNavigating = false;
    } finally {
      _isSwipeNavigating = false;
      _resetSwipeTracking();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRouteVisible) {
      _syncService.incrementalSync();
      _syncService.pushLocalChanges();
      _refreshUserInfo();
    }
  }

  @override
  void didPush() {
    _isRouteVisible = true;
    unawaited(_resumeSyncLoopIfNeeded());
  }

  @override
  void didPopNext() {
    _isRouteVisible = true;
    unawaited(_resumeSyncLoopIfNeeded());
  }

  @override
  void didPushNext() {
    _isRouteVisible = false;
    unawaited(_pauseSyncLoopIfNeeded());
  }

  @override
  void didPop() {
    _isRouteVisible = false;
    unawaited(_pauseSyncLoopIfNeeded());
  }

  Future<void> _loadCalendarId() async {
    try {
      final calendarId = await GoogleCalendarService.instance.storage
          .getDefaultCalendarId();
      _selectedCalendarId = calendarId ?? 'primary';
    } catch (e) {
      _selectedCalendarId = 'primary';
    }
  }

  Future<void> _refreshUserInfo() async {
    try {
      final accountDetails = await GoogleCalendarService.instance
          .getAccountDetails();
      if (!mounted) return;
      final newEmail = accountDetails['email'];
      final newDisplayName = accountDetails['displayName'];
      final newPhotoUrl = accountDetails['photoUrl'];
      if (_userEmail != newEmail ||
          _userDisplayName != newDisplayName ||
          _userPhotoUrl != newPhotoUrl) {
        setState(() {
          _userEmail = newEmail;
          _userDisplayName = newDisplayName;
          _userPhotoUrl = newPhotoUrl;
        });
      }
    } catch (_) {
      // Keep screen usable even if account details are unavailable.
    }
  }

  Future<void> _loadCalendarColors() async {
    try {
      final cached = await GoogleCalendarService.instance.getCachedCalendars();
      if (cached.isNotEmpty) {
        final cachedColors = <String, int>{};
        for (final cal in cached) {
          final calendarId = cal['id'] as String?;
          final calendarColor = cal['color'] as int?;
          if (calendarId != null && calendarColor != null) {
            cachedColors[calendarId] = calendarColor;
          }
        }
        if (mounted) {
          setState(() {
            _calendarColors = cachedColors;
          });
        } else {
          _calendarColors = cachedColors;
        }
      }

      final signedIn = await GoogleCalendarService.instance.isSignedIn();
      if (!signedIn) return;

      final calendars = await GoogleCalendarService.instance.getUserCalendars();
      final remoteColors = <String, int>{};

      for (final cal in calendars) {
        final calendarId = cal['id'] as String;
        final calendarColor = cal['color'] as int;
        remoteColors[calendarId] = calendarColor;
        debugPrint(
          'Loaded color for calendar ${cal['name']}: ${calendarColor.toRadixString(16)}',
        );
      }
      if (remoteColors.isNotEmpty) {
        if (mounted) {
          setState(() {
            _calendarColors = remoteColors;
          });
        } else {
          _calendarColors = remoteColors;
        }
      }
    } catch (e) {
      debugPrint('Error loading calendar colors: $e');
    }
  }

  void _updateEventLists() {
    final allEvents = _eventsMap.values.toList();
    _allDayEvents = allEvents.where(_isAllDayForCurrentDay).toList()
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
    _timedEvents = allEvents.where((e) => !_isAllDayForCurrentDay(e)).toList()
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
  }

  bool _isAllDayForCurrentDay(CalendarEvent event) {
    if (event.allDay) return true;

    final visibleSegment = _eventVisibleSegmentForCurrentDay(event);
    if (visibleSegment == null) return false;

    final dayStart = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));

    final coversEntireDay =
        visibleSegment.start == dayStart && visibleSegment.end == dayEnd;
    if (coversEntireDay) return true;

    // Treat near-24h spans in the current day as all-day for display.
    const fullDayThreshold = Duration(hours: 23, minutes: 59);
    final visibleDuration = visibleSegment.end.difference(visibleSegment.start);
    return visibleDuration >= fullDayThreshold;
  }

  String _timeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good Morning';
    if (hour >= 12 && hour < 21) return 'Good Evening';
    return 'Good Night';
  }

  IconData _timeBasedGreetingIcon() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return Icons.sunny;
    if (hour >= 12 && hour < 21) return Icons.sunny_snowing;
    return Icons.nightlight;
  }

  String _firstNameForGreeting() {
    final profileName = _userDisplayName?.trim();
    if (profileName != null && profileName.isNotEmpty) {
      final firstToken = profileName
          .split(RegExp(r'\s+'))
          .firstWhere(
            (part) => part.trim().isNotEmpty,
            orElse: () => profileName,
          )
          .trim();
      if (firstToken.isNotEmpty) {
        final lower = firstToken.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      }
    }

    final email = _userEmail;
    if (email == null || email.trim().isEmpty) return 'there';
    final localPart = email.split('@').first;
    if (localPart.isEmpty) return 'there';
    final tokens = localPart
        .split(RegExp(r'[._\-]+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    const genericPrefixes = <String>{
      'hello',
      'hi',
      'hey',
      'mail',
      'email',
      'contact',
      'info',
      'support',
      'admin',
      'team',
      'official',
      'noreply',
      'no-reply',
    };

    String candidate = '';
    for (final token in tokens) {
      final normalized = token.trim().toLowerCase();
      if (normalized.isEmpty || genericPrefixes.contains(normalized)) {
        continue;
      }
      candidate = token.trim();
      break;
    }

    if (candidate.isEmpty) return 'there';

    // Avoid showing low-confidence guesses from long concatenated email text.
    if (RegExp(r'\d').hasMatch(candidate)) return 'there';
    if (candidate.length > 12 && !RegExp(r'[A-Z]').hasMatch(candidate)) {
      return 'there';
    }

    final lower = candidate.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }

  Future<int?> _showYearPicker({required int initialYear}) async {
    const startYear = 1970;
    const endYear = 2100;
    const itemExtent = 44.0;
    const dialogListHeight = 360.0;
    final years = List<int>.generate(
      endYear - startYear + 1,
      (index) => endYear - index,
    );
    final initialIndex = years.indexOf(initialYear);
    final safeIndex = initialIndex < 0 ? 0 : initialIndex;
    final maxOffset = (years.length * itemExtent) - dialogListHeight;
    final rawOffset = (safeIndex * itemExtent) - (dialogListHeight / 2);
    final initialOffset = rawOffset.clamp(0.0, maxOffset < 0 ? 0.0 : maxOffset);
    final scrollController = ScrollController(
      initialScrollOffset: initialOffset,
    );

    return showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Select year'),
          content: SizedBox(
            width: 220,
            height: dialogListHeight,
            child: ListView.builder(
              controller: scrollController,
              itemExtent: itemExtent,
              itemCount: years.length,
              itemBuilder: (context, index) {
                final year = years[index];
                final isSelected = year == initialYear;
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: AppColors.selectedColor,
                  title: Text(
                    '$year',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.onBackground,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  onTap: () => Navigator.of(dialogContext).pop(year),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCalendarNavButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return AppPressFeedback(
      child: SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            foregroundColor: AppColors.onBackground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
        ),
      ),
    );
  }

  DateTime _dateWithYearPreservingMonthDay(DateTime source, int targetYear) {
    final maxDayInTargetMonth = DateTime(targetYear, source.month + 1, 0).day;
    final clampedDay = source.day > maxDayInTargetMonth
        ? maxDayInTargetMonth
        : source.day;
    return DateTime(targetYear, source.month, clampedDay);
  }

  Future<void> _showMobileCalendarPicker() async {
    var visibleMonth = DateTime(_currentDate.year, _currentDate.month);
    var selectedDay = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final monthDays = _miniCalendarDays(visibleMonth);
            final monthLabel = DateFormat('MMMM').format(visibleMonth);
            const weekLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
            final today = DateTime.now();
            final normalizedToday = DateTime(
              today.year,
              today.month,
              today.day,
            );

            return Dialog(
              backgroundColor: AppColors.surface,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: SizedBox(
                width: 360,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _buildCalendarNavButton(
                            icon: Icons.chevron_left_rounded,
                            onPressed: () {
                              setStateDialog(() {
                                visibleMonth = DateTime(
                                  visibleMonth.year,
                                  visibleMonth.month - 1,
                                );
                              });
                            },
                          ),
                          Expanded(
                            child: AppPressFeedback(
                              child: TextButton(
                                onPressed: () async {
                                  final selectedYear = await _showYearPicker(
                                    initialYear: visibleMonth.year,
                                  );
                                  if (selectedYear == null ||
                                      !context.mounted) {
                                    return;
                                  }
                                  final targetDate =
                                      _dateWithYearPreservingMonthDay(
                                        selectedDay,
                                        selectedYear,
                                      );
                                  Navigator.of(dialogContext).pop(targetDate);
                                },
                                style:
                                    TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 40),
                                      splashFactory: NoSplash.splashFactory,
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      surfaceTintColor: Colors.transparent,
                                    ).copyWith(
                                      overlayColor:
                                          WidgetStateProperty.resolveWith<
                                            Color?
                                          >((states) => Colors.transparent),
                                    ),
                                child: Text(
                                  '$monthLabel ${visibleMonth.year}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.onBackground,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _buildCalendarNavButton(
                            icon: Icons.chevron_right_rounded,
                            onPressed: () {
                              setStateDialog(() {
                                visibleMonth = DateTime(
                                  visibleMonth.year,
                                  visibleMonth.month + 1,
                                );
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: weekLabels
                            .map(
                              (label) => Expanded(
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 10),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: monthDays.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              childAspectRatio: 1.15,
                            ),
                        itemBuilder: (context, index) {
                          final day = monthDays[index];
                          final normalizedDay = DateTime(
                            day.year,
                            day.month,
                            day.day,
                          );
                          final isCurrentMonth =
                              day.month == visibleMonth.month &&
                              day.year == visibleMonth.year;
                          final isSelected = normalizedDay == selectedDay;
                          final isToday = normalizedDay == normalizedToday;

                          return AppPressFeedback(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => Navigator.of(dialogContext).pop(day),
                              child: Center(
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(18),
                                    border: isToday && !isSelected
                                        ? Border.all(
                                            color: AppColors.primary,
                                            width: 1.2,
                                          )
                                        : null,
                                  ),
                                  child: Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? AppColors.onPrimary
                                          : isCurrentMonth
                                          ? AppColors.onBackground
                                          : AppColors.timeTextColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (picked == null) return;
    final selectedDate = DateTime(picked.year, picked.month, picked.day);
    _miniCalendarVisibleMonth = DateTime(selectedDate.year, selectedDate.month);
    await _handleDateChange(selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.surface,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: KeyboardListener(
        focusNode: _keyboardListenerFocusNode,
        onKeyEvent: _keyboardShortcutsEnabled ? _handleKeyboardShortcut : null,
        child: Stack(
          children: [
            Scaffold(
              key: _scaffoldKey,
              backgroundColor: AppColors.background,
              floatingActionButton: SizedBox(
                width: 55,
                height: 55,
                child: FloatingActionButton(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  onPressed: () {
                    Navigator.pushNamed(context, CreateEventScreen.routeName);
                  },
                  child: const Icon(
                    Icons.add_rounded,
                    color: AppColors.onPrimary,
                    size: 30,
                  ),
                ),
              ),
              body: SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(),
                    Expanded(
                      child: AppFadeSlideIn(
                        child: Stack(
                          children: [
                            RepaintBoundary(child: _buildCalendarContent()),
                            // Context menu overlay
                            if (_contextMenuPosition != null &&
                                _contextMenuEvent != null)
                              _buildContextMenuOverlay(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _isLoading ? 1 : 0,
                  duration: _isLoading
                      ? Duration.zero
                      : const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: const ModernSplashScreen(
                    embedded: true,
                    animateIntro: false,
                    showLoading: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final isMobile = _isMobileLayout(context);
    final dateString = DateFormat('d MMM y').format(_currentDate);
    Future<void> handlePickDate() async {
      await _showMobileCalendarPicker();
    }

    Future<void> handleSync() async {
      await _syncService.incrementalSync();
      await _syncService.pushLocalChanges();
    }

    return Container(
      height: isMobile ? 60 : 64,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderColor)),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: isMobile
                ? AppPressFeedback(
                    child: IconButton(
                      icon: RotationTransition(
                        turns: _syncRotationController,
                        child: const Icon(
                          Icons.sync_rounded,
                          color: AppColors.onBackground,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: handleSync,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _timeBasedGreetingIcon(),
                          size: 20,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_timeBasedGreeting()}, ${_firstNameForGreeting()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Align(
            alignment: Alignment.center,
            child: isMobile
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        child: AppPressFeedback(
                          child: TextButton(
                            onPressed: handlePickDate,
                            style:
                                TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 40,
                                    vertical: 17,
                                  ),
                                  minimumSize: const Size(0, 36),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ).copyWith(
                                  overlayColor:
                                      MaterialStateProperty.resolveWith<Color?>(
                                        (states) {
                                          if (states.contains(
                                            MaterialState.hovered,
                                          )) {
                                            return Colors.transparent;
                                          }
                                          return null;
                                        },
                                      ),
                                ),
                            child: Text(
                              dateString,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: AppColors.onBackground,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppPressFeedback(
                  child: IconButton(
                    icon: _userPhotoUrl != null
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(
                              _userPhotoUrl!,
                              headers: const {'Cache-Control': 'max-age=3600'},
                            ),
                            radius: 16,
                          )
                        : const Icon(Icons.account_circle, size: 32),
                    visualDensity: isMobile ? VisualDensity.compact : null,
                    tooltip: '',
                    onPressed: () {
                      Navigator.pushNamed(context, SettingsScreen.routeName);
                    },
                  ),
                ),
                if (!isMobile) const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarContent() {
    return _buildDayView();
  }

  Widget _buildDayView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktopLike = !_isMobileLayout(context);
        final timelinePhysics =
            (_isDraggingToCreate ||
                _isDraggingEvent ||
                _resizingEventId != null)
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics();
        final allDayHorizontalPhysics = isDesktopLike
            ? const ClampingScrollPhysics()
            : const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              );
        final timeColumnWidth = _timeColumnWidthFor(context);
        // Calculate fixed height for scrollable grid (24 hours * 60 pixels per hour)
        const hourHeight = 60.0;
        const totalHeight = 24 * hourHeight;
        final allDayRowHeight = _allDayEvents.isNotEmpty ? 40.0 : 0.0;
        final noScrollbarBehavior = ScrollConfiguration.of(
          context,
        ).copyWith(scrollbars: false);

        final timelineContent = Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handleSwipePointerDown,
          onPointerUp: (event) {
            _handleSwipePointerUp(event);
            _handleGlobalPointerUp(event);
          },
          onPointerCancel: (_) {
            _resetSwipeTracking();
            _handleGlobalPointerCancel();
          },
          child: Column(
            children: [
              // All-day events row (Google Calendar style)
              if (_allDayEvents.isNotEmpty)
                Container(
                  height: allDayRowHeight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border(
                      bottom: BorderSide(color: AppColors.dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: timeColumnWidth,
                        child: Container(
                          padding: const EdgeInsets.only(right: 8),
                          alignment: Alignment.centerRight,
                          child: Text(
                            'All day',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.timeTextColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: noScrollbarBehavior,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: allDayHorizontalPhysics,
                            child: Row(
                              children: _allDayEvents.map((event) {
                                return Container(
                                  margin: const EdgeInsets.only(right: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Builder(
                                    builder: (context) {
                                      final now = DateTime.now();
                                      final isPastEvent =
                                          event.endDateTime.isBefore(now) ||
                                          event.endDateTime.isAtSameMomentAs(
                                            now,
                                          );
                                      return Container(
                                        child: Opacity(
                                          opacity: isPastEvent
                                              ? _pastEventOpacity
                                              : 1,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: _eventBlockGradient(
                                                event.color,
                                              ),
                                              border: isPastEvent
                                                  ? null
                                                  : Border(
                                                      left: BorderSide(
                                                        color:
                                                            _eventBlockBorderColor(
                                                              event.color,
                                                            ),
                                                        width: 3,
                                                      ),
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                            child: GestureDetector(
                                              onTap: () {
                                                _keyboardActiveEventId =
                                                    event.id;
                                              },
                                              onDoubleTap: () {
                                                _keyboardActiveEventId =
                                                    event.id;
                                                _showEditEventModal(event);
                                              },
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                child: Text(
                                                  event.title,
                                                  style: const TextStyle(
                                                    color: _eventBlockTextColor,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Time grid
              Expanded(
                child: ScrollConfiguration(
                  behavior: noScrollbarBehavior,
                  child: SingleChildScrollView(
                    controller: _dayGridScrollController,
                    physics: timelinePhysics,
                    child: SizedBox(
                      height: totalHeight,
                      child: Row(
                        children: [
                          SizedBox(
                            width: timeColumnWidth,
                            child: _buildTimeColumn(),
                          ),
                          Expanded(
                            child: _buildDayGrid(
                              BoxConstraints(
                                maxWidth:
                                    constraints.maxWidth - timeColumnWidth,
                                maxHeight: totalHeight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        final desktopMultiDay = isDesktopLike && _selectedRangeDayCount > 1;
        final mainTimeline = desktopMultiDay
            ? _buildMultiDayTimeline(
                timeColumnWidth: timeColumnWidth,
                noScrollbarBehavior: noScrollbarBehavior,
              )
            : timelineContent;

        if (!isDesktopLike) {
          return mainTimeline;
        }

        return Row(
          children: [
            _buildMiniCalendarSidebar(),
            Expanded(child: mainTimeline),
          ],
        );
      },
    );
  }

  Widget _buildMultiDayTimeline({
    required double timeColumnWidth,
    required ScrollBehavior noScrollbarBehavior,
  }) {
    return LayoutBuilder(
      builder: (context, panelConstraints) {
        const hourHeight = 60.0;
        const totalHeight = 24 * hourHeight;
        final days = _selectedRangeDays;
        final gridWidth = (panelConstraints.maxWidth - timeColumnWidth).clamp(
          0.0,
          double.infinity,
        );

        return Column(
          children: [
            _buildMultiDayHeaderRow(
              days,
              timeColumnWidth,
              gridWidth: gridWidth,
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: noScrollbarBehavior,
                child: SingleChildScrollView(
                  controller: _dayGridScrollController,
                  child: SizedBox(
                    height: totalHeight,
                    child: Row(
                      children: [
                        SizedBox(
                          width: timeColumnWidth,
                          child: _buildTimeColumn(),
                        ),
                        SizedBox(
                          width: gridWidth,
                          child: _buildMultiDayGrid(
                            BoxConstraints(
                              maxWidth: gridWidth,
                              maxHeight: totalHeight,
                            ),
                            days,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMultiDayHeaderRow(
    List<DateTime> days,
    double timeColumnWidth, {
    required double gridWidth,
  }) {
    final dayWidth = days.isEmpty ? 0.0 : gridWidth / days.length;
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.dividerColor)),
      ),
      child: Row(
        children: [
          SizedBox(width: timeColumnWidth),
          SizedBox(
            width: gridWidth,
            child: Row(
              children: days.map((day) {
                final label = DateFormat('EEE').format(day).toUpperCase();
                final dayNumber = DateFormat('d').format(day);
                final now = DateTime.now();
                final isToday =
                    day.year == now.year &&
                    day.month == now.month &&
                    day.day == now.day;
                return SizedBox(
                  width: dayWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: AppColors.dividerColor),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: AppColors.timeTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dayNumber,
                          style: TextStyle(
                            color: isToday
                                ? AppColors.primary
                                : AppColors.onBackground,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiDayGrid(BoxConstraints constraints, List<DateTime> days) {
    const hourHeight = 60.0;
    final dayWidth = constraints.maxWidth / days.length;
    return Stack(
      children: [
        ...List.generate(24, (index) {
          return Positioned(
            top: hourHeight * index,
            left: 0,
            right: 0,
            child: Container(height: 1, color: AppColors.dividerColor),
          );
        }),
        ...List.generate(days.length - 1, (index) {
          return Positioned(
            left: dayWidth * (index + 1),
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: AppColors.dividerColor),
          );
        }),
        ..._buildMultiDayEventWidgets(days, dayWidth),
      ],
    );
  }

  List<Widget> _buildMultiDayEventWidgets(
    List<DateTime> days,
    double dayWidth,
  ) {
    const hourHeight = 60.0;
    final widgets = <Widget>[];
    for (final event in _timedEvents) {
      for (var dayIndex = 0; dayIndex < days.length; dayIndex++) {
        final segment = _eventVisibleSegmentForDay(event, days[dayIndex]);
        if (segment == null) continue;

        final dayStart = DateTime(
          days[dayIndex].year,
          days[dayIndex].month,
          days[dayIndex].day,
        );
        final startMinutes = segment.start.difference(dayStart).inMinutes;
        final endMinutes = segment.end.difference(dayStart).inMinutes;
        final top = (startMinutes / 60) * hourHeight;
        final height = (((endMinutes - startMinutes) / 60) * hourHeight).clamp(
          1.0,
          24 * hourHeight,
        );

        widgets.add(
          Positioned(
            left: dayIndex * dayWidth + 2,
            top: top,
            width: dayWidth - 4,
            height: height,
            child: Opacity(
              opacity: _isPastEvent(event) ? _pastEventOpacity : 1,
              child: _buildReadOnlyEventCard(event),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  bool _isPastEvent(CalendarEvent event) {
    final now = DateTime.now();
    return event.endDateTime.isBefore(now) ||
        event.endDateTime.isAtSameMomentAs(now);
  }

  Widget _buildReadOnlyEventCard(CalendarEvent event) {
    final isPastEvent = _isPastEvent(event);
    return Container(
      decoration: BoxDecoration(
        gradient: _eventBlockGradient(event.color),
        border: isPastEvent
            ? null
            : Border(
                left: BorderSide(
                  color: _eventBlockBorderColor(event.color),
                  width: 3,
                ),
              ),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.title,
            style: const TextStyle(
              color: _eventBlockTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${DateFormat('h:mm').format(event.startDateTime)} - ${DateFormat('h:mm').format(event.endDateTime)}',
            style: const TextStyle(
              color: _eventBlockTextColor,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  DateTimeRange? _eventVisibleSegmentForDay(CalendarEvent event, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final visibleStart = event.startDateTime.isBefore(dayStart)
        ? dayStart
        : event.startDateTime;
    final visibleEnd = event.endDateTime.isAfter(dayEnd)
        ? dayEnd
        : event.endDateTime;
    if (!visibleEnd.isAfter(visibleStart)) return null;
    return DateTimeRange(start: visibleStart, end: visibleEnd);
  }

  Widget _buildMiniCalendarSidebar() {
    const weekLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final monthLabel = DateFormat('MMMM').format(_miniCalendarVisibleMonth);
    final monthDays = _miniCalendarDays(_miniCalendarVisibleMonth);
    const sidebarTitleStyle = TextStyle(
      color: AppColors.onBackground,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    );

    return Container(
      width: 322,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(right: BorderSide(color: AppColors.dividerColor)),
      ),
      child: LayoutBuilder(
        builder: (context, sidebarConstraints) {
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: sidebarConstraints.maxHeight - 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          _buildCalendarNavButton(
                            icon: Icons.chevron_left,
                            onPressed: () {
                              setState(() {
                                _miniCalendarVisibleMonth = DateTime(
                                  _miniCalendarVisibleMonth.year,
                                  _miniCalendarVisibleMonth.month - 1,
                                );
                              });
                            },
                          ),
                          Expanded(
                            child: AppPressFeedback(
                              child: TextButton(
                                onPressed: () async {
                                  final selectedYear = await _showYearPicker(
                                    initialYear: _miniCalendarVisibleMonth.year,
                                  );
                                  if (selectedYear == null || !mounted) return;
                                  final targetDate =
                                      _dateWithYearPreservingMonthDay(
                                        _currentDate,
                                        selectedYear,
                                      );
                                  setState(() {
                                    _miniCalendarVisibleMonth = DateTime(
                                      targetDate.year,
                                      targetDate.month,
                                    );
                                  });
                                  await _handleDateChange(targetDate);
                                },
                                style:
                                    TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 32),
                                      splashFactory: NoSplash.splashFactory,
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      surfaceTintColor: Colors.transparent,
                                    ).copyWith(
                                      overlayColor:
                                          WidgetStateProperty.resolveWith<
                                            Color?
                                          >((states) => Colors.transparent),
                                    ),
                                child: Text(
                                  '$monthLabel ${_miniCalendarVisibleMonth.year}',
                                  textAlign: TextAlign.center,
                                  style: sidebarTitleStyle,
                                ),
                              ),
                            ),
                          ),
                          _buildCalendarNavButton(
                            icon: Icons.chevron_right,
                            onPressed: () {
                              setState(() {
                                _miniCalendarVisibleMonth = DateTime(
                                  _miniCalendarVisibleMonth.year,
                                  _miniCalendarVisibleMonth.month + 1,
                                );
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: weekLabels.map((label) {
                        return Expanded(
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 9),
                    Listener(
                      key: _miniCalendarGridKey,
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) {
                        _handleMiniCalendarPointerDown(event, monthDays);
                      },
                      onPointerMove: (event) {
                        _handleMiniCalendarPointerMove(event, monthDays);
                      },
                      onPointerUp: (event) {
                        _handleMiniCalendarPointerUp(event);
                      },
                      onPointerCancel: (_) {
                        _handleMiniCalendarPointerCancel();
                      },
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: monthDays.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              childAspectRatio: 1.14,
                            ),
                        itemBuilder: (context, index) {
                          final day = monthDays[index];
                          final isInVisibleMonth =
                              day.month == _miniCalendarVisibleMonth.month &&
                              day.year == _miniCalendarVisibleMonth.year;

                          final rangeStart =
                              _miniCalendarPreviewStartDate ??
                              _selectedRangeStartDate;
                          final rangeEnd =
                              _miniCalendarPreviewEndDate ??
                              _selectedRangeEndDate;
                          final normalizedDay = _normalizeDate(day);
                          final isInRange =
                              !normalizedDay.isBefore(rangeStart) &&
                              !normalizedDay.isAfter(rangeEnd);
                          final isRangeEdge =
                              normalizedDay == rangeStart ||
                              normalizedDay == rangeEnd;

                          final now = DateTime.now();
                          final isToday =
                              day.year == now.year &&
                              day.month == now.month &&
                              day.day == now.day;

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2.4,
                              vertical: 3.2,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isInRange && !isRangeEdge
                                    ? AppColors.selectedColor
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () {
                                    _handleDateChange(day);
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isRangeEdge
                                          ? AppColors.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(999),
                                      border: isToday && !isRangeEdge
                                          ? Border.all(
                                              color: AppColors.primary,
                                              width: 1,
                                            )
                                          : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${day.day}',
                                      style: TextStyle(
                                        color: isRangeEdge
                                            ? AppColors.onPrimary
                                            : isInVisibleMonth
                                            ? AppColors.onBackground
                                            : AppColors.timeTextColor,
                                        fontSize: 16,
                                        fontWeight: isRangeEdge
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 30),
                    _buildSidebarQuickActions(),
                    const SizedBox(height: 30),
                    _buildTodayOverviewSection(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidebarQuickActions() {
    final isSyncing = _isSyncing;

    final buttons =
        <
          ({
            IconData icon,
            String label,
            Future<void> Function() onTap,
            bool syncButton,
          })
        >[
          (
            icon: Icons.add,
            label: 'Create',
            onTap: _handleSidebarAddEvent,
            syncButton: false,
          ),
          (
            icon: Icons.today_rounded,
            label: 'Today',
            onTap: _handleSidebarJumpToToday,
            syncButton: false,
          ),
          (
            icon: Icons.search,
            label: 'Search',
            onTap: _handleSidebarSearchEvent,
            syncButton: false,
          ),
          (
            icon: Icons.sync_rounded,
            label: 'Sync',
            onTap: _handleSidebarSyncNow,
            syncButton: true,
          ),
        ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 14),
            child: Text(
              'Quick Actions',
              style: TextStyle(
                color: AppColors.onBackground,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: buttons.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.6,
            ),
            itemBuilder: (context, index) {
              final item = buttons[index];
              final labelText = item.syncButton && isSyncing
                  ? 'Syncing'
                  : item.label;
              return InkWell(
                onTap: () {
                  unawaited(item.onTap());
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(26),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      item.syncButton && isSyncing
                          ? RotationTransition(
                              turns: _syncRotationController,
                              child: Icon(
                                item.icon,
                                size: 23,
                                color: AppColors.primary,
                              ),
                            )
                          : Icon(item.icon, size: 23, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                          child: Text(
                            labelText,
                            key: ValueKey(labelText),
                            style: const TextStyle(
                              color: AppColors.onBackground,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleSidebarAddEvent() async {
    await _showCreateEventModal();
  }

  Future<void> _handleSidebarJumpToToday() async {
    await _handleDateChange(DateTime.now());
  }

  Future<void> _handleSidebarSyncNow() async {
    await _syncService.incrementalSync();
    await _syncService.pushLocalChanges();
  }

  Future<void> _handleSidebarSearchEvent() async {
    final allEvents = _eventsMap.values.toList()
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
    if (allEvents.isEmpty) {
      if (!mounted) return;
      _showCompactSnackBar('No events to search');
      return;
    }

    final selected = await showDialog<CalendarEvent>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        var query = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final filtered = allEvents.where((event) {
              if (query.isEmpty) return true;
              final q = query.toLowerCase();
              return event.title.toLowerCase().contains(q) ||
                  event.description.toLowerCase().contains(q) ||
                  event.location.toLowerCase().contains(q);
            }).toList();

            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: const Text(
                'Search Events',
                style: TextStyle(color: AppColors.onBackground),
              ),
              content: SizedBox(
                width: 440,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: controller,
                      style: const TextStyle(color: AppColors.onBackground),
                      decoration: InputDecoration(
                        hintText: 'Type title, location, description',
                        hintStyle: TextStyle(color: AppColors.timeTextColor),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.borderColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.borderColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: AppColors.timeTextColor,
                        ),
                      ),
                      onChanged: (value) {
                        setStateDialog(() {
                          query = value.trim();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No matching events',
                                style: TextStyle(
                                  color: AppColors.timeTextColor,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final event = filtered[index];
                                return ListTile(
                                  dense: true,
                                  onTap: () {
                                    Navigator.of(dialogContext).pop(event);
                                  },
                                  title: Text(
                                    event.title,
                                    style: const TextStyle(
                                      color: AppColors.onBackground,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${DateFormat('d MMM, h:mm a').format(event.startDateTime)} - ${DateFormat('h:mm a').format(event.endDateTime)}',
                                    style: TextStyle(
                                      color: AppColors.timeTextColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected == null) return;
    _keyboardActiveEventId = selected.id;
    await _handleDateChange(selected.startDateTime);
    _scrollToTime(selected.startDateTime);
  }

  void _scrollToTime(DateTime dateTime) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dayGridScrollController.hasClients) return;
      const hourHeight = 60.0;
      final pos = ((dateTime.hour * 60 + dateTime.minute) / 60) * hourHeight;
      final viewport = _dayGridScrollController.position.viewportDimension;
      final target = (pos - (viewport * 0.25)).clamp(
        0.0,
        _dayGridScrollController.position.maxScrollExtent,
      );
      _dayGridScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleMiniCalendarPointerDown(
    PointerDownEvent event,
    List<DateTime> monthDays,
  ) {
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    final day = _miniCalendarDateFromPointer(event.position, monthDays);
    if (day == null) return;
    final normalized = _normalizeDate(day);
    setState(() {
      _isMiniCalendarRangeSelecting = true;
      _miniCalendarDragAnchorDate = normalized;
      _miniCalendarPreviewStartDate = normalized;
      _miniCalendarPreviewEndDate = normalized;
    });
  }

  void _handleMiniCalendarPointerMove(
    PointerMoveEvent event,
    List<DateTime> monthDays,
  ) {
    if (!_isMiniCalendarRangeSelecting) return;
    final anchor = _miniCalendarDragAnchorDate;
    if (anchor == null) return;
    final day = _miniCalendarDateFromPointer(event.position, monthDays);
    if (day == null) return;
    final normalized = _normalizeDate(day);
    final start = anchor.isBefore(normalized) ? anchor : normalized;
    final end = anchor.isBefore(normalized) ? normalized : anchor;
    if (_miniCalendarPreviewStartDate == start &&
        _miniCalendarPreviewEndDate == end) {
      return;
    }
    setState(() {
      _miniCalendarPreviewStartDate = start;
      _miniCalendarPreviewEndDate = end;
    });
  }

  void _handleMiniCalendarPointerUp(PointerUpEvent event) {
    if (!_isMiniCalendarRangeSelecting) return;
    final previewStart = _miniCalendarPreviewStartDate;
    final previewEnd = _miniCalendarPreviewEndDate;
    setState(() {
      _isMiniCalendarRangeSelecting = false;
      _miniCalendarDragAnchorDate = null;
      _miniCalendarPreviewStartDate = null;
      _miniCalendarPreviewEndDate = null;
    });
    if (previewStart == null || previewEnd == null) return;
    unawaited(_handleDateRangeChange(previewStart, previewEnd));
  }

  void _handleMiniCalendarPointerCancel() {
    if (!_isMiniCalendarRangeSelecting) return;
    setState(() {
      _isMiniCalendarRangeSelecting = false;
      _miniCalendarDragAnchorDate = null;
      _miniCalendarPreviewStartDate = null;
      _miniCalendarPreviewEndDate = null;
    });
  }

  DateTime? _miniCalendarDateFromPointer(
    Offset globalPosition,
    List<DateTime> monthDays,
  ) {
    final context = _miniCalendarGridKey.currentContext;
    if (context == null) return null;
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return null;

    final local = renderBox.globalToLocal(globalPosition);
    final size = renderBox.size;
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > size.width ||
        local.dy > size.height) {
      return null;
    }

    final cellWidth = size.width / 7;
    final cellHeight = cellWidth / 1.16;
    final maxGridHeight = cellHeight * 6;
    if (local.dy > maxGridHeight) return null;

    final column = (local.dx / cellWidth).floor();
    final row = (local.dy / cellHeight).floor();
    final index = row * 7 + column;
    if (index < 0 || index >= monthDays.length) return null;
    return monthDays[index];
  }

  List<DateTime> _miniCalendarDays(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final leadingSlots = firstDay.weekday - DateTime.monday;
    final startDate = firstDay.subtract(Duration(days: leadingSlots));
    return List<DateTime>.generate(42, (index) {
      return DateTime(startDate.year, startDate.month, startDate.day + index);
    });
  }

  Widget _buildTimeColumn() {
    final hours = List.generate(24, (index) => index);
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.dividerColor)),
      ),
      child: Column(
        children: hours.map((hour) {
          return Expanded(
            child: Container(
              padding: const EdgeInsets.only(right: 8),
              alignment: Alignment.centerRight,
              child: Text(
                hour == 0
                    ? '12 AM'
                    : hour < 12
                    ? '$hour AM'
                    : hour == 12
                    ? '12 PM'
                    : '${hour - 12} PM',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.timeTextColor,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDayGrid(BoxConstraints constraints) {
    const hourHeight = 60.0;
    _dayGridWidth = constraints.maxWidth;
    return Stack(
      children: [
        // Hour lines - Google Calendar style (subtle lines)
        ...List.generate(24, (index) {
          return Positioned(
            top: hourHeight * index,
            left: 0,
            right: 0,
            child: Container(height: 1, color: AppColors.dividerColor),
          );
        }),
        // Clickable grid for creating events (under events)
        IgnorePointer(
          ignoring:
              _isPointerDownOnEvent ||
              _isDraggingEvent ||
              _eventActionsPopoverEventId != null,
          child: _buildClickableGrid(constraints),
        ),
        if ((_isDraggingToCreate &&
                _gridDragStartTime != null &&
                _gridDragEndTime != null) ||
            (_pendingCreateStartTime != null && _pendingCreateEndTime != null))
          _buildDragCreateSelection(),
        // Events (top-most)
        ..._buildEventWidgets(constraints),
        // Keep current-time indicator above event blocks.
        _buildCurrentTimeIndicator(constraints),
      ],
    );
  }

  Widget _buildCurrentTimeIndicator(BoxConstraints constraints) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentDate = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );

    // Only show if viewing today
    if (!today.isAtSameMomentAs(currentDate)) {
      return const SizedBox.shrink();
    }

    const hourHeight = 60.0;
    final hour = now.hour;
    final minute = now.minute;
    final position = ((hour * 60 + minute) / 60) * hourHeight;

    return Positioned(
      top: position,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(child: Container(height: 2, color: AppColors.error)),
        ],
      ),
    );
  }

  LinearGradient _eventBlockGradient(Color baseColor) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [baseColor, _darkenColor(baseColor, 0.16)],
    );
  }

  Color _eventBlockBorderColor(Color baseColor) {
    return _darkenColor(baseColor, 0.24);
  }

  Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness - amount).clamp(0.0, 1.0).toDouble();
    return hsl.withLightness(lightness).toColor();
  }

  List<Widget> _buildEventWidgets(BoxConstraints constraints) {
    final widgets = <Widget>[];

    for (final event in _timedEvents) {
      final isDraggingOriginal =
          _isDraggingEvent && _draggedEventId == event.id;
      widgets.add(
        _buildEventWidget(
          event,
          constraints,
          constraints.maxWidth,
          0,
          isDraggingOriginal: isDraggingOriginal,
        ),
      );
    }

    if (_dragPreviewEvent != null && _draggedEventId == _dragPreviewEvent!.id) {
      widgets.add(
        _buildEventWidget(
          _dragPreviewEvent!,
          constraints,
          constraints.maxWidth,
          0,
          isPreview: true,
        ),
      );
    }

    return widgets;
  }

  Widget _buildEventWidget(
    CalendarEvent event,
    BoxConstraints constraints,
    double width,
    double leftOffset, {
    bool isPreview = false,
    bool isDraggingOriginal = false,
  }) {
    const hourHeight = 60.0;
    final visibleSegment = _eventVisibleSegmentForCurrentDay(event);
    if (visibleSegment == null) {
      return const SizedBox.shrink();
    }

    final dayStart = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    final startMinutes = visibleSegment.start.difference(dayStart).inMinutes;
    final endMinutes = visibleSegment.end.difference(dayStart).inMinutes;
    final startPosition = (startMinutes / 60) * hourHeight;
    final rawHeight = ((endMinutes - startMinutes) / 60) * hourHeight;
    final visualHeight = rawHeight < 1.0 ? 1.0 : rawHeight;
    final isMobile = _isMobileLayout(context);
    final interactionHeight = isMobile
        ? (visualHeight < _mobileMinEventInteractionHeight
              ? _mobileMinEventInteractionHeight
              : visualHeight)
        : visualHeight;
    final topInsetForVisual = (interactionHeight - visualHeight) / 2;
    final maxTop = (24 * hourHeight) - interactionHeight;
    final interactionTop = (startPosition - topInsetForVisual).clamp(
      0.0,
      maxTop < 0 ? 0.0 : maxTop,
    );
    final visualTopInset = startPosition - interactionTop;

    return Positioned(
      left: leftOffset + 2,
      top: interactionTop,
      width: width - 4,
      height: interactionHeight,
      child: _buildEventCard(
        event,
        cardHeight: interactionHeight,
        visualHeight: visualHeight,
        visualTopInset: visualTopInset,
        isPreview: isPreview,
        isDraggingOriginal: isDraggingOriginal,
      ),
    );
  }

  Widget _buildEventCard(
    CalendarEvent event, {
    required double cardHeight,
    required double visualHeight,
    required double visualTopInset,
    bool isPreview = false,
    bool isDraggingOriginal = false,
  }) {
    final edgeHitHeight = _isMobileLayout(context) ? 24.0 : 14.0;
    final eventDurationMinutes = event.endDateTime
        .difference(event.startDateTime)
        .inMinutes;
    final isShortEvent = eventDurationMinutes < 40;
    final now = DateTime.now();
    final isPastEvent =
        !isPreview &&
        (event.endDateTime.isBefore(now) ||
            event.endDateTime.isAtSameMomentAs(now));
    final effectiveOpacity = isDraggingOriginal
        ? 0.35
        : isPastEvent
        ? _pastEventOpacity
        : 1.0;

    bool? resizeZoneForLocal(Offset localPosition) {
      final visualBottom = visualTopInset + visualHeight;
      final isBottom = localPosition.dy >= (visualBottom - edgeHitHeight);
      // Top-edge resize is intentionally disabled.
      if (isBottom) return false;
      return null;
    }

    final isResizeHoverHere = _resizeHoverEventId == event.id;

    final cardContent = MouseRegion(
      onEnter: (_) {},
      onHover: (pointerEvent) {
        if (isPreview || _resizingEventId != null) return;
        final zone = resizeZoneForLocal(pointerEvent.localPosition);
        if (zone != null) {
          if (_resizeHoverEventId != event.id || _resizeHoverFromTop != zone) {
            setState(() {
              _resizeHoverEventId = event.id;
              _resizeHoverFromTop = zone;
            });
          }
        } else if (_resizeHoverEventId == event.id) {
          setState(() {
            _resizeHoverEventId = null;
            _resizeHoverFromTop = null;
          });
        }
      },
      onExit: (_) {
        if (_resizeHoverEventId == event.id) {
          setState(() {
            _resizeHoverEventId = null;
            _resizeHoverFromTop = null;
          });
        }
      },
      cursor: isResizeHoverHere
          ? SystemMouseCursors.resizeUpDown
          : isDraggingOriginal
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (pointerEvent) {
          if (isPreview || _eventActionsPopoverEventId != null) return;
          if (event.allDay) return;
          _keyboardActiveEventId = event.id;

          final zone = resizeZoneForLocal(pointerEvent.localPosition);
          final isBottomResize = zone == false;

          if (isBottomResize) {
            _isPointerDownOnEvent = true;
            _pendingPointerEventId = null;
            _pointerDownGlobalPosition = null;
            _dragThresholdExceeded = false;
            _dragStartGlobalPosition = null;
            _dragStartTime = null;
            _draggedEventOriginal = null;
            _clearEventTouchPressState();

            if (pointerEvent.kind == PointerDeviceKind.touch) {
              _clearPendingResizeTouch();
              _touchPendingResizeEventId = event.id;
              _resizeTouchDownGlobalPosition = pointerEvent.position;
              _resizeLongPressTimer = Timer(_touchLongPressDuration, () {
                if (!mounted) return;
                if (!_isPointerDownOnEvent) return;
                if (_touchPendingResizeEventId != event.id) return;
                final currentEvent = _eventsMap[event.id];
                if (currentEvent == null) return;
                _startEventResizeInteraction(
                  currentEvent,
                  pointerEvent.position.dy,
                );
                _clearPendingResizeTouch();
                HapticFeedback.selectionClick();
              });
              return;
            }

            _startEventResizeInteraction(event, pointerEvent.position.dy);
            return;
          }

          if (pointerEvent.kind == PointerDeviceKind.mouse &&
              pointerEvent.buttons == kSecondaryMouseButton) {
            _showContextMenu(event, pointerEvent.position);
            return;
          }

          _isPointerDownOnEvent = true;
          _touchPendingEventId = event.id;
          _eventLongPressArmed = false;
          _eventLongPressTimer?.cancel();
          _eventLongPressTimer = Timer(_touchLongPressDuration, () {
            if (!mounted) return;
            if (_touchPendingEventId != event.id) return;
            if (_isDraggingEvent) return;
            _eventLongPressArmed = true;
            if (pointerEvent.kind == PointerDeviceKind.touch) {
              HapticFeedback.selectionClick();
            }
          });

          _pendingPointerEventId = event.id;
          _pointerDownGlobalPosition = pointerEvent.position;
          // Track pointer down for click vs drag threshold.
          _dragThresholdExceeded = false;
          _dragStartTime = event.startDateTime;
          _dragStartGlobalPosition = pointerEvent.position;
          _draggedEventOriginal = event;
        },
        onPointerMove: (pointerEvent) {
          if (isPreview || _eventActionsPopoverEventId != null) return;

          if (_touchPendingResizeEventId == event.id &&
              _resizingEventId != event.id) {
            final start = _resizeTouchDownGlobalPosition;
            if (start != null &&
                (pointerEvent.position - start).distance >
                    _touchCancelDistance) {
              _clearPendingResizeTouch();
              _isPointerDownOnEvent = false;
            }
            return;
          }

          if (_resizingEventId == event.id &&
              _resizingFromTop != null &&
              _resizeStartGlobalY != null &&
              _resizeAnchorStart != null &&
              _resizeAnchorEnd != null) {
            final totalDeltaY = pointerEvent.position.dy - _resizeStartGlobalY!;
            _handleEventResizeByDelta(
              event,
              deltaY: totalDeltaY,
              fromTop: _resizingFromTop!,
            );
            return;
          }

          if (_pendingPointerEventId != event.id) return;
          if (_pointerDownGlobalPosition == null) return;

          final distance =
              (pointerEvent.position - _pointerDownGlobalPosition!).distance;
          if (!_eventLongPressArmed) {
            if (distance > _touchCancelDistance) {
              _cancelPendingEventTouchInteraction(event.id);
            }
            return;
          }

          if (!_isDraggingEvent && distance < _dragActivationDistance) {
            return;
          }

          if (!_isDraggingEvent) {
            _dragThresholdExceeded = true;
            setState(() {
              _draggedEventId = event.id;
              _isDraggingEvent = true;
              _dragPreviewEvent = event;
            });
          }

          if (_draggedEventId == event.id) {
            _updateEventDragPreview(event, pointerEvent.position);
          }
        },
        onPointerUp: (pointerEvent) {
          if (isPreview || _eventActionsPopoverEventId != null) return;

          if (_touchPendingResizeEventId == event.id &&
              _resizingEventId != event.id) {
            _clearPendingResizeTouch();
            _isPointerDownOnEvent = false;
            return;
          }

          if (_resizingEventId == event.id) {
            _isPointerDownOnEvent = false;
            _finalizeEventResize();
            return;
          }

          if (_pendingPointerEventId != event.id) return;

          _isPointerDownOnEvent = false;
          final wasDragging = _isDraggingEvent && _draggedEventId == event.id;
          _pendingPointerEventId = null;
          _pointerDownGlobalPosition = null;
          _eventLongPressTimer?.cancel();

          if (wasDragging) {
            _clearEventTouchPressState();
            _finalizeEventDrag();
            return;
          }

          if (!_dragThresholdExceeded) {
            if (pointerEvent.kind == PointerDeviceKind.touch) {
              if (_isMobileDoubleTap(event.id, pointerEvent.position)) {
                _showEditEventModal(event);
              }
            } else {
              if (_isDesktopDoubleClick(event.id, pointerEvent.position)) {
                _showEditEventModal(event);
              }
            }
          }
          _dragThresholdExceeded = false;
          _dragStartGlobalPosition = null;
          _dragStartTime = null;
          _draggedEventOriginal = null;
          _clearEventTouchPressState();
        },
        onPointerCancel: (_) {
          if (_touchPendingResizeEventId == event.id) {
            _clearPendingResizeTouch();
            _isPointerDownOnEvent = false;
          }

          if (_resizingEventId == event.id) {
            final original = _resizingEventOriginal;
            if (original != null) {
              _eventsMap[original.id] = original;
              _updateEventLists();
            }
            setState(() {
              _resizingEventId = null;
              _resizingFromTop = null;
              _resizingEventOriginal = null;
              _resizeHoverEventId = null;
              _resizeHoverFromTop = null;
              _resizeStartGlobalY = null;
              _resizeAnchorStart = null;
              _resizeAnchorEnd = null;
              _isPointerDownOnEvent = false;
            });
            return;
          }

          if (_pendingPointerEventId == event.id) {
            _isPointerDownOnEvent = false;
            _pendingPointerEventId = null;
            _pointerDownGlobalPosition = null;
            _dragThresholdExceeded = false;
            if (_isDraggingEvent && _draggedEventId == event.id) {
              setState(() {
                _clearDragState();
              });
            } else {
              _dragStartGlobalPosition = null;
              _dragStartTime = null;
              _draggedEventOriginal = null;
            }
          }
          _clearEventTouchPressState();
        },
        child: IgnorePointer(
          ignoring: isPreview,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: visualTopInset,
                height: visualHeight,
                child: Opacity(
                  opacity: effectiveOpacity,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: _eventBlockGradient(event.color),
                      border: isPastEvent
                          ? null
                          : Border(
                              left: BorderSide(
                                color: _eventBlockBorderColor(event.color),
                                width: 3,
                              ),
                            ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: isShortEvent
                        ? RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: event.title,
                                  style: const TextStyle(
                                    fontFamily: 'Montserrat',
                                    color: _eventBlockTextColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      ', ${DateFormat('h:mma').format(event.startDateTime).toLowerCase()} - ${DateFormat('h:mma').format(event.endDateTime).toLowerCase()}',
                                  style: const TextStyle(
                                    fontFamily: 'Montserrat',
                                    color: _eventBlockTextColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                style: const TextStyle(
                                  color: _eventBlockTextColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${DateFormat('h:mm').format(event.startDateTime)} - ${DateFormat('h:mm').format(event.endDateTime)}',
                                style: const TextStyle(
                                  color: _eventBlockTextColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isPreview) {
      return cardContent;
    }

    return Focus(focusNode: _getEventFocusNode(event.id), child: cardContent);
  }

  Widget _buildClickableGrid(BoxConstraints constraints) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _handleGridPointerDownEvent(event);
      },
      onPointerMove: (event) {
        _handleGridPointerMove(event);
      },
      onPointerUp: (event) {
        _handleGridPointerUp(event);
      },
      onPointerCancel: (_) {
        _handleGridPointerCancel();
      },
      child: Container(
        color: Colors.transparent,
        width: constraints.maxWidth,
        height: constraints.maxHeight,
      ),
    );
  }

  DateTime? _gridDragStartTime;
  DateTime? _gridDragEndTime;

  static const double _dragActivationDistance = 6.0;

  bool _isPointerOverEvent(Offset localPosition) {
    final gridWidth = _dayGridWidth;
    if (gridWidth == null) return false;

    // All-day events rendered at top of grid
    if (_allDayEvents.isNotEmpty) {
      final rect = Rect.fromLTWH(2, 0, gridWidth - 4, 30);
      if (rect.contains(localPosition)) {
        return true;
      }
    }

    for (final event in _timedEvents) {
      final visibleSegment = _eventVisibleSegmentForCurrentDay(event);
      if (visibleSegment == null) continue;

      const hourHeight = 60.0;
      final dayStart = DateTime(
        _currentDate.year,
        _currentDate.month,
        _currentDate.day,
      );
      final startMinutes = visibleSegment.start.difference(dayStart).inMinutes;
      final endMinutes = visibleSegment.end.difference(dayStart).inMinutes;
      final top = (startMinutes / 60) * hourHeight;
      final rawHeight = ((endMinutes - startMinutes) / 60) * hourHeight;
      final height = rawHeight < 1.0 ? 1.0 : rawHeight;

      final rect = Rect.fromLTWH(2, top, gridWidth - 4, height);
      if (rect.contains(localPosition)) {
        return true;
      }
    }

    return false;
  }

  DateTime _timeFromPosition(Offset localPosition) {
    const hourHeight = 60.0;
    final y = localPosition.dy.clamp(0.0, 24 * hourHeight);
    final minutes = (y / hourHeight) * 60;
    final hour = (minutes / 60).floor();
    final minute = ((minutes % 60) / 15).floor() * 15;

    return DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
      hour,
      minute,
    );
  }

  DateTimeRange? _eventVisibleSegmentForCurrentDay(CalendarEvent event) {
    final dayStart = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));

    final visibleStart = event.startDateTime.isBefore(dayStart)
        ? dayStart
        : event.startDateTime;
    final visibleEnd = event.endDateTime.isAfter(dayEnd)
        ? dayEnd
        : event.endDateTime;

    if (!visibleEnd.isAfter(visibleStart)) return null;
    return DateTimeRange(start: visibleStart, end: visibleEnd);
  }

  void _handleGridPointerDownEvent(PointerDownEvent event) {
    final localPosition = event.localPosition;
    if (_contextMenuPosition != null ||
        _eventActionsPopoverEventId != null ||
        _isPointerDownOnEvent ||
        _isDraggingEvent) {
      return;
    }
    if (_isPointerOverEvent(localPosition)) {
      return;
    }

    final isTouch = event.kind == PointerDeviceKind.touch;
    _gridLongPressTimer?.cancel();
    setState(() {
      _isPointerDownOnGrid = true;
      _gridLongPressArmed = false;
      _gridPointerDownPosition = localPosition;
      _lastGridPointerPosition = localPosition;
      _gridDragStartTime = null;
      _gridDragEndTime = null;
    });

    _gridLongPressTimer = Timer(_touchLongPressDuration, () {
      if (!mounted || !_isPointerDownOnGrid) return;
      final anchor = _lastGridPointerPosition ?? _gridPointerDownPosition;
      if (anchor == null) return;
      setState(() {
        _gridLongPressArmed = true;
        _isDraggingToCreate = true;
        _gridDragStartTime = _timeFromPosition(anchor);
        _gridDragEndTime = _gridDragStartTime;
      });
      if (isTouch) {
        HapticFeedback.selectionClick();
      }
    });
  }

  void _handleGridPointerMove(PointerMoveEvent event) {
    if (!_isPointerDownOnGrid) return;
    final localPosition = event.localPosition;
    _lastGridPointerPosition = localPosition;

    final start = _gridPointerDownPosition;
    if (start == null) return;

    final distance = (localPosition - start).distance;
    if (!_gridLongPressArmed) {
      if (distance > _touchCancelDistance) {
        _handleGridPointerCancel();
      }
      return;
    }

    if (!_isDraggingToCreate && distance < _dragActivationDistance) {
      return;
    }

    if (!_isDraggingToCreate) {
      setState(() {
        _isDraggingToCreate = true;
      });
    }

    final newEnd = _timeFromPosition(localPosition);
    setState(() {
      _gridDragEndTime = newEnd;
      if (_gridDragStartTime != null &&
          _gridDragEndTime!.isBefore(_gridDragStartTime!)) {
        final temp = _gridDragStartTime;
        _gridDragStartTime = _gridDragEndTime;
        _gridDragEndTime = temp;
      }

      if (_gridDragStartTime != null &&
          _gridDragEndTime!.difference(_gridDragStartTime!).inMinutes < 15) {
        _gridDragEndTime = _gridDragStartTime!.add(const Duration(minutes: 15));
      }
    });
  }

  void _handleGridPointerUp(PointerUpEvent _) {
    if (!_isPointerDownOnGrid) return;
    _gridLongPressTimer?.cancel();

    if (!_gridLongPressArmed) {
      _handleGridPointerCancel();
      return;
    }

    if (_isDraggingToCreate &&
        _gridDragStartTime != null &&
        _gridDragEndTime != null) {
      // Ensure minimum duration of 15 minutes before showing modal/preview
      if (_gridDragEndTime!.difference(_gridDragStartTime!).inMinutes < 15) {
        _gridDragEndTime = _gridDragStartTime!.add(const Duration(minutes: 15));
      }
      setState(() {
        _pendingCreateStartTime = _gridDragStartTime;
        _pendingCreateEndTime = _gridDragEndTime;
      });
      _handleGridDragEnd();
    }

    setState(() {
      _isPointerDownOnGrid = false;
      _gridLongPressArmed = false;
      _gridPointerDownPosition = null;
      _lastGridPointerPosition = null;
    });
  }

  void _handleGridPointerCancel() {
    _gridLongPressTimer?.cancel();
    setState(() {
      _isPointerDownOnGrid = false;
      _gridLongPressArmed = false;
      _isDraggingToCreate = false;
      _gridPointerDownPosition = null;
      _lastGridPointerPosition = null;
      _gridDragStartTime = null;
      _gridDragEndTime = null;
      _pendingCreateStartTime = null;
      _pendingCreateEndTime = null;
    });
  }

  void _handleGridDragEnd() {
    if (_isDraggingToCreate &&
        _gridDragStartTime != null &&
        _gridDragEndTime != null) {
      // Ensure minimum duration of 15 minutes
      if (_gridDragEndTime!.difference(_gridDragStartTime!).inMinutes < 15) {
        _gridDragEndTime = _gridDragStartTime!.add(const Duration(minutes: 15));
      }

      // For range selection, open the centered create modal directly
      _showCreateEventModal(
        startTime: _gridDragStartTime!,
        endTime: _gridDragEndTime!,
      );
    }

    setState(() {
      _isDraggingToCreate = false;
      _gridDragStartTime = null;
      _gridDragEndTime = null;
    });
  }

  void _updateEventDragPreview(CalendarEvent event, Offset globalPosition) {
    if (_dragStartTime == null || _dragStartGlobalPosition == null) return;

    const hourHeight = 60.0;
    final deltaY = globalPosition.dy - _dragStartGlobalPosition!.dy;
    final deltaMinutes = (deltaY / hourHeight) * 60;
    final snappedDelta = (deltaMinutes / 15).round() * 15;

    final newStart = _dragStartTime!.add(Duration(minutes: snappedDelta));
    final duration = event.endDateTime.difference(event.startDateTime);
    final newEnd = newStart.add(duration);

    setState(() {
      _dragPreviewEvent = event.copyWith(
        startDateTime: newStart,
        endDateTime: newEnd,
      );
    });
  }

  void _clearDragState() {
    _draggedEventId = null;
    _dragStartTime = null;
    _dragStartGlobalPosition = null;
    _draggedEventOriginal = null;
    _isDraggingEvent = false;
    _dragPreviewEvent = null;
  }

  void _finalizeEventDrag() async {
    if (_draggedEventId == null || _dragPreviewEvent == null) {
      setState(() {
        _clearDragState();
      });
      return;
    }

    final originalEvent = _draggedEventOriginal;
    final updatedEvent = _dragPreviewEvent!;

    if (originalEvent == null) {
      setState(() {
        _clearDragState();
      });
      return;
    }

    setState(() {
      _pinOptimisticEventOverride(updatedEvent);
      _eventsMap[updatedEvent.id] = updatedEvent;
      _updateEventLists();
      _clearDragState();
    });

    try {
      await _repository.updateEvent(updatedEvent);
      unawaited(
        _syncService.pushLocalChanges().catchError((e) {
          debugPrint('Background sync failed after drag update: $e');
        }),
      );
    } catch (e) {
      debugPrint('Error updating event: $e');
      if (!mounted) return;
      setState(() {
        _clearOptimisticEventOverride(originalEvent.id);
        _eventsMap[originalEvent.id] = originalEvent;
        _updateEventLists();
      });
    }
  }

  void _handleEventResizeByDelta(
    CalendarEvent event, {
    required double deltaY,
    required bool fromTop,
  }) {
    final current = _eventsMap[event.id];
    final anchorStart = _resizeAnchorStart;
    final anchorEnd = _resizeAnchorEnd;
    if (current == null || anchorStart == null || anchorEnd == null) return;

    const hourHeight = 60.0;
    final deltaMinutes = (deltaY / hourHeight) * 60;
    // 5-minute snap gives smoother, more accurate resize behavior.
    final snappedDelta = (deltaMinutes / 5).round() * 5;

    DateTime newStart = anchorStart;
    DateTime newEnd = anchorEnd;

    if (fromTop) {
      newStart = anchorStart.add(Duration(minutes: snappedDelta));
      if (newStart.isAfter(newEnd.subtract(const Duration(minutes: 15)))) {
        newStart = newEnd.subtract(const Duration(minutes: 15));
      }
    } else {
      newEnd = anchorEnd.add(Duration(minutes: snappedDelta));
      if (newEnd.isBefore(newStart.add(const Duration(minutes: 15)))) {
        newEnd = newStart.add(const Duration(minutes: 15));
      }
    }

    setState(() {
      if (_eventsMap.containsKey(event.id)) {
        _eventsMap[event.id] = current.copyWith(
          startDateTime: newStart,
          endDateTime: newEnd,
        );
        _updateEventLists();
      }
    });
  }

  void _finalizeEventResize() async {
    if (_resizingEventId == null) return;

    final event = _eventsMap[_resizingEventId];
    if (event == null) return;

    // Optimistic update
    final resizingEventId = _resizingEventId;
    final resizingOriginal = _resizingEventOriginal;
    setState(() {
      _resizingEventId = null;
      _resizingFromTop = null;
      _resizingEventOriginal = null;
      _resizeHoverEventId = null;
      _resizeHoverFromTop = null;
      _resizeStartGlobalY = null;
      _resizeAnchorStart = null;
      _resizeAnchorEnd = null;
    });

    try {
      _pinOptimisticEventOverride(event);
      await _repository.updateEvent(event);
      unawaited(
        _syncService.pushLocalChanges().catchError((e) {
          debugPrint('Background sync failed after resize update: $e');
        }),
      );
    } catch (e) {
      debugPrint('Error resizing event: $e');
      // Revert on error
      if (resizingOriginal != null) {
        if (!mounted) return;
        setState(() {
          _clearOptimisticEventOverride(resizingEventId!);
          _eventsMap[resizingEventId] = resizingOriginal;
          _updateEventLists();
        });
      }
    }
  }

  Future<void> _showCreateEventModal({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final isMobile = MediaQuery.of(context).size.width < 700;
    if (isMobile) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: true,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        builder: (context) => EventCreationModal(
          startTime: startTime,
          endTime: endTime,
          onEventCreated: () {},
          renderAsBottomSheetContent: true,
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (context) => EventCreationModal(
          startTime: startTime,
          endTime: endTime,
          onEventCreated: () {},
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _pendingCreateStartTime = null;
      _pendingCreateEndTime = null;
    });
  }

  FocusNode _getEventFocusNode(String eventId) {
    return _eventFocusNodes.putIfAbsent(eventId, () => FocusNode());
  }

  Future<void> _showEditEventModal(CalendarEvent event) async {
    final isMobile = MediaQuery.of(context).size.width < 700;
    if (isMobile) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: true,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        builder: (context) => EventCreationModal(
          existingEvent: event,
          onEventCreated: () {},
          renderAsBottomSheetContent: true,
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (context) =>
            EventCreationModal(existingEvent: event, onEventCreated: () {}),
      );
    }
  }

  Future<void> _confirmAndDeleteEvent(CalendarEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: const Text('Are you sure you want to delete this event?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _repository.deleteEvent(event.id);
      unawaited(
        _syncService.pushLocalChanges().catchError((e) {
          debugPrint('Background sync failed after delete: $e');
        }),
      );
    } catch (e) {
      if (mounted) {
        _showCompactSnackBar('Error deleting event: $e');
      }
    }
  }

  void _showContextMenu(CalendarEvent event, Offset position) {
    setState(() {
      _contextMenuPosition = position;
      _contextMenuEvent = event;
    });
  }

  void _dismissContextMenu() {
    setState(() {
      _contextMenuPosition = null;
      _contextMenuEvent = null;
    });
  }

  Widget _buildContextMenuOverlay() {
    if (_contextMenuEvent == null || _contextMenuPosition == null) {
      return const SizedBox.shrink();
    }

    final event = _contextMenuEvent!;
    final menuItems = [
      ContextMenuItem(
        label: 'Edit',
        icon: Icons.edit,
        onTap: () {
          _dismissContextMenu();
          _showEditEventModal(event);
        },
      ),
      ContextMenuItem(
        label: 'Delete',
        icon: Icons.delete,
        isDestructive: true,
        onTap: () async {
          _dismissContextMenu();
          await _confirmAndDeleteEvent(event);
        },
      ),
    ];

    return ContextMenu(
      position: _contextMenuPosition!,
      items: menuItems,
      onDismiss: _dismissContextMenu,
    );
  }

  Widget _buildDragCreateSelection() {
    final startTime = _isDraggingToCreate
        ? _gridDragStartTime
        : _pendingCreateStartTime;
    final endTime = _isDraggingToCreate
        ? _gridDragEndTime
        : _pendingCreateEndTime;

    if (startTime == null || endTime == null) {
      return const SizedBox.shrink();
    }

    final calendarColorValue =
        _calendarColors[_selectedCalendarId ?? 'primary'];
    final selectionColor = calendarColorValue != null
        ? Color(calendarColorValue)
        : AppColors.primary;
    final textColor = selectionColor.computeLuminance() > 0.6
        ? Colors.black87
        : Colors.white;

    const hourHeight = 60.0;
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;
    final startPosition = (startMinutes / 60) * hourHeight;
    final height = ((endMinutes - startMinutes) / 60) * hourHeight;

    final isTiny = height < 22;
    final isCompact = height < 48;

    return Positioned(
      left: 0,
      top: startPosition,
      right: 0,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: selectionColor.withOpacity(0.85),
          border: Border.all(color: selectionColor.withOpacity(0.95), width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isTiny ? 4 : 6,
          vertical: isTiny ? 1 : 4,
        ),
        child: isTiny
            ? Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${DateFormat('h:mma').format(startTime).toLowerCase()} - ${DateFormat('h:mma').format(endTime).toLowerCase()}',
                  style: TextStyle(
                    color: textColor.withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : isCompact
            ? Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '(No title)  ${DateFormat('h:mma').format(startTime).toLowerCase()} - ${DateFormat('h:mma').format(endTime).toLowerCase()}',
                  style: TextStyle(
                    color: textColor.withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '(No title)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('h:mm a').format(startTime)} - ${DateFormat('h:mm a').format(endTime)}',
                    style: TextStyle(
                      color: textColor.withOpacity(0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
      ),
    );
  }

  void _clearEventTouchPressState() {
    _eventLongPressTimer?.cancel();
    _eventLongPressArmed = false;
    _touchPendingEventId = null;
  }

  bool _isMobileDoubleTap(String eventId, Offset currentPosition) {
    final now = DateTime.now();
    final lastTime = _lastMobileTapTime;
    final lastEventId = _lastMobileTapEventId;
    final lastPos = _lastMobileTapPosition;

    final withinWindow =
        lastTime != null &&
        now.difference(lastTime) <= _mobileDoubleTapWindow &&
        lastEventId == eventId &&
        lastPos != null &&
        (currentPosition - lastPos).distance <= _mobileDoubleTapDistance;

    if (withinWindow) {
      _lastMobileTapTime = null;
      _lastMobileTapEventId = null;
      _lastMobileTapPosition = null;
      return true;
    }

    _lastMobileTapTime = now;
    _lastMobileTapEventId = eventId;
    _lastMobileTapPosition = currentPosition;
    return false;
  }

  bool _isDesktopDoubleClick(String eventId, Offset currentPosition) {
    final now = DateTime.now();
    final lastTime = _lastDesktopClickTime;
    final lastEventId = _lastDesktopClickEventId;
    final lastPos = _lastDesktopClickPosition;

    final withinWindow =
        lastTime != null &&
        now.difference(lastTime) <= _desktopDoubleClickWindow &&
        lastEventId == eventId &&
        lastPos != null &&
        (currentPosition - lastPos).distance <= _desktopDoubleClickDistance;

    if (withinWindow) {
      _lastDesktopClickTime = null;
      _lastDesktopClickEventId = null;
      _lastDesktopClickPosition = null;
      return true;
    }

    _lastDesktopClickTime = now;
    _lastDesktopClickEventId = eventId;
    _lastDesktopClickPosition = currentPosition;
    return false;
  }

  void _clearPendingResizeTouch() {
    _resizeLongPressTimer?.cancel();
    _touchPendingResizeEventId = null;
    _resizeTouchDownGlobalPosition = null;
  }

  Widget _buildTodayOverviewSection() {
    final viewedDay = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    final summary = _todayOverviewSummary(viewedDay);

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 14),
            child: Text(
              'Day Overview',
              style: TextStyle(
                color: AppColors.onBackground,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          _buildOverviewMetricTile(
            icon: Icons.event_note_rounded,
            title: 'Scheduled Events',
            value: '${summary.eventCount}',
          ),
          const SizedBox(height: 8),
          _buildOverviewMetricTile(
            icon: Icons.schedule_rounded,
            title: 'Free Time',
            value: _formatDurationMinutes(summary.freeMinutes),
          ),
          const SizedBox(height: 8),
          _buildOverviewMetricTile(
            icon: Icons.call_merge_rounded,
            title: 'Overlap Conflicts',
            value: '${summary.overlapCount}',
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewMetricTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF26211D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 23, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.onBackground,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  ({int eventCount, int freeMinutes, int overlapCount}) _todayOverviewSummary(
    DateTime day,
  ) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final todaysEvents = _eventsMap.values.where((event) {
      if (event.allDay) {
        final allDayStart = DateTime(
          event.startDateTime.year,
          event.startDateTime.month,
          event.startDateTime.day,
        );
        var allDayEndExclusive = DateTime(
          event.endDateTime.year,
          event.endDateTime.month,
          event.endDateTime.day,
        );
        if (!allDayEndExclusive.isAfter(allDayStart)) {
          allDayEndExclusive = allDayStart.add(const Duration(days: 1));
        }
        return allDayStart.isBefore(dayEnd) &&
            allDayEndExclusive.isAfter(dayStart);
      }
      return event.startDateTime.isBefore(dayEnd) &&
          event.endDateTime.isAfter(dayStart);
    }).toList();

    final timedToday =
        todaysEvents
            .where((e) => !_treatAsAllDayForMetrics(e, dayStart, dayEnd))
            .toList()
          ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
    final overlapCount = _countTimedOverlapPairsForDay(
      timedToday,
      dayStart,
      dayEnd,
    );

    final busyMinutes = _busyMinutesForTimedDay(timedToday, dayStart, dayEnd);
    final freeMinutes = (24 * 60 - busyMinutes).clamp(0, 24 * 60);

    return (
      eventCount: todaysEvents.length,
      freeMinutes: freeMinutes,
      overlapCount: overlapCount,
    );
  }

  bool _treatAsAllDayForMetrics(
    CalendarEvent event,
    DateTime dayStart,
    DateTime dayEnd,
  ) {
    if (event.allDay) return true;

    // Some calendar providers can represent all-day entries as timed events
    // from 00:00 to 00:00 next day. Treat those as all-day for free-time math.
    final startsAtDayStart = !event.startDateTime.isAfter(dayStart);
    final endsAtDayEndOrAfter = !event.endDateTime.isBefore(dayEnd);
    final spansNearlyWholeDay =
        event.endDateTime.difference(event.startDateTime).inMinutes >=
        (24 * 60 - 1);

    return startsAtDayStart && endsAtDayEndOrAfter && spansNearlyWholeDay;
  }

  int _busyMinutesForTimedDay(
    List<CalendarEvent> timedEvents,
    DateTime dayStart,
    DateTime dayEnd,
  ) {
    if (timedEvents.isEmpty) return 0;

    final intervals =
        timedEvents
            .map((event) {
              final start = event.startDateTime.isBefore(dayStart)
                  ? dayStart
                  : event.startDateTime;
              final end = event.endDateTime.isAfter(dayEnd)
                  ? dayEnd
                  : event.endDateTime;
              if (!end.isAfter(start)) return null;
              return DateTimeRange(start: start, end: end);
            })
            .whereType<DateTimeRange>()
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    if (intervals.isEmpty) return 0;

    var busyMinutes = 0;
    var currentStart = intervals.first.start;
    var currentEnd = intervals.first.end;

    for (var i = 1; i < intervals.length; i++) {
      final segment = intervals[i];
      if (!segment.start.isAfter(currentEnd)) {
        if (segment.end.isAfter(currentEnd)) {
          currentEnd = segment.end;
        }
        continue;
      }

      busyMinutes += currentEnd.difference(currentStart).inMinutes;
      currentStart = segment.start;
      currentEnd = segment.end;
    }

    busyMinutes += currentEnd.difference(currentStart).inMinutes;
    return busyMinutes.clamp(0, 24 * 60);
  }

  int _countTimedOverlapPairsForDay(
    List<CalendarEvent> timedEvents,
    DateTime dayStart,
    DateTime dayEnd,
  ) {
    if (timedEvents.length < 2) return 0;

    final ranges =
        timedEvents
            .map((event) {
              final start = event.startDateTime.isBefore(dayStart)
                  ? dayStart
                  : event.startDateTime;
              final end = event.endDateTime.isAfter(dayEnd)
                  ? dayEnd
                  : event.endDateTime;
              if (!end.isAfter(start)) return null;
              return DateTimeRange(start: start, end: end);
            })
            .whereType<DateTimeRange>()
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    var overlapPairs = 0;
    for (var i = 0; i < ranges.length; i++) {
      for (var j = i + 1; j < ranges.length; j++) {
        if (!ranges[j].start.isBefore(ranges[i].end)) {
          break;
        }
        overlapPairs++;
      }
    }
    return overlapPairs;
  }

  String _formatDurationMinutes(int minutes) {
    final safeMinutes = minutes.clamp(0, 24 * 60);
    final hours = safeMinutes ~/ 60;
    final mins = safeMinutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  void _startEventResizeInteraction(CalendarEvent event, double startGlobalY) {
    setState(() {
      _resizingEventId = event.id;
      _resizingFromTop = false;
      _resizingEventOriginal = event;
      _resizeHoverEventId = event.id;
      _resizeHoverFromTop = false;
      _resizeStartGlobalY = startGlobalY;
      _resizeAnchorStart = event.startDateTime;
      _resizeAnchorEnd = event.endDateTime;
    });
  }

  void _cancelPendingEventTouchInteraction(String eventId) {
    if (_touchPendingEventId != eventId) return;
    _pendingPointerEventId = null;
    _pointerDownGlobalPosition = null;
    _dragThresholdExceeded = false;
    _dragStartGlobalPosition = null;
    _dragStartTime = null;
    _draggedEventOriginal = null;
    _isPointerDownOnEvent = false;
    _clearEventTouchPressState();
  }

  CalendarEvent? _getKeyboardTargetEvent() {
    final activeEventId = _keyboardActiveEventId;
    if (activeEventId != null) {
      final activeEvent = _eventsMap[activeEventId];
      if (activeEvent != null) return activeEvent;
    }

    final activePopoverId = _eventActionsPopoverEventId;
    if (activePopoverId != null) {
      final popoverEvent = _eventsMap[activePopoverId];
      if (popoverEvent != null) return popoverEvent;
    }

    final pendingId = _pendingPointerEventId;
    if (pendingId != null) {
      final pendingEvent = _eventsMap[pendingId];
      if (pendingEvent != null) return pendingEvent;
    }

    for (final entry in _eventFocusNodes.entries) {
      final node = entry.value;
      if (node.hasPrimaryFocus || node.hasFocus) {
        final focusedEvent = _eventsMap[entry.key];
        if (focusedEvent != null) return focusedEvent;
      }
    }

    return null;
  }

  Future<void> _moveEventByKeyboard(
    CalendarEvent event, {
    required int deltaMinutes,
  }) async {
    final updated = event.copyWith(
      startDateTime: event.startDateTime.add(Duration(minutes: deltaMinutes)),
      endDateTime: event.endDateTime.add(Duration(minutes: deltaMinutes)),
    );

    setState(() {
      _pinOptimisticEventOverride(updated);
      _eventsMap[event.id] = updated;
      _updateEventLists();
    });

    try {
      await _repository.updateEvent(updated);
      unawaited(
        _syncService.pushLocalChanges().catchError((e) {
          debugPrint('Background sync failed after keyboard move: $e');
        }),
      );
    } catch (e) {
      debugPrint('Error moving event with keyboard: $e');
      if (!mounted) return;
      setState(() {
        _clearOptimisticEventOverride(event.id);
        _eventsMap[event.id] = event;
        _updateEventLists();
      });
    }
  }

  void _cancelKeyboardInteractions() {
    if (_contextMenuPosition != null || _contextMenuEvent != null) {
      _dismissContextMenu();
    }

    if (_eventActionsPopoverEventId != null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _clearDragState();
      _resizingEventId = null;
      _resizingFromTop = null;
      _resizingEventOriginal = null;
      _resizeHoverEventId = null;
      _resizeHoverFromTop = null;
      _resizeStartGlobalY = null;
      _resizeAnchorStart = null;
      _resizeAnchorEnd = null;
      _isDraggingToCreate = false;
      _gridDragStartTime = null;
      _gridDragEndTime = null;
      _pendingCreateStartTime = null;
      _pendingCreateEndTime = null;
      _pendingPointerEventId = null;
      _pointerDownGlobalPosition = null;
      _dragThresholdExceeded = false;
      _isPointerDownOnEvent = false;
      _isPointerDownOnGrid = false;
      _gridLongPressArmed = false;
      _gridPointerDownPosition = null;
      _lastGridPointerPosition = null;
    });
  }

  void _handleKeyboardShortcut(KeyEvent event) {
    if (!_keyboardShortcutsEnabled) return;

    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    final targetEvent = _getKeyboardTargetEvent();

    if (key == LogicalKeyboardKey.keyC) {
      _showCreateEventModal();
      return;
    }

    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (targetEvent != null) {
        _confirmAndDeleteEvent(targetEvent);
      }
      return;
    }

    if (key == LogicalKeyboardKey.enter) {
      if (targetEvent != null) {
        _showEditEventModal(targetEvent);
      }
      return;
    }

    if (key == LogicalKeyboardKey.escape) {
      _cancelKeyboardInteractions();
      return;
    }

    if (key == LogicalKeyboardKey.keyT) {
      _handleDateChange(DateTime.now());
      return;
    }

    if (targetEvent == null) return;

    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      _moveEventByKeyboard(targetEvent, deltaMinutes: -15);
      return;
    }

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      _moveEventByKeyboard(targetEvent, deltaMinutes: 15);
    }
  }
}
