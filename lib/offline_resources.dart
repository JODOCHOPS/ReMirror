import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mariannmt_wrapper/mariannmt_wrapper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

const _assetRoot = 'assets/offline';
const _modelFiles = <String, int>{
  'model.enzh.intgemm.alphas.bin': 43849787,
  'srcvocab.enzh.spm': 806952,
  'trgvocab.enzh.spm': 772004,
  'lex.50.50.enzh.s2t.bin': 6506248,
};

Future<File> _copyAsset(
    String asset, String filename, int expectedLength) async {
  final support = await getApplicationSupportDirectory();
  final directory =
      Directory('${support.path}${Platform.pathSeparator}offline-v1');
  await directory.create(recursive: true);
  final target = File('${directory.path}${Platform.pathSeparator}$filename');
  if (await target.exists() && await target.length() == expectedLength) {
    return target;
  }
  final bytes = await rootBundle.load(asset);
  if (bytes.lengthInBytes != expectedLength) {
    throw StateError('Bundled offline asset has an unexpected size: $filename');
  }
  final temporary = File('${target.path}.tmp');
  await temporary.writeAsBytes(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    flush: true,
  );
  if (await target.exists()) await target.delete();
  return temporary.rename(target.path);
}

String _yamlPath(String path) =>
    '"${path.replaceAll('\\', '/').replaceAll('"', '\\"')}"';

class OfflineTranslator {
  Future<void>? _loading;

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final files = <String, File>{};
      for (final entry in _modelFiles.entries) {
        files[entry.key] = await _copyAsset(
          '$_assetRoot/model/${entry.key}',
          entry.key,
          entry.value,
        );
      }
      final model = _yamlPath(files['model.enzh.intgemm.alphas.bin']!.path);
      final source = _yamlPath(files['srcvocab.enzh.spm']!.path);
      final target = _yamlPath(files['trgvocab.enzh.spm']!.path);
      final shortlist = _yamlPath(files['lex.50.50.enzh.s2t.bin']!.path);
      final config = '''
models:
  - $model
vocabs:
  - $source
  - $target
shortlist:
  - $shortlist
beam-size: 1
normalize: 1.0
max-length-break: 128
mini-batch-words: 1024
max-length-factor: 2.0
skip-cost: true
cpu-threads: 2
quiet: true
quiet-translation: true
gemm-precision: int8shiftAlphaAll
alignment: soft
''';
      await MarianTranslator.initializeServiceAsync();
      await MarianTranslator.loadModelAsync(config, 'en-zh-Hans');
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<String> translate(String english) async {
    await _ensureLoaded();
    final result = await MarianTranslator.translateMultipleAsync(
      <String>[english],
      'en-zh-Hans',
    );
    if (result.isEmpty || result.single.trim().isEmpty) {
      throw StateError('Offline translation returned no text');
    }
    return result.single.trim();
  }
}

class DictionaryEntry {
  const DictionaryEntry({
    required this.word,
    required this.phonetic,
    required this.translation,
    required this.queried,
  });

  final String word;
  final String phonetic;
  final String translation;
  final String queried;
}

class OfflineDictionary {
  Database? _db;
  Future<void>? _opening;

  Future<void> _ensureOpen() => _opening ??= _open();

  Future<void> _open() async {
    try {
      final file = await _copyAsset(
        '$_assetRoot/dictionary.sqlite',
        'dictionary.sqlite',
        42528768,
      );
      _db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  DictionaryEntry? _find(String word, String queried) {
    final rows = _db!.select(
      'SELECT word, phonetic, translation, lemma FROM entries WHERE word = ?',
      [word],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final lemma = (row['lemma'] as String?)?.trim() ?? '';
    if (lemma.isNotEmpty && lemma != word) {
      final base = _db!.select(
        'SELECT word, phonetic, translation FROM entries WHERE word = ?',
        [lemma],
      );
      if (base.isNotEmpty) {
        final root = base.single;
        return DictionaryEntry(
          word: root['word'] as String,
          phonetic: root['phonetic'] as String,
          translation: root['translation'] as String,
          queried: queried,
        );
      }
    }
    return DictionaryEntry(
      word: row['word'] as String,
      phonetic: row['phonetic'] as String,
      translation: row['translation'] as String,
      queried: queried,
    );
  }

  Future<DictionaryEntry?> lookup(String query) async {
    final normalized =
        query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return null;
    await _ensureOpen();
    final direct = _find(normalized, query.trim());
    if (direct != null) return direct;
    if (normalized.contains(' ')) return null;
    final candidates = <String>{};
    if (normalized.endsWith('ies')) {
      candidates.add('${normalized.substring(0, normalized.length - 3)}y');
    }
    if (normalized.endsWith('es')) {
      candidates.add(normalized.substring(0, normalized.length - 2));
    }
    if (normalized.endsWith('s')) {
      candidates.add(normalized.substring(0, normalized.length - 1));
    }
    if (normalized.endsWith('ing')) {
      final stem = normalized.substring(0, normalized.length - 3);
      candidates.add(stem);
      candidates.add('${stem}e');
      if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
        candidates.add(stem.substring(0, stem.length - 1));
      }
    }
    if (normalized.endsWith('ed')) {
      final stem = normalized.substring(0, normalized.length - 2);
      candidates.add(stem);
      candidates.add('${stem}e');
      if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
        candidates.add(stem.substring(0, stem.length - 1));
      }
    }
    for (final candidate in candidates) {
      final entry = _find(candidate, query.trim());
      if (entry != null) return entry;
    }
    return null;
  }

  void close() {
    _db?.close();
    _db = null;
    _opening = null;
  }
}

final bundledTranslator = OfflineTranslator();
final bundledDictionary = OfflineDictionary();
