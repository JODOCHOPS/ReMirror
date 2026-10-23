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
                      'grammar_issues': [],
                      'naturalness': '表达自然。',
                      'suggestion': '保持现在的表达即可。',
                      'improved_english': 'The feline is asleep.',
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
    expect(reviews[3]?.grammarIssues, isEmpty);
    expect(reviews[3]?.naturalness, '表达自然。');
    expect(observedRequest.url.toString(),
        'https://example.com/v1/chat/completions');
    expect(observedRequest.headers['Authorization'], 'Bearer ai-key');
    final body = jsonDecode(observedRequest.body) as Map<String, dynamic>;
    expect(body['model'], 'model-1');
    final messages = body['messages'] as List;
    expect(messages.first['content'], contains('different correct wording'));
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

  test('review reuses identical answers in memory and refresh bypasses cache',
      () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final inputs = jsonDecode(
          (body['messages'] as List).last['content'] as String) as List;
      expect(inputs, hasLength(1));
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'reviews': [
                    {
                      'id': inputs.single['id'],
                      'verdict': 'mostly_accurate',
                      'reason': '意思基本正确。',
                      'grammar_issues': [
                        {
                          'excerpt': 'He go',
                          'problem': '主语为第三人称单数，动词需要加 s。',
                          'correction': 'He goes',
                        },
                      ],
                      'naturalness': '句子不够自然。',
                      'suggestion': '改正动词形式。',
                      'improved_english': 'He goes home.',
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
    const inputs = [
      AiReviewInput(index: 0, reference: '他回家。', answer: 'He go home.'),
      AiReviewInput(index: 1, reference: '他回家。', answer: 'He go home.'),
    ];
    final first = await service.reviewSentences(inputs, credentials);
    expect(first.keys, containsAll([0, 1]));
    expect(first[1]?.grammarIssues.single.excerpt, 'He go');
    expect(requests, 1);
    await service.reviewSentences(inputs, credentials);
    expect(requests, 1);
    await service.reviewSentences(
      inputs,
      const TranslationCredentials(
        aiEndpoint: 'https://example.com/v1',
        aiApiKey: 'ai-key',
        aiModel: 'model-2',
      ),
    );
    expect(requests, 2);
    await service.reviewSentences(inputs, credentials, forceRefresh: true);
    expect(requests, 3);
  });

  test('review rejects grammar excerpts absent from the student answer',
      () async {
    final service = AiReviewService(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'reviews': [
                        {
                          'id': 0,
                          'verdict': 'needs_work',
                          'reason': '存在语法错误。',
                          'grammar_issues': [
                            {
                              'excerpt': 'does not exist',
                              'problem': '错误定位失真。',
                              'correction': 'He goes',
                            }
                          ],
                          'naturalness': '不自然。',
                          'suggestion': '修改语法。',
                          'improved_english': 'He goes home.',
                        }
                      ]
                    }),
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );
    await expectLater(
      service.reviewSentences(
        const [AiReviewInput(index: 0, reference: '他回家。', answer: 'He go home.')],
        credentials,
      ),
      throwsA(isA<AiReviewException>()),
    );
  });
}
