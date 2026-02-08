import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:ui' show PointerDeviceKind;
import 'dart:async';
import '../models/calendar_event.dart';
import '../services/google_calendar_service.dart';
import '../providers/event_providers.dart';
import '../repositories/event_repository.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import 'widgets/event_creation_modal.dart';
import 'widgets/event_details_popover.dart';
import 'widgets/event_actions_popover.dart';
import '../widgets/context_menu.dart';

enum CalendarView { day, week, month, schedule }

class CalendarDayViewScreen extends ConsumerStatefulWidget {
  final VoidCallback? onSignOut;

  const CalendarDayViewScreen({super.key, this.onSignOut});

  @override
  ConsumerState<CalendarDayViewScreen> createState() =>
      _CalendarDayViewScreenState();
}

class _CalendarDayViewScreenState extends ConsumerState<CalendarDayViewScreen>
    with WidgetsBindingObserver {
  DateTime _currentDate = DateTime.now();
  CalendarView _currentView = CalendarView.day;
  late final EventRepository _repository;
  late final SyncService _syncService;
  StreamSubscription<List<CalendarEvent>>? _eventsSubscription;
  late final ProviderSubscription<AsyncValue<SyncStatus>> _syncStatusSub;

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
  double? _resizeStartY;
  CalendarEvent? _resizingEventOriginal;

  // Scroll controllers for synchronized scrolling
  final ScrollController _timeColumnScrollController = ScrollController();
  final ScrollController _dayGridScrollController = ScrollController();
  bool _isScrolling = false;

  // Interaction state (Google Calendar-like)
  String? _hoveredEventId;
  String? _selectedEventId;
  bool _isHoveringResizeHandle = false;
  final Map<String, FocusNode> _eventFocusNodes = {};
  String? _eventActionsPopoverEventId;
  String? _pendingPointerEventId;
  Offset? _pointerDownGlobalPosition;
  bool _dragThresholdExceeded = false;
  CalendarEvent? _dragPreviewEvent;
  bool _isPointerDownOnEvent = false;
  double? _dayGridWidth;
  double? _dayGridHeight;

  // Drag-to-create state
  bool _isDraggingToCreate = false;
  bool _isPointerDownOnGrid = false;
  Offset? _gridPointerDownPosition;
  Offset? _dragCreateStartPosition;
  DateTime? _pendingCreateStartTime;
  DateTime? _pendingCreateEndTime;

  // Context menu
  Offset? _contextMenuPosition;
  CalendarEvent? _contextMenuEvent;

  // Touch support
  bool _isTouchInteraction = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repository = ref.read(eventRepositoryProvider);
    _syncService = ref.read(syncServiceProvider);

    _initialize();
    _syncStatusSub = ref.listenManual<AsyncValue<SyncStatus>>(
      syncStatusProvider,
      (previous, next) {
        final status = next.valueOrNull;
        if (status?.state == SyncState.error && mounted) {
          final message = status?.error ?? 'Sync error';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      },
    );
    _loadSettings();
    // Setup scroll synchronization
    _syncScrollControllers();
  }

  Future<void> _initialize() async {
    await _loadCalendarId();
    await _loadCalendarColors();
    _subscribeToEvents();
    await _syncService.start(
      range: _currentRange,
      calendarId: _selectedCalendarId ?? 'primary',
    );
    await _syncService.pushLocalChanges();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventsSubscription?.cancel();
    _syncStatusSub.close();
    _syncService.stop();
    _timeColumnScrollController.dispose();
    _dayGridScrollController.dispose();
    for (final node in _eventFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncScrollControllers() {
    // Sync time column scroll with day grid scroll
    _timeColumnScrollController.addListener(() {
      if (!_isScrolling && _dayGridScrollController.hasClients) {
        _isScrolling = true;
        if (_dayGridScrollController.offset !=
            _timeColumnScrollController.offset) {
          _dayGridScrollController.jumpTo(_timeColumnScrollController.offset);
        }
        _isScrolling = false;
      }
    });

    // Sync day grid scroll with time column scroll
    _dayGridScrollController.addListener(() {
      if (!_isScrolling && _timeColumnScrollController.hasClients) {
        _isScrolling = true;
        if (_timeColumnScrollController.offset !=
            _dayGridScrollController.offset) {
          _timeColumnScrollController.jumpTo(_dayGridScrollController.offset);
        }
        _isScrolling = false;
      }
    });
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

    _eventsSubscription = _repository.watchEvents(_currentRange).listen(
      (events) {
        _eventsMap
          ..clear()
          ..addEntries(events.map((e) => MapEntry(e.id, e)));
        setState(() {
          _updateEventLists();
          _isLoading = false;
        });
      },
    );
  }

  Future<void> _handleDateChange(DateTime newDate) async {
    setState(() {
      _currentDate = newDate;
    });
    _subscribeToEvents();
    await _syncService.updateRange(_currentRange);
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

  Future<void> _loadSettings() async {
    // Load keyboard shortcuts preference
    // For now, default to enabled
  }

  @override
  Widget build(BuildContext context) {
    final syncStatusAsync = ref.watch(syncStatusProvider);
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _keyboardShortcutsEnabled ? _handleKeyboardShortcut : null,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
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
    );
  }

  Widget _buildTopBar(AsyncValue<SyncStatus> syncStatusAsync) {
    final dateFormat = DateFormat('EEEE, MMMM d, y');
    final dateString = dateFormat.format(_currentDate);
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
            style: const TextStyle(
              color: AppColors.onBackground,
              fontSize: 12,
            ),
          );
        }
        return const SizedBox.shrink();
      },
      loading: () => const Text(
        'Syncing…',
        style: TextStyle(color: AppColors.onBackground, fontSize: 12),
      ),
      error: (_, __) => const Text(
        'Sync error',
        style: TextStyle(color: AppColors.error, fontSize: 12),
      ),
    );

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderColor)),
      ),
      child: Row(
        children: [
          // Menu icon (Google Calendar style)
          IconButton(
            icon: const Icon(Icons.menu, color: AppColors.onBackground),
            tooltip: 'Menu',
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 8),
          // Today button
          TextButton(
            onPressed: () {
              _handleDateChange(DateTime.now());
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'Today',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          // Back/Next arrows
          IconButton(
            icon: const Icon(Icons.chevron_left, color: AppColors.onBackground),
            onPressed: () {
              _handleDateChange(_currentDate.subtract(const Duration(days: 1)));
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.chevron_right,
              color: AppColors.onBackground,
            ),
            onPressed: () {
              _handleDateChange(_currentDate.add(const Duration(days: 1)));
            },
          ),
          const SizedBox(width: 16),
          // Current date title
          Expanded(
            child: Text(
              dateString,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w400,
                color: AppColors.onBackground,
                letterSpacing: 0,
              ),
            ),
          ),
          // Create event button (Google Calendar style)
          OutlinedButton.icon(
            onPressed: () => _showCreateEventModal(),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Create'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
          // Refresh/Sync button
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.onBackground),
            tooltip: 'Refresh Calendar',
            onPressed: () async {
              await _syncService.incrementalSync();
              await _syncService.pushLocalChanges();
            },
          ),
          const SizedBox(width: 8),
          statusWidget,
          // Search icon
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.onBackground),
            onPressed: () {
              // TODO: Implement search
            },
          ),
          // Settings icon
          IconButton(
            icon: const Icon(Icons.settings, color: AppColors.onBackground),
            onPressed: () {
              _showSettingsDialog();
            },
          ),
          const SizedBox(width: 8),
          // View dropdown
          DropdownButton<CalendarView>(
            value: _currentView,
            items: const [
              DropdownMenuItem(value: CalendarView.day, child: Text('Day')),
              DropdownMenuItem(value: CalendarView.week, child: Text('Week')),
              DropdownMenuItem(value: CalendarView.month, child: Text('Month')),
              DropdownMenuItem(
                value: CalendarView.schedule,
                child: Text('Schedule'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _currentView = value;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarContent() {
    if (_currentView == CalendarView.schedule) {
      return _buildScheduleView();
    }
    return _buildDayView();
  }

  Widget _buildDayView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive: switch to schedule view on small screens
        if (constraints.maxWidth < 600) {
          return _buildScheduleView();
        }

        // Calculate fixed height for scrollable grid (24 hours * 60 pixels per hour)
        const hourHeight = 60.0;
        const totalHeight = 24 * hourHeight;
        final allDayRowHeight = _allDayEvents.isNotEmpty ? 40.0 : 0.0;

        return Column(
          children: [
            // All-day events row (Google Calendar style)
            if (_allDayEvents.isNotEmpty)
              Container(
                height: allDayRowHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: 60,
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
                      width: 60,
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
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _allDayEvents.map((event) {
                            return Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: event.color.withOpacity(0.15),
                                border: Border(
                                  left: BorderSide(
                                    color: event.color,
                                    width: 3,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: GestureDetector(
                                onTapUp: (details) {
                                  _showEventActionsPopover(
                                    event,
                                    details.globalPosition,
                                  );
                                },
                                child: Text(
                                  event.title,
                                  style: TextStyle(
                                    color: event.color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Time grid
            Expanded(
              child: Row(
                children: [
                  // Time column
                  SizedBox(
                    width: 60,
                    child: SingleChildScrollView(
                      controller: _timeColumnScrollController,
                      physics:
                          (_isDraggingToCreate ||
                              _isPointerDownOnGrid ||
                              _isDraggingEvent)
                          ? const NeverScrollableScrollPhysics()
                          : const ClampingScrollPhysics(),
                      child: SizedBox(
                        height: totalHeight,
                        child: _buildTimeColumn(),
                      ),
                    ),
                  ),
                  // Day grid
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _dayGridScrollController,
                      physics:
                          (_isDraggingToCreate ||
                              _isPointerDownOnGrid ||
                              _isDraggingEvent)
                          ? const NeverScrollableScrollPhysics()
                          : const ClampingScrollPhysics(),
                      child: SizedBox(
                        height: totalHeight,
                        child: _buildDayGrid(
                          BoxConstraints(
                            maxWidth: constraints.maxWidth - 60,
                            maxHeight: totalHeight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
              alignment: Alignment.topRight,
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
    _dayGridHeight = constraints.maxHeight;
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
        // Current time indicator (Google Calendar style - red line)
        _buildCurrentTimeIndicator(constraints),
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
    // Include both timed events and all-day events in timeline
    // All-day events should span the full day at the top
    // Group overlapping events (only for timed events, all-day events are separate)
    final timedEventGroups = _groupOverlappingEvents(_timedEvents);
    final widgets = <Widget>[];

    // Build all-day event widgets (spanning full width at top)
    for (final event in _allDayEvents) {
      widgets.add(_buildAllDayEventWidget(event, constraints));
    }

    // Build timed event widgets
    double? previewWidth;
    double? previewLeft;
    for (final group in timedEventGroups) {
      final groupWidth = constraints.maxWidth / group.length;
      for (final entry in group.asMap().entries) {
        final index = entry.key;
        final event = entry.value;
        final isDraggingOriginal =
            _isDraggingEvent && _draggedEventId == event.id;
        if (isDraggingOriginal && _dragPreviewEvent != null) {
          previewWidth = groupWidth;
          previewLeft = index * groupWidth;
        }
        widgets.add(
          _buildEventWidget(
            event,
            constraints,
            groupWidth,
            index * groupWidth,
            isDraggingOriginal: isDraggingOriginal,
          ),
        );
      }
    }

    if (_dragPreviewEvent != null &&
        _draggedEventId == _dragPreviewEvent!.id &&
        previewWidth != null &&
        previewLeft != null) {
      widgets.add(
        _buildEventWidget(
          _dragPreviewEvent!,
          constraints,
          previewWidth,
          previewLeft,
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
    // All-day events appear at the very top (position 0) and span the full day height
    // We'll make them about 30 pixels tall, positioned at the top
    return Positioned(
      left: 2,
      top: 0,
      right: 2,
      height: 30,
      child: GestureDetector(
        onTapUp: (details) {
          _showEventActionsPopover(event, details.globalPosition);
        },
        child: Container(
          decoration: BoxDecoration(
            color: event.color.withOpacity(0.15),
            border: Border(left: BorderSide(color: event.color, width: 3)),
            borderRadius: BorderRadius.circular(2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  event.title,
                  style: TextStyle(
                    color: event.color,
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
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: event.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  'All day',
                  style: TextStyle(
                    color: event.color,
                    fontSize: 9,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Improved overlapping events grouping algorithm
  /// Handles transitive overlaps and ensures proper side-by-side layout
  List<List<CalendarEvent>> _groupOverlappingEvents(
    List<CalendarEvent> events,
  ) {
    if (events.isEmpty) return [];

    // Sort by start time
    final sorted = List<CalendarEvent>.from(events)
      ..sort((a, b) {
        final startCompare = a.startDateTime.compareTo(b.startDateTime);
        if (startCompare != 0) return startCompare;
        return a.endDateTime.compareTo(b.endDateTime);
      });

    // Build overlap graph
    final overlapGroups = <List<CalendarEvent>>[];
    final eventToGroup = <CalendarEvent, int>{};

    for (final event in sorted) {
      // Find all groups this event overlaps with
      final overlappingGroupIndices = <int>{};
      for (final group in overlapGroups.asMap().entries) {
        if (group.value.any((e) => event.overlapsWith(e))) {
          overlappingGroupIndices.add(group.key);
        }
      }

      if (overlappingGroupIndices.isEmpty) {
        // New group
        overlapGroups.add([event]);
        eventToGroup[event] = overlapGroups.length - 1;
      } else {
        // Merge all overlapping groups and add event
        final groupsToMerge = overlappingGroupIndices.toList()..sort();
        final firstGroupIndex = groupsToMerge.first;
        final firstGroup = overlapGroups[firstGroupIndex];
        firstGroup.add(event);
        eventToGroup[event] = firstGroupIndex;

        // Merge other groups into first group
        for (var i = groupsToMerge.length - 1; i > 0; i--) {
          final groupIndex = groupsToMerge[i];
          final groupToMerge = overlapGroups[groupIndex];
          firstGroup.addAll(groupToMerge);
          for (final e in groupToMerge) {
            eventToGroup[e] = firstGroupIndex;
          }
          overlapGroups.removeAt(groupIndex);
          // Update indices for remaining groups
          for (final entry in eventToGroup.entries) {
            if (entry.value > groupIndex) {
              eventToGroup[entry.key] = entry.value - 1;
            }
          }
        }
      }
    }

    return overlapGroups;
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
    final startMinutes =
        event.startDateTime.hour * 60 + event.startDateTime.minute;
    final endMinutes = event.endDateTime.hour * 60 + event.endDateTime.minute;
    final startPosition = (startMinutes / 60) * hourHeight;
    final height = ((endMinutes - startMinutes) / 60) * hourHeight;

    return Positioned(
      left: leftOffset + 2,
      top: startPosition,
      width: width - 4,
      height: height,
      child: _buildEventCard(
        event,
        isPreview: isPreview,
        isDraggingOriginal: isDraggingOriginal,
      ),
    );
  }

  Widget _buildEventCard(
    CalendarEvent event, {
    bool isPreview = false,
    bool isDraggingOriginal = false,
  }) {
    final isHovered = _hoveredEventId == event.id;
    final isSelected = _selectedEventId == event.id;

    final cardContent = MouseRegion(
      onEnter: (_) {
        if (isPreview) return;
        setState(() {
          _hoveredEventId = event.id;
        });
      },
      onExit: (_) {
        if (isPreview) return;
        setState(() {
          if (_hoveredEventId == event.id) {
            _hoveredEventId = null;
          }
        });
      },
      cursor: isDraggingOriginal
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (pointerEvent) {
          if (isPreview || _eventActionsPopoverEventId != null) return;
          if (_isHoveringResizeHandle || _resizingEventId != null) return;
          if (event.allDay) return;

          _isPointerDownOnEvent = true;
          // Detect touch vs mouse
          if (pointerEvent.kind == PointerDeviceKind.touch) {
            _isTouchInteraction = true;
          }

          if (pointerEvent.kind == PointerDeviceKind.mouse &&
              pointerEvent.buttons == kSecondaryMouseButton) {
            _showContextMenu(event, pointerEvent.position);
            return;
          }

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
          if (_pendingPointerEventId != event.id) return;
          if (_pointerDownGlobalPosition == null) return;

          final distance =
              (pointerEvent.position - _pointerDownGlobalPosition!).distance;
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
          if (_pendingPointerEventId != event.id) return;

          _isPointerDownOnEvent = false;
          final wasDragging = _isDraggingEvent && _draggedEventId == event.id;
          _pendingPointerEventId = null;
          _pointerDownGlobalPosition = null;

          if (wasDragging) {
            _finalizeEventDrag();
            return;
          }

          if (!_dragThresholdExceeded) {
            _showEventActionsPopover(event, pointerEvent.position);
          }
          _dragThresholdExceeded = false;
          _dragStartGlobalPosition = null;
          _dragStartTime = null;
          _draggedEventOriginal = null;
        },
        onPointerCancel: (_) {
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
        },
        child: GestureDetector(
          onLongPress: () {
            if (isPreview || _eventActionsPopoverEventId != null) return;
            if (_isTouchInteraction) {
              _showContextMenu(event, Offset.zero);
            }
          },
          child: IgnorePointer(
            ignoring: isPreview,
            child: Opacity(
              opacity: isDraggingOriginal ? 0.35 : 1,
              child: Container(
                decoration: BoxDecoration(
                  color: event.color.withOpacity(
                    isPreview ? 0.35 : (isHovered ? 0.25 : 0.15),
                  ),
                  border: Border(
                    left: BorderSide(
                      color: event.color,
                      width: isHovered || isSelected ? 4 : 3,
                    ),
                    top: isHovered || isSelected
                        ? BorderSide(
                            color: event.color.withOpacity(0.3),
                            width: 1,
                          )
                        : BorderSide.none,
                    bottom: isHovered || isSelected
                        ? BorderSide(
                            color: event.color.withOpacity(0.3),
                            width: 1,
                          )
                        : BorderSide.none,
                    right: isHovered || isSelected
                        ? BorderSide(
                            color: event.color.withOpacity(0.3),
                            width: 1,
                          )
                        : BorderSide.none,
                  ),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: isHovered || isSelected
                      ? [
                          BoxShadow(
                            color: event.color.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Resize handle (top) - with hover detection
                    if (!isPreview && event.durationMinutes >= 30)
                      MouseRegion(
                        onEnter: (_) {
                          setState(() {
                            _isHoveringResizeHandle = true;
                          });
                        },
                        onExit: (_) {
                          setState(() {
                            _isHoveringResizeHandle = false;
                          });
                        },
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: GestureDetector(
                          onPanStart: (details) {
                            setState(() {
                              _resizingEventId = event.id;
                              _resizingFromTop = true;
                              _resizeStartY = details.localPosition.dy;
                              _resizingEventOriginal = event;
                            });
                          },
                          onPanUpdate: (details) {
                            if (_resizingEventId == event.id &&
                                _resizingFromTop == true) {
                              _handleEventResize(details, event, true);
                            }
                          },
                          onPanEnd: (_) {
                            if (_resizingEventId != null) {
                              _finalizeEventResize();
                            }
                          },
                          child: Container(
                            height: 6,
                            color: Colors.transparent,
                            child: Center(
                              child: Container(
                                width: _isHoveringResizeHandle ? 30 : 20,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: event.color.withOpacity(
                                    _isHoveringResizeHandle ? 0.8 : 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(1.5),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Event content
                    Flexible(
                      child: Text(
                        event.title,
                        style: TextStyle(
                          color: event.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: null,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                    // Time display (if space allows)
                    if (!isPreview && event.durationMinutes >= 30)
                      Text(
                        '${DateFormat('h:mm').format(event.startDateTime)} - ${DateFormat('h:mm').format(event.endDateTime)}',
                        style: TextStyle(
                          color: event.color.withOpacity(0.8),
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    // Resize handle (bottom) - with hover detection
                    if (!isPreview)
                      MouseRegion(
                        onEnter: (_) {
                          setState(() {
                            _isHoveringResizeHandle = true;
                          });
                        },
                        onExit: (_) {
                          setState(() {
                            _isHoveringResizeHandle = false;
                          });
                        },
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: GestureDetector(
                          onPanStart: (details) {
                            setState(() {
                              _resizingEventId = event.id;
                              _resizingFromTop = false;
                              _resizeStartY = details.localPosition.dy;
                              _resizingEventOriginal = event;
                            });
                          },
                          onPanUpdate: (details) {
                            if (_resizingEventId == event.id &&
                                _resizingFromTop == false) {
                              _handleEventResize(details, event, false);
                            }
                          },
                          onPanEnd: (_) {
                            if (_resizingEventId != null) {
                              _finalizeEventResize();
                            }
                          },
                          child: Container(
                            height: 6,
                            color: Colors.transparent,
                            child: Center(
                              child: Container(
                                width: _isHoveringResizeHandle ? 30 : 20,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: event.color.withOpacity(
                                    _isHoveringResizeHandle ? 0.8 : 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(1.5),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
        _handleGridPointerDown(event.localPosition);
      },
      onPointerMove: (event) {
        _handleGridPointerMove(event.localPosition);
      },
      onPointerUp: (_) {
        _handleGridPointerUp();
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
    for (final event in _allDayEvents) {
      final rect = Rect.fromLTWH(2, 0, gridWidth - 4, 30);
      if (rect.contains(localPosition)) {
        return true;
      }
    }

    final groups = _groupOverlappingEvents(_timedEvents);
    for (final group in groups) {
      final groupWidth = gridWidth / group.length;
      for (final entry in group.asMap().entries) {
        final index = entry.key;
        final event = entry.value;

        const hourHeight = 60.0;
        final startMinutes =
            event.startDateTime.hour * 60 + event.startDateTime.minute;
        final endMinutes =
            event.endDateTime.hour * 60 + event.endDateTime.minute;
        final top = (startMinutes / 60) * hourHeight;
        final height = ((endMinutes - startMinutes) / 60) * hourHeight;

        final rect = Rect.fromLTWH(
          index * groupWidth + 2,
          top,
          groupWidth - 4,
          height,
        );
        if (rect.contains(localPosition)) {
          return true;
        }
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

  void _handleGridPointerDown(Offset localPosition) {
    if (_contextMenuPosition != null ||
        _eventActionsPopoverEventId != null ||
        _isPointerDownOnEvent ||
        _isDraggingEvent) {
      return;
    }
    if (_isPointerOverEvent(localPosition)) {
      return;
    }

    setState(() {
      _selectedEventId = null;
      _isPointerDownOnGrid = true;
      _gridPointerDownPosition = localPosition;
      _gridDragStartTime = _timeFromPosition(localPosition);
      _gridDragEndTime = _gridDragStartTime;
      _dragCreateStartPosition = localPosition;
    });
  }

  void _handleGridPointerMove(Offset localPosition) {
    if (!_isPointerDownOnGrid) return;

    final start = _gridPointerDownPosition;
    if (start == null) return;

    final distance = (localPosition - start).distance;
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

  void _handleGridPointerUp() {
    if (!_isPointerDownOnGrid) return;

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
    } else if (_gridDragStartTime != null) {
      final start = _gridDragStartTime!;
      final end = start.add(const Duration(minutes: 30));
      setState(() {
        _pendingCreateStartTime = start;
        _pendingCreateEndTime = end;
      });
      _showCreateEventModal(startTime: start, endTime: end);
      setState(() {
        _gridDragStartTime = null;
        _gridDragEndTime = null;
      });
    }

    setState(() {
      _selectedEventId = null;
      _isPointerDownOnGrid = false;
      _gridPointerDownPosition = null;
      _dragCreateStartPosition = null;
    });
  }

  void _handleGridPointerCancel() {
    setState(() {
      _isPointerDownOnGrid = false;
      _isDraggingToCreate = false;
      _gridPointerDownPosition = null;
      _gridDragStartTime = null;
      _gridDragEndTime = null;
      _dragCreateStartPosition = null;
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
      _dragCreateStartPosition = null;
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
      await _syncService.pushLocalChanges();
    } catch (e) {
      debugPrint('Error updating event: $e');
      if (originalEvent != null) {
        _eventsMap[originalEvent.id] = originalEvent;
        _updateEventLists();
      }
    }
  }

  void _handleEventResize(
    DragUpdateDetails details,
    CalendarEvent event,
    bool fromTop,
  ) {
    if (_resizeStartY == null) return;

    const hourHeight = 60.0;
    final deltaY = details.localPosition.dy - _resizeStartY!;
    final deltaMinutes = (deltaY / hourHeight) * 60;
    final snappedDelta = (deltaMinutes / 15).round() * 15;

    DateTime newStart = event.startDateTime;
    DateTime newEnd = event.endDateTime;

    if (fromTop) {
      newStart = event.startDateTime.add(Duration(minutes: snappedDelta));
      if (newStart.isAfter(newEnd.subtract(const Duration(minutes: 15)))) {
        newStart = newEnd.subtract(const Duration(minutes: 15));
      }
    } else {
      newEnd = event.endDateTime.add(Duration(minutes: snappedDelta));
      if (newEnd.isBefore(newStart.add(const Duration(minutes: 15)))) {
        newEnd = newStart.add(const Duration(minutes: 15));
      }
    }

    setState(() {
      if (_eventsMap.containsKey(event.id)) {
        _eventsMap[event.id] = event.copyWith(
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
    setState(() {
      _resizingEventId = null;
      _resizingFromTop = null;
      _resizeStartY = null;
      _resizingEventOriginal = null;
    });

    try {
      await _repository.updateEvent(event);
      await _syncService.pushLocalChanges();
    } catch (e) {
      debugPrint('Error resizing event: $e');
      // Revert on error
      if (_resizingEventOriginal != null) {
        _eventsMap[_resizingEventId!] = _resizingEventOriginal!;
        _updateEventLists();
      }
    }
  }

  Future<void> _showCreateEventModal({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => EventCreationModal(
        startTime: startTime,
        endTime: endTime,
        onEventCreated: () {},
      ),
    );

    if (!mounted) return;
    setState(() {
      _pendingCreateStartTime = null;
      _pendingCreateEndTime = null;
    });
  }

  FocusNode _getEventFocusNode(String eventId) {
    return _eventFocusNodes.putIfAbsent(eventId, () => FocusNode());
  }

  Future<void> _showEventActionsPopover(
    CalendarEvent event,
    Offset anchor,
  ) async {
    if (_eventActionsPopoverEventId != null) return;

    final returnFocusNode = _getEventFocusNode(event.id);
    setState(() {
      _eventActionsPopoverEventId = event.id;
      _selectedEventId = event.id;
    });

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 0),
      pageBuilder: (context, animation, secondaryAnimation) {
        return EventActionsPopover(
          anchor: anchor,
          onEdit: () {
            Navigator.of(context).pop();
            _showEditEventModal(event);
          },
          onDelete: () {
            Navigator.of(context).pop();
            _confirmAndDeleteEvent(event);
          },
          onDismiss: () {
            Navigator.of(context).pop();
          },
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _eventActionsPopoverEventId = null;
    });
    if (returnFocusNode.canRequestFocus) {
      returnFocusNode.requestFocus();
    }
  }

  Future<void> _showEditEventModal(CalendarEvent event) async {
    await showDialog(
      context: context,
      builder: (context) => EventEditModal(
        event: event,
        calendarId: _selectedCalendarId,
        onEventUpdated: () {},
      ),
    );
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
      await _syncService.pushLocalChanges();
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
    final scrollOffset =
        _dayGridScrollController.hasClients ? _dayGridScrollController.offset : 0.0;

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

    final isCompact = height < 32;

    return Positioned(
      left: 60,
      top: startPosition,
      right: 0,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: selectionColor.withOpacity(0.85),
          border: Border.all(color: selectionColor.withOpacity(0.95), width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isCompact) ...[
              Text(
                '(No title)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              '${DateFormat('h:mm a').format(startTime)} - ${DateFormat('h:mm a').format(endTime)}',
              style: TextStyle(
                color: textColor.withOpacity(isCompact ? 0.9 : 0.8),
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

  void _showEventDetails(CalendarEvent event) {
    showDialog(
      context: context,
      builder: (context) => EventDetailsPopover(
        event: event,
        onEventUpdated: () {},
        onEventDeleted: () {},
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settings'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Enable Keyboard Shortcuts'),
                  value: _keyboardShortcutsEnabled,
                  onChanged: (value) {
                    setState(() {
                      _keyboardShortcutsEnabled = value;
                    });
                    this.setState(() {
                      _keyboardShortcutsEnabled = value;
                    });
                  },
                ),
                if (widget.onSignOut != null)
                  ListTile(
                    title: const Text('Sign Out'),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onSignOut?.call();
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildScheduleView() {
    final sortedEvents = _eventsMap.values.toList()
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));

    return ListView.builder(
      itemCount: sortedEvents.length,
      itemBuilder: (context, index) {
        final event = sortedEvents[index];
        return ListTile(
          leading: Container(width: 4, color: event.color),
          title: Text(event.title),
          subtitle: Text(
            '${DateFormat('h:mm a').format(event.startDateTime)} - ${DateFormat('h:mm a').format(event.endDateTime)}',
          ),
          onTap: () => _showEventDetails(event),
        );
      },
    );
  }

  void _handleKeyboardShortcut(KeyEvent event) {
    if (!_keyboardShortcutsEnabled) return;

    if (event is KeyDownEvent) {
      final isModifierPressed =
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;

      // Create new event: 'C' or 'N' (Google Calendar style)
      if (event.logicalKey == LogicalKeyboardKey.keyC ||
          event.logicalKey == LogicalKeyboardKey.keyN) {
        if (isModifierPressed) {
          _showCreateEventModal();
        }
      }
      // Navigate next: Right arrow (Google Calendar style)
      else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (isModifierPressed) {
          _handleDateChange(_currentDate.add(const Duration(days: 1)));
        }
      }
      // Navigate previous: Left arrow (Google Calendar style)
      else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (isModifierPressed) {
          _handleDateChange(_currentDate.subtract(const Duration(days: 1)));
        }
      }
      // Today: 'T' (Google Calendar style)
      else if (event.logicalKey == LogicalKeyboardKey.keyT) {
        if (isModifierPressed) {
          _handleDateChange(DateTime.now());
        }
      }
    }
  }
}
