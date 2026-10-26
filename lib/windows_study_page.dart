import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'study_article_import.dart';
import 'credential_store.dart';
import 'learning_ai.dart';
import 'practice_history.dart';
import 'study_document.dart';
import 'study_storage.dart';
import 'study_library.dart';
import 'translation.dart';
import 'word_lemma.dart';

class WindowsStudyPage extends StatefulWidget {
  const WindowsStudyPage({
    super.key,
    this.studyStore,
    this.credentialStore,
    this.translationService,
    this.aiService,
    this.legacyStore,
    this.libraryStore,
    this.lemmaResolver,
  });

  final StudyStore? studyStore;
  final CredentialStore? credentialStore;
  final TranslationService? translationService;
  final LearningAiService? aiService;
  final PracticeHistoryStore? legacyStore;
  final StudyLibraryStore? libraryStore;
  final WordLemmaResolver? lemmaResolver;

  @override
  State<WindowsStudyPage> createState() => _WindowsStudyPageState();
}

class _WindowsStudyPageState extends State<WindowsStudyPage> {
  final _input = TextEditingController();
  final _answer = TextEditingController();
  late final StudyStore _store = widget.studyStore ?? const StudyStore();
  late final CredentialStore _credentialStore =
      widget.credentialStore ?? const CredentialStore();
  late final TranslationService _translation =
      widget.translationService ?? TranslationService();
  late final LearningAiService _ai = widget.aiService ?? LearningAiService();
  late final StudyLibraryStore _libraryStore =
      widget.libraryStore ?? const StudyLibraryStore();
  late final WordLemmaResolver _lemmas =
      widget.lemmaResolver ?? WordLemmaResolver();
  List<StudyDocument> _documents = [];
  StudyLibrary _library = StudyLibrary();
  StudyDocument? _current;
  TranslationCredentials _credentials = const TranslationCredentials();
  Future<void> _writes = Future.value();
  Timer? _inputSaveTimer;
  Timer? _answerSaveTimer;
  bool _loading = true;
  bool _busy = false;
  bool _inputDirty = false;
  bool _settingAnswer = false;
  String? _error;
  int _translatedCount = 0;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    _answer.addListener(_onAnswerChanged);
    _load();
  }

  @override
  void dispose() {
    _inputSaveTimer?.cancel();
    _answerSaveTimer?.cancel();
    _input.dispose();
    _answer.dispose();
    if (widget.translationService == null) _translation.close();
    if (widget.aiService == null) _ai.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final existingStudyFile = await _store.exists();
      final results = await Future.wait<Object>([
        _store.load(),
        _credentialStore.load(),
        _libraryStore.load(),
      ]);
      var documents = results[0] as List<StudyDocument>;
      final library = results[2] as StudyLibrary;
      if (!existingStudyFile) {
        try {
          final legacy =
              await (widget.legacyStore ?? const PracticeHistoryStore()).load();
          documents = legacy.map(_convertLegacySession).toList();
          if (documents.isNotEmpty) await _store.save(documents);
        } catch (_) {
          // The old history is left untouched if it cannot be migrated.
        }
      }
      for (final document in documents) {
        library.importDocument(document);
      }
      for (final document in documents) {
        for (var index = 0; index < document.sentences.length; index++) {
          final sentence = document.sentences[index];
          if (library.sentences
              .containsKey(sentenceKey(sentence.english, sentence.chinese))) {
            sentence.isFavorite = true;
            library.saveSentence(sentence, '${document.id}:$index');
          }
        }
      }
      final oldWords = library.words.values.toList();
      library.words.clear();
      for (final entry in oldWords) {
        final lemma = await _lemmas.lemma(entry.lemma);
        final target =
            library.words.putIfAbsent(lemma, () => SavedWord(lemma: lemma));
        for (final example in entry.examples) {
          target.addExample(example);
        }
      }
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _library = library;
        _credentials = results[1] as TranslationCredentials;
        _loading = false;
      });
      if (_documents.isNotEmpty) _select(_documents.first);
      _save();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '读取本地记录或 AI 设置失败。';
        });
      }
    }
  }

  StudyDocument _convertLegacySession(PracticeSession session) {
    final sentences = <StudySentence>[];
    final drafts = <int, String>{};
    for (var oldIndex = 0; oldIndex < session.sentences.length; oldIndex++) {
      final old = session.sentences[oldIndex];
      if (old.original?.trim().isEmpty ?? true) continue;
      final newIndex = sentences.length;
      final answer = session.answers[oldIndex];
      final previous = session.importedPractice?.previousAnswers[oldIndex];
      if (answer != null && answer.trim().isNotEmpty && !session.submitted) {
        drafts[newIndex] = answer;
      }
      sentences.add(StudySentence(
        paragraph: old.paragraphNumber,
        english: old.original!,
        chinese: old.reference ?? '',
        attempts: [
          if (previous != null && previous.trim().isNotEmpty)
            StudyAttempt(
              answer: previous,
              createdAt: session.createdAt,
              chinesePrompt: old.reference,
              englishOriginal: old.original,
            ),
          if (answer != null && answer.trim().isNotEmpty && session.submitted)
            StudyAttempt(
              answer: answer,
              createdAt: session.updatedAt,
              chinesePrompt: old.reference,
              englishOriginal: old.original,
            ),
        ],
      ));
    }
    return StudyDocument(
      id: 'legacy-${session.id}',
      title: session.title,
      sourceText: session.paragraphs.isNotEmpty
          ? session.paragraphs.map((part) => part.original).join('\n\n')
          : sentences.map((part) => part.english).join('\n'),
      sentences: sentences,
      drafts: drafts,
      step: sentences.isEmpty
          ? 0
          : sentences.every((item) => item.chinese.isNotEmpty)
              ? 2
              : 1,
    );
  }

  void _onInputChanged() {
    final current = _current;
    if (current == null || current.sourceText == _input.text) return;
    current.sourceText = _input.text;
    _inputDirty = true;
    _inputSaveTimer?.cancel();
    _inputSaveTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  void _onAnswerChanged() {
    if (_settingAnswer) return;
    final current = _current;
    if (current == null || current.sentences.isEmpty) return;
    if (current.practiceIndex >= current.sentences.length) return;
    current.drafts[current.practiceIndex] = _answer.text;
    _answerSaveTimer?.cancel();
    _answerSaveTimer = Timer(const Duration(milliseconds: 500), _save);
    if (mounted) setState(() {});
  }

  void _setAnswerText(String value) {
    _settingAnswer = true;
    _answer.text = value;
    _settingAnswer = false;
  }

  void _save() {
    final snapshot = [for (final document in _documents) document.toJson()];
    final documents = snapshot.map(StudyDocument.fromJson).toList();
    final library = StudyLibrary.fromJson(_library.toJson());
    _writes = _writes.catchError((Object _) {}).then((_) async {
      await _store.save(documents);
      await _libraryStore.save(library);
    }).catchError((Object _) {
      if (mounted) setState(() => _error = '自动保存失败，请导出 XLSX 备份。');
    });
  }

  void _select(StudyDocument document) {
    setState(() {
      _current = document;
      _error = null;
      _inputDirty = false;
      _input.text = document.sourceText;
      final index = document.practiceIndex;
      _setAnswerText(document.drafts[index] ??
          (index < document.sentences.length &&
                  document.sentences[index].attempts.isNotEmpty
              ? document.sentences[index].attempts.last.answer
              : ''));
    });
  }

  Future<void> _deleteDocument(StudyDocument document) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('删除练习记录？'),
              content: Text('将删除“${document.title}”的文章、作答和评价。生词与收藏句子会保留。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    final oldIndex = _documents.indexOf(document);
    if (oldIndex < 0) return;
    final wasCurrent = _current == document;
    setState(() {
      _documents.removeAt(oldIndex);
      if (wasCurrent) _current = null;
    });
    if (wasCurrent && _documents.isNotEmpty) _select(_documents.first);
    _save();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已删除“${document.title}”'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            setState(() => _documents.insert(
                oldIndex.clamp(0, _documents.length), document));
            if (wasCurrent) _select(document);
            _save();
          }),
    ));
  }

  void _newArticle() {
    final document = StudyDocument(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: '新文章',
      sourceText: '',
      sentences: [],
    );
    setState(() => _documents.insert(0, document));
    _select(document);
    _save();
  }

  Future<void> _adopt(StudyDocument document) async {
    final previous = _current;
    setState(() {
      if (previous != null && previous.sentences.isEmpty) {
        _documents.removeWhere((item) => item.id == previous.id);
      }
      _documents.removeWhere((item) => item.id == document.id);
      _documents.insert(0, document);
    });
    _library.importDocument(document);
    final oldWords = _library.words.values.toList();
    _library.words.clear();
    for (final entry in oldWords) {
      final lemma = await _lemmas.lemma(entry.lemma);
      final target =
          _library.words.putIfAbsent(lemma, () => SavedWord(lemma: lemma));
      for (final example in entry.examples) {
        target.addExample(example);
      }
    }
    if (!mounted) return;
    _select(document);
    _save();
  }

  Future<void> _import() async {
    if (_busy) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'docx', 'pdf', 'xlsx'],
      dialogTitle: '导入文章或练习文件',
    );
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final imported = await ArticleImporter.importBytes(file.name, bytes);
      if (!mounted) return;
      if (imported is StudyImportBundle) {
        _mergeImportedLibrary(imported.library);
        for (final sentence in imported.document.sentences) {
          if (imported.library.sentences
              .containsKey(sentenceKey(sentence.english, sentence.chinese))) {
            sentence.isFavorite = true;
          }
        }
        await _adopt(imported.document);
      } else if (imported is StudyDocument) {
        await _adopt(imported);
      } else if (imported is SpreadsheetPreview) {
        final document = await _chooseSpreadsheet(imported, file.name);
        if (document != null && mounted) await _adopt(document);
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '文件读取失败，请确认格式和内容。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _mergeImportedLibrary(StudyLibrary imported) {
    for (final entry in imported.words.entries) {
      final target = _library.words
          .putIfAbsent(entry.key, () => SavedWord(lemma: entry.key));
      for (final example in entry.value.examples) {
        target.addExample(example);
      }
    }
    for (final entry in imported.sentences.entries) {
      final target = _library.sentences.putIfAbsent(
          entry.key,
          () => SavedSentence(
              english: entry.value.english, chinese: entry.value.chinese));
      target.sources.addAll(entry.value.sources);
      target.analyses.addAll(entry.value.analyses);
    }
    for (final document in _documents) {
      for (var index = 0; index < document.sentences.length; index++) {
        final sentence = document.sentences[index];
        if (_library.sentences
            .containsKey(sentenceKey(sentence.english, sentence.chinese))) {
          sentence.isFavorite = true;
          _library.saveSentence(sentence, '${document.id}:$index');
        }
      }
    }
  }

  Future<StudyDocument?> _chooseSpreadsheet(
      SpreadsheetPreview preview, String filename) async {
    if (preview.sheets.isEmpty) {
      throw const FormatException('XLSX 中没有可导入的工作表。');
    }
    var sheet = preview.sheets.first;
    var english = 0;
    var chinese = -1;
    var header = true;
    return showDialog<StudyDocument>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final rows = preview.rows(sheet);
          final columns = rows.fold<int>(
              0, (largest, row) => row.length > largest ? row.length : largest);
          final count = columns == 0 ? 1 : columns;
          if (english >= count) english = 0;
          if (chinese >= count) chinese = -1;
          return AlertDialog(
            title: const Text('选择表格中的英中列'),
            content: SizedBox(
              width: 570,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: sheet,
                    decoration: const InputDecoration(labelText: '工作表'),
                    items: [
                      for (final name in preview.sheets)
                        DropdownMenuItem(value: name, child: Text(name)),
                    ],
                    onChanged: (value) => update(() => sheet = value!),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: DropdownButtonFormField<int>(
                      initialValue: english,
                      decoration: const InputDecoration(labelText: '英文列'),
                      items: [
                        for (var index = 0; index < count; index++)
                          DropdownMenuItem(
                              value: index, child: Text(_columnName(index))),
                      ],
                      onChanged: (value) => update(() => english = value!),
                    )),
                    const SizedBox(width: 12),
                    Expanded(
                        child: DropdownButtonFormField<int>(
                      initialValue: chinese,
                      decoration: const InputDecoration(labelText: '中文列'),
                      items: [
                        const DropdownMenuItem(value: -1, child: Text('无中文列')),
                        for (var index = 0; index < count; index++)
                          DropdownMenuItem(
                              value: index, child: Text(_columnName(index))),
                      ],
                      onChanged: (value) => update(() => chinese = value!),
                    )),
                  ]),
                  CheckboxListTile(
                    title: const Text('第一行是标题'),
                    value: header,
                    onChanged: (value) => update(() => header = value ?? true),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '预览：${rows.take(3).map((row) => row.take(3).join(' | ')).join(' / ')}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
              FilledButton(
                onPressed: chinese == english
                    ? null
                    : () {
                        try {
                          final document = preview.importColumns(
                            sheetName: sheet,
                            englishColumn: english,
                            chineseColumn: chinese < 0 ? null : chinese,
                            firstRowIsHeader: header,
                            title: filename,
                          );
                          Navigator.pop(context, document);
                        } on FormatException catch (error) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.message)),
                          );
                        }
                      },
                child: const Text('导入'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _columnName(int index) => '${String.fromCharCode(65 + index)} 列';

  Future<void> _openSettings() async {
    final updated = await showDialog<
        ({TranslationCredentials credentials, GrammarDepth depth})>(
      context: context,
      builder: (context) => _AiSettingsDialog(
          initial: _credentials, initialDepth: _library.defaultDepth),
    );
    if (updated == null || !mounted) return;
    try {
      await _credentialStore.save(updated.credentials);
      if (mounted) {
        setState(() {
          _credentials = updated.credentials;
          _library.defaultDepth = updated.depth;
        });
      }
      _save();
    } catch (_) {
      if (mounted) setState(() => _error = 'AI 设置保存失败。');
    }
  }

  Future<bool> _ensureAi() async {
    if (_credentials.isConfigured(TranslationSource.ai)) return true;
    await _openSettings();
    return mounted && _credentials.isConfigured(TranslationSource.ai);
  }

  Future<void> _nextFromInput() async {
    final current = _current;
    if (current == null || _input.text.trim().isEmpty) {
      setState(() => _error = '请先输入或导入英文文章。');
      return;
    }
    try {
      if (_inputDirty || current.sentences.isEmpty) {
        final parsed = StudyDocument.fromText(_input.text,
            title: current.title == '新文章' ? null : current.title);
        await _adopt(parsed);
      }
      setState(() {
        _current!.step = 1;
        _error = null;
      });
      _save();
      if (!_current!.hasAllReferences) await _translateMissing();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _translateMissing() async {
    final document = _current;
    if (document == null || _busy || document.hasAllReferences) return;
    if (!await _ensureAi()) return;
    setState(() {
      _busy = true;
      _error = null;
      _translatedCount = 0;
    });
    try {
      for (var sentenceIndex = 0;
          sentenceIndex < document.sentences.length;
          sentenceIndex++) {
        final sentence = document.sentences[sentenceIndex];
        if (sentence.chinese.trim().isNotEmpty) continue;
        final translated = await _translation.translateChunk(
          sentence.english,
          TranslationSource.ai,
          _credentials,
        );
        if (!mounted || _current != document) return;
        setState(() {
          final oldChinese = sentence.chinese;
          sentence.chinese = translated;
          if (sentence.isFavorite) {
            _library.syncSentence(sentence, '${document.id}:$sentenceIndex',
                sentence.english, oldChinese);
          }
          _translatedCount++;
        });
        _save();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'AI 翻译中断；已保留完成的句子，请重试剩余句子。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyzeGrammar(StudySentence sentence,
      {GrammarDepth? depth, bool force = false}) async {
    final selected = depth ?? _library.defaultDepth;
    final cached = sentence.grammarByDepth[selected.name] ??
        (selected == GrammarDepth.standard ? sentence.grammar : null);
    if (cached != null && !force) {
      _showGrammarDialog(sentence, selected, cached);
      return;
    }
    if (_busy || !await _ensureAi()) return;
    setState(() => _busy = true);
    try {
      final result = await _ai.analyzeGrammar(
          sentence.english, sentence.chinese, _credentials,
          depth: selected);
      if (!mounted) return;
      setState(() {
        sentence.grammarByDepth[selected.name] = result;
        _library.syncGrammar(sentence);
      });
      _save();
      _showGrammarDialog(sentence, selected, result);
    } on LearningAiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showGrammarDialog(
      StudySentence sentence, GrammarDepth depth, Map<String, String> result) {
    final isLegacy = !result.containsKey('skeleton');
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('语法分析'),
              content: SizedBox(
                  width: 640,
                  height: (MediaQuery.sizeOf(context).height - 220)
                      .clamp(180.0, 460.0),
                  child: ListView(children: [
                    Text(sentence.english,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<GrammarDepth>(
                      initialValue: depth,
                      decoration: const InputDecoration(labelText: '讲解深度'),
                      items: [
                        for (final item in GrammarDepth.values)
                          DropdownMenuItem(value: item, child: Text(item.label))
                      ],
                      onChanged: (value) {
                        if (value == null || value == depth) return;
                        Navigator.pop(context);
                        _analyzeGrammar(sentence, depth: value);
                      },
                    ),
                    const SizedBox(height: 18),
                    _grammarSection('句子骨架',
                        result[isLegacy ? 'structure' : 'skeleton'] ?? ''),
                    _grammarSection(
                        '关键语法', result[isLegacy ? 'grammar' : 'points'] ?? '',
                        bullets: true),
                    _grammarSection(
                        '中文理解',
                        result[isLegacy ? 'explanation' : 'understanding'] ??
                            ''),
                    if (isLegacy) const Text('旧版分析 · 可重新分析获取新版讲解'),
                  ])),
              actions: [
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _analyzeGrammar(sentence, depth: depth, force: true);
                    },
                    child: const Text('重新分析')),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭')),
              ],
            ));
  }

  Widget _grammarSection(String title, String content, {bool bullets = false}) {
    final parts = content
        .trim()
        .split(RegExp(bullets ? r'\n+|(?<=[。；])' : r'\n+'))
        .map((item) => item.trim().replaceFirst(RegExp(r'^[-•\d.、\s]+'), ''))
        .where((item) => item.isNotEmpty)
        .toList();
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 7),
          for (final part in parts)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(bullets ? '• $part' : part,
                  style: const TextStyle(fontSize: 15, height: 1.5)),
            ),
        ]));
  }

  Future<void> _analyzeWord(StudySentence sentence, String word,
      {bool currentContext = false}) async {
    final key = word.toLowerCase();
    final lemma = _library.words.isEmpty ? key : await _lemmas.lemma(word);
    if (!mounted) return;
    if (!currentContext && _library.words.containsKey(lemma)) {
      _showSavedWord(sentence, word, lemma);
      return;
    }
    if (sentence.words.containsKey(key)) {
      if (_library.words.containsKey(lemma)) {
        _rememberWordExample(lemma, sentence, key);
      }
      _showWordAnalysis(sentence, word, key, lemma);
      return;
    }
    if (_busy || !await _ensureAi()) return;
    setState(() => _busy = true);
    try {
      final result =
          await _ai.analyzeWord(word, sentence.english, _credentials);
      if (!mounted) return;
      setState(() => sentence.words[key] = result);
      if (_library.words.containsKey(lemma)) {
        _rememberWordExample(lemma, sentence, key);
      }
      _save();
      _showWordAnalysis(sentence, word, key, lemma);
    } on LearningAiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _rememberWordExample(String lemma, StudySentence sentence, String key) {
    _library.words[lemma]?.addExample(SavedWordExample(
      word: key,
      sentence: sentence.english,
      source: _current?.title ?? '',
      analysis: sentence.words[key]!,
    ));
    _save();
  }

  void _showSavedWord(StudySentence? sentence, String word, String lemma) {
    final entry = _library.words[lemma]!;
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('$word · ${entry.lemma}'),
              content: SizedBox(
                  width: 560,
                  height: 360,
                  child: ListView(children: [
                    for (final example in entry.examples)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        example.analysis['meaning'] ??
                                            example.word,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    Text(example.sentence),
                                    if (example.source.isNotEmpty)
                                      Text(example.source,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                  ]))),
                  ])),
              actions: [
                if (sentence != null)
                  TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _analyzeWord(sentence, word, currentContext: true);
                      },
                      child: const Text('分析当前用法')),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭')),
              ],
            ));
  }

  Future<void> _removeWord(String lemma) async {
    final wordsToRemove = <StudySentence, Set<String>>{};
    for (final document in _documents) {
      for (final sentence in document.sentences) {
        for (final word in sentence.savedWords) {
          if (await _lemmas.lemma(word) == lemma) {
            wordsToRemove.putIfAbsent(sentence, () => {}).add(word);
          }
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _library.words.remove(lemma);
      for (final entry in wordsToRemove.entries) {
        entry.key.savedWords.removeAll(entry.value);
      }
    });
    _save();
  }

  void _showWordAnalysis(
      StudySentence sentence, String word, String key, String lemma) {
    var activeLemma = lemma;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, refresh) {
        final saved = _library.words.containsKey(activeLemma);
        return AlertDialog(
          title: Text(word),
          content: SizedBox(
            width: 520,
            child: ListView(shrinkWrap: true, children: [
              for (final entry in sentence.words[key]!.entries) ...[
                Text(_analysisLabel(entry.key),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(entry.value),
                const SizedBox(height: 14),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (saved) {
                  await _removeWord(activeLemma);
                } else {
                  activeLemma = await _lemmas.lemma(word);
                  if (!mounted) return;
                  setState(() {
                    sentence.savedWords.add(key);
                    _library.words
                        .putIfAbsent(
                            activeLemma, () => SavedWord(lemma: activeLemma))
                        .addExample(
                          SavedWordExample(
                              word: key,
                              sentence: sentence.english,
                              source: _current?.title ?? '',
                              analysis: sentence.words[key]!),
                        );
                  });
                  _save();
                }
                refresh(() {});
              },
              child: Text(saved ? '移出生词库' : '加入生词库'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭')),
          ],
        );
      }),
    );
  }

  void _openVocabulary() {
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, refresh) {
        final entries = _library.words.values.toList()
          ..sort((a, b) => a.lemma.compareTo(b.lemma));
        return AlertDialog(
          title: Text('生词库（${entries.length}）'),
          content: SizedBox(
            width: 650,
            height: 480,
            child: entries.isEmpty
                ? const Center(child: Text('暂无生词。在阅读页点击单词并选择“加入生词库”。'))
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final example = entry.examples.firstOrNull;
                      return ListTile(
                        title: Text(entry.lemma),
                        subtitle: Text(
                          '${example?.analysis['meaning'] ?? ''}\n${entry.examples.length} 个例句',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        onTap: () {
                          Navigator.pop(context);
                          _showSavedWord(null, entry.lemma, entry.lemma);
                        },
                        trailing: IconButton(
                          tooltip: '移出生词库',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await _removeWord(entry.lemma);
                            refresh(() {});
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭')),
          ],
        );
      }),
    );
  }

  void _toggleFavorite(StudyDocument document, int index) {
    final sentence = document.sentences[index];
    final key = sentenceKey(sentence.english, sentence.chinese);
    setState(() {
      if (_library.sentences.containsKey(key)) {
        _library.sentences.remove(key);
        for (final doc in _documents) {
          for (final item in doc.sentences) {
            if (sentenceKey(item.english, item.chinese) == key) {
              item.isFavorite = false;
            }
          }
        }
      } else {
        for (final doc in _documents) {
          for (var itemIndex = 0;
              itemIndex < doc.sentences.length;
              itemIndex++) {
            final item = doc.sentences[itemIndex];
            if (sentenceKey(item.english, item.chinese) == key) {
              item.isFavorite = true;
              _library.saveSentence(item, '${doc.id}:$itemIndex');
            }
          }
        }
      }
    });
    _save();
  }

  void _openFavorites() {
    showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, refresh) {
              final entries = _library.sentences.values.toList();
              return AlertDialog(
                title: Text('句子收藏（${entries.length}）'),
                content: SizedBox(
                    width: 700,
                    height: (MediaQuery.sizeOf(context).height - 220)
                        .clamp(180.0, 500.0),
                    child: entries.isEmpty
                        ? const Center(child: Text('还没有收藏句子。'))
                        : ListView.builder(
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return ListTile(
                                title: Text(entry.english),
                                subtitle: Text(
                                    '${entry.chinese}\n${entry.analyses.isEmpty ? '待分析' : '已保存语法分析'}',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis),
                                isThreeLine: true,
                                onTap: () {
                                  Navigator.pop(context);
                                  _openFavorite(entry);
                                },
                                trailing: IconButton(
                                  tooltip: '取消收藏',
                                  icon: const Icon(
                                      Icons.bookmark_remove_outlined),
                                  onPressed: () {
                                    final key = sentenceKey(
                                        entry.english, entry.chinese);
                                    setState(() {
                                      _library.sentences.remove(key);
                                      for (final doc in _documents) {
                                        for (final item in doc.sentences) {
                                          if (sentenceKey(
                                                  item.english, item.chinese) ==
                                              key) {
                                            item.isFavorite = false;
                                          }
                                        }
                                      }
                                    });
                                    refresh(() {});
                                    _save();
                                  },
                                ),
                              );
                            })),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'))
                ],
              );
            }));
  }

  void _openFavorite(SavedSentence entry) {
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('收藏句子'),
              content: SizedBox(
                  width: 600,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.english,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Text(entry.chinese),
                        const SizedBox(height: 12),
                        Text(entry.analyses.isEmpty
                            ? '语法分析：待分析'
                            : '已保存 ${entry.analyses.length} 个分析版本'),
                      ])),
              actions: [
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      final sentence = StudySentence(
                          paragraph: 1,
                          english: entry.english,
                          chinese: entry.chinese,
                          grammarByDepth: Map.of(entry.analyses)
                            ..remove('legacy'),
                          grammar: entry.analyses['legacy']);
                      _analyzeGrammar(sentence);
                    },
                    child: const Text('查看 / 生成语法分析')),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭')),
              ],
            ));
  }

  String _analysisLabel(String key) => switch (key) {
        'structure' => '句子结构',
        'grammar' => '语法 / 关键语法',
        'explanation' => '说明',
        'meaning' => '上下文释义 / 语义',
        'partOfSpeech' => '词性',
        'usage' => '用法',
        'naturalness' => '自然度',
        'advice' => '改进建议',
        _ => key,
      };

  Future<void> _editSentence(StudySentence sentence) async {
    var english = sentence.english;
    var chinese = sentence.chinese;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('校对英中对应内容'),
        content: SizedBox(
          width: 600,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
                initialValue: english,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '英文原句'),
                onChanged: (value) => english = value),
            const SizedBox(height: 12),
            TextFormField(
                initialValue: chinese,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '中文对应内容'),
                onChanged: (value) => chinese = value),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    if (english.trim().isEmpty) {
      setState(() => _error = '英文原句不能为空。');
      return;
    }
    final oldEnglish = sentence.english;
    final oldChinese = sentence.chinese;
    final index = _current!.sentences.indexOf(sentence);
    setState(() {
      if (sentence.english != english.trim()) {
        sentence.grammar = null;
        sentence.grammarByDepth.clear();
        sentence.words.clear();
        sentence.savedWords.clear();
      }
      sentence.english = english.trim();
      if (sentence.chinese != chinese.trim()) {
        sentence.grammar = null;
        sentence.grammarByDepth.clear();
      }
      sentence.chinese = chinese.trim();
      if (sentence.isFavorite && index >= 0) {
        _library.syncSentence(
            sentence, '${_current!.id}:$index', oldEnglish, oldChinese);
      }
      _current!.needsAlignmentReview =
          _current!.sentences.any((item) => item.chinese.trim().isEmpty);
      _error = null;
    });
    _save();
  }

  Future<void> _submitAnswer() async {
    final document = _current;
    if (document == null || _busy) return;
    final sentence = document.sentences[document.practiceIndex];
    final answer = _answer.text.trim();
    if (answer.isEmpty) {
      setState(() => _error = '请先填写英文回译。');
      return;
    }
    if (!await _ensureAi()) return;
    StudyAttempt attempt;
    if (sentence.attempts.isNotEmpty &&
        sentence.attempts.last.answer == answer &&
        sentence.attempts.last.review == null) {
      attempt = sentence.attempts.last;
    } else {
      attempt = StudyAttempt(
        answer: answer,
        createdAt: DateTime.now(),
        chinesePrompt: sentence.chinese,
        englishOriginal: sentence.english,
      );
      setState(() => sentence.attempts.add(attempt));
      _save();
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final review = await _ai.reviewAttempt(
        chinese: attempt.chinesePrompt ?? sentence.chinese,
        original: attempt.englishOriginal ?? sentence.english,
        answer: answer,
        credentials: _credentials,
      );
      if (!mounted || _current != document) return;
      setState(() {
        attempt.review = review;
        sentence.skipped = false;
      });
      _save();
    } on LearningAiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goToSentence(int index) {
    final document = _current!;
    setState(() {
      document.practiceIndex = index;
      _error = null;
      _setAnswerText(document.drafts[index] ??
          (document.sentences[index].attempts.isEmpty
              ? ''
              : document.sentences[index].attempts.last.answer));
    });
    _save();
  }

  void _skipSentence() {
    final document = _current;
    if (document == null || _busy || document.sentences.isEmpty) return;
    setState(() => document.sentences[document.practiceIndex].skipped = true);
    if (document.practiceIndex + 1 < document.sentences.length) {
      _goToSentence(document.practiceIndex + 1);
    } else {
      _finishPractice();
    }
  }

  void _finishPractice() {
    final document = _current;
    if (document == null || _busy) return;
    setState(() {
      document.finishedAt = DateTime.now();
      _error = null;
    });
    _save();
  }

  Future<void> _export() async {
    final document = _current;
    if (document == null || document.sentences.isEmpty) return;
    try {
      final included = await _library.forDocument(document, _lemmas.lemma);
      final bytes = exportStudy(document, library: included);
      await FilePicker.saveFile(
        fileName:
            'ReMirror-${document.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.xlsx',
        bytes: Uint8List.fromList(bytes),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        dialogTitle: '保存学习记录',
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'XLSX 导出失败，请重试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = _current;
    return Scaffold(
      appBar: AppBar(
        title: Text(document?.title ?? 'ReMirror',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_documents.isNotEmpty)
            PopupMenuButton<({StudyDocument document, bool delete})>(
              tooltip: '最近文章',
              icon: const Icon(Icons.history),
              onSelected: (value) => value.delete
                  ? _deleteDocument(value.document)
                  : _select(value.document),
              itemBuilder: (context) => [
                for (final item in _documents) ...[
                  PopupMenuItem(
                      value: (document: item, delete: false),
                      child: Text(item.title)),
                  PopupMenuItem(
                      value: (document: item, delete: true),
                      child: Text('删除：${item.title}')),
                ],
              ],
            ),
          TextButton.icon(
              onPressed: _busy ? null : _newArticle,
              icon: const Icon(Icons.add),
              label: const Text('新文章')),
          TextButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.upload_file),
              label: const Text('导入文件')),
          TextButton.icon(
              onPressed: _openVocabulary,
              icon: const Icon(Icons.bookmarks_outlined),
              label: const Text('生词库')),
          if (MediaQuery.sizeOf(context).width >= 1100)
            TextButton.icon(
                onPressed: _openFavorites,
                icon: const Icon(Icons.bookmark_outline),
                label: const Text('句子收藏'))
          else
            IconButton(
                onPressed: _openFavorites,
                tooltip: '句子收藏',
                icon: const Icon(Icons.bookmark_outline)),
          TextButton.icon(
              onPressed:
                  document?.sentences.isNotEmpty == true ? _export : null,
              icon: const Icon(Icons.save_alt),
              label: const Text('导出 XLSX')),
          IconButton(
              onPressed: _openSettings,
              tooltip: 'AI 设置',
              icon: const Icon(Icons.settings)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              return Row(children: [
                if (wide) SizedBox(width: 250, child: _sessionList()),
                Expanded(
                  child: document == null
                      ? _emptyState()
                      : Column(children: [
                          _stepHeader(document),
                          if (_error != null)
                            MaterialBanner(
                              content: Text(_error!),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        setState(() => _error = null),
                                    child: const Text('关闭'))
                              ],
                            ),
                          if (_busy) const LinearProgressIndicator(),
                          Expanded(
                              child: switch (document.step) {
                            0 => _inputStep(document),
                            1 => _readingStep(document),
                            _ => _practiceStep(document),
                          }),
                        ]),
                ),
              ]);
            }),
    );
  }

  Widget _sessionList() => Container(
        decoration: BoxDecoration(
            border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
              padding: EdgeInsets.all(16),
              child:
                  Text('最近文章', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
              child: ListView(children: [
            for (final document in _documents)
              ListTile(
                selected: _current?.id == document.id,
                title: Text(document.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${document.sentences.length} 句'),
                onTap: () => _select(document),
                trailing: IconButton(
                  tooltip: '删除 ${document.title}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _deleteDocument(document),
                ),
              ),
          ])),
        ]),
      );

  Widget _emptyState() => Center(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('粘贴文章，或导入 TXT / MD / DOCX / PDF / XLSX'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _newArticle, child: const Text('开始新文章')),
        ],
      ));

  Widget _stepHeader(StudyDocument document) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          for (var index = 0; index < 3; index++) ...[
            if (index > 0) const Icon(Icons.chevron_right),
            TextButton(
              onPressed: index <= document.step && !_busy
                  ? () => setState(() => document.step = index)
                  : null,
              child: Text(['1 输入文章', '2 阅读与分析', '3 回译训练'][index]),
            ),
          ],
          const Spacer(),
          if (_busy && document.step == 1) Text('已翻译 $_translatedCount 句'),
        ]),
      );

  Widget _inputStep(StudyDocument document) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('粘贴或编辑英文文章；中英双语内容也可直接粘贴。段落用空行分隔。'),
          const SizedBox(height: 12),
          Expanded(
              child: TextField(
            controller: _input,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '在这里输入或粘贴文章…',
            ),
          )),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                  onPressed: _busy ? null : _nextFromInput,
                  child: const Text('下一步：阅读与翻译'))),
        ]),
      );

  Widget _readingStep(StudyDocument document) => Column(children: [
        if (document.needsAlignmentReview)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('检测到部分英中句数不同，请检查每句的中文对应内容。'),
          ),
        Expanded(
            child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          itemCount: document.sentences.length,
          itemBuilder: (context, index) {
            final sentence = document.sentences[index];
            final isNewParagraph = index == 0 ||
                sentence.paragraph != document.sentences[index - 1].paragraph;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isNewParagraph)
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Text('第 ${sentence.paragraph} 段',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  Card(
                      child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InteractiveEnglish(
                            text: sentence.english,
                            resolver: _lemmas,
                            savedLemmas: _library.words.keys.toSet(),
                            onSentence: () => _analyzeGrammar(sentence),
                            onWord: (word) => _analyzeWord(sentence, word),
                          ),
                          const SizedBox(height: 10),
                          Text(
                              sentence.chinese.isEmpty
                                  ? '等待 AI 翻译'
                                  : sentence.chinese,
                              style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, children: [
                            TextButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _analyzeGrammar(sentence),
                                icon: const Icon(Icons.menu_book_outlined),
                                label: const Text('分析句子')),
                            TextButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _editSentence(sentence),
                                icon: const Icon(Icons.edit),
                                label: const Text('校对英中内容')),
                            TextButton.icon(
                                onPressed: () =>
                                    _toggleFavorite(document, index),
                                icon: Icon(_library.sentences.containsKey(
                                        sentenceKey(
                                            sentence.english, sentence.chinese))
                                    ? Icons.bookmark
                                    : Icons.bookmark_outline),
                                label: Text(_library.sentences.containsKey(
                                        sentenceKey(
                                            sentence.english, sentence.chinese))
                                    ? '取消收藏'
                                    : '收藏句子')),
                          ]),
                        ]),
                  )),
                ]);
          },
        )),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            TextButton(
                onPressed:
                    _busy ? null : () => setState(() => document.step = 0),
                child: const Text('返回输入')),
            const Spacer(),
            if (!document.hasAllReferences)
              OutlinedButton(
                  onPressed: _busy ? null : _translateMissing,
                  child: const Text('AI 补译缺失句子')),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: !_busy && document.hasAllReferences
                  ? () {
                      setState(() => document.step = 2);
                      _save();
                    }
                  : null,
              child: const Text('下一步：回译训练'),
            ),
          ]),
        ),
      ]);

  Widget _practiceStep(StudyDocument document) {
    if (document.sentences.isEmpty) {
      return const Center(child: Text('没有可练习的句子。'));
    }
    if (document.finishedAt != null) return _practiceSummary(document);
    final index =
        document.practiceIndex.clamp(0, document.sentences.length - 1).toInt();
    final sentence = document.sentences[index];
    final last = sentence.attempts.isEmpty ? null : sentence.attempts.last;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('第 ${index + 1} / ${document.sentences.length} 句',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Text(sentence.chinese,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        TextField(
          controller: _answer,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '你的英文回译',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _submitAnswer,
          child: Text(last?.review == null &&
                  last != null &&
                  last.answer == _answer.text
              ? '重试 AI 评价'
              : '提交并评价'),
        ),
        if (last != null) ...[
          const SizedBox(height: 22),
          const Text('英文原句', style: TextStyle(fontWeight: FontWeight.bold)),
          InteractiveEnglish(
            text: last.englishOriginal ?? sentence.english,
            resolver: _lemmas,
            savedLemmas: _library.words.keys.toSet(),
            onSentence: () => _analyzeGrammar(sentence),
            onWord: (word) => _analyzeWord(sentence, word),
          ),
          TextButton.icon(
            onPressed: () => _toggleFavorite(document, index),
            icon: Icon(_library.sentences.containsKey(
                    sentenceKey(sentence.english, sentence.chinese))
                ? Icons.bookmark
                : Icons.bookmark_outline),
            label: Text(_library.sentences.containsKey(
                    sentenceKey(sentence.english, sentence.chinese))
                ? '取消收藏'
                : '收藏句子'),
          ),
          const SizedBox(height: 12),
          if (last.answer != _answer.text.trim())
            const Text('当前输入已修改；再次提交后生成新评价。'),
          if (last.review != null)
            Column(children: [
              for (final field in [
                'grammar',
                'meaning',
                'naturalness',
                'advice'
              ])
                ListTile(
                  title: Text(_analysisLabel(field)),
                  subtitle: Text(last.review![field] ?? ''),
                ),
              if (sentence.attempts.length > 1)
                Text('已保存 ${sentence.attempts.length} 次作答，均会进入 XLSX。'),
            ]),
        ],
        const SizedBox(height: 20),
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => document.step = 1);
                          _save();
                        },
                  child: const Text('返回阅读')),
              Wrap(spacing: 12, children: [
                OutlinedButton(
                    onPressed: !_busy && index > 0
                        ? () => _goToSentence(index - 1)
                        : null,
                    child: const Text('上一句')),
                OutlinedButton(
                    onPressed: _busy ? null : _skipSentence,
                    child: const Text('跳过')),
                FilledButton(
                    onPressed: _busy
                        ? null
                        : index + 1 < document.sentences.length
                            ? () => _goToSentence(index + 1)
                            : _finishPractice,
                    child: Text(
                        index + 1 < document.sentences.length ? '下一句' : '结束')),
              ]),
            ]),
      ]),
    );
  }

  Widget _practiceSummary(StudyDocument document) {
    final reviewed = document.sentences
        .where((sentence) =>
            !sentence.skipped &&
            sentence.attempts.any((attempt) => attempt.review != null))
        .length;
    final skipped =
        document.sentences.where((sentence) => sentence.skipped).length;
    final pending = document.sentences.length - reviewed - skipped;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('本轮练习结束', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        Text('已评价 $reviewed 句 · 已跳过 $skipped 句 · 待练习 $pending 句'),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 12, children: [
          FilledButton(
            onPressed: () {
              setState(() => document.finishedAt = null);
              _save();
            },
            child: const Text('继续练习'),
          ),
          OutlinedButton(
            onPressed: () {
              setState(() => document.step = 1);
              _save();
            },
            child: const Text('返回阅读'),
          ),
          OutlinedButton(onPressed: _export, child: const Text('导出 XLSX')),
        ]),
      ]),
    );
  }
}

class InteractiveEnglish extends StatefulWidget {
  const InteractiveEnglish(
      {super.key,
      required this.text,
      required this.resolver,
      required this.savedLemmas,
      required this.onSentence,
      required this.onWord});
  final String text;
  final WordLemmaResolver resolver;
  final Set<String> savedLemmas;
  final VoidCallback onSentence;
  final ValueChanged<String> onWord;

  @override
  State<InteractiveEnglish> createState() => _InteractiveEnglishState();
}

class _InteractiveEnglishState extends State<InteractiveEnglish> {
  final _recognizers = <TapGestureRecognizer>[];
  late Future<Set<String>> _highlighted;

  @override
  void initState() {
    super.initState();
    _highlighted =
        widget.resolver.highlightedForms(widget.text, widget.savedLemmas);
  }

  @override
  void didUpdateWidget(covariant InteractiveEnglish oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text ||
        widget.resolver != oldWidget.resolver ||
        !setEquals(widget.savedLemmas, oldWidget.savedLemmas)) {
      _highlighted =
          widget.resolver.highlightedForms(widget.text, widget.savedLemmas);
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Set<String>>(
        future: _highlighted,
        builder: (context, snapshot) => _buildText(snapshot.data ?? const {}),
      );

  Widget _buildText(Set<String> highlighted) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    var position = 0;
    for (final match in englishWordPattern.allMatches(widget.text)) {
      if (match.start > position) {
        spans.add(TextSpan(text: widget.text.substring(position, match.start)));
      }
      final word = match.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onWord(word);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
          text: word,
          recognizer: recognizer,
          style: TextStyle(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              backgroundColor: highlighted.contains(word.toLowerCase())
                  ? Theme.of(context).colorScheme.tertiaryContainer
                  : null,
              fontWeight: highlighted.contains(word.toLowerCase())
                  ? FontWeight.bold
                  : null)));
      position = match.end;
    }
    if (position < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(position)));
    }
    return InkWell(
      onTap: widget.onSentence,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(TextSpan(children: spans),
            style: const TextStyle(fontSize: 19, height: 1.5)),
      ),
    );
  }
}

class _AiSettingsDialog extends StatefulWidget {
  const _AiSettingsDialog({required this.initial, required this.initialDepth});
  final TranslationCredentials initial;
  final GrammarDepth initialDepth;

  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  late final _endpoint = TextEditingController(text: widget.initial.aiEndpoint);
  late final _key = TextEditingController(text: widget.initial.aiApiKey);
  late final _model = TextEditingController(text: widget.initial.aiModel);
  late GrammarDepth _depth = widget.initialDepth;
  String? _error;

  @override
  void dispose() {
    _endpoint.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  void _done() {
    final uri = Uri.tryParse(_endpoint.text.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      setState(() => _error = '接口地址必须是有效的 HTTPS 地址。');
      return;
    }
    Navigator.pop(context, (
      credentials: TranslationCredentials(
        googleApiKey: widget.initial.googleApiKey,
        baiduAppId: widget.initial.baiduAppId,
        baiduSecret: widget.initial.baiduSecret,
        aiEndpoint: _endpoint.text.trim(),
        aiApiKey: _key.text.trim(),
        aiModel: _model.text.trim(),
      ),
      depth: _depth
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('AI 设置'),
        content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: _endpoint,
                    decoration:
                        const InputDecoration(labelText: 'HTTPS 接口基础地址')),
                TextField(
                    controller: _key,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'API Key')),
                TextField(
                    controller: _model,
                    decoration: const InputDecoration(labelText: '模型名称')),
                const SizedBox(height: 12),
                DropdownButtonFormField<GrammarDepth>(
                  initialValue: _depth,
                  decoration: const InputDecoration(labelText: '默认语法分析深度'),
                  items: [
                    for (final item in GrammarDepth.values)
                      DropdownMenuItem(value: item, child: Text(item.label))
                  ],
                  onChanged: (value) =>
                      setState(() => _depth = value ?? _depth),
                ),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ],
            )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: _done, child: const Text('保存')),
        ],
      );
}
