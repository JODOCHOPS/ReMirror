import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remirror/ai_review.dart';
import 'package:remirror/back_translation.dart';
import 'package:remirror/back_translation_page.dart';
import 'package:remirror/practice_workbook.dart';
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

  test(
      'English boundaries govern aligned Chinese even when punctuation differs',
      () {
    const first = 'Gwendoline (1882–1951) and Margaret (1884–1963) Davies '
        'were the granddaughters of David Davies, a Welshman who amassed a '
        'fortune in the shipping and mining industries.';
    const second = 'In 1907, when Gwendoline came into her inheritance '
        '(Margaret would follow in 1909), the sisters were said to be the '
        'wealthiest unmarried women in Britain.';
    final items = buildPracticeSentences(const [
      TranslatedParagraph(
        '$first $second',
        '格温多琳和玛格丽特是戴维斯的孙女。戴维斯靠航运和采矿致富。1907年，格温多琳继承遗产。',
        sentenceTranslations: [
          '格温多琳和玛格丽特是戴维斯的孙女。戴维斯靠航运和采矿致富。',
          '1907年，格温多琳继承遗产。',
        ],
      ),
    ]);
    expect(items, hasLength(2));
    expect(items.map((item) => item.original), [first, second]);
    expect(items.first.reference, '格温多琳和玛格丽特是戴维斯的孙女。戴维斯靠航运和采矿致富。');
    expect(items.last.reference, '1907年，格温多琳继承遗产。');
    expect(splitSentences('She paid 3.5 pounds (e.g. in 1907). Then left.'), [
      'She paid 3.5 pounds (e.g. in 1907).',
      'Then left.',
    ]);
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

  testWidgets('imported practice hides the previous answer until submission',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final firstRound = PracticeWorkbook.fromParagraphs(const [
      PracticeSentence(
        paragraphNumber: 1,
        sentenceNumber: 1,
        reference: '猫睡着了。',
        original: 'The cat sleeps.',
      ),
    ]);
    final imported = PracticeWorkbook.import(
      firstRound.export({0: 'The dog sleeps.'}),
    );
    await tester.pumpWidget(MaterialApp(
      home: BackTranslationPage(
        paragraphs: const [],
        importedPractice: imported,
      ),
    ));

    expect(find.text('The dog sleeps.'), findsNothing);
    expect(find.text('The cat sleeps.'), findsNothing);
    expect(find.text('导出本轮结果 XLSX'), findsNothing);
    await tester.tap(find.text('结束并查看结果'));
    await tester.pumpAndSettle();
    expect(find.text('上轮回译'), findsOneWidget);
    expect(find.text('The dog sleeps.'), findsOneWidget);
    expect(find.text('导出本轮结果 XLSX'), findsOneWidget);
  });

  testWidgets('configured AI reviews answered sentences and retries a failure',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var requests = 0;
    final observedInputs = <List<dynamic>>[];
    final service = AiReviewService(client: MockClient((request) async {
      requests++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      final inputs = jsonDecode(messages.last['content'] as String) as List;
      observedInputs.add(inputs);
      if (requests == 1) return http.Response('{}', 503);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'reviews': [
                    {
                      'id': 0,
                      'verdict': 'accurate',
                      'reason': '意思准确，用词不同也正确。',
                    },
                  ],
                }),
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }));
    await tester.pumpWidget(MaterialApp(
      home: BackTranslationPage(
        paragraphs: const [
          TranslatedParagraph(
            'The cat sleeps. The sun shines.',
            '猫睡着了。太阳照耀。',
          ),
        ],
        aiCredentials: const TranslationCredentials(
          aiEndpoint: 'https://example.com/v1',
          aiApiKey: 'ai-key',
          aiModel: 'model-1',
        ),
        reviewService: service,
      ),
    ));
    await tester.tap(find.text('点击填写英文回译').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'The feline is asleep.');
    await tester.tap(find.text('保存句子'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束并查看结果'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('重试点评'), findsOneWidget);
    expect(find.text('未作答，已跳过点评。'), findsOneWidget);
    await tester.tap(find.text('重试点评'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(observedInputs.last, hasLength(1));
    expect(
        observedInputs.last.first['student_english'], 'The feline is asleep.');
    expect(find.text('AI 点评 · 准确'), findsOneWidget);
    expect(find.text('意思准确，用词不同也正确。'), findsOneWidget);
  });
}
