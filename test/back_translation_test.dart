import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remirror/back_translation.dart';
import 'package:remirror/back_translation_page.dart';
import 'package:remirror/translation.dart';

void main() {
  test('sentences retain punctuation and paragraph-local order', () {
    expect(splitSentences('Dr. Lee paid 3.5 dollars. Then left!'), [
      'Dr. Lee paid 3.5 dollars.',
      'Then left!',
    ]);
    expect(splitSentences('他说：“你好。”然后离开。'), [
      '他说：“你好。”',
      '然后离开。',
    ]);
    final items = buildPracticeSentences(const [
      TranslatedParagraph('First. Second.', '第一句。'),
      TranslatedParagraph('Third.', '第三句。第四句。'),
    ]);
    expect(items.map((item) => item.paragraphNumber), [1, 1, 2, 2]);
    expect(items.map((item) => item.original),
        ['First.', 'Second.', 'Third.', null]);
    expect(items.map((item) => item.reference), ['第一句。', null, '第三句。', '第四句。']);
  });

  test('word differences mark missing and extra text', () {
    final diff = compareSentence('The cat sleeps.', 'The dog sleeps.');
    expect(diff.original.map((word) => word.matches), [true, false, true]);
    expect(diff.answer.map((word) => word.matches), [true, false, true]);
    expect(diff.exactMatch, isFalse);
    expect(compareSentence('Hello world.', 'Hello world.').exactMatch, isTrue);
  });

  testWidgets('practice hides original until the article is submitted',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: BackTranslationPage(
        paragraphs: [
          TranslatedParagraph(
            'The cat sleeps. The sun shines.',
            '猫睡着了。太阳照耀。',
          ),
        ],
      ),
    ));

    expect(find.text('猫睡着了。'), findsOneWidget);
    expect(find.text('The cat sleeps.'), findsNothing);
    await tester.tap(find.text('点击填写英文回译').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'The dog sleeps.');
    await tester.tap(find.text('保存句子'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The dog sleeps.'), findsOneWidget);
    expect(find.text('The cat sleeps.'), findsNothing);

    await tester.tap(find.text('结束并查看结果'));
    await tester.pumpAndSettle();
    expect(find.text('英文原文'), findsWidgets);
    expect(find.text('你的回译'), findsWidgets);
    expect(find.text('未作答'), findsOneWidget);
    expect(find.textContaining('标色部分是文本差异'), findsOneWidget);
  });
}
