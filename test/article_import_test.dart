import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/article_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('imports UTF-8 and UTF-16 text without byte order marks', () async {
    final utf8Text = await ArticleImport.extract(
      'article.TXT',
      Uint8List.fromList(
          [0xef, 0xbb, 0xbf, ...utf8.encode('First.\n\nSecond.')]),
    );
    expect(utf8Text, 'First.\n\nSecond.');

    final utf16Text = await ArticleImport.extract(
      'article.txt',
      Uint8List.fromList([0xff, 0xfe, 0x48, 0, 0x69, 0]),
    );
    expect(utf16Text, 'Hi');
  });

  test('imports Markdown prose, lists, and table without code or syntax',
      () async {
    const source = '''# A title

An **English** [article](https://example.com) with `code`.

- First point
- Second point

| Word | Meaning |
| --- | --- |
| Apple | Fruit |

```dart
print('skip me');
```
''';
    final text = await ArticleImport.extract(
      'article.md',
      Uint8List.fromList(utf8.encode(source)),
    );
    expect(text, contains('A title\n\nAn English article with .'));
    expect(text, contains('First point\n\nSecond point'));
    expect(text, contains('Word | Meaning\n\nApple | Fruit'));
    expect(text, isNot(contains('print')));
    expect(text, isNot(contains('https://')));
  });

  test('imports DOCX body paragraphs and table in document order', () async {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Heading</w:t></w:r></w:p>
    <w:p><w:r><w:t>Hello </w:t></w:r><w:r><w:t>world.</w:t></w:r><w:del><w:r><w:delText>old</w:delText></w:r></w:del></w:p>
    <w:tbl><w:tr>
      <w:tc><w:p><w:r><w:t>One</w:t></w:r></w:p></w:tc>
      <w:tc><w:p><w:r><w:t>Two</w:t></w:r></w:p></w:tc>
    </w:tr></w:tbl>
  </w:body>
</w:document>''';
    final content = utf8.encode(xml);
    final archive = Archive()
      ..addFile(ArchiveFile('word/document.xml', content.length, content));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    expect(
      await ArticleImport.extract('article.docx', bytes),
      'Heading\n\nHello world.\n\nOne | Two',
    );
  });

  test('extracts selectable text from PDF', () async {
    final text = await ArticleImport.extract('article.pdf', _simplePdf());
    expect(text, contains('Hello world.'));
  });

  test('explains that a PDF without a text layer needs another source',
      () async {
    await expectLater(
      ArticleImport.extract('scan.pdf', _simplePdf(content: '')),
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('扫描版 PDF 暂不支持'),
      )),
    );
  });
}

Uint8List _simplePdf({
  String content = 'BT /F1 12 Tf 72 720 Td (Hello world.) Tj ET',
}) {
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(buffer.length);
    buffer.write('${index + 1} 0 obj\n${objects[index]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n');
  buffer.write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(ascii.encode(buffer.toString()));
}
