import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'study_document.dart';
import 'word_lemma.dart';

enum GrammarDepth { beginner, standard, advanced }

extension GrammarDepthLabel on GrammarDepth {
  String get label => switch (this) {
        GrammarDepth.beginner => '入门',
        GrammarDepth.standard => '标准',
        GrammarDepth.advanced => '进阶',
      };
}

String sentenceKey(String english, String chinese) =>
    '${english.trim().toLowerCase()}\u0000${chinese.trim()}';

class SavedWordExample {
  SavedWordExample(
      {required this.word,
      required this.sentence,
      required this.source,
      required this.analysis});

  final String word;
  final String sentence;
  final String source;
  final Map<String, String> analysis;

  Map<String, dynamic> toJson() => {
        'word': word,
        'sentence': sentence,
        'source': source,
        'analysis': analysis,
      };

  factory SavedWordExample.fromJson(Map<String, dynamic> json) =>
      SavedWordExample(
        word: json['word'] as String,
        sentence: json['sentence'] as String,
        source: json['source'] as String? ?? '',
        analysis: (json['analysis'] as Map)
            .map((key, value) => MapEntry(key as String, value as String)),
      );
}

class SavedWord {
  SavedWord({required this.lemma, List<SavedWordExample>? examples})
      : examples = examples ?? [];

  final String lemma;
  final List<SavedWordExample> examples;

  void addExample(SavedWordExample example) {
    if (examples.any((item) =>
        item.sentence == example.sentence &&
        item.word == example.word &&
        item.source == example.source)) {
      return;
    }
    examples.add(example);
  }

  Map<String, dynamic> toJson() => {
        'lemma': lemma,
        'examples': examples.map((item) => item.toJson()).toList(),
      };

  factory SavedWord.fromJson(Map<String, dynamic> json) => SavedWord(
        lemma: json['lemma'] as String,
        examples: (json['examples'] as List? ?? const [])
            .map((item) =>
                SavedWordExample.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class SavedSentence {
  SavedSentence(
      {required this.english,
      required this.chinese,
      Map<String, Map<String, String>>? analyses,
      Set<String>? sources})
      : analyses = analyses ?? {},
        sources = sources ?? {};

  String english;
  String chinese;
  final Map<String, Map<String, String>> analyses;
  final Set<String> sources;

  Map<String, dynamic> toJson() => {
        'english': english,
        'chinese': chinese,
        'analyses': analyses,
        'sources': sources.toList(),
      };

  factory SavedSentence.fromJson(Map<String, dynamic> json) => SavedSentence(
        english: json['english'] as String,
        chinese: json['chinese'] as String? ?? '',
        analyses: (json['analyses'] as Map? ?? {}).map((key, value) => MapEntry(
            key as String,
            (value as Map).map(
                (field, text) => MapEntry(field as String, text as String)))),
        sources: (json['sources'] as List? ?? const []).cast<String>().toSet(),
      );
}

class StudyLibrary {
  StudyLibrary(
      {Map<String, SavedWord>? words,
      Map<String, SavedSentence>? sentences,
      this.defaultDepth = GrammarDepth.standard})
      : words = words ?? {},
        sentences = sentences ?? {};

  final Map<String, SavedWord> words;
  final Map<String, SavedSentence> sentences;
  GrammarDepth defaultDepth;

  void saveSentence(StudySentence sentence, String source) {
    final key = sentenceKey(sentence.english, sentence.chinese);
    final entry = sentences.putIfAbsent(
        key,
        () => SavedSentence(
            english: sentence.english, chinese: sentence.chinese));
    entry.sources.add(source);
    entry.analyses.addAll(sentence.grammarByDepth);
    if (sentence.grammar != null) {
      entry.analyses.putIfAbsent('legacy', () => sentence.grammar!);
    }
  }

  void syncSentence(StudySentence sentence, String source, String oldEnglish,
      String oldChinese) {
    final oldKey = sentenceKey(oldEnglish, oldChinese);
    final existing = sentences[oldKey];
    if (existing == null || !existing.sources.remove(source)) return;
    if (existing.sources.isEmpty) sentences.remove(oldKey);
    saveSentence(sentence, source);
  }

  void syncGrammar(StudySentence sentence) {
    final entry = sentences[sentenceKey(sentence.english, sentence.chinese)];
    if (entry == null) return;
    entry.analyses.addAll(sentence.grammarByDepth);
    if (sentence.grammar != null) {
      entry.analyses.putIfAbsent('legacy', () => sentence.grammar!);
    }
  }

  void importDocument(StudyDocument document) {
    for (var index = 0; index < document.sentences.length; index++) {
      final sentence = document.sentences[index];
      if (sentence.isFavorite) {
        saveSentence(sentence, '${document.id}:$index');
      }
      for (final word in sentence.savedWords) {
        final analysis = sentence.words[word];
        if (analysis == null) continue;
        final entry = words.putIfAbsent(word, () => SavedWord(lemma: word));
        entry.addExample(SavedWordExample(
            word: word,
            sentence: sentence.english,
            source: document.title,
            analysis: analysis));
      }
    }
  }

  Future<StudyLibrary> forDocument(StudyDocument document,
      Future<String> Function(String) resolveLemma) async {
    final includedWords = <String, SavedWord>{};
    final includedSentences = <String, SavedSentence>{};
    for (final sentence in document.sentences) {
      final key = sentenceKey(sentence.english, sentence.chinese);
      final favorite = sentences[key];
      if (favorite != null) includedSentences[key] = favorite;
      for (final match in englishWordPattern.allMatches(sentence.english)) {
        final lemma = await resolveLemma(match.group(0)!);
        final word = words[lemma];
        if (word != null) includedWords[lemma] = word;
      }
    }
    return StudyLibrary(
        words: includedWords,
        sentences: includedSentences,
        defaultDepth: defaultDepth);
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'defaultDepth': defaultDepth.name,
        'words': words.map((key, value) => MapEntry(key, value.toJson())),
        'sentences':
            sentences.map((key, value) => MapEntry(key, value.toJson())),
      };

  factory StudyLibrary.fromJson(Map<String, dynamic> json) => StudyLibrary(
        defaultDepth: GrammarDepth.values.firstWhere(
            (item) => item.name == json['defaultDepth'],
            orElse: () => GrammarDepth.standard),
        words: (json['words'] as Map? ?? {}).map((key, value) => MapEntry(
            key as String, SavedWord.fromJson(value as Map<String, dynamic>))),
        sentences: (json['sentences'] as Map? ?? {}).map((key, value) =>
            MapEntry(key as String,
                SavedSentence.fromJson(value as Map<String, dynamic>))),
      );
}

class StudyLibraryStore {
  const StudyLibraryStore();

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(
        '${directory.path}${Platform.pathSeparator}remirror_library.json');
  }

  Future<StudyLibrary> load() async {
    final file = await _file();
    final backup = File('${file.path}.bak');
    if (!await file.exists() && !await backup.exists()) return StudyLibrary();
    Future<StudyLibrary> read(File source) async => StudyLibrary.fromJson(
        jsonDecode(await source.readAsString()) as Map<String, dynamic>);
    try {
      return await read(file);
    } catch (_) {
      if (await backup.exists()) return read(backup);
      rethrow;
    }
  }

  Future<void> save(StudyLibrary library) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(jsonEncode(library.toJson()), flush: true);
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
