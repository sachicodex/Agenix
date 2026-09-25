import 'dart:convert';
import 'dart:math' as math;

import 'package:agenix/widgets/Custom%20Input/custom_input.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:hugeicons/hugeicons.dart';
import 'package:reorderable_grid/reorderable_grid.dart';

import '../services/firebase_notes_service.dart';
import '../services/groq_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_popup.dart';
import '../widgets/form_fields.dart';
import '../widgets/Glass Card/glass_carrd.dart';
import '../widgets/expandable_action_fab.dart';
import '../widgets/Primary Button/primary_button.dart' as dialog_buttons;
import 'calendar_day_view_screen.dart';

enum _NotesSection { notes, pinned, archive, trash }

class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    this.autoOpenComposer = false,
    this.onComposerClosed,
    this.editorOnly = false,
  });

  static const routeName = '/notes';
  final bool autoOpenComposer;
  final VoidCallback? onComposerClosed;
  final bool editorOnly;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final FirebaseNotesService _notesService = FirebaseNotesService();
  final GroqService _groqService = GroqService();
  final TextEditingController _searchController = TextEditingController();
  User? _user;
  Stream<List<FirebaseNote>>? _notesStream;
  final _NotesSection _section = _NotesSection.notes;
  String _query = '';
  List<String> _localOrderIds = <String>[];
  bool _isFabExpanded = false;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      _notesStream = _notesService.streamNotes(_user!.uid);
    }
    _searchController.addListener(() {
      if (mounted) setState(() => _query = _searchController.text.trim());
    });
    if (widget.autoOpenComposer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openEditor().then((_) {
            if (mounted) widget.onComposerClosed?.call();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openEditor({
    FirebaseNote? note,
    bool checklistMode = false,
  }) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(text: note?.content ?? '');
    var noteType = note?.noteType ?? (checklistMode ? 'checklist' : 'text');
    var colorValue = note?.colorValue ?? 0xFF1A1A1A;
    var pinned = note?.pinned ?? false;
    var archived = note?.archived ?? false;
    var trashed = note?.trashed ?? false;
    var aiLoading = false;
    var checklist = note?.checklist.toList() ?? <FirebaseChecklistItem>[];
    final checklistControllers = <TextEditingController>[];

    void syncControllers() {
      while (checklistControllers.length < checklist.length) {
        checklistControllers.add(
          TextEditingController(
            text: checklist[checklistControllers.length].text,
          ),
        );
      }
      while (checklistControllers.length > checklist.length) {
        checklistControllers.removeLast().dispose();
      }
    }

    syncControllers();
    if (noteType == 'checklist' && checklist.isEmpty) {
      checklist.add(const FirebaseChecklistItem(text: '', checked: false));
      checklistControllers.add(TextEditingController());
    }
    try {
      final saved = await showAppDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.58),
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final isChecklist = noteType == 'checklist';
            final dialogHeight = (MediaQuery.sizeOf(context).height - 48)
                .clamp(380.0, 560.0)
                .toDouble();
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: GlassCard(
                width: appPopupWidth(context, 680),
                height: dialogHeight,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                borderRadius: BorderRadius.circular(26),
                tintColor: Color(colorValue),
                tintOpacity: 0.075,
                borderOpacity: 0.16,
                blurSigma: 22,
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: isChecklist
                              ? Column(
                                  children: [
                                    for (
                                      var index = 0;
                                      index < checklist.length;
                                      index++
                                    ) ...[
                                      if (index > 0) const SizedBox(height: 8),
                                      _ChecklistEditorRow(
                                        item: checklist[index],
                                        controller: checklistControllers[index],
                                        onChanged: (value) => setDialogState(
                                          () {
                                            checklist[index] =
                                                FirebaseChecklistItem(
                                                  text: value,
                                                  checked:
                                                      checklist[index].checked,
                                                );
                                          },
                                        ),
                                        onChecked: (value) =>
                                            setDialogState(() {
                                              checklist[index] =
                                                  FirebaseChecklistItem(
                                                    text: checklist[index].text,
                                                    checked: value,
                                                  );
                                            }),
                                        onDelete: () => setDialogState(() {
                                          checklist.removeAt(index);
                                          checklistControllers
                                              .removeAt(index)
                                              .dispose();
                                        }),
                                      ),
                                    ],
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 42,
                                        top: 8,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          onPressed: () => setDialogState(() {
                                            checklist.add(
                                              const FirebaseChecklistItem(
                                                text: '',
                                                checked: false,
                                              ),
                                            );
                                            checklistControllers.add(
                                              TextEditingController(),
                                            );
                                          }),
                                          icon: const Icon(
                                            Icons.add_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Add list item'),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ExpandableDescription(
                                  controller: contentController,
                                  hint: 'Take a note...',
                                  minLines: 5,
                                  maxLines: 14,
                                  editorHeight: (dialogHeight - 150)
                                      .clamp(180.0, 390.0)
                                      .toDouble(),
                                  initiallyExpanded: true,
                                  backgroundColor: Colors.transparent,
                                  aiLoading: aiLoading,
                                  onAIClick: () async {
                                    setDialogState(() => aiLoading = true);
                                    try {
                                      final improved = await _groqService
                                          .optimizeNote(
                                            plainDescriptionText(
                                              contentController.text,
                                            ),
                                          );
                                      contentController.text = improved;
                                    } catch (error) {
                                      if (mounted) {
                                        showAppSnackBar(
                                          this.context,
                                          'Could not improve note: $error',
                                        );
                                      }
                                    } finally {
                                      if (dialogContext.mounted) {
                                        setDialogState(() => aiLoading = false);
                                      }
                                    }
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 58,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Row(
                          children: [
                            _EditorActionButton(
                              icon: HugeIcon(
                                icon: pinned
                                    ? HugeIcons.strokeRoundedPin
                                    : HugeIcons.strokeRoundedPinOff,
                                size: 22,
                                color: pinned
                                    ? AppColors.primary
                                    : AppColors.onSurface,
                              ),
                              onPressed: () {
                                if (note == null) {
                                  setDialogState(() => pinned = !pinned);
                                } else {
                                  pinned = !pinned;
                                  Navigator.pop(dialogContext, true);
                                }
                              },
                            ),
                            if (note == null)
                              _EditorActionButton(
                                icon: HugeIcon(
                                  icon: isChecklist
                                      ? HugeIcons.strokeRoundedNote
                                      : HugeIcons.strokeRoundedCheckList,
                                  size: 22,
                                ),
                                onPressed: () => setDialogState(() {
                                  noteType = isChecklist ? 'text' : 'checklist';
                                  if (noteType == 'checklist' &&
                                      checklist.isEmpty) {
                                    checklist.add(
                                      const FirebaseChecklistItem(
                                        text: '',
                                        checked: false,
                                      ),
                                    );
                                    checklistControllers.add(
                                      TextEditingController(),
                                    );
                                  }
                                }),
                              ),
                            if (note != null)
                              _EditorActionButton(
                                icon: const HugeIcon(
                                  icon: HugeIcons.strokeRoundedTrash,
                                  size: 22,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () {
                                  trashed = true;
                                  Navigator.pop(dialogContext, true);
                                },
                              ),
                            const Spacer(),
                            dialog_buttons.PrimaryButton(
                              label: 'Done',
                              height: 42,
                              width: 108,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );

      if (saved != true || !mounted) return;
      final cleanedChecklist = checklist
          .map(
            (item) => FirebaseChecklistItem(
              text: item.text.trim(),
              checked: item.checked,
            ),
          )
          .where((item) => item.text.isNotEmpty)
          .toList(growable: false);
      final contentTitle = plainDescriptionText(contentController.text)
          .trim()
          .split('\n')
          .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
      final generatedTitle = titleController.text.trim().isNotEmpty
          ? titleController.text.trim()
          : (contentTitle.length > 72
                ? '${contentTitle.substring(0, 72).trim()}…'
                : contentTitle);
      if (note == null) {
        await _notesService.createNote(
          title: generatedTitle,
          content: contentController.text,
          noteType: noteType,
          checklist: cleanedChecklist,
          colorValue: colorValue,
          pinned: pinned,
          archived: archived,
          trashed: trashed,
        );
      } else {
        await _notesService.updateNote(
          noteId: note.id,
          title: generatedTitle,
          content: contentController.text,
          noteType: noteType,
          checklist: cleanedChecklist,
          colorValue: colorValue,
          pinned: pinned,
          archived: archived,
          trashed: trashed,
          labels: note.labels,
          order: note.order,
        );
      }
    } catch (error) {
      if (mounted) showAppSnackBar(context, 'Could not save note: $error');
    } finally {
      titleController.dispose();
      contentController.dispose();
      for (final controller in checklistControllers) {
        controller.dispose();
      }
    }
  }

  List<FirebaseNote> _filterNotes(List<FirebaseNote> notes) {
    return notes
        .where((note) {
          final hasContent =
              note.title.trim().isNotEmpty ||
              plainDescriptionText(note.content).trim().isNotEmpty ||
              note.checklist.any((item) => item.text.trim().isNotEmpty);
          if (!hasContent) return false;
          final sectionMatches = switch (_section) {
            _NotesSection.notes => !note.archived && !note.trashed,
            _NotesSection.pinned =>
              note.pinned && !note.archived && !note.trashed,
            _NotesSection.archive => note.archived && !note.trashed,
            _NotesSection.trash => note.trashed,
          };
          if (!sectionMatches) return false;
          if (_query.isEmpty) return true;
          return '${note.title} ${plainDescriptionText(note.content)}'
              .toLowerCase()
              .contains(_query.toLowerCase());
        })
        .toList(growable: false);
  }

  double _cardWidth(FirebaseNote note) {
    final content = note.noteType == 'checklist'
        ? note.checklist.map((item) => item.text).join('\n')
        : plainDescriptionText(note.content);
    final longestLine = content
        .split('\n')
        .fold<int>(
          0,
          (length, line) => line.length > length ? line.length : length,
        );
    return (150 + longestLine * 7.2).clamp(190.0, 430.0).toDouble();
  }

  double _estimatedCardHeight(FirebaseNote note, double width) {
    const verticalPadding = 28.0;
    var contentHeight = 0.0;

    if (note.noteType == 'checklist') {
      final visibleItems = note.checklist.take(6);
      for (final item in visibleItems) {
        final painter = TextPainter(
          text: TextSpan(text: item.text, style: const TextStyle(fontSize: 16)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(1, width - 64));
        contentHeight += math.max(18, painter.height) + 6;
      }
    } else {
      final richLines = _previewLines(note.content);
      if (richLines != null) {
        for (final line in richLines) {
          final markerWidth = line.listType == null ? 0.0 : 24.0;
          final lineWidth = math
              .max(1, width - 30 - (line.indent * 18) - markerWidth)
              .toDouble();
          final painter = TextPainter(
            text: TextSpan(
              style: const TextStyle(fontSize: 16, height: 1.42),
              children: line.spans,
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: lineWidth);
          contentHeight += math.max(22.72, painter.height) + 5;
        }
      } else {
        final painter = TextPainter(
          text: TextSpan(
            text: plainDescriptionText(note.content).trim(),
            style: const TextStyle(fontSize: 16, height: 1.42),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(1, width - 30));
        contentHeight = painter.height;
      }
    }

    // Keep a small safety margin for font fallback and platform text metrics.
    return math.max(56, contentHeight + verticalPadding + 12);
  }

  List<FirebaseNote> _applyLocalOrder(List<FirebaseNote> notes) {
    final ordered = <FirebaseNote>[];
    if (_localOrderIds.isEmpty) {
      ordered.addAll(notes);
    } else {
      final byId = {for (final note in notes) note.id: note};
      for (final id in _localOrderIds) {
        final note = byId.remove(id);
        if (note != null) ordered.add(note);
      }
      ordered.addAll(byId.values);
    }
    if (_section != _NotesSection.notes) return ordered;
    return [
      ...ordered.where((note) => note.pinned),
      ...ordered.where((note) => !note.pinned),
    ];
  }

  Future<void> _onReorder(
    List<FirebaseNote> notes,
    int oldIndex,
    int newIndex,
  ) async {
    final pinnedCount = _section == _NotesSection.notes
        ? notes.where((note) => note.pinned).length
        : 0;
    if (oldIndex < pinnedCount) return;

    final destination = newIndex.clamp(pinnedCount, notes.length - 1);
    if (oldIndex == destination) return;

    final reordered = List<FirebaseNote>.of(notes);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(destination, moved);
    final order = reordered.map((note) => note.id).toList(growable: false);

    setState(() => _localOrderIds = order);
    try {
      await _notesService.updateNoteOrder(order);
    } catch (error) {
      if (!mounted) return;
      setState(() => _localOrderIds = notes.map((note) => note.id).toList());
      showAppSnackBar(context, 'Could not save note order: $error');
    }
  }

  Widget _buildCard(
    FirebaseNote note, {
    double? width,
    bool showBorder = true,
  }) {
    final isChecklist = note.noteType == 'checklist';
    return GestureDetector(
      onDoubleTap: () => _openEditor(note: note),
      child: Container(
        width: width ?? _cardWidth(note),
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
        decoration: BoxDecoration(
          color: Color(note.colorValue).withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(16),
          border: showBorder
              ? Border.all(color: AppColors.onSurface.withValues(alpha: 0.2))
              : null,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isChecklist)
              ...note.checklist
                  .take(6)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            item.checked
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                decoration: item.checked
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
            else
              _RichNotePreview(value: note.content),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesTopBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Open calendar',
            icon: const Icon(Icons.calendar_month_rounded, size: 20),
            onPressed: () =>
                Navigator.pushReplacementNamed(context, '/calendar'),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Agenix Notes',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildReorderableNotes(List<FirebaseNote> notes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final usableWidth = constraints.maxWidth - 32;
        final columns = (usableWidth / 330).floor().clamp(1, 5);
        final tileWidth = (usableWidth - ((columns - 1) * 14)) / columns;
        final columnHeights = List<double>.filled(columns, 0);
        final geometries = <SliverGridGeometry>[];
        for (final note in notes) {
          var column = 0;
          for (var index = 1; index < columns; index++) {
            if (columnHeights[index] < columnHeights[column]) {
              column = index;
            }
          }
          final height = _estimatedCardHeight(note, tileWidth);
          geometries.add(
            SliverGridGeometry(
              scrollOffset: columnHeights[column],
              crossAxisOffset: column * (tileWidth + 14),
              mainAxisExtent: height,
              crossAxisExtent: tileWidth,
            ),
          );
          columnHeights[column] += height + 14;
        }
        final contentExtent = columnHeights.isEmpty
            ? 0.0
            : columnHeights.reduce(math.max) - 14;

        return ReorderableGridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
          gridDelegate: _AdaptiveNoteGridDelegate(
            geometries: geometries,
            contentExtent: contentExtent,
          ),
          itemCount: notes.length,
          onReorder: (oldIndex, newIndex) =>
              _onReorder(notes, oldIndex, newIndex),
          itemDragEnable: (index) => !notes[index].pinned,
          buildDefaultDragHandles: false,
          itemBuilder: (context, index) => KeyedSubtree(
            key: ValueKey(notes[index].id),
            child: ReorderableGridDelayedDragStartListener(
              index: index,
              enabled: !notes[index].pinned,
              child: Align(
                alignment: Alignment.topLeft,
                child: _buildCard(notes[index], width: tileWidth),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSimpleNotesContent(
    BuildContext context,
    List<FirebaseNote> notes,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: CustomInput(
              controller: _searchController,
              prefixIcon: HugeIcon(
                icon: HugeIcons.strokeRoundedSearch01,
                strokeWidth: 2,
              ),
              hintText: 'Find your notes...',
            ),
          ),
        ),
        Expanded(
          child: notes.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty
                        ? 'No notes yet. Tap + to create one.'
                        : 'No notes match “$_query”.',
                    style: const TextStyle(color: AppColors.onTertiary),
                  ),
                )
              : _buildReorderableNotes(notes),
        ),
      ],
    );
  }

  Widget _buildExpandableFab() {
    return ExpandableActionFab(
      expanded: _isFabExpanded,
      onToggle: () => setState(() => _isFabExpanded = !_isFabExpanded),
      actions: [
        ExpandableFabAction(
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedNote, size: 26),
          onPressed: () async {
            setState(() => _isFabExpanded = false);
            await _openEditor();
          },
        ),
        ExpandableFabAction(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedCalendar01,
            size: 26,
          ),
          onPressed: () {
            setState(() => _isFabExpanded = false);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    const CalendarDayViewScreen(autoOpenCreateEvent: true),
              ),
            );
          },
        ),
      ],
    );
    /*
          children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            right: 0,
            bottom: _isFabExpanded ? 160 : 4,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _isFabExpanded ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_isFabExpanded,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      setState(() => _isFabExpanded = false);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const CalendarDayViewScreen(
                            autoOpenCreateEvent: true,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.glassBorder,
                          width: 2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Tooltip(
                          message: 'New event',
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedCalendar01,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            right: 0,
            bottom: _isFabExpanded ? 80 : 4,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _isFabExpanded ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_isFabExpanded,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () async {
                      setState(() => _isFabExpanded = false);
                      await _openEditor();
                    },
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.glassBorder,
                          width: 2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Tooltip(
                          message: 'New note',
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedNote,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SizedBox(
              width: 68,
              height: 68,
              child: FloatingActionButton(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                onPressed: () =>
                    setState(() => _isFabExpanded = !_isFabExpanded),
                child: AnimatedRotation(
                  turns: _isFabExpanded ? 0.125 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(Icons.add_rounded, size: 34),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    */
  }

  @override
  Widget build(BuildContext context) {
    if (widget.editorOnly) return const SizedBox(width: 1, height: 1);
    final user = _user;
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: _buildExpandableFab(),
      body: Column(
        children: [
          _buildNotesTopBar(),
          Expanded(
            child: user == null
                ? const Center(child: Text('Sign in to view your notes.'))
                : StreamBuilder<List<FirebaseNote>>(
                    stream: _notesStream!,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Could not load notes: ${snapshot.error}',
                          ),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final notes = _applyLocalOrder(
                        _filterNotes(snapshot.data ?? const <FirebaseNote>[]),
                      );
                      return _buildSimpleNotesContent(context, notes);
                      /* return LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 920;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (wide)
                                Container(
                                  width: 220,
                                  decoration: const BoxDecoration(
                                    color: AppColors.card,
                                    border: Border(
                                      right: BorderSide(
                                        color: AppColors.borderColor,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 12,
                                      right: 10,
                                    ),
                                    child: Column(
                                      children: [
                                        _sectionButton(
                                          icon: Icons.lightbulb_outline_rounded,
                                          label: 'Notes',
                                          value: _NotesSection.notes,
                                        ),
                                        _sectionButton(
                                          icon: Icons.push_pin_outlined,
                                          label: 'Pinned',
                                          value: _NotesSection.pinned,
                                        ),
                                        _sectionButton(
                                          icon: Icons.archive_outlined,
                                          label: 'Archive',
                                          value: _NotesSection.archive,
                                        ),
                                        _sectionButton(
                                          icon: Icons.delete_outline_rounded,
                                          label: 'Trash',
                                          value: _NotesSection.trash,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        4,
                                        16,
                                        22,
                                      ),
                                      child: Column(
                                        children: [
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 900,
                                            ),
                                            child: TextField(
                                              controller: _searchController,
                                              decoration: InputDecoration(
                                                hintText: 'Search your notes',
                                                prefixIcon: const Icon(
                                                  Icons.search_rounded,
                                                ),
                                                suffixIcon: _query.isEmpty
                                                    ? null
                                                    : IconButton(
                                                        icon: const Icon(
                                                          Icons.clear_rounded,
                                                        ),
                                                        onPressed:
                                                            _searchController
                                                                .clear,
                                                      ),
                                                filled: true,
                                                fillColor: AppColors.surface,
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  borderSide: BorderSide.none,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          _buildComposer(),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: notes.isEmpty
                                          ? Center(
                                              child: Text(
                                                _query.isEmpty
                                                    ? 'No notes here yet. Start with “Take a note...”'
                                                    : 'No notes match “$_query”.',
                                                style: const TextStyle(
                                                  color: AppColors.onTertiary,
                                                ),
                                              ),
                                            )
                                          : SingleChildScrollView(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    16,
                                                    0,
                                                    16,
                                                    28,
                                                  ),
                                              child: Wrap(
                                                spacing: 14,
                                                runSpacing: 14,
                                                children: notes
                                                    .map(
                                                      (note) => KeyedSubtree(
                                                        key: ValueKey(note.id),
                                                        child: _buildCard(note),
                                                      ),
                                                    )
                                                    .toList(),
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ); */
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MasonryReorderableGrid extends StatefulWidget {
  const _MasonryReorderableGrid({
    required this.notes,
    required this.itemHeightBuilder,
    required this.itemBuilder,
    required this.canDrag,
    required this.onReorder,
  });

  final List<FirebaseNote> notes;
  final double Function(FirebaseNote note, double width) itemHeightBuilder;
  final Widget Function(FirebaseNote note, double width) itemBuilder;
  final bool Function(FirebaseNote note) canDrag;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;

  @override
  State<_MasonryReorderableGrid> createState() =>
      _MasonryReorderableGridState();
}

class _MasonryReorderableGridState extends State<_MasonryReorderableGrid> {
  List<FirebaseNote>? _previewNotes;
  String? _draggingId;

  List<FirebaseNote> get _visibleNotes => _previewNotes ?? widget.notes;

  @override
  void didUpdateWidget(covariant _MasonryReorderableGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_draggingId == null) {
      _previewNotes = null;
    }
  }

  void _startDrag(String id) {
    if (!mounted) return;
    setState(() {
      _draggingId = id;
      _previewNotes = List<FirebaseNote>.of(widget.notes);
    });
  }

  bool _moveBefore(String targetId, String draggedId) {
    if (_draggingId != draggedId || targetId == draggedId) return false;
    final current = List<FirebaseNote>.of(_visibleNotes);
    final from = current.indexWhere((note) => note.id == draggedId);
    final target = current.indexWhere((note) => note.id == targetId);
    if (from < 0 || target < 0) return false;
    if (!widget.canDrag(current[from]) || !widget.canDrag(current[target])) {
      return false;
    }

    final pinnedCount = current.where((note) => !widget.canDrag(note)).length;
    if (from < pinnedCount || target < pinnedCount) return false;

    final moved = current.removeAt(from);
    final insertion = target > from ? target - 1 : target;
    current.insert(insertion, moved);
    if (current.map((note) => note.id).join('|') ==
        _visibleNotes.map((note) => note.id).join('|')) {
      return true;
    }
    setState(() => _previewNotes = current);
    return true;
  }

  void _moveToEnd(String draggedId) {
    if (_draggingId != draggedId) return;
    final current = List<FirebaseNote>.of(_visibleNotes);
    final from = current.indexWhere((note) => note.id == draggedId);
    if (from < 0 || !widget.canDrag(current[from])) return;
    final pinnedCount = current.where((note) => !widget.canDrag(note)).length;
    if (from < pinnedCount) return;
    final moved = current.removeAt(from);
    current.add(moved);
    setState(() => _previewNotes = current);
  }

  Future<void> _finishDrag(bool wasAccepted) async {
    final draggedId = _draggingId;
    final preview = _previewNotes;
    final original = widget.notes;
    if (draggedId == null) return;

    setState(() {
      _draggingId = null;
      _previewNotes = null;
    });

    if (!wasAccepted || preview == null) return;
    final oldIndex = original.indexWhere((note) => note.id == draggedId);
    final newIndex = preview.indexWhere((note) => note.id == draggedId);
    if (oldIndex >= 0 && newIndex >= 0 && oldIndex != newIndex) {
      await widget.onReorder(oldIndex, newIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final usableWidth = constraints.maxWidth - 32;
        final columns = (usableWidth / 330).floor().clamp(1, 5);
        final tileWidth = (usableWidth - ((columns - 1) * 14)) / columns;
        final columnHeights = List<double>.filled(columns, 0);
        final positions = <_MasonryPosition>[];
        for (final note in _visibleNotes) {
          var column = 0;
          for (var index = 1; index < columns; index++) {
            if (columnHeights[index] < columnHeights[column]) {
              column = index;
            }
          }
          final height = widget.itemHeightBuilder(note, tileWidth);
          positions.add(
            _MasonryPosition(
              left: 16 + column * (tileWidth + 14),
              top: columnHeights[column],
              width: tileWidth,
              height: height,
            ),
          );
          columnHeights[column] += height + 14;
        }
        final contentHeight = columnHeights.isEmpty
            ? 0.0
            : columnHeights.reduce(math.max);

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 90),
          child: SizedBox(
            height: math.max(0, contentHeight - 14),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var index = 0; index < _visibleNotes.length; index++)
                  _buildPositionedCard(
                    note: _visibleNotes[index],
                    position: positions[index],
                  ),
                Positioned(
                  left: 16,
                  top: math.max(0, contentHeight - 14),
                  width: usableWidth,
                  height: 42,
                  child: DragTarget<String>(
                    onWillAcceptWithDetails: (details) {
                      _moveToEnd(details.data);
                      return true;
                    },
                    builder: (context, candidate, rejected) => const SizedBox(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPositionedCard({
    required FirebaseNote note,
    required _MasonryPosition position,
  }) {
    final card = KeyedSubtree(
      key: ValueKey(note.id),
      child: widget.itemBuilder(note, position.width),
    );
    final draggable = LongPressDraggable<String>(
      data: note.id,
      maxSimultaneousDrags: widget.canDrag(note) ? 1 : 0,
      onDragStarted: () => _startDrag(note.id),
      onDragEnd: (details) => _finishDrag(details.wasAccepted),
      feedback: Material(
        color: Colors.transparent,
        elevation: 10,
        child: SizedBox(
          width: position.width,
          child: widget.itemBuilder(note, position.width),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.08, child: card),
      child: card,
    );
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: position.left,
      top: position.top,
      width: position.width,
      height: position.height,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) {
          if (details.data == note.id) return false;
          return _moveBefore(note.id, details.data);
        },
        builder: (context, candidate, rejected) => draggable,
      ),
    );
  }
}

class _MasonryPosition {
  const _MasonryPosition({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

class _AdaptiveNoteGridDelegate extends SliverGridDelegate {
  const _AdaptiveNoteGridDelegate({
    required this.geometries,
    required this.contentExtent,
  });

  final List<SliverGridGeometry> geometries;
  final double contentExtent;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    return _AdaptiveNoteGridLayout(
      geometries: geometries,
      contentExtent: contentExtent,
    );
  }

  @override
  bool shouldRelayout(covariant _AdaptiveNoteGridDelegate oldDelegate) {
    return contentExtent != oldDelegate.contentExtent ||
        !listEquals(geometries, oldDelegate.geometries);
  }
}

class _AdaptiveNoteGridLayout extends SliverGridLayout {
  const _AdaptiveNoteGridLayout({
    required this.geometries,
    required this.contentExtent,
  });

  final List<SliverGridGeometry> geometries;
  final double contentExtent;

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    var first = geometries.length;
    for (var index = 0; index < geometries.length; index++) {
      if (geometries[index].trailingScrollOffset >= scrollOffset) {
        first = math.min(first, index);
      }
    }
    return first == geometries.length ? 0 : first;
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    var last = -1;
    for (var index = 0; index < geometries.length; index++) {
      if (geometries[index].scrollOffset <= scrollOffset) {
        last = math.max(last, index);
      }
    }
    return last < 0 ? 0 : last;
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    return geometries[index];
  }

  @override
  double computeMaxScrollOffset(int childCount) => contentExtent;
}

class _EditorActionButton extends StatelessWidget {
  const _EditorActionButton({required this.icon, required this.onPressed});

  final Widget icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      icon: icon,
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(minWidth: 46, minHeight: 46),
      splashRadius: 22,
    );
    return button;
  }
}

class _ChecklistEditorRow extends StatelessWidget {
  const _ChecklistEditorRow({
    required this.item,
    required this.controller,
    required this.onChanged,
    required this.onChecked,
    required this.onDelete,
  });

  final FirebaseChecklistItem item;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onChecked;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Checkbox(
              value: item.checked,
              onChanged: (value) => onChecked(value ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'List item',
                filled: true,
                fillColor: AppColors.surface.withValues(alpha: 0.32),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.glassBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 38,
            child: IconButton(
              tooltip: 'Remove item',
              icon: const Icon(Icons.close_rounded, size: 19),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              splashRadius: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _RichNotePreview extends StatelessWidget {
  const _RichNotePreview({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final lines = _previewLines(value);
    if (lines == null) {
      return Text(
        plainDescriptionText(value).trim(),
        style: const TextStyle(fontSize: 16, height: 1.42),
      );
    }

    var orderedIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Padding(
              padding: EdgeInsets.only(left: line.indent * 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (line.listType != null)
                    SizedBox(
                      width: 24,
                      child: Text(
                        line.listType == 'ordered' ? '${++orderedIndex}.' : '•',
                        style: const TextStyle(fontSize: 16, height: 1.42),
                      ),
                    )
                  else
                    const SizedBox(width: 0),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 16, height: 1.42),
                        children: line.spans,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PreviewLine {
  const _PreviewLine({required this.spans, this.listType, this.indent = 0});

  final List<TextSpan> spans;
  final String? listType;
  final int indent;
}

List<_PreviewLine>? _previewLines(String value) {
  if (!value.startsWith('quill:')) return null;
  try {
    final document = quill.Document.fromJson(
      jsonDecode(value.substring(6)) as List,
    );
    final lines = <_PreviewLine>[];
    var spans = <TextSpan>[];

    void finishLine(Map<String, dynamic> attributes) {
      if (spans.isEmpty && lines.isNotEmpty) return;
      final list = attributes['list']?.toString();
      final rawIndent = attributes['indent'];
      final indent = rawIndent is num ? rawIndent.toInt() : 0;
      lines.add(
        _PreviewLine(
          spans: List<TextSpan>.of(spans),
          listType: list,
          indent: indent,
        ),
      );
      spans = <TextSpan>[];
    }

    for (final rawOp in document.toDelta().toJson()) {
      final op = Map<String, dynamic>.from(rawOp as Map);
      final insert = op['insert'];
      final attributes = op['attributes'] is Map
          ? Map<String, dynamic>.from(op['attributes'] as Map)
          : const <String, dynamic>{};
      if (insert is! String) continue;

      final chunks = insert.split('\n');
      for (var index = 0; index < chunks.length; index++) {
        if (chunks[index].isNotEmpty) {
          spans.add(
            TextSpan(text: chunks[index], style: _previewTextStyle(attributes)),
          );
        }
        if (index < chunks.length - 1) finishLine(attributes);
      }
    }
    if (spans.isNotEmpty) finishLine(const <String, dynamic>{});
    return lines;
  } catch (_) {
    return null;
  }
}

TextStyle _previewTextStyle(Map<String, dynamic> attributes) {
  final header = attributes['header'];
  final headerSize = switch (header) {
    1 => 28.0,
    2 => 24.0,
    3 => 20.0,
    _ => null,
  };
  final rawSize = attributes['size'];
  final size =
      headerSize ??
      switch (rawSize) {
        'small' => 14.0,
        'large' => 18.0,
        'huge' => 24.0,
        num value => value.toDouble(),
        String value => double.tryParse(value),
        _ => null,
      };
  return TextStyle(
    fontSize: size,
    fontWeight: attributes['bold'] == true || headerSize != null
        ? FontWeight.w700
        : null,
    fontStyle: attributes['italic'] == true ? FontStyle.italic : null,
    decoration: attributes['underline'] == true
        ? TextDecoration.underline
        : null,
  );
}
