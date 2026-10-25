import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:pdf_document/pdf_document.dart' as pdf;
import 'package:pdf_graphics/pdf_graphics.dart' as pdf_graphics;
import 'package:xml/xml.dart';

/// Extracts editable article text without starting a translation request.
class ArticleImport {
  static const extensions = ['txt', 'md', 'docx', 'pdf'];

  static Future<String> extract(String fileName, Uint8List bytes) async {
    if (bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('文件超过 50 MB，请先截取要练习的文章。');
    }
    final extension = fileName.split('.').last.toLowerCase();
    final String text;
    switch (extension) {
      case 'txt':
        text = _decodeText(bytes);
      case 'md':
        text = _extractMarkdown(_decodeText(bytes));
      case 'docx':
        text = _extractDocx(bytes);
      case 'pdf':
        text = await _extractPdf(bytes);
      default:
        throw const FormatException('仅支持 TXT、Markdown、DOCX 和 PDF 文件。');
    }
    final normalized = _normalize(text);
    if (normalized.isEmpty) {
      throw FormatException(extension == 'pdf'
          ? 'PDF 中没有可提取的文字。扫描版 PDF 暂不支持，请使用可选中文字的文件。'
          : '文件中没有可导入的文字。');
    }
    return normalized;
  }

  static String _decodeText(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      return _decodeUtf16(bytes, littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      return _decodeUtf16(bytes, littleEndian: false);
    }
    try {
      return utf8.decode(bytes).replaceFirst('\ufeff', '');
    } on FormatException {
      throw const FormatException('文本编码无法识别，请将文件保存为 UTF-8 或 UTF-16 后重试。');
    }
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    if ((bytes.length - 2).isOdd) {
      throw const FormatException('UTF-16 文本不完整，请检查文件是否损坏。');
    }
    final units = <int>[];
    for (var index = 2; index < bytes.length; index += 2) {
      units.add(littleEndian
          ? bytes[index] | bytes[index + 1] << 8
          : bytes[index] << 8 | bytes[index + 1]);
    }
    return String.fromCharCodes(units);
  }

  static String _extractMarkdown(String source) {
    final document = markdown.Document(
      extensionSet: markdown.ExtensionSet.gitHubFlavored,
    );
    final blocks = <String>[];

    void addBlock(String value) {
      final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleaned.isNotEmpty) blocks.add(cleaned);
    }

    void visit(markdown.Node node) {
      if (node is! markdown.Element) return;
      final tag = node.tag;
      if (tag == 'pre' || tag == 'hr' || tag == 'img') return;
      if (tag == 'table') {
        for (final row in _markdownElements(node, 'tr')) {
          final cells = (row.children ?? const <markdown.Node>[])
              .whereType<markdown.Element>()
              .where((cell) => cell.tag == 'th' || cell.tag == 'td')
              .map(_markdownInline)
              .where((cell) => cell.trim().isNotEmpty);
          addBlock(cells.join(' | '));
        }
        return;
      }
      if (tag == 'li') {
        final ownContent = (node.children ?? const <markdown.Node>[])
            .where((child) =>
                child is! markdown.Element ||
                (child.tag != 'ul' && child.tag != 'ol'))
            .map(_markdownInline)
            .join();
        addBlock(ownContent);
        for (final child in node.children ?? const <markdown.Node>[]) {
          if (child is markdown.Element &&
              (child.tag == 'ul' || child.tag == 'ol')) {
            visit(child);
          }
        }
        return;
      }
      if (tag == 'p' || RegExp(r'^h[1-6]$').hasMatch(tag)) {
        addBlock(_markdownInline(node));
        return;
      }
      for (final child in node.children ?? const <markdown.Node>[]) {
        visit(child);
      }
    }

    for (final node in document.parse(source)) {
      visit(node);
    }
    return blocks.join('\n\n');
  }

  static Iterable<markdown.Element> _markdownElements(
      markdown.Element parent, String tag) sync* {
    for (final child in parent.children ?? const <markdown.Node>[]) {
      if (child is markdown.Element) {
        if (child.tag == tag) yield child;
        yield* _markdownElements(child, tag);
      }
    }
  }

  static String _markdownInline(markdown.Node node) {
    if (node is markdown.Text) return node.text;
    if (node is! markdown.Element || node.tag == 'code' || node.tag == 'img') {
      return '';
    }
    if (node.tag == 'br') return ' ';
    return (node.children ?? const <markdown.Node>[])
        .map(_markdownInline)
        .join();
  }

  static String _extractDocx(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final file = archive.findFile('word/document.xml');
      if (file == null) throw const FormatException('DOCX 中找不到文档正文。');
      final document =
          XmlDocument.parse(utf8.decode(file.content as List<int>));
      final body = document.descendants
          .whereType<XmlElement>()
          .firstWhere((element) => element.name.local == 'body');
      final blocks = <String>[];
      for (final child in body.children.whereType<XmlElement>()) {
        if (child.name.local == 'p') {
          final paragraph = _docxParagraph(child);
          if (paragraph.isNotEmpty) blocks.add(paragraph);
        } else if (child.name.local == 'tbl') {
          for (final row in child.children.whereType<XmlElement>()) {
            if (row.name.local != 'tr') continue;
            final cells = <String>[];
            for (final cell in row.children.whereType<XmlElement>()) {
              if (cell.name.local != 'tc') continue;
              final value = cell.children
                  .whereType<XmlElement>()
                  .where((part) => part.name.local == 'p')
                  .map(_docxParagraph)
                  .where((part) => part.isNotEmpty)
                  .join(' / ');
              if (value.isNotEmpty) cells.add(value);
            }
            if (cells.isNotEmpty) blocks.add(cells.join(' | '));
          }
        }
      }
      return blocks.join('\n\n');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法读取 DOCX 文件，请确认文件未损坏。');
    }
  }

  static String _docxParagraph(XmlElement paragraph) {
    final buffer = StringBuffer();
    void visit(XmlNode node) {
      if (node is! XmlElement) return;
      switch (node.name.local) {
        case 'del':
          return;
        case 't':
          buffer.write(node.innerText);
          return;
        case 'tab':
          buffer.write(' ');
          return;
        case 'br':
          buffer.write(' ');
          return;
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(paragraph);
    return buffer.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  static Future<String> _extractPdf(Uint8List bytes) async {
    try {
      final document = pdf.PdfDocument.open(bytes);
      final pages = <String>[];
      for (var index = 0; index < document.pageCount; index++) {
        final page = pdf_graphics.PdfTextExtractor.extract(document, index).text.trim();
        if (page.isNotEmpty) pages.add(page);
      }
      return pages.join('\n\n');
    } catch (_) {
      throw const FormatException('无法读取 PDF 文件，请确认文件未损坏或未加密。');
    }
  }

  static String _normalize(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u00a0', ' ')
      .replaceAll('\u00ad', '')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
