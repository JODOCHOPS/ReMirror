import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:pdf_document/pdf_document.dart' as pdf;
import 'package:pdf_graphics/pdf_graphics.dart' as pdf_graphics;

import 'practice_workbook.dart';
import 'sentence_splitter.dart';
import 'study_document.dart';
import 'study_library.dart';

class StudyImportBundle {
  StudyImportBundle(this.document, this.library);

  final StudyDocument document;
  final StudyLibrary library;
}

class SpreadsheetPreview {
  SpreadsheetPreview(this.workbook);

  final Excel workbook;

  List<String> get sheets => workbook.tables.keys
      .where((name) => name != '_ReMirror' && name != '_ReMirrorLibrary')
      .toList();

  List<List<String>> rows(String sheetName) => [
        for (final row in workbook.tables[sheetName]?.rows ?? <List<Data?>>[])
          [for (final cell in row) cell?.value?.toString().trim() ?? ''],
      ];

  StudyDocument importColumns({
    required String sheetName,
    required int englishColumn,
    int? chineseColumn,
    bool firstRowIsHeader = true,
    required String title,
  }) {
    final rows = this.rows(sheetName);
    final sentences = <StudySentence>[];
    var paragraph = 1;
    var pendingBreak = false;
    var needsAlignmentReview = false;
    for (var rowIndex = firstRowIsHeader ? 1 : 0;
        rowIndex < rows.length;
        rowIndex++) {
      final row = rows[rowIndex];
      String value(int? column) =>
          column == null || column >= row.length ? '' : row[column].trim();
      final english = value(englishColumn);
      final chinese = value(chineseColumn);
      if (english.isEmpty && chinese.isEmpty) {
        pendingBreak = sentences.isNotEmpty;
        continue;
      }
      if (english.isEmpty) continue;
      if (pendingBreak) paragraph++;
      pendingBreak = false;
      final englishParts = splitImportedSentences(english);
      final chineseParts = splitImportedSentences(chinese);
      if (chinese.isNotEmpty && englishParts.length != chineseParts.length) {
        needsAlignmentReview = true;
      }
      for (var index = 0; index < englishParts.length; index++) {
        sentences.add(StudySentence(
          paragraph: paragraph,
          english: englishParts[index],
          chinese: index < chineseParts.length
              ? index == englishParts.length - 1 &&
                      chineseParts.length > englishParts.length
                  ? chineseParts.skip(index).join(' ')
                  : chineseParts[index]
              : '',
        ));
      }
    }
    if (sentences.isEmpty) {
      throw const FormatException('选定的英文列没有可导入的句子。');
    }
    return StudyDocument(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      sourceText: rows
          .skip(firstRowIsHeader ? 1 : 0)
          .map(
            (row) => englishColumn < row.length ? row[englishColumn] : '',
          )
          .join('\n'),
      sentences: sentences,
      needsAlignmentReview: needsAlignmentReview,
    );
  }
}

List<String> splitImportedSentences(String text) {
  if (text.trim().isEmpty) return const [];
  return splitSentences(text);
}

class ArticleImporter {
  static Future<Object> importBytes(String filename, Uint8List bytes) async {
    final extension = filename.split('.').last.toLowerCase();
    switch (extension) {
      case 'txt':
      case 'md':
        return StudyDocument.fromText(_decodeText(bytes), title: filename);
      case 'docx':
        return StudyDocument.fromText(_extractDocx(bytes), title: filename);
      case 'pdf':
        final document = pdf.PdfDocument.open(bytes);
        final pages = <String>[];
        for (var index = 0; index < document.pageCount; index++) {
          pages
              .add(pdf_graphics.PdfTextExtractor.extract(document, index).text);
        }
        final text = pages.join('\n\n').trim();
        if (text.isEmpty) {
          throw const FormatException('PDF 没有可选中的文字；扫描版 PDF 暂不支持。');
        }
        return StudyDocument.fromText(text, title: filename);
      case 'xlsx':
        final workbook = Excel.decodeBytes(bytes);
        final saved = workbook.tables['_ReMirror'];
        if (saved != null && saved.rows.isNotEmpty) {
          final serialized = saved.rows.first.first?.value?.toString();
          if (serialized != null) {
            final document = StudyDocument.fromJson(
                jsonDecode(serialized) as Map<String, dynamic>);
            final librarySheet = workbook.tables['_ReMirrorLibrary'];
            final libraryJson =
                librarySheet?.rows.firstOrNull?.firstOrNull?.value?.toString();
            if (libraryJson != null) {
              return StudyImportBundle(
                  document,
                  StudyLibrary.fromJson(
                      jsonDecode(libraryJson) as Map<String, dynamic>));
            }
            return document;
          }
        }
        try {
          final legacy = PracticeWorkbook.import(bytes);
          return StudyDocument(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: filename,
            sourceText:
                legacy.sentences.map((s) => s.original ?? '').join('\n'),
            sentences: [
              for (var index = 0; index < legacy.sentences.length; index++)
                StudySentence(
                  paragraph: legacy.sentences[index].paragraphNumber,
                  english: legacy.sentences[index].original ?? '',
                  chinese: legacy.sentences[index].reference ?? '',
                  attempts: legacy.previousAnswers[index] == null
                      ? []
                      : [
                          StudyAttempt(
                            answer: legacy.previousAnswers[index]!,
                            createdAt: DateTime.now(),
                          ),
                        ],
                ),
            ],
          );
        } on FormatException {
          return SpreadsheetPreview(workbook);
        }
      default:
        throw const FormatException('不支持该文件格式。');
    }
  }
}

String _decodeText(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const FormatException('文本不是 UTF-8 编码，请先转换编码。');
  }
}

String _extractDocx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.findFile('word/document.xml');
  if (file == null) throw const FormatException('DOCX 缺少正文内容。');
  final xml = utf8.decode(file.content as List<int>);
  final paragraphs = <String>[];
  final unescape = HtmlUnescape();
  for (final paragraph
      in RegExp(r'<w:p(?:\s[^>]*)?>[\s\S]*?</w:p>').allMatches(xml)) {
    final content = paragraph.group(0)!;
    final buffer = StringBuffer();
    for (final token
        in RegExp(r'<w:t(?:\s[^>]*)?>([\s\S]*?)</w:t>|<w:tab\s*/>|<w:br\s*/>')
            .allMatches(content)) {
      if (token.group(1) != null) {
        buffer.write(unescape.convert(token.group(1)!));
      } else {
        buffer.write(' ');
      }
    }
    final text = buffer.toString().trim();
    if (text.isNotEmpty) paragraphs.add(text);
  }
  if (paragraphs.isEmpty) {
    throw const FormatException('DOCX 没有可导入的文字。');
  }
  return paragraphs.join('\n\n');
}
