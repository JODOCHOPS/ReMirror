import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/credential_store.dart';
import 'package:remirror/learning_ai.dart';
import 'package:remirror/main.dart';
import 'package:remirror/practice_history.dart';
import 'package:remirror/study_document.dart';
import 'package:remirror/study_library.dart';
import 'package:remirror/study_storage.dart';
import 'package:remirror/translation.dart';
import 'package:remirror/windows_study_page.dart';
import 'package:remirror/word_lemma.dart';

class _MemoryStore extends StudyStore {
  List<StudyDocument> documents = [];
  bool isExisting = true;

  @override
  Future<bool> exists() async => isExisting;

  @override
  Future<List<StudyDocument>> load() async => documents;

  @override
  Future<void> save(List<StudyDocument> value) async => documents = value;
}

class _MemoryLibraryStore extends StudyLibraryStore {
  StudyLibrary library = StudyLibrary();

  @override
  Future<StudyLibrary> load() async => library;

  @override
  Future<void> save(StudyLibrary value) async => library = value;
}

class _Lemmas extends WordLemmaResolver {
  @override
  Future<String> lemma(String word) async => switch (word.toLowerCase()) {
        'went' || 'gone' || 'goes' || 'going' => 'go',
        _ => word.toLowerCase(),
      };
}

class _OldHistory extends PracticeHistoryStore {
  _OldHistory(this.sessions);
  final List<PracticeSession> sessions;

  @override
  Future<List<PracticeSession>> load() async => sessions;
}

class _Credentials extends CredentialStore {
  const _Credentials();

  @override
  Future<TranslationCredentials> load() async => const TranslationCredentials(
        aiEndpoint: 'https://example.test/v1',
        aiApiKey: 'test',
        aiModel: 'test',
      );

  @override
  Future<void> save(TranslationCredentials value) async {}
}

class _Translation extends TranslationService {
  @override
  Future<String> translateChunk(String text, TranslationSource source,
          TranslationCredentials credentials) async =>
      '你好，世界。';
}

class _Ai extends LearningAiService {
  int grammarCalls = 0;
  int wordCalls = 0;

  @override
  Future<Map<String, String>> analyzeGrammar(
      String english, String chinese, TranslationCredentials credentials,
      {GrammarDepth depth = GrammarDepth.standard}) async {
    grammarCalls++;
    return {
      'structure': '主谓结构',
      'grammar': '一般现在时',
      'explanation': '陈述事实',
    };
  }

  @override
  Future<Map<String, String>> analyzeWord(
      String word, String sentence, TranslationCredentials credentials) async {
    wordCalls++;
    return {
      'meaning': '你好',
      'partOfSpeech': '感叹词',
      'usage': '用于问候',
    };
  }

  @override
  Future<Map<String, String>> reviewAttempt({
    required String chinese,
    required String original,
    required String answer,
    required TranslationCredentials credentials,
  }) async =>
      {
        'grammar': '语法正确',
        'meaning': '意思准确',
        'naturalness': '表达自然',
        'advice': '继续保持',
      };
}

void main() {
  testWidgets('existing Windows session and draft are migrated',
      (tester) async {
    final store = _MemoryStore()..isExisting = false;
    final now = DateTime(2026, 1, 1);
    final old = PracticeSession(
      id: '1',
      title: 'Old article',
      source: 'AI',
      createdAt: now,
      updatedAt: now,
      paragraphs: const [
        TranslatedParagraph('Hello world.', '你好，世界。',
            sentenceTranslations: ['你好，世界。'])
      ],
      answers: const {0: 'Hi world.'},
      submitted: false,
    );
    await tester.pumpWidget(MaterialApp(
        home: WindowsStudyPage(
      studyStore: store,
      credentialStore: const _Credentials(),
      translationService: _Translation(),
      aiService: _Ai(),
      legacyStore: _OldHistory([old]),
      libraryStore: _MemoryLibraryStore(),
      lemmaResolver: _Lemmas(),
    )));
    await tester.pumpAndSettle();
    expect(store.documents.single.title, 'Old article');
    expect(store.documents.single.drafts[0], 'Hi world.');
    expect(store.documents.single.sentences.single.chinese, '你好，世界。');
  });

  testWidgets('Windows app opens the new three-step workflow', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(const ReMirrorApp());
      expect(find.byType(WindowsStudyPage), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows study flow reads bilingual text and reviews each answer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _MemoryStore();
    final ai = _Ai();
    await tester.pumpWidget(MaterialApp(
        home: WindowsStudyPage(
      studyStore: store,
      credentialStore: const _Credentials(),
      translationService: _Translation(),
      aiService: ai,
      libraryStore: _MemoryLibraryStore(),
      lemmaResolver: _Lemmas(),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始新文章'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).first, 'Hello world.\n你好，世界。');
    await tester.tap(find.text('下一步：阅读与翻译'));
    await tester.pumpAndSettle();
    expect(find.text('你好，世界。'), findsOneWidget);
    expect(find.text('AI 补译缺失句子'), findsNothing);

    await tester.tap(find.text('分析句子'));
    await tester.pumpAndSettle();
    expect(find.text('主谓结构'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    final english = find.byType(InteractiveEnglish);
    await tester.tapAt(tester.getTopLeft(english) + const Offset(22, 23));
    await tester.pumpAndSettle();
    expect(find.text('用于问候'), findsOneWidget);
    expect(ai.wordCalls, 1);
    await tester.tap(find.text('加入生词库'));
    await tester.pumpAndSettle();
    expect(
        store.documents.single.sentences.single.savedWords, contains('hello'));
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生词库'));
    await tester.pumpAndSettle();
    expect(find.text('生词库（1）'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分析句子'));
    await tester.pumpAndSettle();
    expect(ai.grammarCalls, 1);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一步：回译训练'));
    await tester.pumpAndSettle();
    expect(find.text('英文原句'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'Hi, world!');
    await tester.tap(find.text('提交并评价'));
    await tester.pumpAndSettle();
    expect(find.text('英文原句'), findsOneWidget);
    expect(find.text('意思准确'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('返回阅读')).dy -
          tester.getBottomRight(find.text('继续保持')).dy,
      lessThan(100),
    );
    expect(store.documents.single.sentences.single.attempts.single.review,
        isNotNull);
  });

  testWidgets('skipping a sentence and finishing shows a saved summary',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _MemoryStore()
      ..documents = [
        StudyDocument(
          id: 'practice',
          title: 'Practice',
          sourceText: 'Hello. Bye.',
          step: 2,
          sentences: [
            StudySentence(paragraph: 1, english: 'Hello.', chinese: '你好。'),
            StudySentence(paragraph: 1, english: 'Bye.', chinese: '再见。'),
          ],
        ),
      ];
    await tester.pumpWidget(MaterialApp(
      home: WindowsStudyPage(
        studyStore: store,
        credentialStore: const _Credentials(),
        translationService: _Translation(),
        aiService: _Ai(),
        libraryStore: _MemoryLibraryStore(),
        lemmaResolver: _Lemmas(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 句'), findsOneWidget);
    expect(store.documents.single.sentences.first.skipped, isTrue);
    expect(find.text('结束'), findsOneWidget);
    await tester.tap(find.text('结束'));
    await tester.pumpAndSettle();
    expect(find.text('本轮练习结束'), findsOneWidget);
    expect(find.text('已评价 0 句 · 已跳过 1 句 · 待练习 1 句'), findsOneWidget);
    expect(store.documents.single.finishedAt, isNotNull);
  });

  testWidgets('saved word highlights inflections after its source is deleted',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final source = StudyDocument(
      id: 'source',
      title: 'First',
      sourceText: 'Go.',
      sentences: [
        StudySentence(
          paragraph: 1,
          english: 'Go.',
          chinese: '走。',
          isFavorite: true,
          grammar: {
            'structure': '祈使句',
            'grammar': '动词原形',
            'explanation': '表示命令'
          },
          words: {
            'go': {'meaning': '走', 'partOfSpeech': '动词', 'usage': '表示移动'}
          },
          savedWords: {'go'},
        )
      ],
    );
    final other = StudyDocument(
      id: 'other',
      title: 'Second',
      sourceText: 'He went.',
      step: 1,
      sentences: [
        StudySentence(paragraph: 1, english: 'He went.', chinese: '他走了。')
      ],
    );
    final store = _MemoryStore()..documents = [source, other];
    final libraryStore = _MemoryLibraryStore();
    await tester.pumpWidget(MaterialApp(
        home: WindowsStudyPage(
      studyStore: store,
      libraryStore: libraryStore,
      lemmaResolver: _Lemmas(),
      credentialStore: const _Credentials(),
      translationService: _Translation(),
      aiService: _Ai(),
    )));
    await tester.pumpAndSettle();
    expect(libraryStore.library.words.keys, contains('go'));
    expect(libraryStore.library.sentences.length, 1);

    await tester.tap(find.text('Second').last);
    await tester.pumpAndSettle();
    TextSpan wordSpan() {
      final rich = tester.widget<RichText>(find
          .descendant(
              of: find.byType(InteractiveEnglish),
              matching: find.byType(RichText))
          .first);
      TextSpan? search(InlineSpan span) {
        if (span is! TextSpan) return null;
        if (span.text == 'went') return span;
        for (final child in span.children ?? const <InlineSpan>[]) {
          final found = search(child);
          if (found != null) return found;
        }
        return null;
      }

      return search(rich.text)!;
    }

    expect(wordSpan().style?.backgroundColor, isNotNull);

    await tester.tap(find.byTooltip('删除 First'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(store.documents.map((item) => item.id), ['other']);
    expect(libraryStore.library.words.keys, contains('go'));
    expect(libraryStore.library.sentences.length, 1);
    expect(wordSpan().style?.backgroundColor, isNotNull);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(store.documents.map((item) => item.id), contains('source'));
  });
}
