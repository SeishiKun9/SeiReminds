/// Centralized route definitions and offline-first authentication route guard.
///
/// Non-Canvas routes ([home], [settings]) work fully offline without sign-in.
/// Online Canvas routes ([canvasSettings]) require an authenticated Supabase session.
class AppRoutes {
  static const String home = '/';
  static const String login = '/login';
  static const String signUp = '/signup';
  static const String settings = '/settings';
  static const String canvasHub = '/canvas';
  static const String canvasSettings = '/settings/canvas';

  static const Set<String> authRoutes = <String>{login, signUp};

  static const Set<String> offlineRoutes = <String>{home, settings};

  static const Set<String> publicRoutes = <String>{
    home,
    settings,
    login,
    signUp,
  };

  static const Set<String> protectedRoutes = <String>{
    canvasHub,
    canvasSettings,
  };

  static bool isPublic(String routeName) => publicRoutes.contains(routeName);

  static bool isProtected(String routeName) =>
      protectedRoutes.contains(routeName);

  /// Enforces offline-first route access control:
  /// - Offline routes ([home], [settings]) are accessible with or without auth.
  /// - Protected Canvas routes ([canvasSettings]) redirect to [login] when signed out.
  /// - Authenticated requests to [login] or [signUp] redirect to [home].
  static String resolveAuthorizedRoute(
    String? requestedRoute, {
    required bool isAuthenticated,
  }) {
    final normalized = (requestedRoute == null || requestedRoute.isEmpty)
        ? home
        : requestedRoute;

    if (!isAuthenticated) {
      if (isProtected(normalized)) return login;
      if (offlineRoutes.contains(normalized) ||
          authRoutes.contains(normalized)) {
        return normalized;
      }
      return home;
    }

    if (authRoutes.contains(normalized)) {
      return home;
    }
    if (offlineRoutes.contains(normalized) || isProtected(normalized)) {
      return normalized;
    }
    return home;
  }
}
