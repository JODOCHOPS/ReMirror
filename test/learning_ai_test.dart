import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remirror/learning_ai.dart';
import 'package:remirror/study_library.dart';
import 'package:remirror/translation.dart';

void main() {
  const credentials = TranslationCredentials(
    aiEndpoint: 'https://example.test/v1',
    aiApiKey: 'test-key',
    aiModel: 'test-model',
  );

  test('review uses Chinese meaning and accepts different natural wording',
      () async {
    final client = MockClient((request) async {
      expect(
          request.url.toString(), 'https://example.test/v1/chat/completions');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      final system = messages.first['content'] as String;
      expect(system, contains('不要求措辞或句式相同'));
      final input = jsonDecode(messages.last['content'] as String) as Map;
      expect(input['chinese_prompt'], '他已经回家了。');
      expect(input['student_english'], 'He has gone home.');
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'grammar': '语法正确',
                    'meaning': '意思准确',
                    'naturalness': '表达自然',
                    'advice': '继续保持',
                  })
                }
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final service = LearningAiService(client: client);
    final review = await service.reviewAttempt(
      chinese: '他已经回家了。',
      original: 'He went home already.',
      answer: 'He has gone home.',
      credentials: credentials,
    );
    expect(review['meaning'], '意思准确');
    expect(review['naturalness'], '表达自然');
  });

  test('incomplete AI evaluation is rejected so it can be retried', () async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{"grammar":"正确"}'}
            },
          ],
        }),
        200));
    final service = LearningAiService(client: client);
    expect(
      () => service.reviewAttempt(
        chinese: '你好。',
        original: 'Hello.',
        answer: 'Hi.',
        credentials: credentials,
      ),
      throwsA(isA<LearningAiException>()),
    );
  });

  test('grammar request uses the selected depth and structured sections',
      () async {
    String? sentSystem;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      sentSystem = (body['messages'] as List).first['content'] as String;
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'skeleton': '主语加谓语。',
                    'points': '动名词作主语。',
                    'understanding': '表达一般事实。',
                  })
                }
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final result = await LearningAiService(client: client).analyzeGrammar(
        'Learning helps.', '学习有帮助。', credentials,
        depth: GrammarDepth.beginner);
    expect(result['skeleton'], '主语加谓语。');
    expect(sentSystem, contains('面向入门水平'));
    expect(sentSystem, contains('skeleton、points、understanding'));
  });
}
