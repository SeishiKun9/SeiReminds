/// Centralized route definitions and authentication route guard.
class AppRoutes {
  static const String home = '/';
  static const String login = '/login';
  static const String signUp = '/signup';
  static const String settings = '/settings';
  static const String canvasSettings = '/settings/canvas';

  static const Set<String> publicRoutes = <String>{login, signUp};

  static const Set<String> protectedRoutes = <String>{
    home,
    settings,
    canvasSettings,
  };

  static bool isPublic(String routeName) => publicRoutes.contains(routeName);

  /// Enforces protected-route access control:
  /// - Unauthenticated requests to any protected/unknown route redirect to [login].
  /// - Authenticated requests to [login] or [signUp] redirect to [home].
  static String resolveAuthorizedRoute(
    String? requestedRoute, {
    required bool isAuthenticated,
  }) {
    final normalized = (requestedRoute == null || requestedRoute.isEmpty)
        ? home
        : requestedRoute;

    if (!isAuthenticated) {
      return isPublic(normalized) ? normalized : login;
    }

    if (isPublic(normalized) || !protectedRoutes.contains(normalized)) {
      return home;
    }

    return normalized;
  }
}
