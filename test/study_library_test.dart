import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/study_document.dart';
import 'package:remirror/study_article_import.dart';
import 'package:remirror/study_library.dart';
import 'package:remirror/study_storage.dart';

void main() {
  test('saved sentences keep analysis and follow a corrected translation', () {
    final library = StudyLibrary();
    final first = StudySentence(
      paragraph: 1,
      english: 'Learning helps.',
      chinese: '学习有用。',
      grammarByDepth: {
        'standard': {
          'skeleton': 'Learning 作主语。',
          'points': '动名词作主语。',
          'understanding': '学习有帮助。'
        }
      },
    );
    library.saveSentence(first, 'article:0');
    library.saveSentence(first, 'article2:0');
    expect(library.sentences.length, 1);
    expect(library.sentences.values.single.sources.length, 2);

    first.chinese = '学习有帮助。';
    first.grammarByDepth.clear();
    library.syncSentence(first, 'article:0', 'Learning helps.', '学习有用。');
    expect(library.sentences.length, 2);
    expect(
        library.sentences[sentenceKey('Learning helps.', '学习有帮助。')]?.analyses,
        isEmpty);
    expect(
        library.sentences[sentenceKey('Learning helps.', '学习有用。')]
            ?.analyses['standard']?['skeleton'],
        'Learning 作主语。');

    final restored = StudyLibrary.fromJson(library.toJson());
    expect(restored.sentences.length, 2);
    expect(
        restored.sentences.values
            .where((entry) => entry.chinese == '学习有用。')
            .single
            .sources,
        {'article2:0'});
  });

  test('XLSX carries words used by the article and its sentence favorites',
      () async {
    final document = StudyDocument(
        id: 'second',
        title: 'Second',
        sourceText: 'He went.',
        sentences: [
          StudySentence(paragraph: 1, english: 'He went.', chinese: '他走了。')
        ]);
    final library = StudyLibrary(words: {
      'go': SavedWord(lemma: 'go', examples: [
        SavedWordExample(
            word: 'go',
            sentence: 'Go.',
            source: 'First',
            analysis: {'meaning': '走'})
      ]),
      'read': SavedWord(lemma: 'read'),
    });
    library.saveSentence(document.sentences.single, 'second:0');
    final included = await library.forDocument(
        document,
        (word) async =>
            word.toLowerCase() == 'went' ? 'go' : word.toLowerCase());
    expect(included.words.keys, {'go'});
    final imported = await ArticleImporter.importBytes(
        'second.xlsx', exportStudy(document, library: included));
    expect(imported, isA<StudyImportBundle>());
    final bundle = imported as StudyImportBundle;
    expect(bundle.library.words['go']?.examples.single.source, 'First');
    expect(bundle.library.sentences.keys,
        contains(sentenceKey('He went.', '他走了。')));
  });
}
