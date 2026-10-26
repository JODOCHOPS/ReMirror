import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/back_translation.dart';
import 'package:remirror/practice_workbook.dart';
import 'package:remirror/study_article_import.dart';
import 'package:remirror/study_document.dart';

void main() {
  test('the new study flow retains answers from an old Android workbook',
      () async {
    final document = await ArticleImporter.importBytes(
        'old-android.xlsx', _exampleWorkbook()) as StudyDocument;
    expect(document.sentences.first.english, 'Robots explore Mars.');
    expect(document.sentences.first.chinese, '机器人探索火星。');
    expect(
        document.sentences.first.attempts.single.answer, 'Robots go to Mars.');
    expect(document.sentences[2].paragraph, 2);
  });

  test('imports the example layout and appends a second round', () {
    final imported = PracticeWorkbook.import(_exampleWorkbook());
    expect(imported.nextRoundSheetName, '第二轮');
    expect(imported.sentences.first.reference, '机器人探索火星。');
    expect(imported.sentences.first.original, 'Robots explore Mars.');
    expect(imported.previousAnswers[0], 'Robots go to Mars.');
    expect(imported.sentences[2].paragraphNumber, 2);

    final exported = imported.export({0: 'I have seen robots.'});
    final workbook = Excel.decodeBytes(exported);
    expect(workbook.tables.keys, ['原文解析', '第一轮', '第二轮']);
    expect(workbook['第一轮'].cell(CellIndex.indexByString('B2')).value.toString(),
        'Robots go to Mars.');
    expect(
        workbook['原文解析'].cell(CellIndex.indexByString('A3')).value.toString(),
        'They are machine.');
    expect(workbook['第二轮'].cell(CellIndex.indexByString('A1')).value.toString(),
        '火星示例');
    expect(workbook['第二轮'].cell(CellIndex.indexByString('C1')).value.toString(),
        'Sample Mars');
    expect(workbook['第二轮'].cell(CellIndex.indexByString('B2')).value.toString(),
        'I have seen robots.');
    expect(workbook['第二轮'].cell(CellIndex.indexByString('B4')).value, isNull);

    final reimported = PracticeWorkbook.import(exported);
    expect(reimported.nextRoundSheetName, '第三轮');
    expect(reimported.previousAnswers[0], 'I have seen robots.');
  });

  test('exports a new exercise with paragraph spacing and imports it', () {
    final source = PracticeWorkbook.fromParagraphs(const [
      PracticeSentence(
        paragraphNumber: 1,
        sentenceNumber: 1,
        reference: '第一句。',
        original: 'First.',
      ),
      PracticeSentence(
        paragraphNumber: 2,
        sentenceNumber: 1,
        reference: '第二句。',
        original: 'Second.',
      ),
    ]);
    final bytes = source.export({0: '=SUM(1,2)', 1: 'Second.'});
    final workbook = Excel.decodeBytes(bytes);
    expect(workbook.tables.keys, ['原文解析', '第一轮']);
    expect(workbook['第一轮'].cell(CellIndex.indexByString('B2')).value,
        isA<TextCellValue>());
    final imported = PracticeWorkbook.import(Uint8List.fromList(bytes));
    expect(imported.sentences.length, 2);
    expect(imported.sentences.last.paragraphNumber, 2);
    expect(imported.previousAnswers[0], '=SUM(1,2)');
  });
}

Uint8List _exampleWorkbook() {
  final workbook = Excel.createExcel();
  workbook.rename('Sheet1', '原文解析');
  final original = workbook['原文解析'];
  _put(original, 'A1', 'Sample Mars');
  _put(original, 'A2', 'Robots explore Mars.');
  _put(original, 'A3', 'They are machine.');
  _put(original, 'A5', 'People learn from them.');
  final round = workbook['第一轮'];
  _put(round, 'A1', '火星示例');
  _put(round, 'B1', 'Sample Mars');
  _put(round, 'C1', 'Sample Mars');
  _put(round, 'A2', '机器人探索火星。');
  _put(round, 'B2', 'Robots go to Mars.');
  _put(round, 'C2', 'Robots explore Mars.');
  _put(round, 'A3', '它们是机器。');
  _put(round, 'B3', 'They are machines.');
  _put(round, 'C3', 'They are machines.');
  _put(round, 'A5', '人们向它们学习。');
  _put(round, 'B5', 'People learn from robots.');
  _put(round, 'C5', 'People learn from them.');

  // Reproduce the legacy custom format IDs used by the supplied example.
  final archive = ZipDecoder().decodeBytes(workbook.encode()!);
  final styles = archive.findFile('xl/styles.xml')!;
  var xml = utf8.decode(styles.content as List<int>);
  xml = xml.replaceAll(
    RegExp(r'<numFmts\b[^>]*(?:/>|>.*?</numFmts>)', dotAll: true),
    '',
  );
  xml = xml.replaceFirstMapped(
    RegExp(r'<styleSheet\b[^>]*>'),
    (match) => '${match.group(0)}<numFmts count="1">'
        '<numFmt numFmtId="41" formatCode="0.00"/></numFmts>',
  );
  final content = utf8.encode(xml);
  archive.addFile(ArchiveFile('xl/styles.xml', content.length, content));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void _put(Sheet sheet, String address, String value) {
  sheet.cell(CellIndex.indexByString(address)).value = TextCellValue(value);
}
