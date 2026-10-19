import 'translation.dart';

class PracticeSentence {
  const PracticeSentence({
    required this.paragraphNumber,
    required this.sentenceNumber,
    required this.reference,
    this.original,
  });

  final int paragraphNumber;
  final int sentenceNumber;
  final String? original;
  final String? reference;

  bool get canAnswer => reference != null;
}

/// Splits prose without discarding punctuation or closing quotation marks.
List<String> splitSentences(String text) {
  final value = text.trim();
  if (value.isEmpty) return const [];
  final result = <String>[];
  var start = 0;
  for (var index = 0; index < value.length; index++) {
    final character = value[index];
    if (!'.!?。！？'.contains(character)) continue;
    if (character == '.' &&
        index > 0 &&
        index + 1 < value.length &&
        RegExp(r'\d').hasMatch(value[index - 1]) &&
        RegExp(r'\d').hasMatch(value[index + 1])) {
      continue;
    }
    if (character == '.' && _isAbbreviation(value, index)) continue;
    while (index + 1 < value.length &&
        '.!?。！？”’"\'）)]'.contains(value[index + 1])) {
      index++;
    }
    if (index + 1 < value.length && !RegExp(r'\s').hasMatch(value[index + 1])) {
      // Chinese sentences often have no separating whitespace.
      if (!'。！？'.contains(character)) continue;
    }
    final sentence = value.substring(start, index + 1).trim();
    if (sentence.isNotEmpty) result.add(sentence);
    start = index + 1;
  }
  final tail = value.substring(start).trim();
  if (tail.isNotEmpty) result.add(tail);
  return result;
}

bool _isAbbreviation(String text, int periodIndex) {
  final prefix = text.substring(0, periodIndex + 1);
  return RegExp(r'\b(?:Mr|Mrs|Ms|Dr|Prof|St|vs|etc)\.$', caseSensitive: false)
          .hasMatch(prefix) ||
      RegExp(r'(?:\b[A-Za-z]\.){1,3}$').hasMatch(prefix);
}

/// Pairs sentences in the same paragraph by position. Unmatched sentences
/// remain visible in the final comparison instead of being silently dropped.
List<PracticeSentence> buildPracticeSentences(
  List<TranslatedParagraph> paragraphs,
) {
  final result = <PracticeSentence>[];
  for (var paragraphIndex = 0;
      paragraphIndex < paragraphs.length;
      paragraphIndex++) {
    final original = splitSentences(paragraphs[paragraphIndex].original);
    final reference = splitSentences(paragraphs[paragraphIndex].translated);
    final count =
        original.length > reference.length ? original.length : reference.length;
    for (var index = 0; index < count; index++) {
      result.add(PracticeSentence(
        paragraphNumber: paragraphIndex + 1,
        sentenceNumber: index + 1,
        original: index < original.length ? original[index] : null,
        reference: index < reference.length ? reference[index] : null,
      ));
    }
  }
  return result;
}

class WordDiff {
  const WordDiff(this.text, this.matches);
  final String text;
  final bool matches;
}

class SentenceDiff {
  const SentenceDiff(this.original, this.answer);
  final List<WordDiff> original;
  final List<WordDiff> answer;

  bool get exactMatch =>
      original.every((word) => word.matches) &&
      answer.every((word) => word.matches);
}

/// Marks exact word and punctuation differences with a longest common
/// subsequence. It makes no claim about semantic correctness.
SentenceDiff compareSentence(String original, String answer) {
  final left = original
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  final right = answer
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (left.length * right.length > 40000) {
    return SentenceDiff(
      left.map((word) => WordDiff(word, false)).toList(),
      right.map((word) => WordDiff(word, false)).toList(),
    );
  }
  final lengths = List.generate(
    left.length + 1,
    (_) => List<int>.filled(right.length + 1, 0),
  );
  for (var i = left.length - 1; i >= 0; i--) {
    for (var j = right.length - 1; j >= 0; j--) {
      lengths[i][j] = left[i] == right[j]
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] > lengths[i][j + 1]
              ? lengths[i + 1][j]
              : lengths[i][j + 1]);
    }
  }
  final matchingLeft = <int>{};
  final matchingRight = <int>{};
  var i = 0;
  var j = 0;
  while (i < left.length && j < right.length) {
    if (left[i] == right[j]) {
      matchingLeft.add(i++);
      matchingRight.add(j++);
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return SentenceDiff(
    [
      for (var index = 0; index < left.length; index++)
        WordDiff(left[index], matchingLeft.contains(index))
    ],
    [
      for (var index = 0; index < right.length; index++)
        WordDiff(right[index], matchingRight.contains(index))
    ],
  );
}
