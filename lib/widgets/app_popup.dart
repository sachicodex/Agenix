import 'package:flutter/material.dart';

/// Shows a dialog that automatically hides any older Agenix dialog while it
/// is on top. When this dialog closes, the older dialog is restored.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) async {
  final hasOlderPopup = _appPopupStack.hasOpen;
  final layer = _appPopupStack.open();
  try {
    return await showDialog<T>(
      context: context,
      builder: (dialogContext) =>
          _AppPopupLayer(layer: layer, child: builder(dialogContext)),
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? (hasOlderPopup ? Colors.transparent : null),
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
    );
  } finally {
    _appPopupStack.close(layer);
  }
}

/// Bottom-sheet counterpart to [showAppDialog].
Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool enableDrag = true,
  bool showDragHandle = false,
  Color? backgroundColor,
  Color? barrierColor,
}) async {
  final hasOlderPopup = _appPopupStack.hasOpen;
  final layer = _appPopupStack.open();
  try {
    return await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      backgroundColor: backgroundColor,
      barrierColor: barrierColor ?? (hasOlderPopup ? Colors.transparent : null),
      builder: (sheetContext) =>
          _AppPopupLayer(layer: layer, child: builder(sheetContext)),
    );
  } finally {
    _appPopupStack.close(layer);
  }
}

class _AppPopupStack extends ChangeNotifier {
  int _nextLayer = 0;
  final Set<int> _openLayers = <int>{};

  bool get hasOpen => _openLayers.isNotEmpty;

  int open() {
    final layer = _nextLayer++;
    _openLayers.add(layer);
    notifyListeners();
    return layer;
  }

  void close(int layer) {
    if (_openLayers.remove(layer)) notifyListeners();
  }

  bool isCovered(int layer) =>
      _openLayers.any((openLayer) => openLayer > layer);
}

final _appPopupStack = _AppPopupStack();

class _AppPopupLayer extends StatelessWidget {
  const _AppPopupLayer({required this.layer, required this.child});

  final int layer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appPopupStack,
      child: child,
      builder: (context, child) => IgnorePointer(
        ignoring: _appPopupStack.isCovered(layer),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          opacity: _appPopupStack.isCovered(layer) ? 0 : 1,
          child: child,
        ),
      ),
    );
  }
}
