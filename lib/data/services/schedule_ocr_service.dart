import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'schedule_photo_parser.dart';

enum PhotoImportSource { gallery, camera }

class ScheduleOcrResult {
  const ScheduleOcrResult({
    required this.rawText,
    required this.lines,
    this.imagePath,
  });

  final String rawText;
  final List<OcrTextLine> lines;
  final String? imagePath;
}

/// Abstracts photo picking and on-device OCR so schedule photo import works
/// 100% offline on Android and remains fully testable without native channels.
abstract class ScheduleOcrService {
  Future<ScheduleOcrResult?> pickAndRecognize(PhotoImportSource source);
}

class MlKitScheduleOcrService implements ScheduleOcrService {
  MlKitScheduleOcrService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  bool get _supportsMlKit =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<ScheduleOcrResult?> pickAndRecognize(PhotoImportSource source) async {
    if (!_supportsMlKit) {
      throw UnsupportedError(
        'On-device photo scanning runs on Android/iOS. You can paste schedule text below instead.',
      );
    }

    final picked = await _picker.pickImage(
      source: source == PhotoImportSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 95,
    );
    if (picked == null) return null;

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(picked.path);
      final recognized = await recognizer.processImage(inputImage);
      final lines = <OcrTextLine>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final box = line.boundingBox;
          lines.add(
            OcrTextLine(
              text: line.text,
              left: box.left,
              top: box.top,
              right: box.right,
              bottom: box.bottom,
            ),
          );
        }
      }
      final reconstructed =
          SchedulePhotoParser.reconstructVisualRows(lines).join('\n');
      return ScheduleOcrResult(
        rawText: reconstructed.isNotEmpty ? reconstructed : recognized.text,
        lines: lines,
        imagePath: picked.path,
      );
    } finally {
      await recognizer.close();
    }
  }
}
