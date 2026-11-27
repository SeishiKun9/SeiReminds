import 'package:flutter/material.dart';

import '../../../../data/services/schedule_ocr_service.dart';
import '../../../../data/services/schedule_photo_parser.dart';
import '../../../../domain/models/schedule_models.dart';
import '../../../core/app_theme.dart';
import 'subject_schedule_form_page.dart';

/// Offline photo-to-schedule importer.
/// Lets students pick a timetable photo (Gallery / Camera) or paste/edit the
/// OCR text, review & tweak each detected class, and bulk-import into SQLite.
class PhotoScheduleImportPage extends StatefulWidget {
  const PhotoScheduleImportPage({
    super.key,
    required this.initialWeekday,
    this.ocrService,
  });

  final int initialWeekday;
  final ScheduleOcrService? ocrService;

  @override
  State<PhotoScheduleImportPage> createState() =>
      _PhotoScheduleImportPageState();
}

class _PhotoScheduleImportPageState extends State<PhotoScheduleImportPage> {
  late final ScheduleOcrService _ocrService;
  final TextEditingController _rawTextController = TextEditingController();

  bool _isScanning = false;
  bool _showRawEditor = false;
  String? _statusMessage;
  bool _isError = false;
  List<ParsedScheduleDraft> _drafts = <ParsedScheduleDraft>[];

  @override
  void initState() {
    super.initState();
    _ocrService = widget.ocrService ?? MlKitScheduleOcrService();
  }

  @override
  void dispose() {
    _rawTextController.dispose();
    super.dispose();
  }

  int get _selectedCount => _drafts.where((d) => d.selected).length;

  Future<void> _scanFromPhoto(PhotoImportSource source) async {
    setState(() {
      _isScanning = true;
      _statusMessage = null;
      _isError = false;
    });
    try {
      final result = await _ocrService.pickAndRecognize(source);
      if (!mounted) return;
      if (result == null) {
        setState(() => _isScanning = false);
        return;
      }

      _rawTextController.text = result.rawText;
      final parsed = result.lines.isNotEmpty
          ? SchedulePhotoParser.parseOcrLines(result.lines)
          : SchedulePhotoParser.parseRawText(result.rawText);

      setState(() {
        _drafts = parsed;
        _isScanning = false;
        if (parsed.isEmpty) {
          _showRawEditor = true;
          _isError = true;
          _statusMessage =
              'Text was scanned, but no time ranges were recognized automatically. Edit the detected text below and tap Re-Parse.';
        } else {
          _isError = false;
          _statusMessage =
              'Detected ${parsed.length} ${parsed.length == 1 ? 'class' : 'classes'} offline. Review or tap Edit on any card before importing.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _showRawEditor = true;
        _isError = true;
        _statusMessage = e is UnsupportedError
            ? e.message
            : 'Could not read photo: $e';
      });
    }
  }

  void _parseFromManualText() {
    final text = _rawTextController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _drafts = <ParsedScheduleDraft>[];
        _isError = true;
        _statusMessage = 'Scan a photo or paste schedule text first.';
      });
      return;
    }
    final parsed = SchedulePhotoParser.parseRawText(text);
    setState(() {
      _drafts = parsed;
      _isError = parsed.isEmpty;
      _statusMessage = parsed.isEmpty
          ? 'No classes detected. Include days (e.g., MWF, TTh) and times (e.g., 8:00 AM - 9:30 AM) on each line.'
          : 'Parsed ${parsed.length} ${parsed.length == 1 ? 'class' : 'classes'}. Review below and tap Import.';
    });
  }

  Future<void> _editDraft(int index) async {
    final draft = _drafts[index];
    final tempSchedule = draft.toSubjectSchedule(id: 'draft_$index');
    final edited = await Navigator.of(context).push<SubjectSchedule>(
      MaterialPageRoute<SubjectSchedule>(
        builder: (_) => SubjectScheduleFormPage(
          initialWeekday: widget.initialWeekday,
          existingSchedule: tempSchedule,
        ),
      ),
    );
    if (!mounted || edited == null) return;
    setState(() {
      draft
        ..subjectCode = edited.subjectCode
        ..subject = edited.subject
        ..section = edited.section
        ..classroom = edited.classroom
        ..teacherName = edited.teacherName
        ..sessions = Map<SessionType, SessionSchedule>.of(edited.sessions)
        ..selected = true;
    });
  }

  void _confirmImport() {
    final selected = _drafts.where((d) => d.selected).toList();
    if (selected.isEmpty) return;

    final baseMicros = DateTime.now().microsecondsSinceEpoch;
    final schedules = <SubjectSchedule>[];
    for (var i = 0; i < selected.length; i++) {
      schedules.add(
        selected[i].toSubjectSchedule(id: '${baseMicros}_$i'),
      );
    }
    Navigator.of(context).pop(schedules);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Schedule from Photo'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.document_scanner_outlined,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Auto-Schedule from Photo',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '100% offline on-device scan of your COR, study load, or timetable screenshot.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('import_pick_gallery_button'),
                          onPressed: _isScanning
                              ? null
                              : () => _scanFromPhoto(PhotoImportSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Pick Photo'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('import_take_photo_button'),
                          onPressed: _isScanning
                              ? null
                              : () => _scanFromPhoto(PhotoImportSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Take Photo'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('toggle_raw_ocr_text_button'),
                      onPressed: () {
                        setState(() => _showRawEditor = !_showRawEditor);
                      },
                      icon: Icon(
                        _showRawEditor
                            ? Icons.expand_less
                            : Icons.text_snippet_outlined,
                        size: 18,
                      ),
                      label: Text(
                        _showRawEditor
                            ? 'Hide Scanned / Pasted Text'
                            : 'Edit or Paste Schedule Text Manually',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isScanning) ...<Widget>[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Scanning photo on device...',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (_statusMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              color: _isError ? cs.errorContainer : cs.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      _isError
                          ? Icons.info_outline
                          : Icons.check_circle_outline,
                      size: 20,
                      color: _isError
                          ? cs.onErrorContainer
                          : cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _isError
                              ? cs.onErrorContainer
                              : cs.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_showRawEditor) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Scanned / Pasted Schedule Text',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('import_raw_text_field'),
                      controller: _rawTextController,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText:
                            'Example:\nCS 101 | Data Structures | Sec A | MWF | 8:00 AM - 9:30 AM | Room 304 | Prof. Santos',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      key: const Key('reparse_schedule_text_button'),
                      onPressed: _parseFromManualText,
                      icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                      label: const Text('Parse Schedule Text'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_drafts.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Detected Classes (${_drafts.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final selectAll = _selectedCount < _drafts.length;
                    setState(() {
                      for (final d in _drafts) {
                        d.selected = selectAll;
                      }
                    });
                  },
                  child: Text(
                    _selectedCount < _drafts.length
                        ? 'Select All'
                        : 'Clear Selection',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < _drafts.length; i++)
              _ParsedDraftCard(
                index: i,
                draft: _drafts[i],
                onChanged: (checked) {
                  setState(() => _drafts[i].selected = checked ?? false);
                },
                onEdit: () => _editDraft(i),
              ),
          ],
        ],
      ),
      bottomNavigationBar: _drafts.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  key: const Key('confirm_photo_import_button'),
                  onPressed: _selectedCount == 0 ? null : _confirmImport,
                  icon: const Icon(Icons.download_done_rounded),
                  label: Text(
                    'Import $_selectedCount ${_selectedCount == 1 ? 'Class' : 'Classes'}',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ParsedDraftCard extends StatelessWidget {
  const _ParsedDraftCard({
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onEdit,
  });

  final int index;
  final ParsedScheduleDraft draft;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      key: Key('parsed_draft_card_$index'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Checkbox(
              value: draft.selected,
              onChanged: onChanged,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      if (draft.subjectCode.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            draft.subjectCode,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      Text(
                        draft.subject,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Sec ${draft.section}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (draft.classroom.isNotEmpty ||
                      draft.teacherName.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: <Widget>[
                        if (draft.classroom.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.meeting_room_outlined,
                                size: 14,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                draft.classroom,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        if (draft.teacherName.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.person_outline,
                                size: 14,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                draft.teacherName,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  ...draft.sessions.values.map((session) {
                    final accent =
                        AppTheme.sessionColor(session.type, theme.brightness);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                            session.type.shortLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${session.formatDaysSummary()} · ${session.formatTimeRange()}',
                            style: AppTheme.tabularStyle(
                              theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            IconButton(
              key: Key('edit_parsed_draft_$index'),
              tooltip: 'Edit class details',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
