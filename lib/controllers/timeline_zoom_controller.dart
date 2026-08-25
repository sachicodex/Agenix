import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

/// Google Calendar–style vertical timeline zoom: focal anchoring, scroll
/// compensation, and physics-smoothed hour-height interpolation.
class TimelineZoomController {
  TimelineZoomController({
    required this.scrollController,
    required TickerProvider vsync,
    double initialHourHeight = defaultHourHeight,
    this.minHourHeight = minHourHeightDefault,
    this.maxHourHeight = maxHourHeightDefault,
    this.wheelZoomSensitivity = wheelZoomSensitivityDefault,
    this.interpolationSpeed = interpolationSpeedDefault,
  }) : hourHeight = ValueNotifier(initialHourHeight),
       _targetHourHeight = initialHourHeight,
       _smoothedHourHeight = initialHourHeight {
    _ticker = vsync.createTicker(_onTick);
  }

  static const double defaultHourHeight = 60;
  static const double minHourHeightDefault = 30;
  static const double maxHourHeightDefault = 180;
  static const double wheelZoomSensitivityDefault = 0.0016;
  static const double interpolationSpeedDefault = 18;
  static const int hourCount = 24;

  final ScrollController scrollController;
  final double minHourHeight;
  final double maxHourHeight;
  final double wheelZoomSensitivity;
  final double interpolationSpeed;

  final ValueNotifier<double> hourHeight;

  late Ticker _ticker;

  double _targetHourHeight;
  double _smoothedHourHeight;
  bool _tickerActive = false;

  bool _pinchActive = false;
  double? _pinchBaselineHourHeight;
  double? _focalViewportY;

  Timer? _wheelSessionTimer;
  bool _wheelSessionActive = false;

  /// Viewport-local Y of the zoom focal point (updated per wheel tick; locked for pinch).
  double? get focalViewportY => _focalViewportY;

  bool get isZooming => _pinchActive || _wheelSessionActive || _isInterpolating;

  bool get _isInterpolating =>
      (_smoothedHourHeight - _targetHourHeight).abs() > 0.05;

  double get targetHourHeight => _targetHourHeight;

  void dispose() {
    _ticker.dispose();
    _wheelSessionTimer?.cancel();
    hourHeight.dispose();
  }

  /// Resolves viewport-local Y from a global pointer position on the scroll view.
  double focalViewportYFromGlobal(
    Offset globalPosition,
    BuildContext? context,
  ) {
    if (context == null) return 0;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return 0;
    return renderBox.globalToLocal(globalPosition).dy;
  }

  void _lockFocal(double focalY) {
    _focalViewportY = focalY;
  }

  void _releaseFocalAfterDelay() {
    _wheelSessionTimer?.cancel();
    _wheelSessionTimer = Timer(const Duration(milliseconds: 180), () {
      if (_pinchActive) return;
      _wheelSessionActive = false;
      _focalViewportY = null;
    });
  }

  /// Focal-anchored scroll compensation:
  /// `newOffset = (oldOffset + focalY) * scaleRatio - focalY`
  void _applyHourHeightImmediate(double newHeight, {double? focalY}) {
    final oldHeight = _smoothedHourHeight;
    if ((newHeight - oldHeight).abs() < 0.001) return;

    final clamped = newHeight.clamp(minHourHeight, maxHourHeight);
    final focal = focalY ?? _focalViewportY;

    if (scrollController.hasClients && focal != null && oldHeight > 0) {
      final ratio = clamped / oldHeight;
      final oldOffset = scrollController.offset;
      final newOffset = (oldOffset + focal) * ratio - focal;
      final viewport = scrollController.position.viewportDimension;
      final maxExtent = math.max(0.0, 24 * clamped - viewport);
      scrollController.jumpTo(newOffset.clamp(0.0, maxExtent));
    }

    _smoothedHourHeight = clamped;
    _targetHourHeight = clamped;
    if (hourHeight.value != clamped) {
      hourHeight.value = clamped;
    }
  }

  void _setTargetHourHeight(double target, {required double focalViewportY}) {
    _targetHourHeight = target.clamp(minHourHeight, maxHourHeight);
    _lockFocal(focalViewportY);
    _ensureTicker();
  }

  void _ensureTicker() {
    if (_pinchActive) return;
    if (!_tickerActive) {
      _tickerActive = true;
      _ticker.start();
    }
  }

  void _stopTickerIfIdle() {
    if (_pinchActive || _wheelSessionActive || _isInterpolating) return;
    if (_tickerActive) {
      _ticker.stop();
      _tickerActive = false;
    }
  }

  void _onTick(Duration elapsed) {
    if (_pinchActive) return;

    final dt = elapsed.inMicroseconds / 1000000.0;
    if (dt <= 0) return;

    final diff = _targetHourHeight - _smoothedHourHeight;
    if (diff.abs() < 0.04) {
      if ((_smoothedHourHeight - _targetHourHeight).abs() >= 0.04) {
        _applyHourHeightImmediate(_targetHourHeight, focalY: _focalViewportY);
      }
      _stopTickerIfIdle();
      return;
    }

    final step = 1 - math.exp(-dt * interpolationSpeed);
    final next = _smoothedHourHeight + diff * step;
    _applyHourHeightImmediate(next, focalY: _focalViewportY);

    if (!_pinchActive && !_wheelSessionActive && diff.abs() < 0.5) {
      _stopTickerIfIdle();
    }
  }

  // --- Pinch (touch) ---

  void beginPinch({required double focalViewportY}) {
    _pinchActive = true;
    _wheelSessionActive = false;
    _wheelSessionTimer?.cancel();
    _pinchBaselineHourHeight = hourHeight.value;
    _smoothedHourHeight = hourHeight.value;
    _targetHourHeight = hourHeight.value;
    _lockFocal(focalViewportY);
    if (_tickerActive) {
      _ticker.stop();
      _tickerActive = false;
    }
  }

  void updatePinch({required double scale, required double focalViewportY}) {
    if (!_pinchActive) return;
    final baseline = _pinchBaselineHourHeight ?? hourHeight.value;
    if (scale <= 0) return;
    _lockFocal(focalViewportY);
    final target = (baseline * scale).clamp(minHourHeight, maxHourHeight);
    _applyHourHeightImmediate(target, focalY: focalViewportY);
  }

  void endPinch() {
    _pinchActive = false;
    _pinchBaselineHourHeight = null;
    _targetHourHeight = hourHeight.value;
    _smoothedHourHeight = hourHeight.value;
    _focalViewportY = null;
    _stopTickerIfIdle();
  }

  // --- Ctrl + wheel (desktop) ---

  void applyWheelDelta({
    required double scrollDeltaDy,
    required double focalViewportY,
  }) {
    if (scrollDeltaDy == 0) return;
    _wheelSessionActive = true;
    _releaseFocalAfterDelay();

    final scaleFactor = math.exp(-scrollDeltaDy * wheelZoomSensitivity);
    final nextTarget = (hourHeight.value * scaleFactor).clamp(
      minHourHeight,
      maxHourHeight,
    );
    _setTargetHourHeight(nextTarget, focalViewportY: focalViewportY);
  }

  /// Trackpad pinch with Ctrl held (Windows/Linux).
  void applyTrackpadScale({
    required double scaleDelta,
    required double focalViewportY,
  }) {
    if (scaleDelta == 0) return;
    _wheelSessionActive = true;
    _releaseFocalAfterDelay();

    final scaleFactor = math.exp(scaleDelta * wheelZoomSensitivity * 80);
    final nextTarget = (hourHeight.value * scaleFactor).clamp(
      minHourHeight,
      maxHourHeight,
    );
    _setTargetHourHeight(nextTarget, focalViewportY: focalViewportY);
  }
}
