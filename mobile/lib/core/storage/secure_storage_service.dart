import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps [FlutterSecureStorage] for the JWT persisted by Phase 8's auth
/// screen (`UI-AUTH-002`). Deliberately narrow: callers never touch
/// `FlutterSecureStorage` directly, so the encrypted-storage guarantee from
/// `MOBILE-005` can't be bypassed by a future screen reaching for
/// `shared_preferences` instead.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _jwtKey = 'jwt_token';

  final FlutterSecureStorage _storage;

  Future<void> writeToken(String token) => _storage.write(key: _jwtKey, value: token);

  Future<String?> readToken() => _storage.read(key: _jwtKey);

  Future<void> deleteToken() => _storage.delete(key: _jwtKey);
}
