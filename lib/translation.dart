import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:http/http.dart' as http;

enum TranslationSource { google, baidu, ai }

extension TranslationSourceLabel on TranslationSource {
  String get label => switch (this) {
        TranslationSource.google => 'Google 翻译',
        TranslationSource.baidu => '百度翻译',
        TranslationSource.ai => 'AI 翻译',
      };

  String get shortLabel => switch (this) {
        TranslationSource.google => 'Google',
        TranslationSource.baidu => '百度',
        TranslationSource.ai => 'AI',
      };
}

class TranslationCredentials {
  const TranslationCredentials({
    this.googleApiKey = '',
    this.baiduAppId = '',
    this.baiduSecret = '',
    this.aiEndpoint = 'https://api.openai.com/v1',
    this.aiApiKey = '',
    this.aiModel = '',
  });

  final String googleApiKey;
  final String baiduAppId;
  final String baiduSecret;
  final String aiEndpoint;
  final String aiApiKey;
  final String aiModel;

  bool isConfigured(TranslationSource source) => switch (source) {
        TranslationSource.google => googleApiKey.trim().isNotEmpty,
        TranslationSource.baidu =>
          baiduAppId.trim().isNotEmpty && baiduSecret.trim().isNotEmpty,
        TranslationSource.ai => aiEndpoint.trim().isNotEmpty &&
            aiApiKey.trim().isNotEmpty &&
            aiModel.trim().isNotEmpty,
      };
}

class TranslatedParagraph {
  const TranslatedParagraph(this.original, this.translated);

  final String original;
  final String translated;
}

class TranslationException implements Exception {
  const TranslationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Keeps paragraph boundaries for the future back-translation comparison.
List<String> splitParagraphs(String input) => input
    .replaceAll('\r\n', '\n')
    .split(RegExp(r'\n\s*\n'))
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toList();

/// Breaks a long paragraph at a sentence or word boundary when possible.
List<String> splitForRequest(String paragraph, int maxCharacters) {
  assert(maxCharacters > 0);
  final result = <String>[];
  var remaining = paragraph.trim();
  while (remaining.length > maxCharacters) {
    var cut = -1;
    for (var index = maxCharacters - 1; index >= maxCharacters ~/ 2; index--) {
      if ('.!?。！？'.contains(remaining[index])) {
        cut = index + 1;
        break;
      }
    }
    if (cut < 0) {
      cut = remaining.lastIndexOf(RegExp(r'\s'), maxCharacters);
    }
    if (cut <= 0) cut = maxCharacters;
    result.add(remaining.substring(0, cut).trim());
    remaining = remaining.substring(cut).trimLeft();
  }
  if (remaining.isNotEmpty) result.add(remaining);
  return result;
}

class TranslationService {
  TranslationService({http.Client? client, DateTime Function()? now})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _now = now ?? DateTime.now;

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final HtmlUnescape _unescape = HtmlUnescape();

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<TranslatedParagraph>> translateArticle({
    required String english,
    required TranslationSource source,
    required TranslationCredentials credentials,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!credentials.isConfigured(source)) {
      throw const TranslationException('请先配置当前翻译源的凭据。');
    }
    final paragraphs = splitParagraphs(english);
    if (paragraphs.isEmpty) {
      throw const TranslationException('请先输入英文原文。');
    }
    final limit = switch (source) {
      TranslationSource.baidu => 900,
      TranslationSource.google => 4500,
      TranslationSource.ai => 3000,
    };
    final chunks = paragraphs
        .map((paragraph) => splitForRequest(paragraph, limit))
        .toList();
    final total = chunks.fold<int>(0, (count, part) => count + part.length);
    var completed = 0;
    final translated = <TranslatedParagraph>[];
    onProgress?.call(0, total);

    for (var index = 0; index < paragraphs.length; index++) {
      final pieces = <String>[];
      for (final chunk in chunks[index]) {
        if (isCancelled?.call() ?? false) {
          throw const TranslationException('已取消翻译。');
        }
        if (source == TranslationSource.baidu && completed > 0) {
          // The standard Baidu tier allows one request per second.
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        }
        pieces.add(await translateChunk(chunk, source, credentials));
        completed++;
        onProgress?.call(completed, total);
      }
      translated.add(TranslatedParagraph(paragraphs[index], pieces.join('')));
    }
    return translated;
  }

  Future<String> translateChunk(
    String text,
    TranslationSource source,
    TranslationCredentials credentials,
  ) =>
      switch (source) {
        TranslationSource.google => _google(text, credentials.googleApiKey),
        TranslationSource.baidu => _baidu(
            text,
            credentials.baiduAppId,
            credentials.baiduSecret,
          ),
        TranslationSource.ai => _ai(text, credentials),
      };

  Future<String> _google(String text, String apiKey) async {
    final uri = Uri.https(
      'translation.googleapis.com',
      '/language/translate/v2',
      {'key': apiKey.trim()},
    );
    final response = await _postJson(uri, {
      'q': text,
      'source': 'en',
      'target': 'zh-CN',
      'format': 'text',
    });
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw TranslationException(
        _providerError('Google', body, response.statusCode),
      );
    }
    final data = body['data'];
    if (data is! Map ||
        data['translations'] is! List ||
        (data['translations'] as List).isEmpty) {
      throw const TranslationException('Google 返回的译文格式无法识别。');
    }
    final first = (data['translations'] as List).first;
    final result = first is Map ? first['translatedText'] : null;
    if (result is! String || result.isEmpty) {
      throw const TranslationException('Google 没有返回译文。');
    }
    return _unescape.convert(result);
  }

  Future<String> _baidu(String text, String appId, String secret) async {
    appId = appId.trim();
    secret = secret.trim();
    final salt = _now().microsecondsSinceEpoch.toString();
    final sign = md5.convert(utf8.encode('$appId$text$salt$secret')).toString();
    final response = await _postForm(
      Uri.https('fanyi-api.baidu.com', '/api/trans/vip/translate'),
      {
        'q': text,
        'from': 'en',
        'to': 'zh',
        'appid': appId,
        'salt': salt,
        'sign': sign,
      },
    );
    final body = _decode(response);
    if (response.statusCode != 200 || body['error_code'] != null) {
      throw TranslationException(
        _providerError('百度', body, response.statusCode),
      );
    }
    final list = body['trans_result'];
    if (list is! List || list.isEmpty) {
      throw const TranslationException('百度没有返回译文。');
    }
    final result = list
        .whereType<Map>()
        .map((item) => item['dst'])
        .whereType<String>()
        .join('\n');
    if (result.isEmpty) {
      throw const TranslationException('百度返回的译文格式无法识别。');
    }
    return result;
  }

  Future<String> _ai(String text, TranslationCredentials credentials) async {
    final endpoint = credentials.aiEndpoint.trim().replaceAll(
          RegExp(r'/$'),
          '',
        );
    final url = endpoint.endsWith('/chat/completions')
        ? endpoint
        : '$endpoint/chat/completions';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const TranslationException('AI 接口地址必须是有效的 HTTPS 地址。');
    }
    final response = await _postJson(
      uri,
      {
        'model': credentials.aiModel.trim(),
        'messages': [
          {
            'role': 'system',
            'content':
                'Translate the English text into natural Simplified Chinese. '
                    'Preserve meaning, tone, and paragraph structure. '
                    'Return only the Chinese translation with no explanation.',
          },
          {'role': 'user', 'content': text},
        ],
      },
      headers: {'Authorization': 'Bearer ${credentials.aiApiKey.trim()}'},
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw TranslationException(
        _providerError('AI', body, response.statusCode),
      );
    }
    final choices = body['choices'];
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    final message = first is Map ? first['message'] : null;
    final result = message is Map ? message['content'] : null;
    if (result is! String || result.trim().isEmpty) {
      throw const TranslationException('AI 没有返回译文。请检查接口和模型配置。');
    }
    return result.trim();
  }

  Future<http.Response> _postJson(
    Uri uri,
    Map<String, Object?> data, {
    Map<String, String> headers = const {},
  }) async {
    try {
      return await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json', ...headers},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 45));
    } catch (_) {
      throw const TranslationException('网络请求失败或超时，请检查网络连接和接口地址。');
    }
  }

  Future<http.Response> _postForm(Uri uri, Map<String, String> data) async {
    try {
      return await _client
          .post(uri, body: data)
          .timeout(const Duration(seconds: 45));
    } catch (_) {
      throw const TranslationException('网络请求失败或超时，请检查网络连接。');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is Map<String, dynamic>) return json;
    } catch (_) {
      // Keep response details and credentials out of user-facing errors.
    }
    throw TranslationException('翻译服务返回了无法识别的响应（HTTP ${response.statusCode}）。');
  }

  String _providerError(String provider, Map<String, dynamic> body, int code) {
    final error = body['error'];
    final detail = error is Map ? error['message'] : body['error_msg'];
    final message = detail is String && detail.isNotEmpty
        ? detail.replaceAll(RegExp(r'https?://\S+'), '[接口地址]')
        : 'HTTP $code';
    return '$provider 翻译失败：$message';
  }
}
