import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'back_translation.dart';
import 'practice_workbook.dart';
import 'translation.dart';

class PracticeSession {
  const PracticeSession({
    required this.id,
    required this.title,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.paragraphs,
    required this.answers,
    required this.submitted,
    this.importedPractice,
  });

  final String id;
  final String title;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TranslatedParagraph> paragraphs;
  final PracticeWorkbook? importedPractice;
  final Map<int, String> answers;
  final bool submitted;

  List<PracticeSentence> get sentences =>
      importedPractice?.sentences ?? buildPracticeSentences(paragraphs);
  int get sentenceCount =>
      sentences.where((sentence) => sentence.canAnswer).length;
  int get answeredCount =>
      answers.values.where((answer) => answer.trim().isNotEmpty).length;

  PracticeSession withProgress(Map<int, String> value, bool isSubmitted) =>
      PracticeSession(
        id: id,
        title: title,
        source: source,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        paragraphs: paragraphs,
        answers: Map.of(value),
        submitted: isSubmitted,
        importedPractice: importedPractice,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'paragraphs': [
          for (final paragraph in paragraphs)
            {
              'original': paragraph.original,
              'translated': paragraph.translated
            },
        ],
        'importedPractice': importedPractice?.toJson(),
        'answers': answers.map((key, value) => MapEntry(key.toString(), value)),
        'submitted': submitted,
      };

  factory PracticeSession.fromJson(Map<String, dynamic> json) =>
      PracticeSession(
        id: json['id'] as String,
        title: json['title'] as String,
        source: json['source'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        paragraphs: (json['paragraphs'] as List).map((item) {
          final paragraph = item as Map<String, dynamic>;
          return TranslatedParagraph(
            paragraph['original'] as String,
            paragraph['translated'] as String,
          );
        }).toList(),
        importedPractice: json['importedPractice'] == null
            ? null
            : PracticeWorkbook.fromJson(
                json['importedPractice'] as Map<String, dynamic>,
              ),
        answers: (json['answers'] as Map).map(
          (key, value) => MapEntry(int.parse(key as String), value as String),
        ),
        submitted: json['submitted'] as bool,
      );
}

class PracticeHistoryStore {
  const PracticeHistoryStore({this.directory});

  final Directory? directory;

  Future<File> _file() async {
    final root = directory ?? await getApplicationSupportDirectory();
    await root.create(recursive: true);
    return File('${root.path}${Platform.pathSeparator}practice_history.json');
  }

  Future<List<PracticeSession>> load() async {
    final file = await _file();
    final backup = File('${file.path}.bak');
    if (!await file.exists() && !await backup.exists()) return [];
    try {
      return await _read(file);
    } catch (_) {
      if (await backup.exists()) return _read(backup);
      rethrow;
    }
  }

  Future<List<PracticeSession>> _read(File file) async {
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw const FormatException('不支持的练习记录版本');
    }
    return (data['sessions'] as List)
        .map((item) => PracticeSession.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<PracticeSession> sessions) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    final data = jsonEncode({
      'version': 1,
      'sessions': [for (final session in sessions) session.toJson()],
    });
    await temporary.writeAsString(data, flush: true);
    if (await file.exists()) {
      await file.copy(backup.path);
      await file.delete();
    }
    await temporary.rename(file.path);
    await file.copy(backup.path);
  }
}
