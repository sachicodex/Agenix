import 'package:flutter/widgets.dart';

class AppRouteObserver extends RouteObserver<ModalRoute<void>>
    with ChangeNotifier {
  Route<dynamic>? _currentRoute;

  String? get currentRouteName => _currentRoute?.settings.name;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _currentRoute = route;
    notifyListeners();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _currentRoute = previousRoute;
    notifyListeners();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (_currentRoute == oldRoute || _currentRoute == null) {
      _currentRoute = newRoute;
      notifyListeners();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_currentRoute == route) {
      _currentRoute = previousRoute;
      notifyListeners();
    }
  }
}

final AppRouteObserver appRouteObserver = AppRouteObserver();
