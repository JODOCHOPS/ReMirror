import 'dart:io';

import 'package:mariannmt_wrapper/mariannmt_wrapper.dart';

String _path(String name) {
  final path = File('assets/offline/model/$name').absolute.path;
  if (!File(path).existsSync()) {
    throw StateError('Missing offline model asset: $name');
  }
  return '"${path.replaceAll('\\', '/')}"';
}

Future<void> main() async {
  final config = '''
models:
  - ${_path('model.enzh.intgemm.alphas.bin')}
vocabs:
  - ${_path('srcvocab.enzh.spm')}
  - ${_path('trgvocab.enzh.spm')}
shortlist:
  - ${_path('lex.50.50.enzh.s2t.bin')}
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
  final translated = await MarianTranslator.translateMultipleAsync(
    ['The quick brown fox jumps over the lazy dog.'],
    'en-zh-Hans',
  );
  if (translated.length != 1 ||
      !RegExp(r'[\u4e00-\u9fff]').hasMatch(translated.single)) {
    throw StateError('Offline translation smoke test failed: $translated');
  }
  stdout.writeln('Offline translation smoke test passed: ${translated.single}');
  await MarianTranslator.cleanupAsync(true);
}
