import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/timeline_zoom_controller.dart';

/// Blocks wheel/trackpad scroll while Ctrl (or Cmd) is held so modifier+scroll zooms only.
class TimelineZoomScrollPhysics extends ClampingScrollPhysics {
  const TimelineZoomScrollPhysics({super.parent});

  @override
  TimelineZoomScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return TimelineZoomScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        (Platform.isMacOS && keyboard.isMetaPressed)) {
      return 0.0;
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }
}

/// Scrollable timeline with premium focal-point zoom (pinch + Ctrl+wheel).
class TimelineZoomViewport extends StatefulWidget {
  const TimelineZoomViewport({
    super.key,
    required this.scrollController,
    required this.zoomController,
    required this.hourHeightListenable,
    required this.physics,
    required this.scrollBehavior,
    required this.timelineBuilder,
    this.enablePinchZoom = true,
    this.onTouchPinchZoomStateChanged,
  });

  final ScrollController scrollController;
  final TimelineZoomController zoomController;
  final ValueListenable<double> hourHeightListenable;
  final ScrollPhysics physics;
  final ScrollBehavior scrollBehavior;

  /// Builds the timeline body for a given [hourHeight] and total [gridHeight].
  final Widget Function(
    BuildContext context,
    double hourHeight,
    double gridHeight,
  )
  timelineBuilder;

  final bool enablePinchZoom;
  final ValueChanged<bool>? onTouchPinchZoomStateChanged;

  @override
  State<TimelineZoomViewport> createState() => _TimelineZoomViewportState();
}

class _TimelineZoomViewportState extends State<TimelineZoomViewport> {
  final GlobalKey _scrollSurfaceKey = GlobalKey();
  final Set<int> _activeTouchPointers = <int>{};
  bool _touchPinchZoomActive = false;

  bool get _isZoomModifierPressed {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isControlPressed ||
        (Platform.isMacOS && keyboard.isMetaPressed);
  }

  double _focalFromGlobal(Offset global) {
    return widget.zoomController.focalViewportYFromGlobal(
      global,
      _scrollSurfaceKey.currentContext,
    );
  }

  void _updateTouchPinchZoomState(bool active) {
    if (_touchPinchZoomActive == active) return;
    _touchPinchZoomActive = active;
    widget.onTouchPinchZoomStateChanged?.call(active);
    if (mounted) {
      setState(() {});
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _activeTouchPointers.add(event.pointer);
    if (_activeTouchPointers.length >= 2) {
      _updateTouchPinchZoomState(true);
    }
  }

  void _handlePointerUpOrCancel(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _activeTouchPointers.remove(event.pointer);
    if (_activeTouchPointers.length < 2) {
      _updateTouchPinchZoomState(false);
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _isZoomModifierPressed) {
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
      final delta = event.scrollDelta.dy;
      if (delta == 0) return;
      widget.zoomController.applyWheelDelta(
        scrollDeltaDy: delta,
        focalViewportY: _focalFromGlobal(event.position),
      );
      return;
    }

    if (event is PointerScaleEvent && _isZoomModifierPressed) {
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
      if (event.scale == 1.0) return;
      widget.zoomController.applyTrackpadScale(
        scaleDelta: event.scale - 1.0,
        focalViewportY: _focalFromGlobal(event.position),
      );
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (!widget.enablePinchZoom || details.pointerCount < 2) return;
    widget.zoomController.beginPinch(
      focalViewportY: _focalFromGlobal(details.focalPoint),
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!widget.enablePinchZoom || details.pointerCount < 2) return;
    widget.zoomController.updatePinch(
      scale: details.scale,
      focalViewportY: _focalFromGlobal(details.focalPoint),
    );
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!widget.enablePinchZoom) return;
    widget.zoomController.endPinch();
  }

  @override
  void dispose() {
    _activeTouchPointers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ScrollConfiguration(
          key: _scrollSurfaceKey,
          behavior: widget.scrollBehavior,
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) => false,
            child: ValueListenableBuilder<double>(
              valueListenable: widget.hourHeightListenable,
              builder: (context, hourHeight, _) {
                final gridHeight =
                    TimelineZoomController.hourCount * hourHeight;
                return CustomScrollView(
                  controller: widget.scrollController,
                  physics: _touchPinchZoomActive
                      ? const NeverScrollableScrollPhysics()
                      : widget.physics,
                  clipBehavior: Clip.hardEdge,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _handlePointerDown,
                        onPointerUp: _handlePointerUpOrCancel,
                        onPointerCancel: _handlePointerUpOrCancel,
                        child: GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: _onScaleEnd,
                          behavior: HitTestBehavior.translucent,
                          child: RepaintBoundary(
                            child: IgnorePointer(
                              ignoring: _touchPinchZoomActive,
                              child: widget.timelineBuilder(
                                context,
                                hourHeight,
                                gridHeight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerSignal: _handlePointerSignal,
            child: const IgnorePointer(child: SizedBox.expand()),
          ),
        ),
      ],
    );
  }
}
