import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remirror/ai_review.dart';
import 'package:remirror/translation.dart';

const credentials = TranslationCredentials(
  aiEndpoint: 'https://example.com/v1',
  aiApiKey: 'ai-key',
  aiModel: 'model-1',
);

void main() {
  test('review sends prompt, original and answer and accepts semantic accuracy',
      () async {
    late http.Request observedRequest;
    final client = MockClient((request) async {
      observedRequest = request;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'reviews': [
                    {
                      'id': 3,
                      'verdict': 'accurate',
                      'reason': '意思准确，表达自然。',
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
    });
    final service = AiReviewService(client: client);
    final reviews = await service.reviewSentences(
      const [
        AiReviewInput(
          index: 3,
          reference: '猫睡着了。',
          original: 'The cat sleeps.',
          answer: 'The feline is asleep.',
        ),
      ],
      credentials,
    );
    expect(reviews[3]?.verdict, AiReviewVerdict.accurate);
    expect(reviews[3]?.reason, '意思准确，表达自然。');
    expect(observedRequest.url.toString(),
        'https://example.com/v1/chat/completions');
    expect(observedRequest.headers['Authorization'], 'Bearer ai-key');
    final body = jsonDecode(observedRequest.body) as Map<String, dynamic>;
    expect(body['model'], 'model-1');
    final messages = body['messages'] as List;
    expect(
        messages.first['content'], contains('do not require matching wording'));
    final inputs = jsonDecode(messages.last['content'] as String) as List;
    expect(inputs, [
      {
        'id': 3,
        'chinese_prompt': '猫睡着了。',
        'original_english': 'The cat sleeps.',
        'student_english': 'The feline is asleep.',
      },
    ]);
  });

  test(
      'review rejects incomplete responses so missing sentences can be retried',
      () async {
    final service = AiReviewService(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"reviews":[]}'},
                },
              ],
            }),
            200,
          )),
    );
    await expectLater(
      service.reviewSentences(
        const [AiReviewInput(index: 0, reference: '你好。', answer: 'Hello.')],
        credentials,
      ),
      throwsA(isA<AiReviewException>()),
    );
  });
}
