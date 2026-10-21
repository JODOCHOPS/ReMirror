import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/back_translation_page.dart';
import 'package:remirror/translation.dart';

void main() {
  testWidgets('Windows practice resumes answers and submits progress',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<int, String>? savedAnswers;
    bool? savedSubmitted;

    await tester.pumpWidget(MaterialApp(
      home: BackTranslationPage(
        paragraphs: const [TranslatedParagraph('Hello world.', '你好，世界。')],
        initialAnswers: const {0: 'Hello world.'},
        onProgress: (answers, submitted) {
          savedAnswers = answers;
          savedSubmitted = submitted;
        },
      ),
    ));

    expect(find.text('进度  1 / 1 句'), findsOneWidget);
    expect(find.text('你的回译：Hello world.'), findsOneWidget);
    await tester.tap(find.text('结束并查看结果'));
    await tester.pumpAndSettle();
    expect(find.text('回译结果'), findsOneWidget);
    expect(savedAnswers?[0], 'Hello world.');
    expect(savedSubmitted, isTrue);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
