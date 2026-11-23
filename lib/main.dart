import 'package:flutter/material.dart';

import 'data/repositories/canvas_token_repository.dart';
import 'data/repositories/schedule_repository.dart';
import 'data/services/alarm_service.dart';
import 'data/services/canvas_api_client.dart';
import 'data/services/canvas_secure_storage.dart';
import 'data/services/sqlite_database_service.dart';
import 'ui/core/app_theme.dart';
import 'ui/features/canvas/view_models/canvas_settings_view_model.dart';
import 'ui/features/schedule/view_models/schedule_view_model.dart';
import 'ui/features/schedule/views/schedule_home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = ScheduleRepository(
    database: SqliteScheduleDatabase(),
    alarmService: MethodChannelAlarmService(),
  );
  final canvasRepository = CanvasTokenRepository(
    store: FlutterSecureKeyValueStore(),
    apiClient: CanvasApiClient(),
  );
  runApp(
    SeiRemindsApp(
      repository: repository,
      canvasRepository: canvasRepository,
    ),
  );
}

class SeiRemindsApp extends StatefulWidget {
  const SeiRemindsApp({
    super.key,
    required this.repository,
    this.canvasRepository,
    this.initialWeekday,
  });

  final ScheduleRepository repository;
  final CanvasTokenRepository? canvasRepository;
  final int? initialWeekday;

  @override
  State<SeiRemindsApp> createState() => _SeiRemindsAppState();
}

class _SeiRemindsAppState extends State<SeiRemindsApp> {
  late final ScheduleViewModel _viewModel;
  CanvasSettingsViewModel? _canvasViewModel;

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
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _canvasViewModel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SeiReminds',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: ScheduleHomePage(
        viewModel: _viewModel,
        canvasViewModel: _canvasViewModel,
      ),
    );
  }
}
