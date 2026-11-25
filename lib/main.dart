import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_config.dart';
import 'data/repositories/canvas_token_repository.dart';
import 'data/repositories/schedule_repository.dart';
import 'data/services/alarm_service.dart';
import 'data/services/auth_service.dart';
import 'data/services/canvas_api_client.dart';
import 'data/services/canvas_secure_storage.dart';
import 'data/services/sqlite_database_service.dart';
import 'ui/core/app_routes.dart';
import 'ui/core/app_theme.dart';
import 'ui/features/auth/view_models/auth_view_model.dart';
import 'ui/features/auth/views/auth_pages.dart';
import 'ui/features/canvas/view_models/canvas_settings_view_model.dart';
import 'ui/features/canvas/views/canvas_hub_page.dart';
import 'ui/features/canvas/views/canvas_settings_page.dart';
import 'ui/features/schedule/view_models/schedule_view_model.dart';
import 'ui/features/schedule/views/schedule_home_page.dart';
import 'ui/features/schedule/views/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var supabaseReady = false;
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    supabaseReady = true;
  } catch (_) {
    // Allow full offline operation even when Supabase cannot initialize.
  }

  final repository = ScheduleRepository(
    database: SqliteScheduleDatabase(),
    alarmService: MethodChannelAlarmService(),
  );
  final canvasRepository = CanvasTokenRepository(
    store: FlutterSecureKeyValueStore(),
    apiClient: CanvasApiClient(),
  );
  final authService = SupabaseAuthService(isAvailable: supabaseReady);

  runApp(
    SeiRemindsApp(
      repository: repository,
      canvasRepository: canvasRepository,
      authService: authService,
      onlineChecker: checkOnlineConnectivity,
    ),
  );
}

class SeiRemindsApp extends StatefulWidget {
  const SeiRemindsApp({
    super.key,
    required this.repository,
    this.canvasRepository,
    this.authService,
    this.onlineChecker,
    this.initialWeekday,
    this.initialRoute,
  });

  final ScheduleRepository repository;
  final CanvasTokenRepository? canvasRepository;
  final AuthService? authService;
  final OnlineStatusChecker? onlineChecker;
  final int? initialWeekday;
  final String? initialRoute;

  @override
  State<SeiRemindsApp> createState() => _SeiRemindsAppState();
}

class _SeiRemindsAppState extends State<SeiRemindsApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final ScheduleViewModel _viewModel;
  CanvasSettingsViewModel? _canvasViewModel;
  AuthViewModel? _authViewModel;
  bool _wasAuthenticated = false;
  String? _pendingProtectedRoute;

  bool get _isAuthenticated => _authViewModel?.isAuthenticated ?? true;

  @override
  void initState() {
    super.initState();
    _viewModel = ScheduleViewModel(
      repository: widget.repository,
      initialWeekday: widget.initialWeekday,
    );
    Future.microtask(_viewModel.initialize);
    if (widget.canvasRepository != null) {
      final canvasRepo = widget.canvasRepository!;
      _canvasViewModel = CanvasSettingsViewModel(
        repository: canvasRepo,
        onSyncTodayUpdates: () => _viewModel.syncTodayCanvasUpdates(canvasRepo),
        onDisconnected: _viewModel.clearCanvasDailyCache,
        onlineChecker: widget.onlineChecker,
      );
      Future.microtask(_canvasViewModel!.load);
    }
    if (widget.authService != null) {
      _authViewModel = AuthViewModel(authService: widget.authService!);
      _wasAuthenticated = _authViewModel!.isAuthenticated;
      _authViewModel!.addListener(_handleAuthChange);
    }
    final requestedInitial = widget.initialRoute;
    if (!_isAuthenticated &&
        requestedInitial != null &&
        AppRoutes.isProtected(requestedInitial)) {
      _pendingProtectedRoute = requestedInitial;
    }
  }

  void _handleAuthChange() {
    final authVm = _authViewModel;
    if (authVm == null) return;
    final nowAuthenticated = authVm.isAuthenticated;
    if (nowAuthenticated == _wasAuthenticated) return;
    _wasAuthenticated = nowAuthenticated;

    final nav = _navigatorKey.currentState;
    if (nav == null) return;

    if (nowAuthenticated) {
      final pending = _pendingProtectedRoute;
      _pendingProtectedRoute = null;
      nav.pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
      if (pending != null && pending != AppRoutes.home) {
        nav.pushNamed(pending);
      }
      return;
    }

    // On sign-out or session expiry, immediately remove any protected Canvas
    // route from the stack while keeping the offline timetable accessible.
    _pendingProtectedRoute = null;
    nav.pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final requested = settings.name;
    if (!_isAuthenticated &&
        requested != null &&
        AppRoutes.isProtected(requested)) {
      _pendingProtectedRoute = requested;
    }

    final resolved = AppRoutes.resolveAuthorizedRoute(
      requested,
      isAuthenticated: _isAuthenticated,
    );

    Widget page;
    switch (resolved) {
      case AppRoutes.login:
        page = LoginPage(viewModel: _authViewModel!);
      case AppRoutes.signUp:
        page = SignUpPage(viewModel: _authViewModel!);
      case AppRoutes.settings:
        page = SettingsPage(
          viewModel: _viewModel,
          canvasViewModel: _canvasViewModel,
          authViewModel: _authViewModel,
        );
      case AppRoutes.canvasHub:
        page = _canvasViewModel != null
            ? CanvasHubPage(
                scheduleViewModel: _viewModel,
                canvasViewModel: _canvasViewModel!,
              )
            : ScheduleHomePage(
                viewModel: _viewModel,
                authViewModel: _authViewModel,
              );
      case AppRoutes.canvasSettings:
        page = _canvasViewModel != null
            ? CanvasSettingsPage(viewModel: _canvasViewModel!)
            : SettingsPage(
                viewModel: _viewModel,
                authViewModel: _authViewModel,
              );
      case AppRoutes.home:
      default:
        page = ScheduleHomePage(
          viewModel: _viewModel,
          canvasViewModel: _canvasViewModel,
          authViewModel: _authViewModel,
        );
    }

    return MaterialPageRoute<void>(
      settings: RouteSettings(name: resolved),
      builder: (_) => page,
    );
  }

  @override
  void dispose() {
    _authViewModel?.removeListener(_handleAuthChange);
    _authViewModel?.dispose();
    _viewModel.dispose();
    _canvasViewModel?.dispose();
    widget.canvasRepository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startRoute = AppRoutes.resolveAuthorizedRoute(
      widget.initialRoute ?? AppRoutes.home,
      isAuthenticated: _isAuthenticated,
    );

    return MaterialApp(
      title: 'SeiReminds',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      initialRoute: startRoute,
      onGenerateRoute: _onGenerateRoute,
    );
  }
}
