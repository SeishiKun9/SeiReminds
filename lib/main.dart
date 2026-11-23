import 'package:flutter/material.dart';

import 'data/repositories/schedule_repository.dart';
import 'data/services/alarm_service.dart';
import 'data/services/sqlite_database_service.dart';
import 'ui/core/app_theme.dart';
import 'ui/features/schedule/view_models/schedule_view_model.dart';
import 'ui/features/schedule/views/schedule_home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = ScheduleRepository(
    database: SqliteScheduleDatabase(),
    alarmService: MethodChannelAlarmService(),
  );
  runApp(SeiRemindsApp(repository: repository));
}

class SeiRemindsApp extends StatefulWidget {
  const SeiRemindsApp({
    super.key,
    required this.repository,
    this.initialWeekday,
  });

  final ScheduleRepository repository;
  final int? initialWeekday;

  @override
  State<SeiRemindsApp> createState() => _SeiRemindsAppState();
}

class _SeiRemindsAppState extends State<SeiRemindsApp> {
  late final ScheduleViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ScheduleViewModel(
      repository: widget.repository,
      initialWeekday: widget.initialWeekday,
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
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
      home: ScheduleHomePage(viewModel: _viewModel),
    );
  }
}
