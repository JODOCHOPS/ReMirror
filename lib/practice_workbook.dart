import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart';

import 'back_translation.dart';

/// The data needed to continue an imported exercise without translating it again.
class PracticeWorkbook {
  PracticeWorkbook._({
    required this.sentences,
    required this.rowIndexes,
    required this.previousAnswers,
    required this.roundNumber,
    required this.chineseTitle,
    required this.englishTitle,
    this.sourceBytes,
  });

  final List<PracticeSentence> sentences;
  final List<int> rowIndexes;
  final Map<int, String> previousAnswers;
  final int roundNumber;
  final String chineseTitle;
  final String englishTitle;
  final Uint8List? sourceBytes;

  String get nextRoundSheetName => '第${_chineseNumber(roundNumber + 1)}轮';

  factory PracticeWorkbook.fromParagraphs(List<PracticeSentence> sentences) {
    final rowIndexes = <int>[];
    var row = 1;
    int? lastParagraph;
    for (final sentence in sentences) {
      if (lastParagraph != null && sentence.paragraphNumber != lastParagraph) {
        row++;
      }
      rowIndexes.add(row++);
      lastParagraph = sentence.paragraphNumber;
    }
    return PracticeWorkbook._(
      sentences: sentences,
      rowIndexes: rowIndexes,
      previousAnswers: const {},
      roundNumber: 0,
      chineseTitle: '中文参考',
      englishTitle: '英文原文',
    );
  }

  Map<String, dynamic> toJson() => {
        'sentences': [
          for (final sentence in sentences)
            {
              'paragraphNumber': sentence.paragraphNumber,
              'sentenceNumber': sentence.sentenceNumber,
              'original': sentence.original,
              'reference': sentence.reference,
            },
        ],
        'rowIndexes': rowIndexes,
        'previousAnswers': previousAnswers.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
        'roundNumber': roundNumber,
        'chineseTitle': chineseTitle,
        'englishTitle': englishTitle,
        'sourceBytes': sourceBytes == null ? null : base64Encode(sourceBytes!),
      };

  factory PracticeWorkbook.fromJson(Map<String, dynamic> json) =>
      PracticeWorkbook._(
        sentences: (json['sentences'] as List).map((item) {
          final sentence = item as Map<String, dynamic>;
          return PracticeSentence(
            paragraphNumber: sentence['paragraphNumber'] as int,
            sentenceNumber: sentence['sentenceNumber'] as int,
            original: sentence['original'] as String?,
            reference: sentence['reference'] as String?,
          );
        }).toList(),
        rowIndexes: (json['rowIndexes'] as List).cast<int>(),
        previousAnswers: (json['previousAnswers'] as Map).map(
          (key, value) => MapEntry(int.parse(key as String), value as String),
        ),
        roundNumber: json['roundNumber'] as int,
        chineseTitle: json['chineseTitle'] as String,
        englishTitle: json['englishTitle'] as String,
        sourceBytes: json['sourceBytes'] == null
            ? null
            : base64Decode(json['sourceBytes'] as String),
      );

  factory PracticeWorkbook.import(Uint8List bytes) {
    final Excel excel;
    try {
      excel = _decodeWorkbook(bytes);
    } catch (_) {
      throw const FormatException('无法读取 XLSX 文件，请确认文件未损坏。');
    }
    final rounds = excel.tables.keys
        .where((name) => RegExp(r'^第[一二三四五六七八九十百\d]+轮$').hasMatch(name))
        .toList();
    if (rounds.isEmpty) {
      throw const FormatException('找不到“第一轮”等练习工作表。');
    }
    final sheet = excel.tables[rounds.last]!;
    final rows = sheet.rows;
    if (rows.length < 2) {
      throw const FormatException('练习工作表没有可导入的句子。');
    }
    final sentences = <PracticeSentence>[];
    final rowIndexes = <int>[];
    final previousAnswers = <int, String>{};
    var paragraph = 1;
    var sentenceNumber = 0;
    var afterBlank = false;
    var hasChinese = false;
    var hasEnglish = false;
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final chinese = _text(row, 0);
      final answer = _text(row, 1);
      final english = _text(row, 2);
      if (chinese == null && english == null) {
        if (sentences.isNotEmpty) afterBlank = true;
        continue;
      }
      if (afterBlank) {
        paragraph++;
        sentenceNumber = 0;
        afterBlank = false;
      }
      sentenceNumber++;
      hasChinese |= chinese != null;
      hasEnglish |= english != null;
      final index = sentences.length;
      sentences.add(PracticeSentence(
        paragraphNumber: paragraph,
        sentenceNumber: sentenceNumber,
        original: english,
        reference: chinese,
      ));
      rowIndexes.add(rowIndex);
      if (answer != null) previousAnswers[index] = answer;
    }
    if (sentences.isEmpty || !hasChinese || !hasEnglish) {
      throw const FormatException('练习工作表需要 A 列中文和 C 列英文原文。');
    }
    return PracticeWorkbook._(
      sentences: sentences,
      rowIndexes: rowIndexes,
      previousAnswers: previousAnswers,
      roundNumber: rounds.length,
      chineseTitle: _text(rows.first, 0) ?? '中文参考',
      englishTitle: _text(rows.first, 2) ?? '英文原文',
      sourceBytes: bytes,
    );
  }

  Uint8List export(Map<int, String> answers) {
    final excel = sourceBytes == null
        ? Excel.createExcel()
        : _decodeWorkbook(sourceBytes!);
    if (sourceBytes == null) {
      excel.rename('Sheet1', '原文解析');
      final originalSheet = excel['原文解析'];
      _put(originalSheet, 0, 0, englishTitle);
      for (var index = 0; index < sentences.length; index++) {
        _put(originalSheet, rowIndexes[index], 0, sentences[index].original);
      }
      originalSheet.setColumnWidth(0, 70);
    }
    final name = nextRoundSheetName;
    if (excel.tables.containsKey(name)) {
      throw const FormatException('文件中已存在目标轮次工作表，请检查工作表名称。');
    }
    final sheet = excel[name];
    _put(sheet, 0, 0, chineseTitle);
    _put(sheet, 0, 1, '第${_chineseNumber(roundNumber + 1)}轮回译');
    _put(sheet, 0, 2, englishTitle);
    for (var index = 0; index < sentences.length; index++) {
      final row = rowIndexes[index];
      final sentence = sentences[index];
      _put(sheet, row, 0, sentence.reference);
      _put(sheet, row, 1, answers[index]?.trim());
      _put(sheet, row, 2, sentence.original);
    }
    sheet.setColumnWidth(0, 55);
    sheet.setColumnWidth(1, 65);
    sheet.setColumnWidth(2, 65);
    final result = excel.encode();
    if (result == null) {
      throw const FormatException('生成 XLSX 文件失败。');
    }
    return Uint8List.fromList(result);
  }
}

Excel _decodeWorkbook(Uint8List bytes) {
  // Some spreadsheet writers declare custom formats with built-in IDs 41–44.
  // excel expects custom IDs to start at 164, even when those formats are not
  // used by any cell. Remap them in memory so the supplied example can load.
  final archive = ZipDecoder().decodeBytes(bytes);
  final styles = archive.findFile('xl/styles.xml');
  if (styles == null) return Excel.decodeBytes(bytes);
  var xml = utf8.decode(styles.content as List<int>);
  final customIds = RegExp(r'<numFmt\b[^>]*\bnumFmtId="(\d+)"')
      .allMatches(xml)
      .map((match) => int.parse(match.group(1)!))
      .toSet();
  final legacyIds = customIds.where((id) => id < 164).toList()..sort();
  if (legacyIds.isEmpty) return Excel.decodeBytes(bytes);
  var nextId = 164;
  if (customIds.isNotEmpty) {
    final largest = customIds.reduce((a, b) => a > b ? a : b);
    if (largest >= nextId) nextId = largest + 1;
  }
  final remapped = <int, int>{};
  for (final id in legacyIds) {
    remapped[id] = nextId++;
  }
  xml = xml.replaceAllMapped(RegExp(r'numFmtId="(\d+)"'), (match) {
    final id = int.parse(match.group(1)!);
    return 'numFmtId="${remapped[id] ?? id}"';
  });
  final content = utf8.encode(xml);
  archive.addFile(ArchiveFile('xl/styles.xml', content.length, content));
  return Excel.decodeBytes(ZipEncoder().encode(archive));
}

String? _text(List<Data?> row, int column) {
  if (column >= row.length) return null;
  final value = row[column]?.value;
  final text = switch (value) {
    TextCellValue() => value.toString(),
    null => null,
    _ => null,
  };
  return text == null || text.trim().isEmpty ? null : text.trim();
}

void _put(Sheet sheet, int row, int column, String? value) {
  if (value == null || value.isEmpty) return;
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
      .value = TextCellValue(value);
}

String _chineseNumber(int number) {
  const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  if (number < 10) return digits[number];
  if (number < 20) return '十${number == 10 ? '' : digits[number % 10]}';
  if (number < 100) {
    final ones = number % 10;
    return '${digits[number ~/ 10]}十${ones == 0 ? '' : digits[ones]}';
  }
  return '$number';
}
