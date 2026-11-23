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
import 'ui/features/canvas/views/canvas_settings_page.dart';
import 'ui/features/schedule/view_models/schedule_view_model.dart';
import 'ui/features/schedule/views/schedule_home_page.dart';
import 'ui/features/schedule/views/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  final repository = ScheduleRepository(
    database: SqliteScheduleDatabase(),
    alarmService: MethodChannelAlarmService(),
  );
  final canvasRepository = CanvasTokenRepository(
    store: FlutterSecureKeyValueStore(),
    apiClient: CanvasApiClient(),
  );
  final authService = SupabaseAuthService();

  runApp(
    SeiRemindsApp(
      repository: repository,
      canvasRepository: canvasRepository,
      authService: authService,
    ),
  );
}

class SeiRemindsApp extends StatefulWidget {
  const SeiRemindsApp({
    super.key,
    required this.repository,
    this.canvasRepository,
    this.authService,
    this.initialWeekday,
    this.initialRoute,
  });

  final ScheduleRepository repository;
  final CanvasTokenRepository? canvasRepository;
  final AuthService? authService;
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

  bool get _isAuthenticated => _authViewModel?.isAuthenticated ?? true;

  @override
  void initState() {
    super.initState();
    _viewModel = ScheduleViewModel(
      repository: widget.repository,
      initialWeekday: widget.initialWeekday,
    );
    if (widget.canvasRepository != null) {
      _canvasViewModel = CanvasSettingsViewModel(
        repository: widget.canvasRepository!,
      )..load();
    }
    if (widget.authService != null) {
      _authViewModel = AuthViewModel(authService: widget.authService!);
      _wasAuthenticated = _authViewModel!.isAuthenticated;
      _authViewModel!.addListener(_handleAuthChange);
    }
  }

  void _handleAuthChange() {
    final authVm = _authViewModel;
    if (authVm == null) return;
    final nowAuthenticated = authVm.isAuthenticated;
    if (nowAuthenticated == _wasAuthenticated) return;
    _wasAuthenticated = nowAuthenticated;

    // Immediately reset the entire navigation stack on sign-in or sign-out
    // so no protected route remains reachable via back navigation.
    final targetRoute = nowAuthenticated ? AppRoutes.home : AppRoutes.login;
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      targetRoute,
      (_) => false,
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final resolved = AppRoutes.resolveAuthorizedRoute(
      settings.name,
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
