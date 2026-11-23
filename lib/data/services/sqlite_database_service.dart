import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/canvas_token_models.dart';
import '../../domain/models/schedule_models.dart';

class SqliteScheduleDatabase {
  SqliteScheduleDatabase({
    this._databaseFactory,
    this._databasePath,
  });

  static const String dbFileName = 'seireminds.db';
  static const int _dbVersion = 3;
  static const String _metaLastCleanupDate = 'last_daily_cleanup_date';
  static const String _metaLastCleanupRemoved = 'last_daily_cleanup_removed';

  final DatabaseFactory? _databaseFactory;
  final String? _databasePath;
  Database? _db;

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;

    final factory = _databaseFactory ?? databaseFactory;
    final path = _databasePath ?? p.join(await getDatabasesPath(), dbFileName);
    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        singleInstance: _databasePath == null,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE schedules (
        id TEXT PRIMARY KEY,
        subject TEXT NOT NULL,
        section TEXT NOT NULL,
        reminder_minutes_before INTEGER NOT NULL,
        reminder_enabled INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE schedule_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        schedule_id TEXT NOT NULL,
        session_type TEXT NOT NULL,
        days_csv TEXT NOT NULL,
        time_in_minutes INTEGER NOT NULL,
        time_out_minutes INTEGER NOT NULL,
        UNIQUE(schedule_id, session_type),
        FOREIGN KEY(schedule_id) REFERENCES schedules(id) ON DELETE CASCADE
      )
    ''');

    await _createEventsTableV2(db, tableName: 'events');

    await db.execute('''
      CREATE TABLE history_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        title TEXT NOT NULL,
        details TEXT NOT NULL,
        snapshot_json TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await _createDailyCacheTablesV3(db);
  }

  Future<void> _createDailyCacheTablesV3(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS canvas_daily_items (
        item_id TEXT NOT NULL,
        posted_date TEXT NOT NULL,
        kind TEXT NOT NULL,
        course_name TEXT NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        posted_at TEXT NOT NULL,
        notified INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (item_id, posted_date)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_canvas_daily_items_date ON canvas_daily_items(posted_date)',
    );
  }

  Future<void> _createEventsTableV2(
    DatabaseExecutor db, {
    required String tableName,
  }) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        days_csv TEXT NOT NULL,
        period TEXT NOT NULL,
        morning_time_in INTEGER,
        morning_time_out INTEGER,
        afternoon_time_in INTEGER,
        afternoon_time_out INTEGER,
        evening_time_in INTEGER,
        reminder_minutes_before INTEGER NOT NULL,
        reminder_enabled INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await _createEventsTableV2(txn, tableName: 'events_v2');
        final oldRows = await txn.query('events');

        for (final row in oldRows) {
          final rawPeriod = row['period'] as String;
          final timeIn = row['time_in_minutes'] as int;
          final timeOut = row['time_out_minutes'] as int;

          String nextPeriod;
          int? morningIn;
          int? morningOut;
          int? afternoonIn;
          int? afternoonOut;

          if (rawPeriod == 'morning') {
            nextPeriod = EventPeriod.morning.key;
            morningIn = timeIn;
            morningOut = timeOut;
          } else if (rawPeriod == 'afternoon') {
            nextPeriod = EventPeriod.afternoon.key;
            afternoonIn = timeIn;
            afternoonOut = timeOut;
          } else {
            // Losslessly split legacy 'both' events at noon into Whole Day slots.
            nextPeriod = EventPeriod.wholeDay.key;
            morningIn = timeIn;
            morningOut = kNoonMinutes;
            afternoonIn = kNoonMinutes;
            afternoonOut = timeOut;
          }

          await txn.insert('events_v2', <String, Object?>{
            'id': row['id'],
            'title': row['title'],
            'days_csv': row['days_csv'],
            'period': nextPeriod,
            'morning_time_in': morningIn,
            'morning_time_out': morningOut,
            'afternoon_time_in': afternoonIn,
            'afternoon_time_out': afternoonOut,
            'evening_time_in': null,
            'reminder_minutes_before': row['reminder_minutes_before'],
            'reminder_enabled': row['reminder_enabled'],
            'updated_at': row['updated_at'],
          });
        }

        await txn.execute('DROP TABLE events');
        await txn.execute('ALTER TABLE events_v2 RENAME TO events');
      });
    }

    if (oldVersion < 3) {
      await _createDailyCacheTablesV3(db);
    }
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  Future<List<SubjectSchedule>> loadSchedules() async {
    final db = await _open();
    return _readSchedules(db);
  }

  Future<List<SubjectSchedule>> _readSchedules(DatabaseExecutor db) async {
    final scheduleRows = await db.query('schedules', orderBy: 'subject ASC');
    if (scheduleRows.isEmpty) return <SubjectSchedule>[];

    final sessionRows = await db.query('schedule_sessions');
    final sessionsByScheduleId = <String, Map<SessionType, SessionSchedule>>{};

    for (final row in sessionRows) {
      final scheduleId = row['schedule_id'] as String;
      final type = SessionType.fromKey(row['session_type'] as String);
      final session = SessionSchedule(
        type: type,
        days: _decodeDays(row['days_csv'] as String),
        timeIn: ScheduleTime.fromTotalMinutes(row['time_in_minutes'] as int),
        timeOut: ScheduleTime.fromTotalMinutes(row['time_out_minutes'] as int),
      );
      sessionsByScheduleId.putIfAbsent(
        scheduleId,
        () => <SessionType, SessionSchedule>{},
      )[type] = session;
    }

    return scheduleRows.map((row) {
      final id = row['id'] as String;
      return SubjectSchedule(
        id: id,
        subject: row['subject'] as String,
        section: row['section'] as String,
        sessions:
            sessionsByScheduleId[id] ?? const <SessionType, SessionSchedule>{},
        reminderMinutesBefore: row['reminder_minutes_before'] as int,
        reminderEnabled: (row['reminder_enabled'] as int) == 1,
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
    }).toList();
  }

  Future<void> upsertSchedule(
    SubjectSchedule schedule, {
    required bool isNew,
  }) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.insert(
        'schedules',
        <String, Object?>{
          'id': schedule.id,
          'subject': schedule.subject,
          'section': schedule.section,
          'reminder_minutes_before': schedule.reminderMinutesBefore,
          'reminder_enabled': schedule.reminderEnabled ? 1 : 0,
          'updated_at': schedule.updatedAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'schedule_sessions',
        where: 'schedule_id = ?',
        whereArgs: <Object>[schedule.id],
      );

      for (final session in schedule.sessions.values) {
        await txn.insert('schedule_sessions', <String, Object?>{
          'schedule_id': schedule.id,
          'session_type': session.type.key,
          'days_csv': _encodeDays(session.days),
          'time_in_minutes': session.timeIn.totalMinutes,
          'time_out_minutes': session.timeOut.totalMinutes,
        });
      }

      final sessionSummary = schedule.sessions.values
          .map(
            (s) =>
                '${s.type.label} (${s.formatDaysSummary()} · ${s.formatTimeRange()})',
          )
          .join('; ');

      await _insertHistory(
        txn,
        action: isNew ? 'schedule_added' : 'schedule_updated',
        entityType: 'schedule',
        entityId: schedule.id,
        title: '${schedule.subject} · Sec ${schedule.section}',
        details: sessionSummary,
        snapshotJson: jsonEncode(schedule.toJson()),
      );
    });
  }

  /// Schedules can only be removed via explicit removal from the schedule screen.
  Future<void> deleteSchedule(
    String id, {
    required bool confirmedFromSchedule,
  }) async {
    if (!confirmedFromSchedule) {
      throw const ScheduleProtectionException(
        'Schedules cannot be removed unless explicitly deleted from your schedule.',
      );
    }

    final db = await _open();
    await db.transaction((txn) async {
      final all = await _readSchedules(txn);
      final target = all.where((s) => s.id == id).firstOrNull;
      if (target == null) return;

      await txn.delete(
        'schedules',
        where: 'id = ?',
        whereArgs: <Object>[id],
      );

      await _insertHistory(
        txn,
        action: 'schedule_deleted',
        entityType: 'schedule',
        entityId: target.id,
        title: '${target.subject} · Sec ${target.section}',
        details: 'Removed from schedule',
        snapshotJson: jsonEncode(target.toJson()),
      );
    });
  }

  Future<void> toggleScheduleReminder(String id, bool enabled) async {
    final db = await _open();
    await db.transaction((txn) async {
      final all = await _readSchedules(txn);
      final target = all.where((s) => s.id == id).firstOrNull;
      if (target == null) return;

      final updated = target.copyWith(reminderEnabled: enabled);
      await txn.update(
        'schedules',
        <String, Object?>{
          'reminder_enabled': enabled ? 1 : 0,
          'updated_at': updated.updatedAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: <Object>[id],
      );

      await _insertHistory(
        txn,
        action: 'reminder_toggled',
        entityType: 'schedule',
        entityId: updated.id,
        title: '${updated.subject} · Sec ${updated.section}',
        details: enabled ? 'Alarm reminder enabled' : 'Alarm reminder muted',
        snapshotJson: jsonEncode(updated.toJson()),
      );
    });
  }

  Future<List<EventSchedule>> loadEvents() async {
    final db = await _open();
    return _readEvents(db);
  }

  Future<List<EventSchedule>> _readEvents(DatabaseExecutor db) async {
    final rows = await db.query(
      'events',
      orderBy: 'COALESCE(morning_time_in, afternoon_time_in, evening_time_in) ASC, title ASC',
    );
    return rows.map((row) {
      final morningIn = row['morning_time_in'] as int?;
      final morningOut = row['morning_time_out'] as int?;
      final afternoonIn = row['afternoon_time_in'] as int?;
      final afternoonOut = row['afternoon_time_out'] as int?;
      final eveningIn = row['evening_time_in'] as int?;

      return EventSchedule(
        id: row['id'] as String,
        title: row['title'] as String,
        days: _decodeDays(row['days_csv'] as String),
        period: EventPeriod.fromKey(row['period'] as String),
        morningTimeIn:
            morningIn != null ? ScheduleTime.fromTotalMinutes(morningIn) : null,
        morningTimeOut: morningOut != null
            ? ScheduleTime.fromTotalMinutes(morningOut)
            : null,
        afternoonTimeIn: afternoonIn != null
            ? ScheduleTime.fromTotalMinutes(afternoonIn)
            : null,
        afternoonTimeOut: afternoonOut != null
            ? ScheduleTime.fromTotalMinutes(afternoonOut)
            : null,
        eveningTimeIn:
            eveningIn != null ? ScheduleTime.fromTotalMinutes(eveningIn) : null,
        reminderMinutesBefore: row['reminder_minutes_before'] as int,
        reminderEnabled: (row['reminder_enabled'] as int) == 1,
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
    }).toList();
  }

  Future<void> upsertEvent(
    EventSchedule event, {
    required bool isNew,
    List<DaySessionItem> affectedSessions = const <DaySessionItem>[],
  }) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.insert(
        'events',
        <String, Object?>{
          'id': event.id,
          'title': event.title,
          'days_csv': _encodeDays(event.days),
          'period': event.period.key,
          'morning_time_in': event.morningTimeIn?.totalMinutes,
          'morning_time_out': event.morningTimeOut?.totalMinutes,
          'afternoon_time_in': event.afternoonTimeIn?.totalMinutes,
          'afternoon_time_out': event.afternoonTimeOut?.totalMinutes,
          'evening_time_in': event.eveningTimeIn?.totalMinutes,
          'reminder_minutes_before': event.reminderMinutesBefore,
          'reminder_enabled': event.reminderEnabled ? 1 : 0,
          'updated_at': event.updatedAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final cancelNote = affectedSessions.isEmpty
          ? 'No overlapping classes'
          : 'Cancels ${affectedSessions.map((s) => s.shortSummary).join(', ')}';

      await _insertHistory(
        txn,
        action: isNew ? 'event_added' : 'event_updated',
        entityType: 'event',
        entityId: event.id,
        title: 'Event: ${event.title}',
        details:
            '${event.formatDaysSummary()} · ${event.period.label} (${event.formatTimeSummary()}) · $cancelNote',
        snapshotJson: jsonEncode(event.toJson()),
      );
    });
  }

  Future<void> deleteEvent(String id) async {
    final db = await _open();
    await db.transaction((txn) async {
      final all = await _readEvents(txn);
      final target = all.where((e) => e.id == id).firstOrNull;
      if (target == null) return;

      await txn.delete(
        'events',
        where: 'id = ?',
        whereArgs: <Object>[id],
      );

      await _insertHistory(
        txn,
        action: 'event_deleted',
        entityType: 'event',
        entityId: target.id,
        title: 'Event: ${target.title}',
        details: 'Event removed (${target.formatDaysSummary()})',
        snapshotJson: jsonEncode(target.toJson()),
      );
    });
  }

  Future<void> toggleEventReminder(String id, bool enabled) async {
    final db = await _open();
    await db.transaction((txn) async {
      final all = await _readEvents(txn);
      final target = all.where((e) => e.id == id).firstOrNull;
      if (target == null) return;

      final updated = target.copyWith(reminderEnabled: enabled);
      await txn.update(
        'events',
        <String, Object?>{
          'reminder_enabled': enabled ? 1 : 0,
          'updated_at': updated.updatedAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: <Object>[id],
      );

      await _insertHistory(
        txn,
        action: 'reminder_toggled',
        entityType: 'event',
        entityId: updated.id,
        title: 'Event: ${updated.title}',
        details: enabled ? 'Event alarm enabled' : 'Event alarm muted',
        snapshotJson: jsonEncode(updated.toJson()),
      );
    });
  }

  Future<List<HistoryEntry>> loadHistory({bool archivedOnly = false}) async {
    final db = await _open();
    final rows = await db.query(
      'history_entries',
      where: 'is_archived = ?',
      whereArgs: <Object>[archivedOnly ? 1 : 0],
      orderBy: 'id DESC',
    );
    return rows.map(_rowToHistoryEntry).toList();
  }

  Future<int> countArchivedHistory() async {
    final db = await _open();
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM history_entries WHERE is_archived = 1',
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Soft-clears visible history without deleting data from SQLite.
  /// Validates that active schedules remain untouched.
  Future<int> clearHistory() async {
    final db = await _open();
    return db.transaction((txn) async {
      final beforeScheduleIds = await _readScheduleIds(txn);
      final updatedCount = await txn.rawUpdate(
        'UPDATE history_entries SET is_archived = 1 WHERE is_archived = 0',
      );
      final afterScheduleIds = await _readScheduleIds(txn);
      _assertSchedulesUnchanged(beforeScheduleIds, afterScheduleIds);
      return updatedCount;
    });
  }

  /// Restores soft-cleared history rows back to the active History view.
  Future<int> restoreArchivedHistory() async {
    final db = await _open();
    return db.rawUpdate(
      'UPDATE history_entries SET is_archived = 0 WHERE is_archived = 1',
    );
  }

  /// Permanently deletes ONLY history rows after explicit confirmation.
  /// Validates that active schedules remain untouched.
  Future<int> permanentlyClearHistory({required bool confirmedPermanent}) async {
    if (!confirmedPermanent) {
      throw const ScheduleProtectionException(
        'Permanent history deletion requires explicit confirmation.',
      );
    }

    final db = await _open();
    return db.transaction((txn) async {
      final beforeScheduleIds = await _readScheduleIds(txn);
      final deletedCount = await txn.delete('history_entries');
      final afterScheduleIds = await _readScheduleIds(txn);
      _assertSchedulesUnchanged(beforeScheduleIds, afterScheduleIds);
      return deletedCount;
    });
  }

  /// Clears transient Canvas announcement/activity cache from previous days
  /// to save device storage. Validates that saved class schedules remain untouched.
  Future<DailyCleanupResult> runDailyStorageCleanup({DateTime? now}) async {
    final db = await _open();
    final todayKey = localDateKey(now ?? DateTime.now());

    return db.transaction((txn) async {
      final beforeScheduleIds = await _readScheduleIds(txn);
      final removed = await txn.delete(
        'canvas_daily_items',
        where: 'posted_date != ?',
        whereArgs: <Object>[todayKey],
      );
      await _recordDailyCleanupMeta(txn, todayKey: todayKey, removedNow: removed);
      final afterScheduleIds = await _readScheduleIds(txn);
      _assertSchedulesUnchanged(beforeScheduleIds, afterScheduleIds);
      return DailyCleanupResult(dateKey: todayKey, clearedItemsCount: removed);
    });
  }

  /// Runs daily cleanup first, discards any non-today items, stores only
  /// current-day items, and returns all today items plus newly unnotified items.
  Future<
      ({
        List<CanvasDailyItem> todayItems,
        List<CanvasDailyItem> newlyUnnotified,
        DailyCleanupResult cleanup,
      })> syncTodayCanvasItems(
    List<CanvasDailyItem> incoming, {
    DateTime? now,
  }) async {
    final db = await _open();
    final current = now ?? DateTime.now();
    final todayKey = localDateKey(current);

    return db.transaction((txn) async {
      final beforeScheduleIds = await _readScheduleIds(txn);
      final removed = await txn.delete(
        'canvas_daily_items',
        where: 'posted_date != ?',
        whereArgs: <Object>[todayKey],
      );
      await _recordDailyCleanupMeta(txn, todayKey: todayKey, removedNow: removed);

      for (final item in incoming) {
        if (!isPostedOnCurrentDay(item.postedAt, now: current)) {
          continue;
        }
        await txn.insert(
          'canvas_daily_items',
          <String, Object?>{
            'item_id': item.id,
            'posted_date': todayKey,
            'kind': item.kind.key,
            'course_name': item.courseName,
            'title': item.title,
            'message': item.message,
            'posted_at': item.postedAt.toUtc().toIso8601String(),
            'notified': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      final rows = await txn.query(
        'canvas_daily_items',
        where: 'posted_date = ?',
        whereArgs: <Object>[todayKey],
        orderBy: 'posted_at DESC',
      );
      final todayItems = rows.map(_rowToCanvasDailyItem).toList();
      final newlyUnnotified =
          todayItems.where((item) => !item.notified).toList();

      final afterScheduleIds = await _readScheduleIds(txn);
      _assertSchedulesUnchanged(beforeScheduleIds, afterScheduleIds);

      return (
        todayItems: todayItems,
        newlyUnnotified: newlyUnnotified,
        cleanup: DailyCleanupResult(
          dateKey: todayKey,
          clearedItemsCount: removed,
        ),
      );
    });
  }

  Future<void> markCanvasItemsNotified(
    List<String> itemIds, {
    required String postedDate,
  }) async {
    if (itemIds.isEmpty) return;
    final db = await _open();
    await db.transaction((txn) async {
      for (final id in itemIds) {
        await txn.update(
          'canvas_daily_items',
          const <String, Object?>{'notified': 1},
          where: 'item_id = ? AND posted_date = ?',
          whereArgs: <Object>[id, postedDate],
        );
      }
    });
  }

  Future<List<CanvasDailyItem>> loadTodayCanvasItems({DateTime? now}) async {
    final db = await _open();
    final todayKey = localDateKey(now ?? DateTime.now());
    final rows = await db.query(
      'canvas_daily_items',
      where: 'posted_date = ?',
      whereArgs: <Object>[todayKey],
      orderBy: 'posted_at DESC',
    );
    return rows.map(_rowToCanvasDailyItem).toList();
  }

  Future<({String? lastDate, int lastRemovedCount})>
      getDailyCleanupMeta() async {
    final db = await _open();
    final rows = await db.query(
      'app_meta',
      where: 'key IN (?, ?)',
      whereArgs: <Object>[_metaLastCleanupDate, _metaLastCleanupRemoved],
    );
    String? lastDate;
    var lastRemoved = 0;
    for (final row in rows) {
      final key = row['key'] as String;
      final value = row['value'] as String;
      if (key == _metaLastCleanupDate) {
        lastDate = value;
      } else if (key == _metaLastCleanupRemoved) {
        lastRemoved = int.tryParse(value) ?? 0;
      }
    }
    return (lastDate: lastDate, lastRemovedCount: lastRemoved);
  }

  Future<void> clearCanvasDailyCache() async {
    final db = await _open();
    await db.transaction((txn) async {
      final beforeScheduleIds = await _readScheduleIds(txn);
      await txn.delete('canvas_daily_items');
      final afterScheduleIds = await _readScheduleIds(txn);
      _assertSchedulesUnchanged(beforeScheduleIds, afterScheduleIds);
    });
  }

  Future<void> _recordDailyCleanupMeta(
    DatabaseExecutor db, {
    required String todayKey,
    required int removedNow,
  }) async {
    final rows = await db.query(
      'app_meta',
      where: 'key IN (?, ?)',
      whereArgs: <Object>[_metaLastCleanupDate, _metaLastCleanupRemoved],
    );
    String? prevDate;
    var prevRemoved = 0;
    for (final row in rows) {
      if (row['key'] == _metaLastCleanupDate) {
        prevDate = row['value'] as String;
      } else if (row['key'] == _metaLastCleanupRemoved) {
        prevRemoved = int.tryParse(row['value'] as String) ?? 0;
      }
    }
    final nextRemoved = prevDate == todayKey ? prevRemoved + removedNow : removedNow;
    await _writeMeta(db, _metaLastCleanupDate, todayKey);
    await _writeMeta(db, _metaLastCleanupRemoved, nextRemoved.toString());
  }

  Future<void> _writeMeta(
    DatabaseExecutor db,
    String key,
    String value,
  ) async {
    await db.insert(
      'app_meta',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  CanvasDailyItem _rowToCanvasDailyItem(Map<String, Object?> row) {
    return CanvasDailyItem(
      id: row['item_id'] as String,
      kind: CanvasDailyItemKind.fromKey(row['kind'] as String),
      courseName: row['course_name'] as String,
      title: row['title'] as String,
      message: row['message'] as String,
      postedAt: DateTime.parse(row['posted_at'] as String).toUtc(),
      postedDate: row['posted_date'] as String,
      notified: (row['notified'] as int) == 1,
    );
  }

  Future<Set<String>> _readScheduleIds(DatabaseExecutor db) async {
    final rows = await db.query('schedules', columns: <String>['id']);
    return rows.map((row) => row['id'] as String).toSet();
  }

  void _assertSchedulesUnchanged(Set<String> before, Set<String> after) {
    if (before.length != after.length || !before.containsAll(after)) {
      throw const ScheduleProtectionException(
        'Schedule protection validation failed: history clear must never delete active schedules.',
      );
    }
  }

  Future<void> _insertHistory(
    DatabaseExecutor db, {
    required String action,
    required String entityType,
    required String entityId,
    required String title,
    required String details,
    String? snapshotJson,
  }) async {
    await db.insert('history_entries', <String, Object?>{
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'title': title,
      'details': details,
      'snapshot_json': snapshotJson,
      'is_archived': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  HistoryEntry _rowToHistoryEntry(Map<String, Object?> row) {
    return HistoryEntry(
      id: row['id'] as int,
      action: row['action'] as String,
      entityType: row['entity_type'] as String,
      entityId: row['entity_id'] as String,
      title: row['title'] as String,
      details: row['details'] as String,
      snapshotJson: row['snapshot_json'] as String?,
      isArchived: (row['is_archived'] as int) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  static String _encodeDays(List<int> days) => days.join(',');

  static List<int> _decodeDays(String csv) {
    if (csv.trim().isEmpty) return const <int>[];
    return csv
        .split(',')
        .where((part) => part.isNotEmpty)
        .map(int.parse)
        .toList();
  }
}
