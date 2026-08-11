import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../storage/secure_storage_service.dart';
import 'auth_session_providers.dart';

/// Bridges the auth API ([ApiClient]) and JWT persistence
/// ([SecureStorageService]) for Screen 1 (`UI-AUTH-001`/`UI-AUTH-002`).
/// After every session mutation it invalidates [authTokenProvider] so
/// `app.dart`'s root widget reacts to sign-in/out immediately without any
/// manual navigation call from the screen.
class AuthRepository {
  AuthRepository(this._ref, this._api, this._storage);

  final Ref _ref;
  final ApiClient _api;
  final SecureStorageService _storage;

  /// `AUTH-001` — throws [ApiException] on failure (e.g. duplicate email).
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final result = await _api.register(name: name, email: email, password: password);
    await _persistSession(result);
  }

  /// `AUTH-002` — throws [ApiException] on failure (e.g. bad credentials).
  Future<void> login({required String email, required String password}) async {
    final result = await _api.login(email: email, password: password);
    await _persistSession(result);
  }

  Future<void> logout() async {
    await _storage.deleteToken();
    _ref.invalidate(authTokenProvider);
  }

  Future<void> _persistSession(AuthResult result) async {
    await _storage.writeToken(result.accessToken); // UI-AUTH-002
    _ref.invalidate(authTokenProvider);
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref, ref.watch(apiClientProvider), ref.watch(secureStorageServiceProvider));
});
