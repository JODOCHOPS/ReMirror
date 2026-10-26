import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/study_article_import.dart';
import 'package:remirror/study_document.dart';
import 'package:remirror/study_storage.dart';

void main() {
  test('bilingual text aligns sentences and preserves paragraph boundaries',
      () {
    final document = StudyDocument.fromText(
      'Hello world. I am learning.\n你好，世界。我正在学习。\n\n'
      'Practice helps.\n练习有帮助。',
    );
    expect(document.sentences.map((s) => s.english), [
      'Hello world.',
      'I am learning.',
      'Practice helps.',
    ]);
    expect(document.sentences.map((s) => s.chinese), [
      '你好，世界。',
      '我正在学习。',
      '练习有帮助。',
    ]);
    expect(document.sentences.map((s) => s.paragraph), [1, 1, 2]);
    expect(document.hasAllReferences, isTrue);
  });

  test('English-only text marks missing translations for AI', () {
    final document = StudyDocument.fromText('One sentence. Another sentence.');
    expect(document.sentences.length, 2);
    expect(document.hasAllReferences, isFalse);
  });

  test('inline bilingual sentence skips AI translation', () {
    final document = StudyDocument.fromText('Hello world. 你好，世界。');
    expect(document.sentences.single.english, 'Hello world.');
    expect(document.sentences.single.chinese, '你好，世界。');
    expect(document.hasAllReferences, isTrue);
  });

  test('Chinese-first bilingual paragraphs align without translation', () {
    final document = StudyDocument.fromText(
        '你好，世界。\nHello world.\n\n练习有帮助。\nPractice helps.');
    expect(document.sentences.map((s) => s.chinese), ['你好，世界。', '练习有帮助。']);
    expect(document.hasAllReferences, isTrue);
  });

  test('DOCX import extracts paragraphs and bilingual content', () async {
    final xml = '<w:document xmlns:w="x"><w:body>'
        '<w:p><w:r><w:t>Hello world.</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>你好，世界。</w:t></w:r></w:p>'
        '</w:body></w:document>';
    final archive = Archive()
      ..addFile(ArchiveFile(
          'word/document.xml', utf8.encode(xml).length, utf8.encode(xml)));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final document =
        await ArticleImporter.importBytes('story.docx', bytes) as StudyDocument;
    expect(document.sentences.single.english, 'Hello world.');
    expect(document.sentences.single.chinese, '你好，世界。');
  });

  test('XLSX export and reimport retain analysis and every attempt', () async {
    final document = StudyDocument.fromText('Hello world.\n你好，世界。');
    final sentence = document.sentences.single;
    sentence.grammar = {
      'structure': '主谓结构',
      'grammar': '一般现在时',
      'explanation': '陈述事实'
    };
    sentence.grammarByDepth['beginner'] = {
      'skeleton': 'Hello 是问候。',
      'points': '短句。',
      'understanding': '你好。',
    };
    sentence.isFavorite = true;
    sentence.words['hello'] = {
      'meaning': '你好',
      'partOfSpeech': '感叹词',
      'usage': '用于问候'
    };
    sentence.savedWords.add('hello');
    document.finishedAt = DateTime(2026, 1, 3);
    sentence.attempts.addAll([
      StudyAttempt(
          answer: 'Hello world.',
          createdAt: DateTime(2026, 1, 1),
          chinesePrompt: sentence.chinese,
          englishOriginal: sentence.english,
          review: {
            'grammar': '正确',
            'meaning': '准确',
            'naturalness': '自然',
            'advice': '继续保持'
          }),
      StudyAttempt(
          answer: 'Hello, world!',
          createdAt: DateTime(2026, 1, 2),
          chinesePrompt: sentence.chinese,
          englishOriginal: sentence.english,
          review: {
            'grammar': '正确',
            'meaning': '准确',
            'naturalness': '自然',
            'advice': '继续保持'
          }),
    ]);
    final bytes = exportStudy(document);
    final workbook = Excel.decodeBytes(bytes);
    expect(workbook.tables.keys,
        containsAll(['文章', '语法分析', '生词', '回译评价', '_ReMirror']));
    final restored =
        await ArticleImporter.importBytes('study.xlsx', bytes) as StudyDocument;
    expect(restored.sentences.single.grammar?['structure'], '主谓结构');
    expect(restored.sentences.single.grammarByDepth['beginner']?['skeleton'],
        'Hello 是问候。');
    expect(restored.sentences.single.isFavorite, isTrue);
    expect(restored.sentences.single.words['hello']?['meaning'], '你好');
    expect(restored.sentences.single.savedWords, contains('hello'));
    expect(restored.sentences.single.attempts.length, 2);
    expect(restored.finishedAt, DateTime(2026, 1, 3));
  });

  test('skipped practice state survives local JSON roundtrip', () {
    final document = StudyDocument.fromText('Hello.\n你好。');
    document.sentences.single.skipped = true;
    final restored = StudyDocument.fromJson(document.toJson());
    expect(restored.sentences.single.skipped, isTrue);
  });

  test('ordinary XLSX lets the user map English and Chinese columns', () async {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('序号');
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('English');
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('中文');
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue('A test.');
    sheet.cell(CellIndex.indexByString('C2')).value = TextCellValue('一个测试。');
    final preview = await ArticleImporter.importBytes(
      'ordinary.xlsx',
      Uint8List.fromList(workbook.encode()!),
    ) as SpreadsheetPreview;
    final document = preview.importColumns(
      sheetName: 'Sheet1',
      englishColumn: 1,
      chineseColumn: 2,
      title: 'ordinary.xlsx',
    );
    expect(document.sentences.single.english, 'A test.');
    expect(document.sentences.single.chinese, '一个测试。');
  });

  test('text PDF imports without native PDF assets', () async {
    final document =
        await ArticleImporter.importBytes('story.pdf', _simplePdf())
            as StudyDocument;
    expect(document.sentences.single.english, contains('Hello world.'));
  });
}

Uint8List _simplePdf() {
  const stream = 'BT /F1 18 Tf 72 720 Td (Hello world.) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(latin1.encode(out.toString()).length);
    out.write('${index + 1} 0 obj\n${objects[index]}\nendobj\n');
  }
  final xref = latin1.encode(out.toString()).length;
  out.write('xref\n0 ${objects.length + 1}\n');
  out.write('0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n');
  out.write('startxref\n$xref\n%%EOF');
  return Uint8List.fromList(latin1.encode(out.toString()));
}
