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
import '../widgets/context_menu.dart';

class CalendarDayViewScreen extends ConsumerStatefulWidget {
  final VoidCallback? onSignOut;

  const CalendarDayViewScreen({super.key, this.onSignOut});

  @override
  ConsumerState<CalendarDayViewScreen> createState() =>
      _CalendarDayViewScreenState();
}

class _CalendarDayViewScreenState extends ConsumerState<CalendarDayViewScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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

  DateTime _currentDate = DateTime.now();
  late final EventRepository _repository;
  late final SyncService _syncService;
  StreamSubscription<List<CalendarEvent>>? _eventsSubscription;
  late final ProviderSubscription<AsyncValue<SyncStatus>> _syncStatusSub;
  late final AnimationController _syncRotationController;
  late final FocusNode _keyboardListenerFocusNode;

  // Use Map to prevent duplicates - key is event ID
  final Map<String, CalendarEvent> _eventsMap = {};
  List<CalendarEvent> _allDayEvents = [];
  List<CalendarEvent> _timedEvents = [];

  bool _keyboardShortcutsEnabled = true;
  bool _isLoading = true;
  String? _selectedCalendarId;
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

  @override
  void initState() {
    super.initState();
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
        _updateSyncRotation(next);
        final status = next.valueOrNull;
        if (status?.state == SyncState.error && mounted) {
          final message = status?.error ?? 'Sync error';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
    _updateSyncRotation(ref.read(syncStatusProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keyboardListenerFocusNode.requestFocus();
    });
  }

  Future<void> _initialize() async {
    await _loadCalendarId();
    await _loadCalendarColors();
    _subscribeToEvents();
    await _syncService.start(
      range: _currentRange,
      calendarId: _selectedCalendarId ?? 'primary',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventsSubscription?.cancel();
    _syncStatusSub.close();
    _syncRotationController.dispose();
    _keyboardListenerFocusNode.dispose();
    _syncService.stop();
    _dayGridScrollController.dispose();
    for (final node in _eventFocusNodes.values) {
      node.dispose();
    }
    _eventLongPressTimer?.cancel();
    _resizeLongPressTimer?.cancel();
    _gridLongPressTimer?.cancel();
    super.dispose();
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
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));
    return DateTimeRange(start: dayStart, end: dayEnd);
  }

  void _subscribeToEvents() {
    _eventsSubscription?.cancel();
    setState(() {
      _isLoading = true;
    });

    _eventsSubscription = _repository.watchEvents(_currentRange).listen((
      events,
    ) {
      _eventsMap
        ..clear()
        ..addEntries(events.map((e) => MapEntry(e.id, e)));
      setState(() {
        _updateEventLists();
        _isLoading = false;
      });
      _scrollToNowOnInitialOpen();
    });
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
    final normalizedDate = DateTime(newDate.year, newDate.month, newDate.day);
    final currentNormalized = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    if (normalizedDate.isAtSameMomentAs(currentNormalized)) return;

    setState(() {
      _currentDate = normalizedDate;
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

  void _handleSwipePointerDown(PointerDownEvent event) {
    if (!_isMobileLayout(context)) return;
    _swipeStartGlobalPosition = event.position;
    _swipeStartTime = DateTime.now();
  }

  void _resetSwipeTracking() {
    _swipeStartGlobalPosition = null;
    _swipeStartTime = null;
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
    if (state == AppLifecycleState.resumed) {
      _syncService.incrementalSync();
      _syncService.pushLocalChanges();
    }
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

  Future<void> _loadCalendarColors() async {
    try {
      final cached = await GoogleCalendarService.instance.getCachedCalendars();
      if (cached.isNotEmpty) {
        _calendarColors.clear();
        for (final cal in cached) {
          final calendarId = cal['id'] as String?;
          final calendarColor = cal['color'] as int?;
          if (calendarId != null && calendarColor != null) {
            _calendarColors[calendarId] = calendarColor;
          }
        }
      }

      final signedIn = await GoogleCalendarService.instance.isSignedIn();
      if (!signedIn) return;

      final calendars = await GoogleCalendarService.instance.getUserCalendars();
      _calendarColors.clear();

      for (final cal in calendars) {
        final calendarId = cal['id'] as String;
        final calendarColor = cal['color'] as int;
        _calendarColors[calendarId] = calendarColor;
        debugPrint(
          'Loaded color for calendar ${cal['name']}: ${calendarColor.toRadixString(16)}',
        );
      }
    } catch (e) {
      debugPrint('Error loading calendar colors: $e');
    }
  }

  void _updateEventLists() {
    final allEvents = _eventsMap.values.toList();
    _allDayEvents = allEvents.where((e) => e.allDay).toList()
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
    _timedEvents = allEvents.where((e) => !e.allDay).toList()
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
  }

  @override
  Widget build(BuildContext context) {
    final syncStatusAsync = ref.watch(syncStatusProvider);
    return KeyboardListener(
      focusNode: _keyboardListenerFocusNode,
      onKeyEvent: _keyboardShortcutsEnabled ? _handleKeyboardShortcut : null,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(syncStatusAsync),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Stack(
                        children: [
                          _buildCalendarContent(),
                          // Context menu overlay
                          if (_contextMenuPosition != null &&
                              _contextMenuEvent != null)
                            _buildContextMenuOverlay(),
                          // Drag-to-create selection block
                          if ((_isDraggingToCreate &&
                                  _gridDragStartTime != null &&
                                  _gridDragEndTime != null) ||
                              (_pendingCreateStartTime != null &&
                                  _pendingCreateEndTime != null))
                            _buildDragCreateSelection(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(AsyncValue<SyncStatus> syncStatusAsync) {
    final isMobile = _isMobileLayout(context);
    final dateString = DateFormat('d MMM y').format(_currentDate);
    final showStatusText = !isMobile;
    Future<void> handlePickDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: _currentDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Move to date',
      );
      if (picked == null) return;
      final selectedDate = DateTime(picked.year, picked.month, picked.day);
      await _handleDateChange(selectedDate);
    }

    Future<void> handleSync() async {
      await _syncService.incrementalSync();
      await _syncService.pushLocalChanges();
    }

    final statusWidget = syncStatusAsync.when(
      data: (status) {
        if (status.state == SyncState.syncing) {
          return const Text(
            'Syncing…',
            style: TextStyle(color: AppColors.onBackground, fontSize: 12),
          );
        }
        if (status.state == SyncState.error) {
          return const Text(
            'Sync error',
            style: TextStyle(color: AppColors.error, fontSize: 12),
          );
        }
        if (status.lastSyncTime != null) {
          final time = DateFormat('h:mm a').format(status.lastSyncTime!);
          return Text(
            'Last sync $time',
            style: const TextStyle(color: AppColors.onBackground, fontSize: 12),
          );
        }
        return const SizedBox.shrink();
      },
      loading: () => const Text(
        'Syncing…',
        style: TextStyle(color: AppColors.onBackground, fontSize: 12),
      ),
      error: (error, stackTrace) => const Text(
        'Sync error',
        style: TextStyle(color: AppColors.error, fontSize: 12),
      ),
    );

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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    color: AppColors.onBackground,
                    size: isMobile ? 18 : 20,
                  ),
                  visualDensity: isMobile ? VisualDensity.compact : null,
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  child: TextButton(
                    onPressed: handlePickDate,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 40 : 60,
                        vertical: 17,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      dateString,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isMobile ? 15 : 17,
                        fontWeight: FontWeight.w400,
                        color: AppColors.onBackground,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: RotationTransition(
                    turns: _syncRotationController,
                    child: const Icon(
                      Icons.sync_rounded,
                      color: AppColors.onBackground,
                    ),
                  ),
                  visualDensity: isMobile ? VisualDensity.compact : null,
                  onPressed: handleSync,
                ),
                if (showStatusText) ...[const SizedBox(width: 8), statusWidget],
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

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handleSwipePointerDown,
          onPointerUp: (event) {
            _handleSwipePointerUp(event);
          },
          onPointerCancel: (_) {
            _resetSwipeTracking();
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
                    color: AppColors.surface,
                    border: Border(
                      bottom: BorderSide(color: AppColors.dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: timeColumnWidth,
                        child: Text(
                          'All day',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.timeTextColor,
                            fontWeight: FontWeight.w400,
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
                                              color: event.color,
                                              border: Border(
                                                left: BorderSide(
                                                  color: event.color,
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
                                                    fontWeight: FontWeight.w500,
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
                                maxWidth: constraints.maxWidth - timeColumnWidth,
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
      },
    );
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

  List<Widget> _buildEventWidgets(BoxConstraints constraints) {
    final widgets = <Widget>[];

    // Build all-day event widgets (spanning full width at top)
    for (final event in _allDayEvents) {
      widgets.add(_buildAllDayEventWidget(event, constraints));
    }

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

  Widget _buildAllDayEventWidget(
    CalendarEvent event,
    BoxConstraints constraints,
  ) {
    final now = DateTime.now();
    final isPastEvent =
        event.endDateTime.isBefore(now) ||
        event.endDateTime.isAtSameMomentAs(now);

    // All-day events appear at the very top (position 0) and span the full day height
    // We'll make them about 30 pixels tall, positioned at the top
    return Positioned(
      left: 2,
      top: 0,
      right: 2,
      height: 30,
      child: GestureDetector(
        onTap: () {
          _keyboardActiveEventId = event.id;
        },
        onDoubleTap: () {
          _keyboardActiveEventId = event.id;
          _showEditEventModal(event);
        },
        child: Opacity(
          opacity: isPastEvent ? _pastEventOpacity : 1,
          child: Container(
            decoration: BoxDecoration(
              // Keep color inside BoxDecoration to avoid color+decoration assert.
              color: event.color,
              border: Border(left: BorderSide(color: event.color, width: 3)),
              borderRadius: BorderRadius.circular(2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    style: const TextStyle(
                      color: _eventBlockTextColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // All-day indicator
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: event.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text(
                    'All day',
                    style: TextStyle(
                      color: _eventBlockTextColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
          : SystemMouseCursors.grab,
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

            setState(() {
              _resizingEventId = event.id;
              _resizingFromTop = false;
              _resizingEventOriginal = event;
              _resizeHoverEventId = event.id;
              _resizeHoverFromTop = false;
              _resizeStartGlobalY = pointerEvent.position.dy;
              _resizeAnchorStart = event.startDateTime;
              _resizeAnchorEnd = event.endDateTime;
            });
            if (pointerEvent.kind == PointerDeviceKind.touch) {
              HapticFeedback.selectionClick();
            }
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
                      // Use exact event color for the block fill.
                      color: event.color,
                      border: Border(
                        left: BorderSide(color: event.color, width: 3),
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
                                    color: _eventBlockTextColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      ', ${DateFormat('h:mma').format(event.startDateTime).toLowerCase()}',
                                  style: const TextStyle(
                                    color: _eventBlockTextColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
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

  bool _isWithinDayRange(CalendarEvent event) {
    final dayStart = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));
    return !event.startDateTime.isBefore(dayStart) &&
        !event.endDateTime.isAfter(dayEnd);
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

    if (originalEvent == null || !_isWithinDayRange(updatedEvent)) {
      setState(() {
        _clearDragState();
      });
      return;
    }

    setState(() {
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
      _eventsMap[originalEvent.id] = originalEvent;
      _updateEventLists();
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
        _eventsMap[resizingEventId!] = resizingOriginal;
        _updateEventLists();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting event: $e'),
            backgroundColor: AppColors.error,
          ),
        );
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

    final allDayRowHeight = _allDayEvents.isNotEmpty ? 40.0 : 0.0;
    final scrollOffset = _dayGridScrollController.hasClients
        ? _dayGridScrollController.offset
        : 0.0;

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
    final startPosition =
        (startMinutes / 60) * hourHeight - scrollOffset + allDayRowHeight;
    final height = ((endMinutes - startMinutes) / 60) * hourHeight;

    final isTiny = height < 22;
    final isCompact = height < 48;

    return Positioned(
      left: _timeColumnWidthFor(context),
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

    if (!_isWithinDayRange(updated)) return;

    setState(() {
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
