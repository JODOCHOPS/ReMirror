import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remirror/translation.dart';

void main() {
  test(
    'long paragraphs stay ordered and within the provider request limit',
    () {
      final input = '${List.filled(90, 'A short sentence. ').join()}\n\n'
          '${List.filled(80, 'Another sentence. ').join()}';
      final paragraphs = splitParagraphs(input);
      expect(paragraphs, hasLength(2));
      for (final paragraph in paragraphs) {
        final chunks = splitForRequest(paragraph, 900);
        expect(chunks.length, greaterThan(1));
        expect(chunks.every((chunk) => chunk.length <= 900), isTrue);
        expect(
          chunks.join(' ').replaceAll(RegExp(r'\s+'), ' '),
          paragraph.replaceAll(RegExp(r'\s+'), ' '),
        );
      }
    },
  );

  test(
    'Google request uses the configured key and English to Chinese',
    () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'translation.googleapis.com');
        expect(request.url.queryParameters['key'], 'google-key');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['q'], 'A sentence.');
        expect(body['source'], 'en');
        expect(body['target'], 'zh-CN');
        return http.Response(
          jsonEncode({
            'data': {
              'translations': [
                {'translatedText': '一句话。'},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = TranslationService(client: client);
      final result = await service.translateChunk(
        'A sentence.',
        TranslationSource.google,
        const TranslationCredentials(googleApiKey: 'google-key'),
      );
      expect(result, '一句话。');
    },
  );

  test('article translation preserves paragraphs and reports progress',
      () async {
    final progress = <String>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final translated = body['q'] == 'First paragraph.' ? '第一段。' : '第二段。';
      return http.Response(
        jsonEncode({
          'data': {
            'translations': [
              {'translatedText': translated},
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = TranslationService(client: client);
    final result = await service.translateArticle(
      english: 'First paragraph.\n\nSecond paragraph.',
      source: TranslationSource.google,
      credentials: const TranslationCredentials(googleApiKey: 'key'),
      onProgress: (done, total) => progress.add('$done/$total'),
    );
    expect(result.map((part) => part.original),
        ['First paragraph.', 'Second paragraph.']);
    expect(result.map((part) => part.translated), ['第一段。', '第二段。']);
    expect(progress, ['0/2', '1/2', '2/2']);
  });

  test(
      'article sends each English sentence separately and keeps its translation',
      () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      final text =
          (jsonDecode(request.body) as Map<String, dynamic>)['q'] as String;
      requests.add(text);
      final translated =
          text.startsWith('First') ? '第一部分。还有一个中文句号。' : '第二部分，没有句号';
      return http.Response(
        jsonEncode({
          'data': {
            'translations': [
              {'translatedText': translated}
            ]
          }
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final result = await TranslationService(client: client).translateArticle(
      english: 'First sentence (e.g. an example). Second sentence.',
      source: TranslationSource.google,
      credentials: const TranslationCredentials(googleApiKey: 'key'),
    );
    expect(requests, [
      'First sentence (e.g. an example).',
      'Second sentence.',
    ]);
    expect(result.single.sentenceTranslations, ['第一部分。还有一个中文句号。', '第二部分，没有句号']);
  });

  test('Baidu request signs the exact submitted text', () async {
    final now = DateTime.fromMillisecondsSinceEpoch(1234567890000);
    final client = MockClient((request) async {
      expect(request.url.host, 'fanyi-api.baidu.com');
      final fields = Uri.splitQueryString(request.body);
      expect(fields['q'], 'Hello world.');
      expect(fields['from'], 'en');
      expect(fields['to'], 'zh');
      final expected = md5
          .convert(
            utf8.encode('appHello world.${now.microsecondsSinceEpoch}secret'),
          )
          .toString();
      expect(fields['sign'], expected);
      return http.Response(
        jsonEncode({
          'trans_result': [
            {'dst': '你好，世界。'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = TranslationService(client: client, now: () => now);
    final result = await service.translateChunk(
      'Hello world.',
      TranslationSource.baidu,
      const TranslationCredentials(baiduAppId: 'app', baiduSecret: 'secret'),
    );
    expect(result, '你好，世界。');
  });

  test('AI request uses Chat Completions and returns only content', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://example.com/v1/chat/completions');
      expect(request.headers['Authorization'], 'Bearer ai-key');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'model-1');
      expect((body['messages'] as List).last['content'], 'Hello.');
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '你好。'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = TranslationService(client: client);
    final result = await service.translateChunk(
      'Hello.',
      TranslationSource.ai,
      const TranslationCredentials(
        aiEndpoint: 'https://example.com/v1',
        aiApiKey: 'ai-key',
        aiModel: 'model-1',
      ),
    );
    expect(result, '你好。');
  });
}
