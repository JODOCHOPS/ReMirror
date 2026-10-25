import 'sentence_splitter.dart';

class StudyAttempt {
  StudyAttempt({
    required this.answer,
    required this.createdAt,
    this.chinesePrompt,
    this.englishOriginal,
    this.review,
  });

  final String answer;
  final DateTime createdAt;
  final String? chinesePrompt;
  final String? englishOriginal;
  Map<String, String>? review;

  Map<String, dynamic> toJson() => {
        'answer': answer,
        'createdAt': createdAt.toIso8601String(),
        'chinesePrompt': chinesePrompt,
        'englishOriginal': englishOriginal,
        'review': review,
      };

  factory StudyAttempt.fromJson(Map<String, dynamic> json) => StudyAttempt(
        answer: json['answer'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        chinesePrompt: json['chinesePrompt'] as String?,
        englishOriginal: json['englishOriginal'] as String?,
        review: (json['review'] as Map?)?.map(
          (key, value) => MapEntry(key as String, value as String),
        ),
      );
}

class StudySentence {
  StudySentence({
    required this.paragraph,
    required this.english,
    this.chinese = '',
    this.grammar,
    Map<String, Map<String, String>>? words,
    List<StudyAttempt>? attempts,
  })  : words = words ?? {},
        attempts = attempts ?? [];

  final int paragraph;
  String english;
  String chinese;
  Map<String, String>? grammar;
  final Map<String, Map<String, String>> words;
  final List<StudyAttempt> attempts;

  Map<String, dynamic> toJson() => {
        'paragraph': paragraph,
        'english': english,
        'chinese': chinese,
        'grammar': grammar,
        'words': words,
        'attempts': attempts.map((item) => item.toJson()).toList(),
      };

  factory StudySentence.fromJson(Map<String, dynamic> json) => StudySentence(
        paragraph: json['paragraph'] as int,
        english: json['english'] as String,
        chinese: json['chinese'] as String? ?? '',
        grammar: (json['grammar'] as Map?)?.map(
          (key, value) => MapEntry(key as String, value as String),
        ),
        words: (json['words'] as Map?)?.map(
          (key, value) => MapEntry(
            key as String,
            (value as Map).map(
              (field, content) => MapEntry(field as String, content as String),
            ),
          ),
        ),
        attempts: (json['attempts'] as List? ?? [])
            .map((item) => StudyAttempt.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class StudyDocument {
  StudyDocument({
    required this.id,
    required this.title,
    required this.sourceText,
    required this.sentences,
    Map<int, String>? drafts,
    this.step = 0,
    this.practiceIndex = 0,
    this.needsAlignmentReview = false,
  }) : drafts = drafts ?? {};

  final String id;
  String title;
  String sourceText;
  final List<StudySentence> sentences;
  final Map<int, String> drafts;
  int step;
  int practiceIndex;
  bool needsAlignmentReview;

  bool get hasAllReferences =>
      sentences.isNotEmpty &&
      sentences.every((s) => s.chinese.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'title': title,
        'sourceText': sourceText,
        'step': step,
        'practiceIndex': practiceIndex,
        'needsAlignmentReview': needsAlignmentReview,
        'sentences': sentences.map((item) => item.toJson()).toList(),
        'drafts': drafts.map((key, value) => MapEntry(key.toString(), value)),
      };

  factory StudyDocument.fromJson(Map<String, dynamic> json) => StudyDocument(
        id: json['id'] as String,
        title: json['title'] as String,
        sourceText: json['sourceText'] as String,
        step: json['step'] as int? ?? 0,
        practiceIndex: json['practiceIndex'] as int? ?? 0,
        needsAlignmentReview: json['needsAlignmentReview'] as bool? ?? false,
        sentences: (json['sentences'] as List)
            .map((item) => StudySentence.fromJson(item as Map<String, dynamic>))
            .toList(),
        drafts: (json['drafts'] as Map? ?? {}).map(
          (key, value) => MapEntry(int.parse(key as String), value as String),
        ),
      );

  factory StudyDocument.fromText(String text, {String? title}) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    final blocks = <String>[];
    for (final paragraph in normalized.split(RegExp(r'\n\s*\n'))) {
      final lines = paragraph
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .expand(_splitBilingualLine);
      String? language;
      var grouped = <String>[];
      for (final line in lines) {
        final current = _looksChinese(line) ? 'zh' : 'en';
        if (language != null && language != current) {
          blocks.add(grouped.join(' '));
          grouped = [];
        }
        grouped.add(line);
        language = current;
      }
      if (grouped.isNotEmpty) blocks.add(grouped.join(' '));
    }
    final sentences = <StudySentence>[];
    var paragraph = 0;
    var needsReview = false;
    String? precedingChinese;
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (!_looksEnglish(block)) {
        precedingChinese = block;
        continue;
      }
      paragraph++;
      final english = splitSentences(block);
      final chineseBlock = precedingChinese ??
          (index + 1 < blocks.length && _looksChinese(blocks[index + 1])
              ? blocks[++index]
              : '');
      precedingChinese = null;
      final chinese = splitSentences(chineseBlock);
      if (chineseBlock.isNotEmpty && chinese.length != english.length) {
        needsReview = true;
      }
      for (var number = 0; number < english.length; number++) {
        sentences.add(StudySentence(
          paragraph: paragraph,
          english: english[number],
          chinese: number < chinese.length
              ? number == english.length - 1 && chinese.length > english.length
                  ? chinese.skip(number).join(' ')
                  : chinese[number]
              : '',
        ));
      }
    }
    if (sentences.isEmpty) {
      throw const FormatException('没有识别到英文文章，请检查文件内容。');
    }
    final first = sentences.first.english;
    return StudyDocument(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title:
          title ?? (first.length > 48 ? '${first.substring(0, 48)}…' : first),
      sourceText: normalized,
      sentences: sentences,
      needsAlignmentReview: needsReview,
    );
  }
}

bool _looksEnglish(String text) {
  final english = RegExp(r'[A-Za-z]').allMatches(text).length;
  final chinese = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
  return english > 0 && english >= chinese;
}

bool _looksChinese(String text) {
  final english = RegExp(r'[A-Za-z]').allMatches(text).length;
  final chinese = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
  return chinese > 0 && chinese > english;
}

List<String> _splitBilingualLine(String line) {
  final han = RegExp(r'[\u4e00-\u9fff]').firstMatch(line)?.start;
  final latin = RegExp(r'[A-Za-z]').firstMatch(line)?.start;
  if (han == null || latin == null) return [line];
  if (latin < han) {
    final english = line.substring(0, han).trim();
    final chinese = line.substring(han).trim();
    if (RegExp(r'[.!?][\s—–|:：-]*$').hasMatch(english)) {
      return [english, chinese];
    }
  } else {
    final chinese = line.substring(0, latin).trim();
    final english = line.substring(latin).trim();
    if (RegExp(r'[。！？][\s—–|:：-]*$').hasMatch(chinese)) {
      return [chinese, english];
    }
  }
  return [line];
}
