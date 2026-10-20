import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/translation.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('offline source needs no API credentials', () {
    expect(
        const TranslationCredentials().isConfigured(TranslationSource.offline),
        isTrue);
  });

  test('bundled dictionary includes headwords, inflections and phrases', () {
    final file = File('assets/offline/dictionary.sqlite');
    expect(file.existsSync(), isTrue);
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      final learn = db
          .select('SELECT translation FROM entries WHERE word = ?', ['learn']);
      expect(learn.single['translation'], contains('学习'));
      final learning =
          db.select('SELECT lemma FROM entries WHERE word = ?', ['learning']);
      expect(learning.single['lemma'], 'learn');
      final phrase = db.select(
          'SELECT translation FROM entries WHERE word = ?', ['straight line']);
      expect(phrase, isNotEmpty);
    } finally {
      db.close();
    }
  });
}
