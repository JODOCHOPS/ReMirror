/// Splits prose at sentence-ending punctuation while keeping closing quotes.
/// Parenthesized text, abbreviations, and decimal points stay in the sentence.
List<String> splitSentences(String text) {
  final value = text.trim();
  if (value.isEmpty) return const [];
  final result = <String>[];
  var start = 0;
  var bracketDepth = 0;
  for (var index = 0; index < value.length; index++) {
    final character = value[index];
    if ('(（[［{'.contains(character)) {
      bracketDepth++;
      continue;
    }
    if (')）]］}'.contains(character)) {
      if (bracketDepth > 0) bracketDepth--;
      continue;
    }
    if (bracketDepth > 0 || !'.!?。！？'.contains(character)) continue;
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
  return RegExp(r'\b(?:Mr|Mrs|Ms|Dr|Prof|St|vs|etc|e\.g|i\.e)\.$',
              caseSensitive: false)
          .hasMatch(prefix) ||
      RegExp(r'(?:\b[A-Za-z]\.){1,3}$').hasMatch(prefix);
}
