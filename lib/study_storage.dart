import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:path_provider/path_provider.dart';

import 'study_document.dart';

class StudyStore {
  const StudyStore();

  Future<bool> exists() async {
    final file = await _file();
    return await file.exists() || await File('${file.path}.bak').exists();
  }

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(
        '${directory.path}${Platform.pathSeparator}remirror_studies.json');
  }

  Future<List<StudyDocument>> load() async {
    final file = await _file();
    final backup = File('${file.path}.bak');
    if (!await file.exists() && !await backup.exists()) return [];
    Future<List<StudyDocument>> read(File source) async {
      final json = jsonDecode(await source.readAsString()) as List;
      return json
          .map((item) => StudyDocument.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    try {
      return await read(file);
    } catch (_) {
      if (await backup.exists()) return read(backup);
      rethrow;
    }
  }

  Future<void> save(List<StudyDocument> documents) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(
        jsonEncode(documents.map((d) => d.toJson()).toList()),
        flush: true);
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temporary.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await file.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }
}

Uint8List exportStudy(StudyDocument document) {
  final workbook = Excel.createExcel();
  workbook.rename('Sheet1', '文章');
  final article = workbook['文章'];
  _row(article, 0, ['段落', '英文原句', '中文参考']);
  for (var index = 0; index < document.sentences.length; index++) {
    final sentence = document.sentences[index];
    _row(article, index + 1, [
      '${sentence.paragraph}',
      sentence.english,
      sentence.chinese,
    ]);
  }
  article.setColumnWidth(1, 70);
  article.setColumnWidth(2, 70);

  final grammar = workbook['语法分析'];
  _row(grammar, 0, ['句子序号', '英文原句', '句子结构', '关键语法', '解释']);
  var grammarRow = 1;
  for (var index = 0; index < document.sentences.length; index++) {
    final sentence = document.sentences[index];
    if (sentence.grammar == null) continue;
    _row(grammar, grammarRow++, [
      '${index + 1}',
      sentence.english,
      sentence.grammar!['structure'] ?? '',
      sentence.grammar!['grammar'] ?? '',
      sentence.grammar!['explanation'] ?? '',
    ]);
  }

  final words = workbook['生词'];
  _row(words, 0, ['句子序号', '单词', '上下文释义', '词性', '用法']);
  var wordRow = 1;
  for (var index = 0; index < document.sentences.length; index++) {
    for (final entry in document.sentences[index].words.entries) {
      _row(words, wordRow++, [
        '${index + 1}',
        entry.key,
        entry.value['meaning'] ?? '',
        entry.value['partOfSpeech'] ?? '',
        entry.value['usage'] ?? '',
      ]);
    }
  }

  final attempts = workbook['回译评价'];
  _row(attempts, 0, [
    '句子序号',
    '轮次',
    '中文提示',
    '英文原句',
    '我的回译',
    '语法',
    '语义',
    '自然度',
    '改进建议',
    '提交时间',
  ]);
  var attemptRow = 1;
  for (var index = 0; index < document.sentences.length; index++) {
    final sentence = document.sentences[index];
    for (var number = 0; number < sentence.attempts.length; number++) {
      final attempt = sentence.attempts[number];
      _row(attempts, attemptRow++, [
        '${index + 1}',
        '${number + 1}',
        attempt.chinesePrompt ?? sentence.chinese,
        attempt.englishOriginal ?? sentence.english,
        attempt.answer,
        attempt.review?['grammar'] ?? '',
        attempt.review?['meaning'] ?? '',
        attempt.review?['naturalness'] ?? '',
        attempt.review?['advice'] ?? '',
        attempt.createdAt.toIso8601String(),
      ]);
    }
  }

  _row(workbook['_ReMirror'], 0, [jsonEncode(document.toJson())]);
  final encoded = workbook.encode();
  if (encoded == null) throw const FormatException('生成 XLSX 文件失败。');
  return Uint8List.fromList(encoded);
}

void _row(Sheet sheet, int row, List<String> values) {
  for (var column = 0; column < values.length; column++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
        .value = TextCellValue(values[column]);
  }
}
