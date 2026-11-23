import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/schedule_models.dart';

class StorageFormatException implements Exception {
  const StorageFormatException(this.message);
  final String message;

  @override
  String toString() => 'StorageFormatException: $message';
}

abstract class ScheduleStorage {
  Future<List<SubjectSchedule>> readAll();
  Future<void> writeAll(List<SubjectSchedule> schedules);
}

class SharedPreferencesScheduleStorage implements ScheduleStorage {
  SharedPreferencesScheduleStorage({this._prefs});

  static const String storageKey = 'seireminds_schedules_v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _instance() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<List<SubjectSchedule>> readAll() async {
    final prefs = await _instance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return <SubjectSchedule>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        throw const StorageFormatException('Stored schedules payload is not a list.');
      }
      return decoded.map((dynamic entry) {
        if (entry is! Map<String, dynamic>) {
          throw const StorageFormatException('Stored schedule entry is invalid.');
        }
        return SubjectSchedule.fromJson(entry);
      }).toList();
    } on StorageFormatException {
      rethrow;
    } on FormatException catch (e) {
      throw StorageFormatException(e.message);
    }
  }

  @override
  Future<void> writeAll(List<SubjectSchedule> schedules) async {
    final prefs = await _instance();
    final encoded = jsonEncode(
      schedules.map((s) => s.toJson()).toList(),
    );
    final ok = await prefs.setString(storageKey, encoded);
    if (!ok) {
      throw const StorageFormatException('Failed to save schedules to local storage.');
    }
  }
}
