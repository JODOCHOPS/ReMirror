import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/practice_history.dart';
import 'package:remirror/practice_workbook.dart';
import 'package:remirror/translation.dart';

void main() {
  test('practice and imported workbook survive a store reload', () async {
    final directory =
        await Directory.systemTemp.createTemp('remirror-history-');
    addTearDown(() => directory.delete(recursive: true));

    final paragraphs = [
      const TranslatedParagraph('Hello world.', '你好，世界。'),
    ];
    final seed = PracticeWorkbook.fromParagraphs(
      PracticeSession(
        id: 'seed',
        title: 'seed',
        source: '离线翻译',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        paragraphs: paragraphs,
        answers: const {},
        submitted: false,
      ).sentences,
    );
    final imported = PracticeWorkbook.import(seed.export({0: 'Hello world.'}));
    final session = PracticeSession(
      id: 'one',
      title: '示例练习',
      source: 'XLSX 导入',
      createdAt: DateTime(2026, 10, 21),
      updatedAt: DateTime(2026, 10, 21),
      paragraphs: const [],
      importedPractice: imported,
      answers: const {0: 'Hello again.'},
      submitted: false,
    );

    final store = PracticeHistoryStore(directory: directory);
    await store.save([session]);
    final restored = (await store.load()).single;

    expect(restored.title, '示例练习');
    expect(restored.source, 'XLSX 导入');
    expect(restored.answeredCount, 1);
    expect(restored.sentenceCount, 1);
    expect(restored.answers[0], 'Hello again.');
    expect(restored.importedPractice?.previousAnswers[0], 'Hello world.');
    expect(restored.importedPractice?.sourceBytes, isNotEmpty);

    await store.save([
      session.withProgress(const {0: 'Updated answer.'}, false)
    ]);
    await File(
            '${directory.path}${Platform.pathSeparator}practice_history.json')
        .writeAsString('broken');
    final recovered = (await store.load()).single;
    expect(recovered.answers[0], 'Updated answer.');
  });
}
