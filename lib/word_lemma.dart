import 'offline_resources.dart';

final englishWordPattern = RegExp(r"[A-Za-z]+(?:['’-][A-Za-z]+)*");

/// Resolves inflected spellings to a shared vocabulary key without an AI call.
class WordLemmaResolver {
  final Map<String, Future<String>> _cache = {};

  Future<String> lemma(String word) {
    final key = word.trim().toLowerCase();
    return _cache.putIfAbsent(key, () async {
      try {
        return (await bundledDictionary.lookup(key))?.word ?? _fallback(key);
      } catch (_) {
        return _fallback(key);
      }
    });
  }

  Future<Set<String>> highlightedForms(String text, Set<String> lemmas) async {
    if (lemmas.isEmpty) return {};
    final forms = englishWordPattern
        .allMatches(text)
        .map((match) => match.group(0)!.toLowerCase())
        .toSet();
    final matches = <String>{};
    await Future.wait(forms.map((form) async {
      if (lemmas.contains(await lemma(form))) matches.add(form);
    }));
    return matches;
  }

  String _fallback(String word) {
    const irregular = {
      'went': 'go',
      'gone': 'go',
      'was': 'be',
      'were': 'be',
      'been': 'be',
      'saw': 'see',
      'seen': 'see',
      'did': 'do',
      'done': 'do',
      'had': 'have',
      'made': 'make',
      'took': 'take',
      'taken': 'take',
      'came': 'come',
      'got': 'get',
      'gotten': 'get',
      'wrote': 'write',
      'written': 'write',
      'ran': 'run',
      'bought': 'buy',
      'brought': 'bring',
      'thought': 'think',
      'taught': 'teach',
      'children': 'child',
      'men': 'man',
      'women': 'woman',
      'mice': 'mouse',
      'feet': 'foot',
      'teeth': 'tooth',
    };
    return irregular[word] ?? word;
  }
}
