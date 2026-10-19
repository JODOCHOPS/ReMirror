import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'translation.dart';

class CredentialStore {
  const CredentialStore();

  static const _storage = FlutterSecureStorage();

  Future<TranslationCredentials> load() async => TranslationCredentials(
        googleApiKey: await _storage.read(key: 'google_api_key') ?? '',
        baiduAppId: await _storage.read(key: 'baidu_app_id') ?? '',
        baiduSecret: await _storage.read(key: 'baidu_secret') ?? '',
        aiEndpoint: await _storage.read(key: 'ai_endpoint') ??
            'https://api.openai.com/v1',
        aiApiKey: await _storage.read(key: 'ai_api_key') ?? '',
        aiModel: await _storage.read(key: 'ai_model') ?? '',
      );

  Future<void> save(TranslationCredentials value) async {
    await _storage.write(key: 'google_api_key', value: value.googleApiKey);
    await _storage.write(key: 'baidu_app_id', value: value.baiduAppId);
    await _storage.write(key: 'baidu_secret', value: value.baiduSecret);
    await _storage.write(key: 'ai_endpoint', value: value.aiEndpoint);
    await _storage.write(key: 'ai_api_key', value: value.aiApiKey);
    await _storage.write(key: 'ai_model', value: value.aiModel);
  }
}
